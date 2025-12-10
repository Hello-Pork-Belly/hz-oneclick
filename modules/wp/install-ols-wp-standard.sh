#!/usr/bin/env bash
#
# install-ols-wp-standard.sh
# 版本: v0.3.0
#
# 用途:
#   - 在 Ubuntu 22.04 / 24.04 上部署单站点 OpenLiteSpeed + WordPress 标准站
#   - 自动完成: 环境检查、OLS 安装/启用、创建站点目录、下载 WordPress、
#     生成 wp-config.php、写入 OLS 虚拟主机与 HTTP 80 listener 映射
#   - 安装结束后给出 521 / 403 / 404 以及 UFW / 云厂商安全组 / CDN 常见排查提示
#
# 特点:
#   - 不自动创建数据库 (DB 由用户在目标实例手动创建)
#   - 仅开 HTTP 80，不自动签发 SSL (方便配合 Cloudflare / 其它 CDN)
#   - 可多次运行，同一 slug 会复用站点目录和 vhost
#
# 步骤总览 (对应大纲主节点):
#   Step 1  安装前检查：root / Ubuntu 22.04 & 24.04 / 端口 / UFW / Nginx-Apache-OLS
#   Step 2  检查 / 安装 OpenLiteSpeed
#   Step 3  站点基础信息（域名 / slug / docroot）
#   Step 4  数据库信息（host:port / DB / 用户 / 密码 / 表前缀）
#   Step 5  目录与权限（/var/www/<slug>/html）
#   Step 6  安装 WordPress 核心
#   Step 7  生成 wp-config.php + OLS 虚拟主机 + 80 端口映射 + 常见问题排查提示
#

set -euo pipefail

# 颜色
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

# 全局变量 (避免 set -u 报未定义)
WP_DOMAIN=""
WP_SLUG=""
WP_DOCROOT=""
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
TABLE_PREFIX=""

# ----------- 通用输出函数 -----------

info()  { echo -e "${GREEN}[INFO] $*${NC}"; }
warn()  { echo -e "${YELLOW}[WARN] $*${NC}"; }
error() { echo -e "${RED}[ERROR] $*${NC}" >&2; }

pause() {
  echo
  read -rp "按回车键继续..." _
}

header_step() {
  local step="$1"
  local total="$2"
  local title="$3"
  echo
  echo "==================== Step ${step}/${total} ===================="
  echo "${title}"
  echo "===================================================="
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "请用 root 执行本脚本。"
    exit 1
  fi
}

restart_ols() {
  # 统一重启 OLS，兼容不同 service 名
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -q "^lsws\.service"; then
      systemctl restart lsws
      return
    fi
    if systemctl list-unit-files | grep -q "^lshttpd\.service"; then
      systemctl restart lshttpd
      return
    fi
  fi

  if [ -x /usr/local/lsws/bin/lswsctrl ]; then
    /usr/local/lsws/bin/lswsctrl restart
  fi
}

# ----------- Step 1: 安装前检查 -----------

env_check_step() {
  header_step 1 7 "安装前检查：root / 系统版本 / 端口 / UFW / Web 服务进程"

  info "当前用户: $(id)"
  info "已使用 root 运行 (如非 root，脚本已在前面退出)。"

  local OS_NAME="unknown"
  local OS_VER="unknown"
  local ARCH
  ARCH="$(uname -m)"

  if command -v lsb_release >/dev/null 2>&1; then
    OS_NAME="$(lsb_release -si 2>/dev/null || echo "unknown")"
    OS_VER="$(lsb_release -sr 2>/dev/null || echo "unknown")"
  fi

  info "检测到系统: ${OS_NAME} ${OS_VER} (${ARCH})"

  if [[ "$OS_NAME" != "Ubuntu" || ( "$OS_VER" != "22.04" && "$OS_VER" != "24.04" ) ]]; then
    warn "本脚本主要针对 Ubuntu 22.04 / 24.04 设计，其他系统请谨慎使用。"
  fi

  # 检测已有 Web 服务
  local running_web=()

  if pgrep -x nginx >/dev/null 2>&1; then
    running_web+=("nginx")
  fi
  if pgrep -x apache2 >/dev/null 2>&1 || pgrep -x httpd >/dev/null 2>&1; then
    running_web+=("Apache")
  fi
  if pgrep -f lshttpd >/dev/null 2>&1; then
    running_web+=("OpenLiteSpeed")
  fi

  if ((${#running_web[@]} > 0)); then
    warn "检测到当前已有 Web 服务进程: ${running_web[*]}"
    warn "如果是从 Nginx / Apache 迁移过来，请确保不会与 OLS 同时抢占 80 / 443 端口。"
  else
    info "未发现 nginx / Apache / OLS 进程。"
  fi

  # 检测 80 / 443 / 7080 端口占用
  local port
  for port in 80 443 7080; do
    if command -v ss >/dev/null 2>&1; then
      if ss -tuln | grep -q ":${port} " ; then
        warn "端口 ${port} 当前已有进程监听。下面是部分监听信息："
        ss -tulnp | grep ":${port} " | head -n 5 || true
      else
        info "端口 ${port} 当前未被占用。"
      fi
    elif command -v netstat >/dev/null 2>&1; then
      if netstat -tuln | grep -q ":${port} " ; then
        warn "端口 ${port} 当前已有进程监听 (netstat 检测)。"
        netstat -tulnp | grep ":${port} " | head -n 5 || true
      else
        info "端口 ${port} 当前未被占用。"
      fi
    else
      warn "系统未找到 ss / netstat，无法自动检测端口 ${port} 是否占用，请手工确认。"
    fi
  done

  # UFW 状态
  if command -v ufw >/dev/null 2>&1; then
    echo
    info "当前 UFW 状态："
    ufw status || true
    echo
    warn "如计划通过公网访问，请确保防火墙已放行 80 / 443。"
  else
    info "未检测到 ufw，本机可能使用其它防火墙或者未启用防火墙。"
  fi

  echo
  echo "额外提醒："
  echo "  - 请在云厂商安全组 / 防火墙中放行 80 / 443 (以及 SSH 所需端口)。"
  echo "  - 如后面接入 Cloudflare / 其它 CDN，注意 521 / 522 多半与“源站端口不通”有关。"

  pause
}

# ----------- Step 2: 检查 / 安装 OLS -----------

install_ols_step() {
  header_step 2 7 "检查 / 安装 OpenLiteSpeed"

  if command -v lswsctrl >/dev/null 2>&1 || [ -d /usr/local/lsws ]; then
    info "检测到系统中已经存在 OpenLiteSpeed 相关文件，将尝试直接启用。"
  else
    warn "未检测到 OpenLiteSpeed，将尝试使用官方仓库安装。"
    read -rp "现在自动安装 OLS（会执行 apt 操作）？ [y/N，默认: y] " INSTALL_OLS
    INSTALL_OLS=${INSTALL_OLS:-y}
    if [[ "$INSTALL_OLS" =~ ^[Yy]$ ]]; then
      info "开始安装 OLS（使用 LiteSpeed 官方仓库）..."
      apt update -y
      apt install -y wget gnupg lsb-release
      wget -O - https://repo.litespeed.sh | bash
      apt update -y
      apt install -y openlitespeed
    else
      error "用户选择不安装 OLS，无法继续。"
      exit 1
    fi
  fi

  restart_ols
  sleep 2

  if pgrep -f lshttpd >/dev/null 2>&1; then
    info "OLS 进程正在运行。"
  else
    warn "无法确认 OLS 进程是否正常运行，请手动检查：systemctl status lsws"
  fi

  pause
}

# ----------- Step 3: 站点信息 -----------

collect_site_info_step() {
  header_step 3 7 "收集站点信息（域名 / slug / 路径）"

  # 域名
  while true; do
    read -rp "请输入站点主域名（例如: ols.horizontech.page）: " WP_DOMAIN
    if [ -n "$WP_DOMAIN" ]; then
      break
    fi
    warn "域名不能为空，请重新输入。"
  done

  # slug
  read -rp "请输入站点代号 slug（例如: ols，默认: 根据域名自动生成）: " WP_SLUG
  if [ -z "$WP_SLUG" ]; then
    WP_SLUG=$(echo "$WP_DOMAIN" | cut -d'.' -f1)
    [ -z "$WP_SLUG" ] && WP_SLUG="site"
  fi

  # docroot
  local default_docroot="/var/www/${WP_SLUG}/html"
  read -rp "WordPress 安装目录（默认: ${default_docroot}）: " WP_DOCROOT
  WP_DOCROOT=${WP_DOCROOT:-$default_docroot}

  echo
  info "将使用以下站点配置："
  echo "  域名:   ${WP_DOMAIN}"
  echo "  slug:   ${WP_SLUG}"
  echo "  路径:   ${WP_DOCROOT}"
  echo
  echo "小提示：可以稍后用下面命令简单测试 DNS 是否已生效："
  echo "  dig +short ${WP_DOMAIN}"
  echo "或使用 ping 检查是否指向正确 IP。"

  pause
}

# ----------- Step 4: 数据库信息 -----------

collect_db_info_step() {
  header_step 4 7 "收集数据库信息（请确保数据库已在目标实例中创建好）"

  warn "当前版本不会自动创建数据库，只会把你输入的信息写入 wp-config.php。"
  warn "请提前在目标 DB 实例中创建对应的 DB / 用户 / 授权。"
  echo

  # DB host
  read -rp "DB 主机（默认: 127.0.0.1，可不带端口）: " DB_HOST
  DB_HOST=${DB_HOST:-127.0.0.1}

  # DB port
  read -rp "DB 端口（默认: 3306）: " DB_PORT
  DB_PORT=${DB_PORT:-3306}

  # DB 名
  while true; do
    read -rp "DB 名称（例如: ${WP_SLUG}_wp）: " DB_NAME
    [ -n "$DB_NAME" ] && break
    warn "DB 名称不能为空。"
  done

  # DB 用户
  while true; do
    read -rp "DB 用户名（例如: ${WP_SLUG}_user）: " DB_USER
    [ -n "$DB_USER" ] && break
    warn "DB 用户名不能为空。"
  done

  # DB 密码
  while true; do
    read -rsp "DB 密码（输入时不显示）: " DB_PASSWORD
    echo
    [ -n "$DB_PASSWORD" ] && break
    warn "DB 密码不能为空。"
  done

  # 表前缀
  read -rp "表前缀（默认: wp_）: " TABLE_PREFIX
  TABLE_PREFIX=${TABLE_PREFIX:-wp_}

  echo
  info "DB 配置信息如下（仅用于生成 wp-config.php）："
  echo "  DB_HOST: ${DB_HOST}"
  echo "  DB_PORT: ${DB_PORT}"
  echo "  DB_NAME: ${DB_NAME}"
  echo "  DB_USER: ${DB_USER}"
  echo "  表前缀: ${TABLE_PREFIX}"
  warn "请确认目标 DB 实例已创建上述数据库和用户，并已授予权限。"

  pause
}

# ----------- Step 5: 目录与权限 -----------

prepare_docroot_step() {
  header_step 5 7 "准备站点目录与权限"

  info "创建站点目录: ${WP_DOCROOT}"
  mkdir -p "${WP_DOCROOT}"
  mkdir -p "/var/www/${WP_SLUG}"

  # 默认用 nobody:nogroup，与 OLS 默认运行用户保持一致
  chown -R nobody:nogroup "/var/www/${WP_SLUG}"
  find "/var/www/${WP_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${WP_SLUG}" -type f -exec chmod 644 {} \;

  info "站点目录准备完成。"
  pause
}

# ----------- Step 6: 安装 WordPress 核心 -----------

install_wordpress_step() {
  header_step 6 7 "下载并安装 WordPress 核心"

  if [ -f "${WP_DOCROOT}/wp-config.php" ]; then
    warn "${WP_DOCROOT}/wp-config.php 已存在，将跳过 WordPress 核心文件安装，仅在后面更新 OLS 配置。"
    pause
    return
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  cd "$tmpdir"

  info "正在下载最新 WordPress..."
  curl -fsSL -o wordpress.tar.gz https://wordpress.org/latest.tar.gz
  tar xf wordpress.tar.gz

  info "拷贝 WordPress 文件到 ${WP_DOCROOT}..."
  cp -R wordpress/* "${WP_DOCROOT}/"

  cd /
  rm -rf "$tmpdir"

  chown -R nobody:nogroup "/var/www/${WP_SLUG}"
  find "/var/www/${WP_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${WP_SLUG}" -type f -exec chmod 644 {} \;

  info "WordPress 核心文件安装完成。"
  pause
}

# ----------- Step 7: wp-config + OLS vhost + 80 listener -----------

generate_wp_config_and_vhost_step() {
  header_step 7 7 "生成 wp-config.php 与 OLS 虚拟主机配置"

  # 生成 wp-config.php（如不存在）
  if [ ! -f "${WP_DOCROOT}/wp-config.php" ]; then
    info "生成新的 wp-config.php..."

    local WP_SALTS
    WP_SALTS="$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ || echo "")"

    cat > "${WP_DOCROOT}/wp-config.php" <<EOF
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST', '${DB_HOST}:${DB_PORT}' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

\$table_prefix = '${TABLE_PREFIX}';

EOF

    if [ -n "$WP_SALTS" ]; then
      echo "$WP_SALTS" >> "${WP_DOCROOT}/wp-config.php"
    else
      echo "// TODO: 请到 https://api.wordpress.org/secret-key/1.1/salt/ 生成 SALT 并替换。" >> "${WP_DOCROOT}/wp-config.php"
    fi

    cat >> "${WP_DOCROOT}/wp-config.php" <<'EOF'

define( 'WP_DEBUG', false );
define( 'FS_METHOD', 'direct' );

if ( ! defined( 'ABSPATH' ) ) {
        define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF

    chown nobody:nogroup "${WP_DOCROOT}/wp-config.php"
    chmod 640 "${WP_DOCROOT}/wp-config.php"
  else
    warn "${WP_DOCROOT}/wp-config.php 已存在，请手工确认其中的 DB 配置信息是否正确。"
  fi

  # 创建 OLS vhost 配置
  info "为该站点创建 OLS 虚拟主机配置..."

  local lsws_conf_root="/usr/local/lsws/conf"
  local vhost_dir="${lsws_conf_root}/vhosts/${WP_SLUG}"
  local vhconf="${vhost_dir}/vhconf.conf"
  local httpd_conf="${lsws_conf_root}/httpd_config.conf"

  mkdir -p "$vhost_dir"

  cat > "$vhconf" <<EOF
docRoot                   ${WP_DOCROOT}
vhDomain                  ${WP_DOMAIN}
enableGzip                1
index  {
  useServer               0
  indexFiles              index.php,index.html
}
context / {
  location                ${WP_DOCROOT}
  allowBrowse             1
}
phpIniOverride  {
}
EOF

  # 在 httpd_config.conf 中追加 virtualhost 与 listener 配置（如果不存在）
  if ! grep -q "virtualhost ${WP_SLUG}" "$httpd_conf" 2>/dev/null; then
    cat >> "$httpd_conf" <<EOF

virtualhost ${WP_SLUG} {
  vhRoot                  /var/www/${WP_SLUG}
  configFile              conf/vhosts/${WP_SLUG}/vhconf.conf
  allowSymbolLink         1
  enableScript            1
  restrained              1
}
EOF
  fi

  # 创建/更新 HTTP listener 映射 80 端口
  if ! grep -q "listener HTTP" "$httpd_conf" 2>/dev/null; then
    cat >> "$httpd_conf" <<EOF

listener HTTP {
  address                 *:80
  secure                  0
  map                     ${WP_SLUG} ${WP_DOMAIN}
}
EOF
  else
    # 如果 listener HTTP 已存在，只提示用户检查是否包含 map 行
    if ! grep -q "map.*${WP_SLUG}.*${WP_DOMAIN}" "$httpd_conf" 2>/dev/null; then
      warn "检测到已有 listener HTTP，请手动确认其中已包含："
      warn "  map ${WP_SLUG} ${WP_DOMAIN}"
    fi
  fi

  info "重启 OLS 以应用新配置..."
  restart_ols

  echo
  echo -e "${GREEN}[完成] OLS + WordPress 标准安装完成（v0.3.0）。${NC}"
  echo "====================== 安装总结 ======================"
  echo "  域名：       ${WP_DOMAIN}"
  echo "  slug：       ${WP_SLUG}"
  echo "  安装路径：   ${WP_DOCROOT}"
  echo "  DB_HOST：    ${DB_HOST}"
  echo "  DB_PORT：    ${DB_PORT}"
  echo "  DB_NAME：    ${DB_NAME}"
  echo "  DB_USER：    ${DB_USER}"
  echo
  echo "================== 访问与排查小贴士 =================="
  echo "1) 本机连通性快速自检："
  echo "   curl -I http://127.0.0.1/                # 简单确认 80 是否有响应"
  echo "   curl -I http://${WP_DOMAIN}/             # 如本机 DNS 已指向本机可直接测试"
  echo
  echo "2) 如接入 Cloudflare / 其它 CDN 后出现 521 / 522："
  echo "   - 优先检查："
  echo "       * OLS 是否在本机监听 80 (ss -tuln | grep :80)"
  echo "       * 本机防火墙 (ufw / firewalld) 是否放行 80"
  echo "       * 云厂商安全组是否放行 80 / 443"
  echo "   - 521 / 522 通常是“源站端口不通或拒绝连接”，与 WordPress 本身无关。"
  echo
  echo "3) 首次安装建议："
  echo "   - 先在浏览器中用 http:// 域名访问，确认站点能正常打开；"
  echo "   - 再决定是否在 OLS / 其它脚本中配置 HTTPS / SSL；"
  echo "   - 结合 hz-oneclick 里的备份 / wp-cron 模块，为站点配置备份与定时任务。"
  echo "======================================================"
}

# ----------- 主入口 -----------

main() {
  require_root

  echo
  echo "===================================================="
  echo "  OLS + WordPress 标准安装模块（v0.3.0）"
  echo "  定位：简单、可重复、适合新手的一键标准安装"
  echo "===================================================="

  env_check_step
  install_ols_step
  collect_site_info_step
  collect_db_info_step
  prepare_docroot_step
  install_wordpress_step
  generate_wp_config_and_vhost_step
}

main "$@"
