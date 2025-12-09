#!/usr/bin/env bash
#
# install-ols-wp-standard.sh
# Version: v0.11 (2025-12-09)
#
# Changelog v0.11
# - 新增“环境自检”：系统版本 / 端口监听 / UFW 提示 / 云厂商安全组提示
# - 统一站点路径为 /var/www/<slug>/html（不写死任何真实机器名或域名）
# - 在输入数据库信息后，实际用 mysql 测试连接和 USE <DB_NAME>，失败直接退出
# - 自动生成独立 OLS Virtual Host 和 listener（HTTP + 可选 HTTPS）
# - 支持 SSL 三选一：1) 仅 HTTP  2) Cloudflare Origin Cert  3) Let’s Encrypt
# - 结束时打印站点信息和 IPv4/IPv6，提醒去 DNS 配置
# - 清理功能本版只给安全提示，不自动删除任何文件，避免误删
#

set -euo pipefail

SCRIPT_VERSION="v0.11"

# 彩色输出
cecho() { # $1=level info/warn/error, $2=message
  local level="$1"; shift || true
  local msg="$*"
  case "$level" in
    info)  printf "\033[1;32m[INFO]\033[0m %s\n" "$msg" ;;
    warn)  printf "\033[1;33m[WARN]\033[0m %s\n" "$msg" ;;
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
  echo "======================================================="
  echo "  OLS + WordPress 标准安装模块  ${SCRIPT_VERSION}"
  echo "======================================================="
  echo
}

###########################################################
# 1. 环境自检
###########################################################
env_check() {
  cecho info "Step 1/4：环境自检（系统版本 / 端口 / 防火墙 / 云厂商安全组）"

  # 系统信息
  local os=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os="${PRETTY_NAME:-}"
  fi
  cecho info "当前系统：${os:-未知}"

  # CPU / 内存
  local mem_total
  mem_total="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  cecho info "检测到内存约：${mem_total} MB"

  if (( mem_total < 2048 )); then
    cecho warn "当前内存 < 2G，不建议在本机同时跑 OLS + 数据库 + Redis。"
  elif (( mem_total < 4096 )); then
    cecho warn "当前内存 < 4G，建议数据库 / Redis 考虑使用其他高配实例，本机只跑 OLS + WordPress 前端或 LNMP。"
  fi

  echo
  cecho info "检查 80 / 443 端口监听情况（仅查看，不做修改）..."
  ss -lnpt '( sport = :80 or sport = :443 )' || true
  echo

  # 防火墙
  if command -v ufw >/dev/null 2>&1; then
    local ufw_status
    ufw_status="$(ufw status 2>/dev/null || true)"
    cecho info "UFW 状态："
    echo "$ufw_status"
    echo
    cecho warn "如 UFW 为 active，请确认已允许 80/tcp 和 443/tcp：例如"
    echo "  ufw allow 80/tcp"
    echo "  ufw allow 443/tcp"
  else
    cecho info "未检测到 UFW（或未启用），略过本机防火墙检查。"
  fi

  echo
  cecho warn "请务必确认：云厂商后台（安全组 / 安全列表等）已经放行 80 和 443 端口。"
  cecho warn "否则即使本机已监听端口，外网依然无法访问。"
  echo
}

###########################################################
# 2. 确保 OLS 已安装
###########################################################
ensure_ols_installed() {
  if command -v lswsctrl >/dev/null 2>&1 || [[ -x /usr/local/lsws/bin/lswsctrl ]]; then
    cecho info "检测到 OpenLiteSpeed 已安装，将复用现有安装。"
    return 0
  fi

  cecho warn "未检测到 OpenLiteSpeed，是否现在自动安装？"
  read -r -p "输入 y 继续自动安装，其他任意键取消: " ans || true
  if [[ "${ans,,}" != "y" ]]; then
    cecho error "未安装 OLS，本模块无法继续。"
    exit 1
  fi

  cecho info "开始安装 OpenLiteSpeed（官方仓库方式）..."

  # 只针对 Debian/Ubuntu 系列简单处理
  if ! command -v apt-get >/dev/null 2>&1; then
    cecho error "当前系统非 Debian/Ubuntu，自动安装 OLS 未实现，请手动安装后重试。"
    exit 1
  fi

  # 安装必要依赖
  apt-get update
  apt-get install -y curl ca-certificates gnupg lsb-release

  # LiteSpeed 官方 repo（简化写法，生产环境建议对照官方文档）
  if [[ ! -f /etc/apt/sources.list.d/lst_debian_repo.list ]]; then
    cecho info "添加 LiteSpeed 官方仓库..."
    curl -fsSL https://repo.litespeed.sh | bash || {
      cecho error "添加 LiteSpeed 仓库失败，请检查网络或稍后再试。"
      exit 1
    }
  fi

  cecho info "安装 openlitespeed 和 lsphp..."
  apt-get install -y openlitespeed lsphp83

  cecho info "启动并设置开机自启..."
  /usr/local/lsws/bin/lswsctrl start || true
  systemctl enable lsws || true

  cecho info "OpenLiteSpeed 安装步骤完成。"
}

###########################################################
# 3. 数据库连接测试
###########################################################
test_db_connection() {
  local host="$1" port="$2" user="$3" pass="$4" db="$5"

  cecho info "测试数据库连接：${user}@${host}:${port}，数据库：${db}"
  if ! command -v mysql >/dev/null 2>&1; then
    cecho error "未检测到 mysql 客户端，请先安装（例如 apt-get install -y mysql-client）。"
    exit 1
  fi

  # -e 'USE db' 可以同时验证连接和数据库是否存在
  if MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -e "USE \`$db\`;" >/dev/null 2>&1; then
    cecho info "数据库连接测试成功。"
  else
    cecho error "数据库连接失败，请检查：DB 主机 / 端口 / 用户名 / 密码 / 数据库名 是否正确。"
    cecho error "建议重新确认 wp-config.php、或直接在 DB 宿主机上用 mysql 命令测试。"
    exit 1
  fi
}

###########################################################
# 4. 生成随机 SALT
###########################################################
generate_wp_salts() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ || return 1
  else
    return 1
  fi
}

###########################################################
# 5. 配置 OLS vhost & listener
###########################################################
configure_ols_vhost_and_listener() {
  local slug="$1" domain="$2" ssl_mode="$3" ssl_key="$4" ssl_cert="$5"

  local lsws_dir="/usr/local/lsws"
  local httpd_conf="${lsws_dir}/conf/httpd_config.conf"
  local vhost_dir="${lsws_dir}/conf/vhosts/${slug}"
  local vhconf="${vhost_dir}/vhconf.conf"

  if [[ ! -f "$httpd_conf" ]]; then
    cecho error "未找到 ${httpd_conf}，OLS 配置目录不符合预期。"
    exit 1
  fi

  mkdir -p "$vhost_dir"

  cecho info "写入 Virtual Host 配置：${vhconf}"

  cat > "$vhconf" <<EOF
docRoot                   /var/www/${slug}/html/
vhRoot                    /var/www/${slug}/
configFile                conf/vhosts/${slug}/vhconf.conf
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

  # 在 httpd_config.conf 中增加 virtualhost 块（如不存在）
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
  else
    cecho warn "httpd_config.conf 中已存在 virtualhost ${slug}，跳过新增 virtualhost 段。"
  fi

  # 新增 HTTP listener（独立，避免动现有 listener）
  if ! grep -q "listener ${slug}-HTTP" "$httpd_conf"; then
    cecho info "新增 HTTP listener ${slug}-HTTP 监听 *:80 ..."
    cat >> "$httpd_conf" <<EOF

listener ${slug}-HTTP {
  address                 *:80
  secure                  0
  map                     ${slug} ${domain}
}
EOF
  else
    cecho warn "httpd_config.conf 中已存在 listener ${slug}-HTTP，跳过创建。"
  fi

  # 根据 ssl_mode 设置 HTTPS listener
  # ssl_mode: 1=无SSL  2=Cloudflare Origin Cert  3=Let's Encrypt
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
    else
      cecho warn "httpd_config.conf 中已存在 listener ${slug}-HTTPS，跳过创建。"
    fi
  else
    cecho warn "本次选择不配置 SSL，暂不创建 HTTPS listener。"
  fi

  cecho info "尝试重启 OpenLiteSpeed 应用新配置..."
  if command -v lswsctrl >/dev/null 2>&1; then
    lswsctrl restart || true
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl restart lsws || true
  fi

  cecho info "Virtual Host + listener 配置步骤完成。"
}

###########################################################
# 6. 主安装流程：OLS + WP
###########################################################
install_ols_wp() {
  env_check
  ensure_ols_installed

  echo
  cecho info "Step 2/4：收集站点基本信息"

  local slug domain
  read -r -p "请输入站点代号（slug，例如 ols-demo 或 blog，不含空格）: " slug
  if [[ -z "$slug" ]]; then
    cecho error "slug 不能为空。"
    exit 1
  fi

  read -r -p "请输入站点域名（例如 blog.example.com）: " domain
  if [[ -z "$domain" ]]; then
    cecho error "域名不能为空。"
    exit 1
  fi

  local wp_root="/var/www/${slug}/html"
  mkdir -p "$wp_root"

  echo
  cecho info "Step 3/4：数据库信息（请严格按照已存在的 DB 配置填写）"
  cecho warn "提示：这是“公共脚本”，不会帮你创建数据库和用户。请提前在 DB 宿主机创建："
  echo "  - 数据库（如 ${slug}_wp）"
  echo "  - 对应用户（如 ${slug}_user）并授予该库全部权限"
  echo

  local db_host db_port db_name db_user db_pass
  read -r -p "DB 主机（Host，例如 127.0.0.1 或 内网 / Tailscale IP）: " db_host
  db_host="${db_host:-127.0.0.1}"

  read -r -p "DB 端口（Port，默认 3306）: " db_port
  db_port="${db_port:-3306}"

  read -r -p "DB 数据库名（例如 ${slug}_wp，必须是已创建好的）: " db_name
  if [[ -z "$db_name" ]]; then
    cecho error "数据库名不能为空。"
    exit 1
  fi

  read -r -p "DB 用户名（例如 ${slug}_user）: " db_user
  if [[ -z "$db_user" ]]; then
    cecho error "DB 用户名不能为空。"
    exit 1
  fi

  read -r -s -p "DB 密码（输入时不显示）: " db_pass
  echo
  if [[ -z "$db_pass" ]]; then
    cecho error "DB 密码不能为空。"
    exit 1
  fi

  # 实测数据库连接
  test_db_connection "$db_host" "$db_port" "$db_user" "$db_pass" "$db_name"

  echo
  cecho info "Step 4/4：选择 SSL 模式"
  echo "  1) 暂时仅 HTTP（以后自己配置 SSL）"
  echo "  2) 使用 Cloudflare Origin Certificate（你已在 CF 生成 key/cert）"
  echo "  3) 使用 Let’s Encrypt 自动申请和续期（需确保 80 端口可被公网访问）"
  read -r -p "请选择 [1-3]（默认 1）: " ssl_choice
  ssl_choice="${ssl_choice:-1}"
  if [[ "$ssl_choice" != "1" && "$ssl_choice" != "2" && "$ssl_choice" != "3" ]]; then
    cecho warn "输入无效，默认选择 1（仅 HTTP）。"
    ssl_choice="1"
  fi

  local ssl_key_file=""
  local ssl_cert_file=""

  if [[ "$ssl_choice" == "2" ]]; then
    cecho info "请先在 Cloudflare 后台为 ${domain} 创建 Origin Certificate。"
    read -r -p "请输入保存到本机的 key 文件路径（例如 /etc/ssl/private/${slug}.key）: " ssl_key_file
    read -r -p "请输入保存到本机的 cert 文件路径（例如 /etc/ssl/certs/${slug}.crt）: " ssl_cert_file
    if [[ ! -f "$ssl_key_file" || ! -f "$ssl_cert_file" ]]; then
      cecho error "找不到 key 或 cert 文件，请确认路径。"
      exit 1
    fi
  elif [[ "$ssl_choice" == "3" ]]; then
    cecho info "将尝试通过 Let’s Encrypt (certbot) 为 ${domain} 申请证书。"
    cecho warn "请确认："
    cecho warn "  - DNS 已有 A 记录将 ${domain} 指向本机 IPv4"
    cecho warn "  - 暂时将此记录设为 DNS only（不经过 Cloudflare 代理），否则 HTTP-01 验证可能失败。"
    pause

    if ! command -v certbot >/dev/null 2>&1; then
      cecho info "安装 certbot..."
      apt-get update
      apt-get install -y certbot
    fi

    # 使用 standalone 模式占用 80 端口申请证书
    systemctl stop lsws || true
    cecho info "停止 OLS 后申请 Let’s Encrypt 证书..."
    certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "admin@${domain}" || {
      cecho error "Let’s Encrypt 申请失败，请检查域名解析和 80 端口连通性。"
      systemctl start lsws || true
      exit 1
    }
    systemctl start lsws || true

    ssl_key_file="/etc/letsencrypt/live/${domain}/privkey.pem"
    ssl_cert_file="/etc/letsencrypt/live/${domain}/fullchain.pem"

    if [[ ! -f "$ssl_key_file" || ! -f "$ssl_cert_file" ]]; then
      cecho error "未找到 Let’s Encrypt 生成的证书文件。"
      exit 1
    fi

    cecho info "Let’s Encrypt 证书申请完成。certbot 已自动配置续期。"
  fi

  echo
  cecho info "下载并部署 WordPress 到 ${wp_root} ..."

  # 下载 WP 最新版
  local tmp_zip="/tmp/latest-wp.zip"
  curl -fsSL https://wordpress.org/latest.zip -o "$tmp_zip"
  rm -rf "${wp_root}"/*
  unzip -q "$tmp_zip" -d /tmp/wp-install-tmp
  # 解压出来是 /tmp/wp-install-tmp/wordpress/*
  mv /tmp/wp-install-tmp/wordpress/* "$wp_root"/
  rm -rf /tmp/wp-install-tmp "$tmp_zip"

  cecho info "生成 wp-config.php ..."
  local wp_config="${wp_root}/wp-config.php"
  cp "${wp_root}/wp-config-sample.php" "$wp_config"

  # 替换数据库配置
  sed -i "s/database_name_here/${db_name}/" "$wp_config"
  sed -i "s/username_here/${db_user}/" "$wp_config"
  sed -i "s/password_here/${db_pass}/" "$wp_config"
  sed -i "s/localhost/${db_host}/" "$wp_config"

  # 设置 DB 端口（如非默认）
  if [[ "$db_port" != "3306" ]]; then
    # 通过定义常量方式指定端口
    sed -i "/DB_HOST/s/'${db_host}'/'${db_host}:${db_port}'/" "$wp_config"
  fi

  # 写入 SALT
  local salts
  if salts="$(generate_wp_salts)"; then
    sed -i "/AUTH_KEY/d;/SECURE_AUTH_KEY/d;/LOGGED_IN_KEY/d;/NONCE_KEY/d;/AUTH_SALT/d;/SECURE_AUTH_SALT/d;/LOGGED_IN_SALT/d;/NONCE_SALT/d" "$wp_config"
    printf "%s\n" "$salts" >> "$wp_config"
  else
    cecho warn "获取在线 SALT 失败，使用默认样例（安全性略低，建议后续手动替换）。"
  fi

  # 设置权限（以 nobody:nogroup 为例，可视环境调整）
  if id nobody >/dev/null 2>&1; then
    chown -R nobody:nogroup "/var/www/${slug}"
  fi
  find "/var/www/${slug}" -type d -exec chmod 755 {} \;
  find "/var/www/${slug}" -type f -exec chmod 644 {} \;

  # 配置 OLS vhost + listener
  configure_ols_vhost_and_listener "$slug" "$domain" "$ssl_choice" "$ssl_key_file" "$ssl_cert_file"

  # 尝试探测 IPv4/IPv6
  local ipv4 ipv6
  ipv4="$(curl -s4 https://ifconfig.co 2>/dev/null || true)"
  ipv6="$(curl -s6 https://ifconfig.co 2>/dev/null || true)"

  echo
  echo "======================================================="
  cecho info "安装流程完成（不代表外网一定能直接访问，请按下列信息检查）："
  echo
  echo "  站点 slug：      ${slug}"
  echo "  站点域名：        ${domain}"
  echo "  WordPress 路径： /var/www/${slug}/html"
  echo "  DB_HOST：        ${db_host}"
  echo "  DB_PORT：        ${db_port}"
  echo "  DB_NAME：        ${db_name}"
  echo "  DB_USER：        ${db_user}"
  echo
  echo "  系统探测到的公网 IPv4（仅供参考）：${ipv4:-获取失败}"
  echo "  系统探测到的公网 IPv6（仅供参考）：${ipv6:-获取失败}"
  echo
  cecho warn "请在域名 DNS 里："
  echo "  1) 先只添加 A 记录 → 本机 IPv4，类型设为 DNS only 做联通性测试；"
  echo "  2) 使用 http://${domain} 测试站点是否可以正常打开；"
  echo "  3) 确认无误后，再按需添加 AAAA 记录和 Cloudflare 代理（橙云）；"
  echo "  4) 如本次脚本已配置 SSL，再把 Cloudflare SSL/TLS 模式设为 Full (strict)。"
  echo "======================================================="
}

###########################################################
# 7. 清理功能（本版只提示，不自动删除）
###########################################################
cleanup_notice() {
  echo
  cecho warn "【重要】为了避免误删，本版本不会自动删除任何 OLS / WordPress / DB / Redis。"
  echo
  echo "建议手动清理的大致步骤（示意）："
  echo "  1) 备份："
  echo "     - 导出对应数据库（mysqldump ...）"
  echo "     - 备份站点目录（/var/www/<slug>）"
  echo "  2) 删除站点文件："
  echo "     - rm -rf /var/www/<slug>"
  echo "  3) 如要移除 vhost："
  echo "     - 编辑 /usr/local/lsws/conf/httpd_config.conf，删除对应 virtualhost 和 listener 段"
  echo "     - 删除 /usr/local/lsws/conf/vhosts/<slug> 目录"
  echo "     - 重启 lsws"
  echo "  4) 数据库 / Redis 清理："
  echo "     - 在 DB 宿主机上 DROP DATABASE / DROP USER"
  echo "     - Redis 可根据业务手动 FLUSHDB / 删除 key"
  echo
  cecho warn "等我们把标准安装路径完全验证稳定后，再添加真正的自动清理功能。"
}

###########################################################
# 8. 主菜单
###########################################################
main_menu() {
  ensure_root
  show_header

  echo "菜单选项 / Menu options"
  echo "  1) 安装 / 修复 单站 OLS + WordPress（标准模式）"
  echo "  2) 仅做环境自检（端口 / 防火墙 / 云厂商安全组提示）"
  echo "  3) 查看“如何手动清理本机 OLS / WordPress / DB/Redis”的安全说明"
  echo "  0) 退出"
  echo

  read -r -p "请输入选项并按回车: " choice || true
  case "$choice" in
    1) install_ols_wp ;;
    2) env_check ;;
    3) cleanup_notice ;;
    0) echo "再见～"; exit 0 ;;
    *) cecho error "无效选项。"; exit 1 ;;
  esac
}

main_menu
