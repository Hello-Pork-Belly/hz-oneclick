#!/usr/bin/env bash
# install-ols-wp-standard.sh
# v0.11 - OLS + WordPress 标准安装（HTTP 版，带环境自检 / 自动调优 / 清理工具）
# 2025-12-09
#
# 变更摘要：
# - 新增：环境自检（系统 / 端口 / 防火墙），打印排错提示，减少 521 类问题
# - 新增：根据本机内存自动写入 WP_MEMORY_LIMIT / WP_MAX_MEMORY_LIMIT
# - 新增：自动删除 Hello Dolly / Akismet，只保留最新默认主题 + GeneratePress
# - 修复：数据库密码不再用占位符替换，改为双重输入校验 + mysql 连接测试
# - 修复：打印公网 IPv4 / IPv6，不再误用 10.x 内网地址
# - 修复：GeneratePress 下载 / 解压失败时不再导致脚本退出，缺 unzip 自动安装，失败仅 WARN

set -Eeuo pipefail

SCRIPT_NAME="install-ols-wp-standard.sh"
SCRIPT_VERSION="v0.11"

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
CYAN="\033[36m"
NC="\033[0m"

# ---------------- 公共小工具 ----------------

pause() {
  echo
  read -rp "按回车键继续..." _
}

press_enter_to_continue() {
  echo
  read -rp "按回车键返回上一层菜单..." _
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_note()  { echo -e "${CYAN}[NOTE]${NC} $*"; }

ensure_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log_error "请用 root 运行本脚本（或在前面加 sudo）。"
    exit 1
  fi
}

header() {
  clear
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  HorizonTech - OLS + WordPress 标准安装模块（${SCRIPT_VERSION}）${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo
}

header_step() {
  local step="$1" total="$2" title="$3"
  echo
  echo -e "${BLUE}---- 步骤 ${step}/${total}: ${title} ----${NC}"
}

confirm_or_exit() {
  read -rp "确认继续吗？(y/N): " ans
  case "${ans:-N}" in
    y|Y) ;;
    *) log_warn "已取消当前操作。"; return 1 ;;
  esac
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ---------------- 环境自检 ----------------

detect_public_ipv4() {
  local ip=""
  if command_exists curl; then
    ip=$(curl -4 -fsS https://api.ipify.org 2>/dev/null \
         || curl -4 -fsS https://ipv4.icanhazip.com 2>/dev/null \
         || true)
  fi
  echo "$ip"
}

detect_public_ipv6() {
  local ip=""
  if command_exists curl; then
    ip=$(curl -6 -fsS https://api64.ipify.org 2>/dev/null \
         || curl -6 -fsS https://ipv6.icanhazip.com 2>/dev/null \
         || true)
  fi
  echo "$ip"
}

env_check_summary() {
  header_step 1 4 "环境自检"

  echo "1) 系统信息："
  echo "   - Hostname : $(hostname)"
  echo "   - 内核     : $(uname -r)"
  echo "   - 发行版   : $(grep -E '^(PRETTY_|NAME=)' /etc/os-release | sed 's/^/     /')"
  echo

  echo "2) 硬件资源（粗略）："
  local mem_kb mem_gb disk_total disk_avail
  mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  mem_gb=$(( (mem_kb + 1048575) / 1048576 ))
  disk_total=$(df -h / | awk 'NR==2{print $2}')
  disk_avail=$(df -h / | awk 'NR==2{print $4}')
  echo "   - 内存约   : ${mem_gb} GB"
  echo "   - 根分区   : 总计 ${disk_total} / 可用 ${disk_avail}"
  if (( mem_gb < 4 )); then
    log_warn "当前机器内存 < 4G，建议【只跑 OLS + WordPress 前端】，DB / Redis 放到其他高配机器。"
  fi
  echo

  echo "3) 端口监听情况（80 / 443）："
  if command_exists ss; then
    ss -lntp | awk 'NR==1 || /:80 |:443 /'
  else
    log_warn "未找到 ss 命令，无法展示端口监听情况。"
  fi
  echo

  echo "4) 防火墙（ufw）状态："
  if command_exists ufw; then
    ufw status verbose || true
    log_note "如果 ufw 已启用，请确认 80/tcp 和 443/tcp 已允许。"
  else
    log_note "未检测到 ufw（也可能用的是别的防火墙或只靠云厂商安全组）。"
  fi
  echo

  log_note "⚠️ 重要：云厂商（例如 Oracle）安全列表里也要放行 80/443，否则前面 Cloudflare 绿灯，后面依然 521。"
  echo
}

# ---------------- OLS 安装 & 基础配置 ----------------

install_ols_if_needed() {
  header_step 2 4 "安装 / 检查 OpenLiteSpeed"

  if command_exists lswsctrl || [[ -x /usr/local/lsws/bin/lswsctrl ]]; then
    log_info "检测到已安装 OpenLiteSpeed，跳过安装，仅检查服务。"
  else
    log_info "未检测到 OpenLiteSpeed，准备安装（Ubuntu 22.04/24.04）。"

    if ! command_exists wget; then
      apt-get update -y
      apt-get install -y wget
    fi

    wget -O - https://repo.litespeed.sh | bash
    apt-get install -y openlitespeed lsphp83 lsphp83-mysql lsphp83-common

    log_info "OpenLiteSpeed 安装完成。"
  fi

  systemctl enable --now lsws || systemctl enable --now openlitespeed || true

  if ! systemctl is-active --quiet lsws && ! systemctl is-active --quiet openlitespeed; then
    log_error "OpenLiteSpeed 服务未能启动，请手动检查。"
    exit 1
  fi

  log_info "OpenLiteSpeed 服务运行中。"
}

# ---------------- 收集站点 / DB 信息 ----------------

SITE_SLUG=""
SITE_DOMAIN=""
SITE_DOCROOT=""
SITE_LOGROOT=""
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""

collect_site_info() {
  header_step 3 4 "收集站点基本信息"

  read -rp "请输入站点 slug（例如 ols-test，用于目录名和 vhost 名称）： " SITE_SLUG
  SITE_SLUG="${SITE_SLUG:-ols-site}"

  read -rp "请输入主域名（例如 ols.example.com，可先用测试域名）： " SITE_DOMAIN
  SITE_DOMAIN="${SITE_DOMAIN:-ols.example.com}"

  SITE_DOCROOT="/var/www/${SITE_SLUG}/html"
  SITE_LOGROOT="/var/www/${SITE_SLUG}/logs"

  log_info "站点将安装到：${SITE_DOCROOT}"
  log_info "站点访问日志目录：${SITE_LOGROOT}"
}

collect_db_info() {
  header_step 4 4 "收集数据库连接信息（必须是已存在的 DB / 用户）"

  log_note "说明：本模块【不自动创建数据库和用户】，请先在 DB 机器上建好："
  log_note "      - 数据库名（例如 ${SITE_SLUG}_wp）"
  log_note "      - 专用 DB 用户（例如 ${SITE_SLUG}_user，并授予此库全部权限）"
  echo

  read -rp "请输入数据库 Host（IP / 域名 / Tailscale IP，默认 127.0.0.1）: " DB_HOST
  DB_HOST="${DB_HOST:-127.0.0.1}"

  read -rp "请输入数据库 Port（默认 3306）: " DB_PORT
  DB_PORT="${DB_PORT:-3306}"

  read -rp "请输入数据库名（必须与已创建的数据库名称完全一致，例如 ${SITE_SLUG}_wp）: " DB_NAME
  DB_NAME="${DB_NAME:-${SITE_SLUG}_wp}"

  read -rp "请输入数据库用户名（必须与已创建的用户完全一致，例如 ${SITE_SLUG}_user）: " DB_USER
  DB_USER="${DB_USER:-${SITE_SLUG}_user}"

  while true; do
    read -rsp "请输入数据库密码（不会回显，建议用密码管理器保存，禁止包含单引号 ' ）: " DB_PASSWORD
    echo
    if [[ "$DB_PASSWORD" == *"'"* ]]; then
      log_warn "密码中不能包含单引号 ' ，请重新输入。"
      continue
    fi
    read -rsp "请再输入一次数据库密码以确认: " DB_PASSWORD2
    echo
    if [[ "$DB_PASSWORD" != "$DB_PASSWORD2" ]]; then
      log_warn "两次输入不一致，请重新输入。"
      continue
    fi
    break
  done

  log_info "现在测试数据库连接是否正确..."
  if ! command_exists mysql; then
    log_note "未检测到 mysql/mariadb 客户端，将自动安装 mariadb-client。"
    apt-get update -y
    apt-get install -y mariadb-client
  fi

  if MYSQL_PWD="${DB_PASSWORD}" \
     mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" \
     -e "SELECT 1;" >/dev/null 2>&1; then
    log_info "数据库连接测试成功。"
  else
    log_error "数据库连接失败，请检查 Host / Port / DB 名 / 用户 / 密码是否正确。"
    confirm_or_exit || exit 1
  fi
}

# ---------------- 准备目录 & 安装 WordPress ----------------

prepare_docroot() {
  header_step 1 3 "创建站点目录与权限"

  mkdir -p "${SITE_DOCROOT}" "${SITE_LOGROOT}"

  chown -R nobody:nogroup "/var/www/${SITE_SLUG}"
  find "/var/www/${SITE_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${SITE_SLUG}" -type f -exec chmod 644 {} \;

  log_info "站点目录与权限已就绪：${SITE_DOCROOT}"
}

install_wordpress_core() {
  header_step 2 3 "下载并安装最新英文版 WordPress"

  if [[ -f "${SITE_DOCROOT}/wp-settings.php" ]]; then
    log_warn "检测到 ${SITE_DOCROOT} 下已有 WordPress 文件，将跳过重新下载。"
    return
  fi

  cd /tmp
  rm -rf wordpress latest.tar.gz
  curl -fsSLO https://wordpress.org/latest.tar.gz
  tar -xzf latest.tar.gz
  cp -a wordpress/. "${SITE_DOCROOT}/"
  rm -rf wordpress latest.tar.gz

  chown -R nobody:nogroup "${SITE_DOCROOT}"
  log_info "WordPress 核心文件已安装到 ${SITE_DOCROOT}"
}

generate_wp_config() {
  header_step 3 3 "生成 wp-config.php（写入 DB 信息 + 基础调优）"

  local wp_config="${SITE_DOCROOT}/wp-config.php"

  if [[ -f "${wp_config}" ]]; then
    log_warn "检测到已存在 wp-config.php，将覆盖其中的 DB 配置相关部分。"
  fi

  local salts
  salts=$(curl -fsS https://api.wordpress.org/secret-key/1.1/salt/ || true)
  if [[ -z "${salts}" ]]; then
    log_warn "获取官方 SALT 失败，将使用本地随机字符串。"
    local tmp_salt
    tmp_salt=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64)
    salts=$(printf "define('AUTH_KEY', '%s');\n" "$tmp_salt")
  fi

  cat > "${wp_config}" <<EOF
<?php
/** 自动生成的 wp-config.php（${SCRIPT_VERSION}） */

define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST', '${DB_HOST}:${DB_PORT}' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

${salts}

/**
 * 表前缀：如需多个站点共享 DB，可修改。
 */
\$table_prefix = 'wp_';

/**
 * 建议关闭 WP 内置假 cron，由 systemd 定时任务驱动（可配合 gen-wp-cron 模块）。
 */
define( 'DISABLE_WP_CRON', true );

/* 自动调优部分将在稍后由脚本写入（WP_MEMORY_LIMIT 等）。 */

if ( ! defined( 'ABSPATH' ) ) {
  define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF

  chown nobody:nogroup "${wp_config}"
  chmod 640 "${wp_config}"

  auto_tune_wp_config "${wp_config}"

  log_info "wp-config.php 已生成并写入数据库配置 + 基础调优。"
}

auto_tune_wp_config() {
  local wp_config="$1"
  header_step "3b" 3 "根据本机内存自动调节 WP 内存限制"

  local mem_kb mem_gb wp_mem wp_max
  mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  mem_gb=$(( (mem_kb + 1048575) / 1048576 ))

  if (( mem_gb < 4 )); then
    wp_mem="96M"
    wp_max="192M"
    log_note "内存 < 4G：WP_MEMORY_LIMIT=${wp_mem}，WP_MAX_MEMORY_LIMIT=${wp_max}。"
  elif (( mem_gb < 8 )); then
    wp_mem="128M"
    wp_max="256M"
    log_note "内存约 ${mem_gb}G：WP_MEMORY_LIMIT=${wp_mem}，WP_MAX_MEMORY_LIMIT=${wp_max}。"
  else
    wp_mem="196M"
    wp_max="384M"
    log_note "内存 ≥ 8G：WP_MEMORY_LIMIT=${wp_mem}，WP_MAX_MEMORY_LIMIT=${wp_max}。"
  fi

  awk -v wp_mem="$wp_mem" -v wp_max="$wp_max" '
    /require_once ABSPATH . '\''wp-settings.php'\'';/ {
      print "define( '\''WP_MEMORY_LIMIT'\'', '\''"wp_mem"'\'' );"
      print "define( '\''WP_MAX_MEMORY_LIMIT'\'', '\''"wp_max"'\'' );"
      print ""
      print $0
      next
    }
    { print }
  ' "$wp_config" > "${wp_config}.tmp" && mv "${wp_config}.tmp" "$wp_config"
}

post_install_cleanup() {
  header_step 4 4 "清理默认插件 / 主题（尽量让 Site Health 更干净）"

  # 删除默认插件 Hello Dolly / Akismet
  rm -rf "${SITE_DOCROOT}/wp-content/plugins/hello.php" \
         "${SITE_DOCROOT}/wp-content/plugins/akismet" || true

  # 安装 GeneratePress 主题（失败只 WARN，不中断脚本）
  local gp_ver="3.6.1"
  local gp_zip="/tmp/generatepress-${gp_ver}.zip"

  if [[ ! -d "${SITE_DOCROOT}/wp-content/themes/generatepress" ]]; then
    log_info "尝试自动安装 GeneratePress ${gp_ver} 主题（失败将跳过，仅给提示）..."

    # 确保 unzip 可用
    if ! command_exists unzip; then
      log_note "未检测到 unzip，将尝试自动安装 unzip..."
      if ! apt-get update -y >/dev/null 2>&1; then
        log_warn "apt update 失败，跳过 GeneratePress 自动安装。"
      else
        if ! apt-get install -y unzip >/dev/null 2>&1; then
          log_warn "安装 unzip 失败，跳过 GeneratePress 自动安装。"
        fi
      fi
    fi

    if command_exists unzip; then
      if curl -fsSL -o "${gp_zip}" "https://downloads.wordpress.org/theme/generatepress.${gp_ver}.zip"; then
        if unzip -q "${gp_zip}" -d "${SITE_DOCROOT}/wp-content/themes"; then
          log_info "GeneratePress 主题已解压。"
        else
          log_warn "unzip 解压 GeneratePress 失败，稍后可在后台手动安装。"
        fi
      else
        log_warn "下载 GeneratePress 失败，稍后可在后台手动安装。"
      fi
    else
      log_warn "系统中仍然没有 unzip，无法自动解压 GeneratePress，稍后可在后台手动安装。"
    fi
  fi

  # 保留 twentytwentyfive + generatepress，删除 twentytwentythree / twentytwentyfour
  rm -rf "${SITE_DOCROOT}/wp-content/themes/twentytwentythree" \
         "${SITE_DOCROOT}/wp-content/themes/twentytwentyfour" || true

  chown -R nobody:nogroup "${SITE_DOCROOT}/wp-content"
  log_info "默认插件/主题清理完成。"
}

# ---------------- OLS vhost 基础配置（仅 HTTP） ----------------

configure_ols_vhost() {
  header_step 4 4 "为站点创建 OLS 虚拟主机（仅 HTTP 80）"

  local lsws_conf="/usr/local/lsws/conf"
  local vhost_conf="${lsws_conf}/vhosts/${SITE_SLUG}.conf"

  mkdir -p "${lsws_conf}/vhosts"

  cat > "${vhost_conf}" <<EOF
docRoot                   ${SITE_DOCROOT}
vhDomain                  ${SITE_DOMAIN}
vhAliases                 www.${SITE_DOMAIN}
adminEmails               you@example.com
enableScript              1
scriptHandler             lsapi:${SITE_SLUG}_php

errorlog ${SITE_LOGROOT}/error.log {
  useServer               0
  logLevel                ERROR
  rollingSize             10M
}

accesslog ${SITE_LOGROOT}/access.log {
  useServer               0
  logFormat               "%h %l %u %t \"%r\" %>s %b"
  rollingSize             10M
}

index  {
  useServer               0
  indexFiles              index.php,index.html
}

phpIniOverride  {
}
EOF

  local vh_include="${lsws_conf}/httpd_config.conf"
  if ! grep -q "virtualHost ${SITE_SLUG}" "${vh_include}" 2>/dev/null; then
    cat >> "${vh_include}" <<EOF

extProcessor ${SITE_SLUG}_php {
  type                    lsapi
  address                 uds://tmp/lshttpd/${SITE_SLUG}_php.sock
  maxConns                35
  env                     LSAPI_CHILDREN=35
  path                    /usr/local/lsws/lsphp83/bin/lsphp
  initTimeout             60
  retryTimeout            0
  persistConn             1
  responseBuffer          0
  autoStart               1
  maxIdleTime             10
  priority                0
  memSoftLimit            2047M
  memHardLimit            2047M
  procSoftLimit           400
  procHardLimit           500
}

virtualHost ${SITE_SLUG} {
  vhRoot                  /var/www/${SITE_SLUG}/
  configFile              conf/vhosts/${SITE_SLUG}.conf
  allowSymbolLink         1
  enableScript            1
  restrained              0
}

listener listener80 {
  address                 *:80
  secure                  0
}

listener listener80 {
  vhmap                   ${SITE_DOMAIN} ${SITE_SLUG}
}
EOF
  fi

  systemctl restart lsws || systemctl restart openlitespeed || true
  log_info "OLS 虚拟主机已配置并重启。"
}

# ---------------- 清理 OLS / WordPress ----------------

cleanup_ols() {
  header_step 1 2 "彻底移除本机 OLS（openlitespeed + lsphp83）"

  echo "本操作会卸载 openlitespeed / lsphp83 并删除 /usr/local/lsws（不会动 /var/www）。"
  confirm_or_exit || return 0

  systemctl stop lsws || systemctl stop openlitespeed || true
  apt-get remove --purge -y openlitespeed lsphp* || true
  rm -rf /usr/local/lsws

  log_info "本机 OLS 已尝试卸载完成（如有残留可手动检查 /usr/local/lsws）。"
  press_enter_to_continue
}

cleanup_wp_site() {
  header_step 2 2 "按 slug 清理本机某个 WordPress 站点"

  read -rp "请输入要清理的站点 slug（例如 ols-test）： " slug
  [[ -z "${slug}" ]] && { log_warn "slug 不能为空。"; press_enter_to_continue; return; }

  local root="/var/www/${slug}"
  if [[ ! -d "${root}" ]]; then
    log_warn "目录 ${root} 不存在，似乎本机没有该站点。"
    press_enter_to_continue
    return
  fi

  echo "将删除目录：${root}"
  confirm_or_exit || return

  rm -rf "${root}"
  log_info "已删除 ${root}。"

  rm -f "/usr/local/lsws/conf/vhosts/${slug}.conf" || true
  sed -i "/virtualHost ${slug} /,/^}/d" /usr/local/lsws/conf/httpd_config.conf 2>/dev/null || true
  sed -i "/vhmap.*${slug}\$/d" /usr/local/lsws/conf/httpd_config.conf 2>/dev/null || true

  systemctl restart lsws || systemctl restart openlitespeed || true

  log_info "与该 slug 相关的 OLS vhost 配置也已尽量清理。"
  press_enter_to_continue
}

cleanup_local_menu() {
  while true; do
    header
    echo ">>> 清理本机 OLS / WordPress："
    echo "  1) 彻底移除本机 OLS（卸载 openlitespeed + /usr/local/lsws）"
    echo "  2) 按 slug 清理本机某个 WordPress 站点（/var/www/<slug> + vhost）"
    echo "  3) 返回上一层"
    echo "  0) 退出脚本"
    echo
    read -rp "请输入选项: " c
    case "${c:-3}" in
      1) cleanup_ols ;;
      2) cleanup_wp_site ;;
      3) return ;;
      0) echo "再见～"; exit 0 ;;
      *) log_warn "无效选项。"; pause ;;
    esac
  done
}

# ---------------- 主安装流程 ----------------

install_ols_wp_standard() {
  header
  log_info "当前版本：${SCRIPT_VERSION}"
  echo

  env_check_summary
  confirm_or_exit || return

  install_ols_if_needed
  collect_site_info
  collect_db_info

  prepare_docroot
  install_wordpress_core
  generate_wp_config
  post_install_cleanup
  configure_ols_vhost

  echo
  log_info "✅ OLS + WordPress 标准站点安装完成。"
  echo

  local pub4 pub6
  pub4=$(detect_public_ipv4)
  pub6=$(detect_public_ipv6)

  echo "================ 安装结果摘要 ================"
  echo "  站点 slug        : ${SITE_SLUG}"
  echo "  站点目录         : ${SITE_DOCROOT}"
  echo "  主域名           : ${SITE_DOMAIN}"
  echo
  echo "  数据库 Host      : ${DB_HOST}"
  echo "  数据库 Port      : ${DB_PORT}"
  echo "  数据库名         : ${DB_NAME}"
  echo "  数据库用户       : ${DB_USER}"
  echo
  echo "  本机公网 IPv4    : ${pub4:-获取失败（可能没有 IPv4 或出网被限制）}"
  echo "  本机公网 IPv6    : ${pub6:-获取失败（可能没有 IPv6 或出网被限制）}"
  echo
  log_note "请在 Cloudflare / 其他 DNS 供应商中，将上述 IP 配置到 ${SITE_DOMAIN}。"
  log_note "⚠️ 建议首次调试时将记录设为『DNS only』，确认 HTTP 正常后再开启代理。"
  echo

  press_enter_to_continue
}

# ---------------- 主菜单 ----------------

main_menu() {
  while true; do
    header
    echo "菜单选项："
    echo "  1) 安装 / 初始化 OLS + WordPress 标准站点"
    echo "  2) 仅运行环境自检（端口 / 防火墙 / 资源概览）"
    echo "  3) 清理本机 OLS / WordPress（卸载 OLS / 按 slug 删除站点）"
    echo "  0) 退出脚本"
    echo
    read -rp "请输入选项: " choice
    case "${choice:-0}" in
      1) install_ols_wp_standard ;;
      2) header; env_check_summary; press_enter_to_continue ;;
      3) cleanup_local_menu ;;
      0) echo "再见～"; exit 0 ;;
      *) log_warn "无效选项，请重新输入。"; pause ;;
    esac
  done
}

ensure_root
main_menu
