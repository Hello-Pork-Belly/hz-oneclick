#!/usr/bin/env bash
set -Eeo pipefail
cd /

# 颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
BOLD="\033[1m"
NC="\033[0m"

SCRIPT_NAME="install-ols-wp-standard.sh"
SCRIPT_VERSION="0.7"

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}==== $* ====${NC}\n"; }

trap 'log_error "脚本执行中断（行号: $LINENO）。"; exit 1' ERR

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 root 运行本脚本。"
    exit 1
  fi
}

check_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu)
        :
        ;;
      *)
        log_warn "检测到系统为 $PRETTY_NAME，本脚本主要针对 Ubuntu 22.04/24.04 设计。"
        ;;
    esac
  fi
}

detect_ram_mb() {
  awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo
}

# 尝试探测公网 IP（优先 curl，其次本机网卡，过滤内网 / Tailscale）
detect_public_ip() {
  local ipv4 ipv6
  ipv4="$(curl -4s --max-time 5 https://ifconfig.me || true)"
  if ! echo "$ipv4" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    ipv4=""
  fi

  if [ -z "$ipv4" ]; then
    ipv4="$(ip -4 -o addr show 2>/dev/null | awk '!/ lo /{print $4}' | cut -d/ -f1 | while read -r ip; do
      case "$ip" in
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|127.*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
          continue
          ;;
        *)
          echo "$ip"
          break
          ;;
      esac
    done)"
  fi

  ipv6="$(curl -6s --max-time 5 https://ifconfig.me || true)"
  if ! echo "$ipv6" | grep -qiE '^[0-9a-f:]+$'; then
    ipv6=""
  fi
  if [ -z "$ipv6" ]; then
    ipv6="$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  fi

  SERVER_IPV4="$ipv4"
  SERVER_IPV6="$ipv6"
}

# 内存不足提示 + LNMP 占位
memory_menu_if_low() {
  local ram_mb choice
  ram_mb="$(detect_ram_mb)"

  if [ -z "$ram_mb" ]; then
    log_warn "无法检测内存大小，跳过低内存提示。"
    return
  fi

  if [ "$ram_mb" -lt 3800 ]; then
    log_warn "当前机器内存约为 ${ram_mb}MB。"
    echo -e "${YELLOW}[WARN] 当前机器内存 < 4G，建议数据库 / Redis 使用其他高配机器实例，${NC}"
    echo -e "${YELLOW}       本机只跑 OLS + WordPress 前端，或者改为跑 LNMP。${NC}"
    echo
    echo "请选择："
    echo "  1) 继续当前机器仅安装 OLS + WordPress 前端（数据库/Redis 使用其他高配实例）"
    echo "  2) 改为 LNMP（占位：后续一键 LNMP 模块完成后自动跳转）"
    echo "  3) 返回 / 退出脚本"
    echo

    read -rp "请输入数字 [1-3，默认: 1]: " choice
    choice="${choice:-1}"

    case "$choice" in
      1)
        log_info "继续 OLS + WordPress 前端安装。"
        ;;
      2)
        log_warn "LNMP 模块尚未集成，本版本仅做提示，请稍后使用 LNMP 专用一键脚本。"
        exit 0
        ;;
      3)
        log_info "用户选择退出。"
        exit 0
        ;;
      *)
        log_warn "无效输入，默认继续 OLS + WordPress 前端安装。"
        ;;
    esac
  fi
}

prompt_site_info() {
  echo
  echo "================ 站点基础信息 ================"
  while :; do
    read -rp "请输入站点域名（例如: example.com 或 blog.example.com）: " SITE_DOMAIN
    if [ -n "$SITE_DOMAIN" ]; then
      break
    fi
    log_warn "域名不能为空。"
  done`

  read -rp "请输入站点 Slug（仅小写字母/数字，例如: ols，默认: 取域名第一个字段）: " SITE_SLUG
  if [ -z "$SITE_SLUG" ]; then
    SITE_SLUG="${SITE_DOMAIN%%.*}"
    SITE_SLUG="${SITE_SLUG//[^a-zA-Z0-9]/}"
    SITE_SLUG="$(echo "$SITE_SLUG" | tr 'A-Z' 'a-z')"
  fi

  if [ -z "$SITE_SLUG" ]; then
    SITE_SLUG="wpsite"
  fi

  DOC_ROOT="/var/www/${SITE_SLUG}/html"

  log_info "站点域名: ${SITE_DOMAIN}"
  log_info "站点 Slug: ${SITE_SLUG}"
  log_info "站点根目录: ${DOC_ROOT}"
}

prompt_db_info() {
  echo
  echo "================ 数据库设置（必须已在目标 DB 实例中创建） ================"
  echo "请注意：本脚本不会在远程数据库上自动创建库/用户。"
  echo "请先在你的数据库实例中『手动』创建好："
  echo "  - 独立数据库，例如：${SITE_SLUG}_wp"
  echo "  - 独立数据库用户，例如：${SITE_SLUG}_user，并分配该库全部权限"
  echo

  while :; do
    read -rp "DB Host（可带端口，例如: 100.82.140.65:3306）: " DB_HOST
    if [ -n "$DB_HOST" ]; then
      break
    fi
    log_warn "DB Host 不能为空。"
  done

  while :; do
    read -rp "DB 名称（必须与已创建数据库名称完全一致，例如: ${SITE_SLUG}_wp）: " DB_NAME
    if [ -n "$DB_NAME" ]; then
      break
    fi
    log_warn "DB 名称不能为空。"
  done

  while :; do
    read -rp "DB 用户名（必须与已创建的数据库用户一致，例如: ${SITE_SLUG}_user）: " DB_USER
    if [ -n "$DB_USER" ]; then
      break
    fi
    log_warn "DB 用户名不能为空。"
  done

  while :; do
    read -rsp "DB 密码（不会回显，请确保与该 DB 用户在数据库中的密码一致）: " DB_PASSWORD
    echo
    if [ -n "$DB_PASSWORD" ]; then
      break
    fi
    log_warn "DB 密码不能为空。"
  done

  log_info "数据库信息将写入 wp-config.php，请确保以上信息真实可用。"
}

install_packages() {
  log_step "安装 OpenLiteSpeed 与 PHP 组件"

  apt update
  apt install -y software-properties-common curl

  if ! command -v openlitespeed >/dev/null 2>&1; then
    log_info "安装 openlitespeed..."
    apt install -y openlitespeed
  else
    log_info "openlitespeed 已安装，跳过。"
  fi

  # PHP 版本：以 8.3 为主，如有需要可调整
  if ! dpkg -l | grep -q 'lsphp83'; then
    log_info "安装 lsphp83 及常用扩展..."
    apt install -y lsphp83 lsphp83-mysql lsphp83-common lsphp83-curl lsphp83-xml lsphp83-zip
  else
    log_info "lsphp83 已安装，跳过。"
  fi

  # 保证 systemd 服务启用
  systemctl enable lsws >/dev/null 2>&1 || true
  systemctl restart lsws
}

setup_vhost_config() {
  log_step "配置 OpenLiteSpeed Virtual Host"

  local LSWS_ROOT="/usr/local/lsws"
  local HTTPD_CONF="${LSWS_ROOT}/conf/httpd_config.conf"
  local VH_CONF_DIR="${LSWS_ROOT}/conf/vhosts/${SITE_SLUG}"
  local VH_CONF_FILE="${VH_CONF_DIR}/vhconf.conf"
  local VH_ROOT="/var/www/${SITE_SLUG}"

  if [ ! -d "$LSWS_ROOT" ]; then
    log_error "未找到 ${LSWS_ROOT}，请确认 openlitespeed 安装成功。"
    exit 1
  fi

  mkdir -p "$VH_CONF_DIR"
  mkdir -p "$DOC_ROOT"

  # virtualhost 块
  if ! grep -q "virtualhost ${SITE_SLUG}" "$HTTPD_CONF"; then
    cat >>"$HTTPD_CONF" <<EOF

virtualhost ${SITE_SLUG} {
  vhRoot                  ${VH_ROOT}/
  configFile              conf/vhosts/${SITE_SLUG}/vhconf.conf
  allowSymbolLink         1
  enableScript            1
  restrained              0
}
EOF
    log_info "已在 httpd_config.conf 中添加 virtualhost ${SITE_SLUG} 定义。"
  else
    log_info "virtualhost ${SITE_SLUG} 已存在，跳过新增。"
  fi

  # vhost 配置文件
  if [ ! -f "$VH_CONF_FILE" ]; then
    cat >"$VH_CONF_FILE" <<EOF
docRoot                   \$VH_ROOT/html/
enableGzip                1

index  {
  useServer               0
  indexFiles              index.php, index.html, index.htm
}

errorlog ${VH_ROOT}/logs/error.log {
  logLevel                ERROR
  useServer               0
}

accesslog ${VH_ROOT}/logs/access.log {
  useServer               0
  logHeaders              1
  rollingSize             10M
  keepDays                7
  compressArchive         1
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
}

context / {
  allowBrowse             1
}
EOF
    mkdir -p "${VH_ROOT}/logs"
    log_info "已生成 vhost 配置文件：${VH_CONF_FILE}"
  else
    log_info "vhost 配置文件已存在：${VH_CONF_FILE}"
  fi

  # 配置 HTTP 监听器（80）
  if ! grep -q "^listener http " "$HTTPD_CONF"; then
    cat >>"$HTTPD_CONF" <<EOF

listener http {
  address                 *:80
  secure                  0
  map                     ${SITE_SLUG} ${SITE_DOMAIN}
}
EOF
    log_info "已创建 listener http 并映射到 ${SITE_SLUG} / ${SITE_DOMAIN}。"
  else
    if ! awk "/^listener http /,/^}/" "$HTTPD_CONF" | grep -q "map[[:space:]]\+${SITE_SLUG}[[:space:]]\+${SITE_DOMAIN}"; then
      # 在 http listener 块中追加 map 行
      awk -v vh="${SITE_SLUG}" -v dom="${SITE_DOMAIN}" '
        BEGIN{in_http=0}
        {
          if($1=="listener" && $2=="http"){
            in_http=1
          }
          if(in_http && $0 ~ /^}/){
            printf("  map                     %s %s\n", vh, dom)
            in_http=0
          }
          print
        }
      ' "$HTTPD_CONF" > "${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"
      log_info "已在 listener http 中追加 map ${SITE_SLUG} ${SITE_DOMAIN}。"
    else
      log_info "listener http 中已存在 ${SITE_SLUG} / ${SITE_DOMAIN} 映射。"
    fi
  fi

  systemctl restart lsws
}

download_wordpress() {
  log_step "下载并部署 WordPress"

  if [ -f "${DOC_ROOT}/wp-config.php" ]; then
    log_warn "检测到 ${DOC_ROOT}/wp-config.php 已存在，将跳过 WordPress 文件下载，仅检查配置。"
    return
  fi

  mkdir -p "$DOC_ROOT"
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null

  log_info "从官方源下载 WordPress..."
  curl -fsSL https://wordpress.org/latest.tar.gz -o wordpress.tar.gz
  tar -xzf wordpress.tar.gz

  if [ ! -d wordpress ]; then
    log_error "解压 WordPress 失败。"
    popd >/dev/null
    rm -rf "$tmpdir"
    exit 1
  fi

  cp -a wordpress/. "$DOC_ROOT"/

  popd >/dev/null
  rm -rf "$tmpdir"

  log_info "WordPress 已部署到 ${DOC_ROOT}。"
}

generate_wp_config() {
  log_step "生成 wp-config.php"

  local wp_config="${DOC_ROOT}/wp-config.php"
  local sample="${DOC_ROOT}/wp-config-sample.php"

  if [ -f "$wp_config" ]; then
    log_warn "检测到已存在 wp-config.php，将不覆盖。请手动确认其中 DB_* 配置是否与本次输入一致。"
    return
  fi

  if [ ! -f "$sample" ]; then
    log_error "未找到 ${sample}，无法生成 wp-config.php。"
    exit 1
  fi

  cp "$sample" "$wp_config"

  sed -i "s/database_name_here/${DB_NAME}/" "$wp_config"
  sed -i "s/username_here/${DB_USER}/" "$wp_config"
  sed -i "s/password_here/${DB_PASSWORD}/" "$wp_config"
  sed -i "s/localhost/${DB_HOST}/" "$wp_config"

  # 保留 WordPress 默认 salt 占位符；如需自动生成，可后续扩展。

  log_info "已根据输入生成 wp-config.php。"
}

configure_ssl() {
  log_step "处理 SSL / HTTPS（可选）"

  local choice
  echo "请选择 HTTPS 方案："
  echo "  1) 暂不配置 SSL，仅使用 HTTP 80（适合先确认站点正常，再配置 HTTPS）"
  echo "  2) 使用 Cloudflare Origin Certificate（手动粘贴证书和私钥）"
  echo "  3) 使用 Let’s Encrypt 自动申请证书（需域名指向本机，且暂时设为 DNS only / 灰云）"
  echo

  read -rp "请输入数字 [1-3，默认: 1]: " choice
  choice="${choice:-1}"

  local LSWS_ROOT="/usr/local/lsws"
  local HTTPD_CONF="${LSWS_ROOT}/conf/httpd_config.conf"

  case "$choice" in
    1)
      log_warn "本次安装暂不配置 SSL，仅监听 80 端口。"
      log_warn "如你在 Cloudflare 中使用 Full (strict)，请注意：源站无证书会导致 521。"
      ;;

    2)
      log_info "你选择 Cloudflare Origin Certificate。"
      log_info "请先在 Cloudflare 为当前域名生成 Origin Certificate，复制证书和私钥。"

      local cert_file key_file
      read -rp "请输入证书保存路径（例如: /usr/local/lsws/conf/ssl/${SITE_SLUG}.cert.pem）: " cert_file
      read -rp "请输入私钥保存路径（例如: /usr/local/lsws/conf/ssl/${SITE_SLUG}.key.pem）: " key_file

      if [ -z "$cert_file" ] || [ -z "$key_file" ]; then
        log_error "证书路径 / 私钥路径不能为空，放弃配置 SSL。"
        return
      fi

      mkdir -p "$(dirname "$cert_file")"

      echo
      echo "请粘贴 Cloudflare Origin Certificate 内容，结束后按 Ctrl+D："
      cat >"$cert_file"
      echo
      echo "请粘贴对应私钥内容，结束后按 Ctrl+D："
      cat >"$key_file"

      chmod 600 "$cert_file" "$key_file"

      if ! grep -q "^listener https " "$HTTPD_CONF"; then
        cat >>"$HTTPD_CONF" <<EOF

listener https {
  address                 *:443
  secure                  1
  keyFile                 ${key_file}
  certFile                ${cert_file}
  map                     ${SITE_SLUG} ${SITE_DOMAIN}
}
EOF
        log_info "已创建 listener https 并配置 Cloudflare Origin 证书。"
      else
        # 更新现有 https listener 的 keyFile / certFile
        awk -v keyf="${key_file}" -v certf="${cert_file}" '
          BEGIN{in_https=0}
          {
            if($1=="listener" && $2=="https"){
              in_https=1
            }
            if(in_https && $1=="keyFile"){
              $2=keyf
            }
            if(in_https && $1=="certFile"){
              $2=certf
            }
            print
            if(in_https && $0 ~ /^}/){
              in_https=0
            }
          }
        ' "$HTTPD_CONF" > "${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"

        if ! awk "/^listener https /,/^}/" "$HTTPD_CONF" | grep -q "map[[:space:]]\+${SITE_SLUG}[[:space:]]\+${SITE_DOMAIN}"; then
          awk -v vh="${SITE_SLUG}" -v dom="${SITE_DOMAIN}" '
            BEGIN{in_https=0}
            {
              if($1=="listener" && $2=="https"){
                in_https=1
              }
              if(in_https && $0 ~ /^}/){
                printf("  map                     %s %s\n", vh, dom)
                in_https=0
              }
              print
            }
          ' "$HTTPD_CONF" > "${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"
        fi

        log_info "已更新 listener https 的证书路径，并保证映射 ${SITE_SLUG} / ${SITE_DOMAIN} 存在。"
      fi

      systemctl restart lsws
      ;;

    3)
      log_info "你选择使用 Let’s Encrypt 自动签发证书。"
      log_warn "请确保："
      log_warn "  - 域名 ${SITE_DOMAIN} 的 A/AAAA 记录已指向本机；"
      log_warn "  - 当前在 Cloudflare 中，该域名记录已设为 DNS only（灰云）；"
      log_warn "  - 80 端口可从公网访问。"

      apt install -y certbot

      local le_email
      read -rp "请输入用于 Let’s Encrypt 注册的邮箱（必填）: " le_email
      if [ -z "$le_email" ]; then
        log_error "邮箱不能为空，无法自动申请 Let’s Encrypt 证书，本次将跳过 SSL 配置。"
        return
      fi

      certbot certonly --webroot -w "$DOC_ROOT" -d "$SITE_DOMAIN" --agree-tos -m "$le_email" --non-interactive || {
        log_error "Let’s Encrypt 申请证书失败，本次将跳过 SSL 配置。"
        return
      }

      local cert_path="/etc/letsencrypt/live/${SITE_DOMAIN}/fullchain.pem"
      local key_path="/etc/letsencrypt/live/${SITE_DOMAIN}/privkey.pem"

      if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
        log_error "未找到 Let’s Encrypt 生成的证书文件，跳过 SSL 配置。"
        return
      fi

      if ! grep -q "^listener https " "$HTTPD_CONF"; then
        cat >>"$HTTPD_CONF" <<EOF

listener https {
  address                 *:443
  secure                  1
  keyFile                 ${key_path}
  certFile                ${cert_path}
  map                     ${SITE_SLUG} ${SITE_DOMAIN}
}
EOF
        log_info "已创建 listener https 并配置 Let’s Encrypt 证书。"
      else
        # 更新现有 https listener 的 keyFile / certFile
        awk -v keyf="${key_path}" -v certf="${cert_path}" '
          BEGIN{in_https=0}
          {
            if($1=="listener" && $2=="https"){
              in_https=1
            }
            if(in_https && $1=="keyFile"){
              $2=keyf
            }
            if(in_https && $1=="certFile"){
              $2=certf
            }
            print
            if(in_https && $0 ~ /^}/){
              in_https=0
            }
          }
        ' "$HTTPD_CONF" > "${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"

        if ! awk "/^listener https /,/^}/" "$HTTPD_CONF" | grep -q "map[[:space:]]\+${SITE_SLUG}[[:space:]]\+${SITE_DOMAIN}"; then
          awk -v vh="${SITE_SLUG}" -v dom="${SITE_DOMAIN}" '
            BEGIN{in_https=0}
            {
              if($1=="listener" && $2=="https"){
                in_https=1
              }
              if(in_https && $0 ~ /^}/){
                printf("  map                     %s %s\n", vh, dom)
                in_https=0
              }
              print
            }
          ' "$HTTPD_CONF" > "${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"
        fi

        log_info "已更新 listener https 的证书路径，并保证映射 ${SITE_SLUG} / ${SITE_DOMAIN} 存在。"
      fi

      systemctl restart lsws
      ;;
    *)
      log_warn "无效输入，默认不配置 SSL。"
      ;;
  esac
}

fix_permissions() {
  log_step "修正站点目录权限"

  chown -R nobody:nogroup "/var/www/${SITE_SLUG}" || true
  find "/var/www/${SITE_SLUG}" -type d -exec chmod 755 {} \; || true
  find "/var/www/${SITE_SLUG}" -type f -exec chmod 644 {} \; || true
}

print_summary() {
  log_step "安装完成总结（${SCRIPT_NAME} v${SCRIPT_VERSION}）"

  detect_public_ip

  echo -e "${BOLD}站点信息${NC}"
  echo "  站点域名：${SITE_DOMAIN}"
  echo "  站点 Slug：${SITE_SLUG}"
  echo "  Document Root：${DOC_ROOT}"
  echo
  echo -e "${BOLD}数据库（请确保已在远程实例中存在）${NC}"
  echo "  DB_HOST：${DB_HOST}"
  echo "  DB_NAME：${DB_NAME}"
  echo "  DB_USER：${DB_USER}"
  echo "  （DB_PASSWORD 已写入 wp-config.php，此处不再显示）"
  echo
  echo -e "${BOLD}服务器网络信息（仅供参考）${NC}"
  if [ -n "$SERVER_IPV4" ]; then
    echo "  服务器 IPv4：${SERVER_IPV4}"
  else
    echo "  服务器 IPv4：自动获取失败，请在面板或 cloud 控制台中查看。"
  fi
  if [ -n "$SERVER_IPV6" ]; then
    echo "  服务器 IPv6：${SERVER_IPV6}"
  else
    echo "  服务器 IPv6：自动获取失败或未配置。"
  fi
  echo
  echo -e "${BOLD}下一步建议${NC}"
  echo "  1. 确认数据库实例中 ${DB_NAME} 已创建，并可从本机使用 ${DB_USER} 正常连接。"
  echo "  2. 确认域名 ${SITE_DOMAIN} 的 DNS A/AAAA 记录指向本机公网 IP。"
  echo "  3. 首次访问 WordPress 前台/后台，完成安装向导。"
  echo "  4. 若在 Cloudflare 使用 Full (strict)，务必先在本机配置 SSL（本脚本 HTTPS 步骤）。"
  echo
  echo -e "${GREEN}本模块执行结束，你可以：${NC}"
  echo "  - 直接按回车返回（如果是从主菜单调用，将返回上级菜单）；"
  echo "  - 或按 Ctrl+C 退出当前终端。"
  read -r _
}

main() {
  echo -e "${BOLD}== OLS + WordPress 标准一键安装（v${SCRIPT_VERSION}）==${NC}"
  require_root
  check_os
  memory_menu_if_low
  prompt_site_info
  prompt_db_info
  install_packages
  setup_vhost_config
  download_wordpress
  generate_wp_config
  configure_ssl
  fix_permissions
  print_summary
}

main "$@"