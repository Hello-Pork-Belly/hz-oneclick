#!/usr/bin/env bash
#
# install-ols-wp-standard.sh
# Version: v0.12 (2025-12-10)
#
# Changelog v0.12
# - 修复：主菜单选 3 不再直接返回外层菜单，而是进入【清理本机 OLS / WordPress】子菜单
# - 调整：主菜单文案恢复为简洁清晰的表达，避免“查看安全说明”这类易混淆文字
# - 调整：清理逻辑恢复为：
#   * 1) 彻底移除本机 OLS（卸载 openlitespeed / lsphp* + 删除 /usr/local/lsws）
#   * 2) 按 slug 清理本机某个 WordPress 站点（/var/www/<slug> + OLS vhost）
#   * 3) 返回上一层  0) 退出脚本
# - 其余安装流程沿用上一版：环境自检 / DB 连接测试 / HTTP + 可选 SSL（CF Origin / Let’s Encrypt）

set -euo pipefail

SCRIPT_VERSION="v0.12"

#####################################
# 彩色输出 & 小工具
#####################################

cecho() { # $1=info|warn|error, $2...=msg
  local level="$1"; shift || true
  local msg="${*:-}"
  case "$level" in
    info)  printf "\033[1;32m[INFO]\033[0m %s\n"  "$msg" ;;
    warn)  printf "\033[1;33m[WARN]\033[0m %s\n"  "$msg" ;;
    error) printf "\033[1;31m[ERROR]\033[0m %s\n" "$msg" ;;
    *)     printf "[%s] %s\n" "$level" "$msg" ;;
  esac
}

pause() {
  read -r -p "按回车继续..." _ || true
}

ensure_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    cecho error "请用 root（或 sudo）执行本脚本。"
    exit 1
  fi
}

show_header() {
  clear
  echo "======================================================="
  echo "  OLS + WordPress 标准安装模块  ${SCRIPT_VERSION}"
  echo "======================================================="
  echo
}

#####################################
# 1. 环境自检
#####################################

env_check() {
  cecho info "Step 1/4：环境自检（系统 / 端口 / 防火墙 / 云厂商安全组）"

  # 系统信息
  local os=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os="${PRETTY_NAME:-}"
  fi
  cecho info "当前系统：${os:-未知}"

  # 内存
  local mem_total
  mem_total="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  cecho info "检测到内存约：${mem_total} MB"

  if (( mem_total < 2048 )); then
    cecho warn "当前内存 < 2G，不建议本机同时跑 OLS + 数据库 + Redis。"
  elif (( mem_total < 4096 )); then
    cecho warn "当前内存 < 4G，建议数据库 / Redis 使用其他高配机器，本机只跑 OLS + WordPress 前端或 LNMP。"
  fi

  echo
  cecho info "当前 80 / 443 端口监听情况："
  ss -lnpt '( sport = :80 or sport = :443 )' || true
  echo

  # UFW 状态
  if command -v ufw >/dev/null 2>&1; then
    cecho info "UFW 状态："
    ufw status verbose || true
    echo
    cecho warn "如果 UFW 为 active，请确认已允许 80/tcp 和 443/tcp，例如："
    echo "  ufw allow 80/tcp"
    echo "  ufw allow 443/tcp"
  else
    cecho info "未检测到 UFW（或未启用），略过本机防火墙检查。"
  fi

  echo
  cecho warn "⚠️ 还需要去云厂商控制台确认安全组 / 安全列表已放行 80 和 443，否则依然无法从公网访问。"
  echo
}

#####################################
# 2. 确保 OLS 已安装
#####################################

ensure_ols_installed() {
  if command -v lswsctrl >/dev/null 2>&1 || [[ -x /usr/local/lsws/bin/lswsctrl ]]; then
    cecho info "检测到已安装 OpenLiteSpeed，将复用现有安装。"
    return 0
  fi

  cecho warn "未检测到 OpenLiteSpeed，是否现在自动安装？"
  read -r -p "输入 y 继续自动安装，其他任意键取消: " ans || true
  if [[ "${ans,,}" != "y" ]]; then
    cecho error "未安装 OLS，本模块无法继续。"
    exit 1
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    cecho error "当前系统非 Debian / Ubuntu，自动安装 OLS 暂未实现，请手动安装后重试。"
    exit 1
  fi

  cecho info "安装 OLS 所需依赖..."
  apt-get update
  apt-get install -y curl ca-certificates gnupg lsb-release

  if [[ ! -f /etc/apt/sources.list.d/lst_debian_repo.list ]]; then
    cecho info "添加 LiteSpeed 官方仓库..."
    curl -fsSL https://repo.litespeed.sh | bash || {
      cecho error "添加 LiteSpeed 仓库失败，请检查网络。"
      exit 1
    }
  fi

  cecho info "安装 openlitespeed + lsphp..."
  apt-get install -y openlitespeed lsphp83

  cecho info "启动并设置开机自启..."
  /usr/local/lsws/bin/lswsctrl start || true
  systemctl enable lsws || true

  cecho info "OpenLiteSpeed 安装完成。"
}

#####################################
# 3. DB 连接测试
#####################################

test_db_connection() {
  local host="$1" port="$2" user="$3" pass="$4" db="$5"

  cecho info "测试数据库连接：${user}@${host}:${port}，数据库：${db}"
  if ! command -v mysql >/dev/null 2>&1; then
    cecho error "未检测到 mysql 客户端，请先安装（例如 apt-get install -y mariadb-client）。"
    exit 1
  fi

  if MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -e "USE \`$db\`;" >/dev/null 2>&1; then
    cecho info "数据库连接测试成功。"
  else
    cecho error "数据库连接失败，请检查：DB 主机 / 端口 / 用户名 / 密码 / 数据库名 是否正确。"
    exit 1
  fi
}

#####################################
# 4. SALT 生成
#####################################

generate_wp_salts() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ || return 1
  else
    return 1
  fi
}

#####################################
# 5. 配置 OLS vhost + listener
#####################################

configure_ols_vhost_and_listener() {
  local slug="$1" domain="$2" ssl_mode="$3" ssl_key="$4" ssl_cert="$5"

  local lsws_dir="/usr/local/lsws"
  local httpd_conf="${lsws_dir}/conf/httpd_config.conf"
  local vhost_dir="${lsws_dir}/conf/vhosts/${slug}"
  local vhconf="${vhost_dir}/vhconf.conf"

  if [[ ! -f "$httpd_conf" ]]; then
    cecho error "未找到 $httpd_conf，OLS 配置目录不符合预期。"
    exit 1
  fi

  mkdir -p "$vhost_dir"

  cecho info "写入 Virtual Host 配置：${vhconf}"
  cat > "$vhconf" <<EOF
docRoot                   /var/www/${slug}/html/
vhRoot                    /var/www/${slug}/
enableGzip                1
enableIpGeo               0

errorlog logs/${slug}_error.log {
  useServer               0
  logLevel                NOTICE
  rollingSize             10M
}

accesslog logs/${slug}_access.log {
  useServer               0
  logHeaders              3
  rollingSize             10M
  keepDays                7
}

index  {
  useServer               0
  indexFiles              index.php,index.html
}

context / {
  type                    root
  location                /
  allowBrowse             1
}

phpIniOverride  {
}
EOF

  # virtualhost 块
  if ! grep -q "virtualhost ${slug} " "$httpd_conf"; then
    cecho info "在 httpd_config.conf 中注册 virtualhost ${slug} ..."
    cat >> "$httpd_conf" <<EOF

virtualhost ${slug} {
  vhRoot                  /var/www/${slug}/
  configFile              conf/vhosts/${slug}/vhconf.conf
  allowSymbolLink         1
  enableScript            1
  restrained              1
}
EOF
  fi

  # HTTP listener
  if ! grep -q "listener ${slug}-HTTP" "$httpd_conf"; then
    cecho info "新增 HTTP listener ${slug}-HTTP 监听 *:80 ..."
    cat >> "$httpd_conf" <<EOF

listener ${slug}-HTTP {
  address                 *:80
  secure                  0
  map                     ${slug} ${domain}
}
EOF
  fi

  # HTTPS listener（按需）
  if [[ "$ssl_mode" != "1" ]]; then
    if ! grep -q "listener ${slug}-HTTPS" "$httpd_conf"; then
      cecho info "新增 HTTPS listener ${slug}-HTTPS 监听 *:443 ..."
      cat >> "$httpd_conf" <<EOF

listener ${slug}-HTTPS {
  address                 *:443
  secure                  1
  keyFile                 ${ssl_key}
  certFile                ${ssl_cert}
  map                     ${slug} ${domain}
}
EOF
    fi
  else
    cecho warn "本次未配置 SSL，仅创建 HTTP listener。"
  fi

  cecho info "重启 OpenLiteSpeed 以应用新配置..."
  if command -v lswsctrl >/dev/null 2>&1; then
    lswsctrl restart || true
  else
    systemctl restart lsws || true
  fi

  cecho info "Virtual Host + listener 配置完成。"
}

#####################################
# 6. 安装 / 修复 OLS + WP（单站）
#####################################

install_ols_wp() {
  env_check
  ensure_ols_installed

  echo
  cecho info "Step 2/4：收集站点基本信息"

  local slug domain
  read -r -p "请输入站点代号（slug，例如 ols 或 blog，不含空格）: " slug
  if [[ -z "$slug" ]]; then
    cecho error "slug 不能为空。"
    return 1
  fi

  read -r -p "请输入站点域名（例如 ols.example.com）: " domain
  if [[ -z "$domain" ]]; then
    cecho error "域名不能为空。"
    return 1
  fi

  local wp_root="/var/www/${slug}/html"
  mkdir -p "$wp_root"

  echo
  cecho info "Step 3/4：数据库信息（请提前在 DB 宿主机创建好库和用户）"
  echo "  建议命名示例："
  echo "    数据库名：${slug}_wp"
  echo "    用户名：  ${slug}_user"
  echo

  local db_host db_port db_name db_user db_pass
  read -r -p "DB 主机（Host，例如 127.0.0.1 或 Tailscale IP）: " db_host
  db_host="${db_host:-127.0.0.1}"

  read -r -p "DB 端口（Port，默认 3306）: " db_port
  db_port="${db_port:-3306}"

  read -r -p "DB 数据库名（例如 ${slug}_wp，必须已存在）: " db_name
  if [[ -z "$db_name" ]]; then
    cecho error "数据库名不能为空。"
    return 1
  fi

  read -r -p "DB 用户名（例如 ${slug}_user）: " db_user
  if [[ -z "$db_user" ]]; then
    cecho error "DB 用户名不能为空。"
    return 1
  fi

  read -r -s -p "DB 密码（输入时不显示）: " db_pass
  echo
  if [[ -z "$db_pass" ]]; then
    cecho error "DB 密码不能为空。"
    return 1
  fi

  test_db_connection "$db_host" "$db_port" "$db_user" "$db_pass" "$db_name"

  echo
  cecho info "Step 4/4：选择 SSL 模式"
  echo "  1) 暂时仅 HTTP（先调试，以后自己配置 SSL）"
  echo "  2) 使用 Cloudflare Origin Certificate（已在 CF 后台生成）"
  echo "  3) 使用 Let’s Encrypt 自动申请和续期（需确保 80 公网可访问）"
  read -r -p "请选择 [1-3]（默认 1）: " ssl_choice
  ssl_choice="${ssl_choice:-1}"
  if [[ "$ssl_choice" != "1" && "$ssl_choice" != "2" && "$ssl_choice" != "3" ]]; then
    cecho warn "无效输入，默认选择 1（仅 HTTP）。"
    ssl_choice="1"
  fi

  local ssl_key_file="" ssl_cert_file=""

  if [[ "$ssl_choice" == "2" ]]; then
    cecho info "请先在 Cloudflare → SSL/TLS → Origin Certificates 为 ${domain} 生成 key/cert。"
    read -r -p "请输入本机保存的 key 文件路径（例如 /etc/ssl/private/${slug}.key）: " ssl_key_file
    read -r -p "请输入本机保存的 cert 文件路径（例如 /etc/ssl/certs/${slug}.crt）: " ssl_cert_file
    if [[ ! -f "$ssl_key_file" || ! -f "$ssl_cert_file" ]]; then
      cecho error "找不到 key 或 cert 文件，请确认路径。"
      return 1
    fi
  elif [[ "$ssl_choice" == "3" ]]; then
    cecho info "将使用 Let’s Encrypt 申请证书：${domain}"
    cecho warn "请确认："
    cecho warn "  1) DNS 已有 A 记录指向当前机器 IPv4；"
    cecho warn "  2) 该记录暂时设为 DNS only（关闭 CF 橙云代理）；"
    pause

    if ! command -v certbot >/dev/null 2>&1; then
      cecho info "安装 certbot..."
      apt-get update
      apt-get install -y certbot
    fi

    cecho info "停止 OLS，使用 standalone 模式在 80 端口完成验证..."
    systemctl stop lsws || true

    if ! certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "admin@${domain}"; then
      cecho error "Let’s Encrypt 申请失败，请检查域名解析 / 80 端口连通性。"
      systemctl start lsws || true
      return 1
    fi

    systemctl start lsws || true

    ssl_key_file="/etc/letsencrypt/live/${domain}/privkey.pem"
    ssl_cert_file="/etc/letsencrypt/live/${domain}/fullchain.pem"

    if [[ ! -f "$ssl_key_file" || ! -f "$ssl_cert_file" ]]; then
      cecho error "未找到 Let’s Encrypt 证书文件，请检查 certbot 输出。"
      return 1
    fi

    cecho info "Let’s Encrypt 证书申请完成，certbot 已配置自动续期。"
  fi

  echo
  cecho info "下载并部署 WordPress 到 ${wp_root} ..."

  local tmp_zip="/tmp/latest-wp.zip"
  apt-get update >/dev/null 2>&1 || true
  apt-get install -y curl unzip >/dev/null 2>&1 || true

  curl -fsSL https://wordpress.org/latest.zip -o "$tmp_zip"
  rm -rf "${wp_root}"/*
  rm -rf /tmp/wp-install-tmp
  mkdir -p /tmp/wp-install-tmp
  unzip -q "$tmp_zip" -d /tmp/wp-install-tmp
  mv /tmp/wp-install-tmp/wordpress/* "$wp_root"/
  rm -rf /tmp/wp-install-tmp "$tmp_zip"

  cecho info "生成 wp-config.php ..."
  local wp_config="${wp_root}/wp-config.php"
  cp "${wp_root}/wp-config-sample.php" "$wp_config"

  sed -i "s/database_name_here/${db_name}/" "$wp_config"
  sed -i "s/username_here/${db_user}/"      "$wp_config"
  sed -i "s/password_here/${db_pass}/"      "$wp_config"
  sed -i "s/localhost/${db_host}/"          "$wp_config"

  if [[ "$db_port" != "3306" ]]; then
    sed -i "/DB_HOST/s/'${db_host}'/'${db_host}:${db_port}'/" "$wp_config"
  fi

  # SALT
  local salts
  if salts="$(generate_wp_salts)"; then
    sed -i "/AUTH_KEY/d;/SECURE_AUTH_KEY/d;/LOGGED_IN_KEY/d;/NONCE_KEY/d;/AUTH_SALT/d;/SECURE_AUTH_SALT/d;/LOGGED_IN_SALT/d;/NONCE_SALT/d" "$wp_config"
    printf "%s\n" "$salts" >> "$wp_config"
  else
    cecho warn "无法从官方获取 SALT，暂保留样例 SALT（安全性略低，建议后续手动替换）。"
  fi

  # 权限
  if id nobody >/dev/null 2>&1; then
    chown -R nobody:nogroup "/var/www/${slug}"
  fi
  find "/var/www/${slug}" -type d -exec chmod 755 {} \;
  find "/var/www/${slug}" -type f -exec chmod 644 {} \;

  # 配置 OLS
  configure_ols_vhost_and_listener "$slug" "$domain" "$ssl_choice" "$ssl_key_file" "$ssl_cert_file"

  # 探测公网 IP（仅做参考）
  local ipv4 ipv6
  ipv4="$(curl -s4 https://ifconfig.co 2>/dev/null || true)"
  ipv6="$(curl -s6 https://ifconfig.co 2>/dev/null || true)"

  echo
  echo "======================================================="
  cecho info "安装流程完成（注意：外网是否能访问，还取决于 DNS / 代理 / 端口）"
  echo
  echo "  站点 slug：      ${slug}"
  echo "  站点域名：        ${domain}"
  echo "  WordPress 路径：  /var/www/${slug}/html"
  echo
  echo "  DB_HOST：        ${db_host}"
  echo "  DB_PORT：        ${db_port}"
  echo "  DB_NAME：        ${db_name}"
  echo "  DB_USER：        ${db_user}"
  echo
  echo "  公网 IPv4（仅供参考）：${ipv4:-获取失败}"
  echo "  公网 IPv6（仅供参考）：${ipv6:-获取失败}"
  echo
  cecho warn "建议调试顺序："
  echo "  1) 只配 A 记录 → 当前机器 IPv4，先用 http://${domain} 测试；"
  echo "  2) 确认 HTTP 正常后，再按需添加 AAAA 记录和 Cloudflare 代理；"
  echo "  3) 如已配置 SSL，再把 Cloudflare SSL/TLS 模式设为 Full (strict)。"
  echo "======================================================="

  cecho info "本轮安装结束，你可以选择继续在当前菜单做其它操作，或选 0 退出。"
}

#####################################
# 7. 清理本机 OLS / WordPress
#####################################

cleanup_ols() {
  cecho warn "即将【彻底移除本机 OLS】："
  echo "  - 停止 lsws/openlitespeed 服务"
  echo "  - apt remove/purge openlitespeed 和 lsphp*"
  echo "  - 删除 /usr/local/lsws"
  echo
  read -r -p "如确认，请输入 'remove-ols' 然后回车（其他输入取消）: " confirm || true
  if [[ "$confirm" != "remove-ols" ]]; then
    cecho warn "取消移除 OLS。"
    return 0
  fi

  systemctl stop lsws      >/dev/null 2>&1 || true
  systemctl stop openlitespeed >/dev/null 2>&1 || true
  apt-get remove --purge -y openlitespeed lsphp* || true
  rm -rf /usr/local/lsws

  cecho info "已尝试卸载 OLS（如有残留，可手动检查 /usr/local/lsws）。"
  pause
}

cleanup_wp_site() {
  cecho info "按 slug 清理本机 WordPress 站点"

  local slug root
  read -r -p "请输入要清理的站点 slug（例如 ols 或 blog）: " slug
  if [[ -z "$slug" ]]; then
    cecho warn "slug 不能为空。"
    pause
    return 0
  fi

  root="/var/www/${slug}"
  if [[ ! -d "$root" ]]; then
    cecho warn "目录 ${root} 不存在，本机似乎没有该站点。"
    pause
    return 0
  fi

  echo
  echo "将删除目录：${root}"
  echo "并尝试删除与该 slug 相关的 OLS vhost 配置。"
  read -r -p "如确认，请再次输入 slug '${slug}' 然后回车（其他输入取消）: " confirm || true
  if [[ "$confirm" != "$slug" ]]; then
    cecho warn "slug 不匹配，取消本次清理。"
    pause
    return 0
  fi

  rm -rf "$root"
  cecho info "已删除站点目录：${root}"

  local httpd_conf="/usr/local/lsws/conf/httpd_config.conf"
  local vhost_dir="/usr/local/lsws/conf/vhosts/${slug}"

  if [[ -d "$vhost_dir" ]]; then
    rm -rf "$vhost_dir"
    cecho info "已删除 vhost 目录：${vhost_dir}"
  fi

  if [[ -f "$httpd_conf" ]]; then
    # 删除 virtualhost、listener 段和 map
    sed -i "/virtualhost ${slug} /,/^}/d" "$httpd_conf" 2>/dev/null || true
    sed -i "/listener ${slug}-HTTP /,/^}/d" "$httpd_conf" 2>/dev/null || true
    sed -i "/listener ${slug}-HTTPS /,/^}/d" "$httpd_conf" 2>/dev/null || true
    sed -i "/map \+${slug} /d" "$httpd_conf" 2>/dev/null || true
    sed -i "/map \+${slug} ${slug}/d" "$httpd_conf" 2>/dev/null || true
  fi

  # 重启 OLS
  if command -v lswsctrl >/dev/null 2>&1; then
    lswsctrl restart || true
  else
    systemctl restart lsws || true
  fi

  cecho info "已尽量清理与该 slug 相关的 OLS 配置。"
  pause
}

cleanup_menu() {
  while true; do
    show_header
    echo ">>> 清理本机 OLS / WordPress"
    echo
    echo "  1) 彻底移除本机 OLS（卸载 openlitespeed + lsphp*，删除 /usr/local/lsws）"
    echo "  2) 按 slug 清理本机某个 WordPress 站点（/var/www/<slug> + OLS vhost）"
    echo "  3) 返回上一层菜单"
    echo "  0) 退出脚本"
    echo
    read -r -p "请输入选项并按回车: " c || true
    case "${c:-3}" in
      1) cleanup_ols ;;
      2) cleanup_wp_site ;;
      3) break ;;
      0) cecho info "再见～"; exit 0 ;;
      *) cecho warn "无效选项。"; pause ;;
    esac
  done
}

#####################################
# 8. 主菜单（循环，不会“闪一下就退出”）
#####################################

main_menu() {
  ensure_root

  while true; do
    show_header
    echo "菜单选项 / Menu options"
    echo "  1) 安装 / 修复 单站 OLS + WordPress（标准模式）"
    echo "  2) 仅做环境自检（端口 / 防火墙 / 云厂商安全组提示）"
    echo "  3) 清理本机 OLS / WordPress"
    echo "  0) 退出脚本"
    echo
    read -r -p "请输入选项并按回车: " choice || true
    case "${choice:-0}" in
      1)
        install_ols_wp || cecho error "本轮安装流程出现错误，请根据提示排查。"
        pause
        ;;
      2)
        env_check
        pause
        ;;
      3)
        cleanup_menu
        ;;
      0)
        cecho info "再见～"
        exit 0
        ;;
      *)
        cecho warn "无效选项，请重新输入。"
        pause
        ;;
    esac
  done
}

main_menu
