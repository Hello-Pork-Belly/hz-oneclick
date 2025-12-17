#!/usr/bin/env bash
set -Eeo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
if [[ "$SCRIPT_SOURCE" != /* ]]; then
  SCRIPT_SOURCE="$(pwd)/${SCRIPT_SOURCE}"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMON_LIB="${REPO_ROOT}/lib/common.sh"

cd /

# install-ols-wp-standard.sh
# Version: v0.9
# 更新记录:
# - v0.9:
#   - 完成“彻底移除本机 OLS”“按 slug 清理站点”后，不再直接退出脚本，
#     而是提示已完成并返回「清理本机 OLS / WordPress」菜单。
#   - 完成“清理数据库 / Redis”后，不再直接退出脚本，而是返回「清理数据库 / Redis」菜单。
#   - 安装流程完成后，在总结信息下方新增简单菜单：1) 返回主菜单  0) 退出脚本。
# - v0.8:
#   - 修复: 不再安装不存在的 lsphp83-xml / lsphp83-zip 包，避免 apt 报错中断。
#   - 新增: 顶层主菜单 (0/1/2/3/4)，支持安装、LNMP 占位、本机 OLS/WordPress 清理、DB/Redis 清理。
#   - 新增: “清理本机 OLS / WordPress” 二级菜单:
#         1) 彻底移除本机 OLS (apt purge openlitespeed + lsphp83*，删除 /usr/local/lsws)
#         2) 按 slug 清理某个站点 (删除 vhost + /var/www/<slug>)。
#   - 新增: “清理数据库 / Redis” 二级菜单:
#         1) 清理数据库 (DROP DATABASE + DROP USER，需多次确认)
#         2) 清理 Redis (按 DB index 执行 FLUSHDB，需双重确认 + YES)
#   - 调整: 内存不足提示整合进主菜单; 安装流程封装为 install_lomp_flow()。

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
BOLD="\033[1m"
NC="\033[0m"

SCRIPT_VERSION="0.9"
POST_SUMMARY_SHOWN=0

if [ -r "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  . "$COMMON_LIB"
fi

: "${TIER_LITE:=lite}"
: "${TIER_STANDARD:=standard}"
: "${TIER_HUB:=hub}"

if ! declare -f normalize_tier >/dev/null 2>&1; then
  normalize_tier() {
    local tier
    tier="${1:-}"
    tier="${tier,,}"

    case "$tier" in
      "$TIER_LITE"|"$TIER_STANDARD"|"$TIER_HUB")
        printf "%s" "$tier"
        ;;
      *)
        return 1
        ;;
    esac
  }
fi

if ! declare -f is_valid_tier >/dev/null 2>&1; then
  is_valid_tier() {
    normalize_tier "$1" >/dev/null 2>&1
  }
fi

get_default_lomp_tier() {
  local normalized
  normalized="$(normalize_tier "${TIER_STANDARD}")" || true
  if [ -n "$normalized" ]; then
    printf "%s" "$normalized"
  else
    printf "%s" "$TIER_STANDARD"
  fi
}

LOMP_DEFAULT_TIER="$(get_default_lomp_tier)"

log_info()  {
  # [ANCHOR:LOG_INFO]
  echo -e "${GREEN}[INFO]${NC} $*"
}
log_warn()  {
  # [ANCHOR:LOG_WARN]
  echo -e "${YELLOW}[WARN]${NC} $*"
}
log_error() {
  # [ANCHOR:LOG_ERROR]
  echo -e "${RED}[ERROR]${NC} $*"
}
log_step()  {
  # [ANCHOR:LOG_STEP]
  echo -e "\n${CYAN}==== $* ====${NC}\n"
}

trap 'log_error "脚本执行中断（行号: $LINENO）。"; exit 1' ERR

require_root() {
  # [ANCHOR:ENV_PRECHECK]
  if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 root 运行本脚本。"
    exit 1
  fi
}

check_os() {
  # [ANCHOR:ENV_PRECHECK]
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

# 读取内存 MB
get_ram_mb() {
  # [ANCHOR:GET_RAM_MB]
  awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0
}

# 探测公网 IP（尽量避免 10.x / 内网）
_detect_public_ip() {
  # [ANCHOR:DETECT_PUBLIC_IP]
  local ipv4 ipv6
  ipv4="$(curl -4s --max-time 5 https://ifconfig.me || true)"
  if ! echo "$ipv4" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    ipv4=""
  fi
  if [ -z "$ipv4" ]; then
    ipv4="$(ip -4 -o addr show 2>/dev/null | awk '!/ lo /{print $4}' | cut -d/ -f1 | while read -r ip; do
      case "$ip" in
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|127.*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
          continue;;
        *) echo "$ip"; break;;
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

# [ANCHOR:POST_INSTALL_SUMMARY]
get_public_ipv4() {
  local urls=(
    "https://api.ipify.org"
    "https://ipv4.icanhazip.com"
    "https://ifconfig.me/ip"
  )
  local ip

  for url in "${urls[@]}"; do
    ip="$(curl -fsS4 --max-time 3 "$url" 2>/dev/null || true)"
    ip="$(echo "$ip" | tr -d ' \t\r\n')"
    if [ -n "$ip" ]; then
      echo "$ip"
      return
    fi
  done
}

get_public_ipv6() {
  local urls=(
    "https://api64.ipify.org"
    "https://ipv6.icanhazip.com"
    "https://ifconfig.me/ip"
  )
  local ip

  for url in "${urls[@]}"; do
    ip="$(curl -fsS6 --max-time 3 "$url" 2>/dev/null || true)"
    ip="$(echo "$ip" | tr -d ' \t\r\n')"
    if [ "$url" = "https://ifconfig.me/ip" ] && [ -z "$ip" ]; then
      continue
    fi
    if [ -n "$ip" ]; then
      echo "$ip"
      return
    fi
  done
}

show_post_install_summary() {
  local domain="$1"

  if [ "${POST_SUMMARY_SHOWN:-0}" -eq 1 ]; then
    return
  fi

  local ipv4 ipv6
  ipv4="$(get_public_ipv4)"
  ipv6="$(get_public_ipv6)"

  POST_SUMMARY_SHOWN=1

  echo
  echo -e "${CYAN}================ 部署信息（请务必保存） ================${NC}"
  echo -e "${GREEN}域名：${NC}${domain}"

  if [[ -n "${ipv4}" ]]; then
    echo -e "${GREEN}公网 IPv4：${NC}${ipv4}"
  else
    echo -e "${YELLOW}公网 IPv4：${NC}未检测到（可稍后自行查询）"
  fi

  if [[ -n "${ipv6}" ]]; then
    echo -e "${GREEN}公网 IPv6：${NC}${ipv6}"
  else
    echo -e "${YELLOW}公网 IPv6：${NC}未检测到（或当前网络未启用 IPv6）"
  fi

  echo
  echo -e "${CYAN}DNS 解析指引：${NC}"
  echo -e "  - A 记录：@ -> ${ipv4:-<填写服务器公网 IPv4>}"
  if [[ -n "${ipv6}" ]]; then
    echo -e "  - AAAA 记录：@ -> ${ipv6}"
  fi
  echo -e "  - 如使用代理/CDN，请确认源站 IP 填写为实际服务器地址。"

  echo
  echo -e "${CYAN}防火墙检查：${NC}"
  echo -e "  - 确认系统防火墙已放行 80/443"
  echo -e "  - 确认云防火墙/安全组已放行 80/443"

  echo
  echo -e "${CYAN}=========================================================${NC}"
  echo
  read -rp "按回车返回主菜单..." _
}

########################
#  顶层主菜单         #
########################

show_main_menu() {
  # [ANCHOR:MENU_MAIN]
  local ram
  ram="$(get_ram_mb)"

  echo
  echo -e "${BOLD}== OLS + WordPress 标准模块 (v${SCRIPT_VERSION}) ==${NC}"
  if [ "$ram" -gt 0 ]; then
    echo -e "当前检测到内存约: ${BOLD}${ram} MB${NC}"
    if [ "$ram" -lt 3800 ]; then
      log_warn "当前机器内存 < 4G，强烈建议：数据库 / Redis 放在其他高配机器，本机只跑 OLS + WordPress 前端。"
    else
      log_info "内存 ≥ 4G，可作为前后端一体机或仅前端。"
    fi
  fi

  echo
  echo "请选择要执行的操作："
  echo "  1) 安装 / 配置本机 OLS + WordPress（标准模式）"
  echo "  2) 改为 LNMP（占位，目前仅提示）"
  echo "  3) 清理本机 OLS / WordPress（危险操作，慎用）"
  echo "  4) 清理数据库 / Redis（需在 DB/Redis 所在机器执行）"
  echo "  0) 退出脚本"
  echo

  local choice
  read -rp "请输入选项 [0-4]: " choice
  echo

  case "$choice" in
    1) install_lomp_flow ;;
    2)
      log_warn "LNMP 一键模块尚未集成，请使用独立 LNMP 脚本。"
      read -rp "按回车返回主菜单..." _
      show_main_menu
      ;;
    3) cleanup_lomp_menu ;;
    4) cleanup_db_redis_menu ;;
    0)
      # [ANCHOR:EXIT]
      log_info "已退出脚本。"
      exit 0
      ;;
    *)
      log_warn "无效输入，请重新运行脚本并选择 0-4。"
      exit 1
      ;;
  esac
}

################################
# 3: 清理本机 OLS / WordPress #
################################

cleanup_lomp_menu() {
  # [ANCHOR:CLEANUP_MENU]
  echo -e "${YELLOW}[危险]${NC} 本菜单会在本机删除 OLS 或站点，请确认已备份。"
  echo
  echo "3) 清理本机 OLS / WordPress："
  echo "  1) 彻底移除本机 OLS（卸载 openlitespeed + lsphp83*，删除 /usr/local/lsws）"
  echo "  2) 按 slug 清理本机某个 WordPress 站点（删除 vhost + /var/www/<slug>）"
  echo "  3) 返回上一层"
  echo "  0) 退出脚本"
  echo

  local sub
  read -rp "请输入选项 [0-3]: " sub
  echo

  case "$sub" in
    1) remove_ols_global ;;
    2) remove_wp_by_slug ;;
    3) show_main_menu ;;
    0)
      log_info "已退出脚本。"; exit 0 ;;
    *)
      log_warn "无效输入，返回主菜单。"; show_main_menu ;;
  esac
}

remove_ols_global() {
  # [ANCHOR:REMOVE_OLS_GLOBAL]
  echo -e "${YELLOW}[警告]${NC} 即将 ${BOLD}彻底移除本机 OLS${NC}"
  echo "本操作将："
  echo "  - systemctl 停止/禁用 lsws;"
  echo "  - apt remove/purge openlitespeed 与 lsphp83 相关组件;"
  echo "  - 删除 /usr/local/lsws 目录;"
  echo "  - 不会自动删除 /var/www 下的站点目录。"
  echo
  local c
  read -rp "如需继续，请输入大写 'REMOVE_OLS' 确认: " c
  if [ "$c" != "REMOVE_OLS" ]; then
    log_warn "确认字符串不匹配，已取消。"
    cleanup_lomp_menu
    return
  fi

  log_step "停止并卸载 OpenLiteSpeed"

  if systemctl list-unit-files | grep -q '^lsws\.service'; then
    systemctl stop lsws || true
    systemctl disable lsws || true
  fi

  log_info "使用 apt 移除 openlitespeed 与 lsphp83 相关组件（如不存在则跳过）。"
  set +e
  apt remove --purge -y openlitespeed 2>/dev/null
  apt remove --purge -y lsphp83 lsphp83-common lsphp83-mysql lsphp83-opcache 2>/dev/null
  apt autoremove -y 2>/dev/null
  set -Eeo pipefail

  if [ -d /usr/local/lsws ]; then
    log_info "删除 /usr/local/lsws 目录..."
    rm -rf /usr/local/lsws
  fi

  log_info "本机 OLS 卸载流程已完成。"
  read -rp "按回车返回“清理本机 OLS / WordPress”菜单..." _
  cleanup_lomp_menu
  return
}

remove_wp_by_slug() {
  # [ANCHOR:REMOVE_WP_BY_SLUG]
  local LSWS_ROOT="/usr/local/lsws"
  local HTTPD_CONF="${LSWS_ROOT}/conf/httpd_config.conf"

  if [ ! -d "$LSWS_ROOT" ] || [ ! -f "$HTTPD_CONF" ]; then
    log_error "未找到 ${LSWS_ROOT} 或 ${HTTPD_CONF}，似乎尚未安装 OLS。"
    read -rp "按回车返回“清理本机 OLS / WordPress”菜单..." _
    cleanup_lomp_menu
    return
  fi

  echo "按 slug 清理单个站点："
  echo "  - 删除 vhost 配置目录 /usr/local/lsws/conf/vhosts/<slug>/"
  echo "  - 删除站点目录 /var/www/<slug>/"
  echo "  - 从 httpd_config.conf 中移除 virtualhost 与 map"
  echo

  local slug slug2
  read -rp "请输入要清理的站点 slug（例如: ols 或 horizontech）: " slug
  if [ -z "$slug" ]; then
    log_warn "slug 不能为空，已取消。"
    cleanup_lomp_menu
    return
  fi
  read -rp "请再次输入 slug 确认: " slug2
  if [ "$slug" != "$slug2" ]; then
    log_warn "两次 slug 不一致，已取消。"
    cleanup_lomp_menu
    return
  fi

  local VH_CONF_DIR="${LSWS_ROOT}/conf/vhosts/${slug}"
  local DOC_ROOT_BASE="/var/www/${slug}"

  echo
  echo "将执行："
  echo "  - 删除 vhost: ${VH_CONF_DIR}"
  echo "  - 删除站点: ${DOC_ROOT_BASE}"
  echo "  - 从 httpd_config.conf 移除 virtualhost ${slug} 及 map 行"
  local ok
  read -rp "如需继续，请输入大写 'YES': " ok
  if [ "$ok" != "YES" ]; then
    log_warn "未输入 YES，已取消。"
    cleanup_lomp_menu
    return
  fi

  log_step "清理 virtualhost ${slug} 配置"

  # 移除 virtualhost 块
  awk -v vh="$slug" '
    BEGIN{skip=0}
    {
      if($1=="virtualhost" && $2==vh){ skip=1 }
      if(skip==0){ print $0 }
      if(skip==1 && $0 ~ /^}/){ skip=0 }
    }
  ' "$HTTPD_CONF" >"${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"

  # 移除 listener 中的 map 行
  sed -i "/map[[:space:]]\+${slug}[[:space:]]\+/d" "$HTTPD_CONF"

  if [ -d "$VH_CONF_DIR" ]; then
    log_info "删除 vhost 目录: ${VH_CONF_DIR}"
    rm -rf "$VH_CONF_DIR"
  else
    log_warn "未找到 vhost 目录: ${VH_CONF_DIR}，可能已被删除。"
  fi

  if [ -d "$DOC_ROOT_BASE" ]; then
    log_info "删除站点目录: ${DOC_ROOT_BASE}"
    rm -rf "$DOC_ROOT_BASE"
  else
    log_warn "未找到站点目录: ${DOC_ROOT_BASE}，可能已被删除。"
  fi

  if systemctl list-unit-files | grep -q '^lsws\.service'; then
    systemctl restart lsws || true
  fi

  log_info "按 slug 清理站点完成。"
  read -rp "按回车返回“清理本机 OLS / WordPress”菜单..." _
  cleanup_lomp_menu
  return
}

##################################
# 4: 清理数据库 / Redis 子菜单  #
##################################

cleanup_db_redis_menu() {
  # [ANCHOR:CLEANUP_DB_REDIS_MENU]
  echo -e "${YELLOW}[危险]${NC} 本菜单会对数据库 / Redis 执行删除/清空操作，请务必提前备份。"
  echo
  echo "4) 清理数据库 / Redis（应在 DB / Redis 所在机器执行）："
  echo "  1) 清理数据库（DROP DATABASE + DROP USER）"
  echo "  2) 清理 Redis（对某个 DB index 执行 FLUSHDB）"
  echo "  3) 返回上一层"
  echo "  0) 退出脚本"
  echo

  local sub
  read -rp "请输入选项 [0-3]: " sub
  echo

  case "$sub" in
    1) cleanup_db_interactive ;;
    2) cleanup_redis_interactive ;;
    3) show_main_menu ;;
    0)
      log_info "已退出脚本。"; exit 0 ;;
    *)
      log_warn "无效输入，返回主菜单。"; show_main_menu ;;
  esac
}

cleanup_db_interactive() {
  # [ANCHOR:DB_CLEANUP_FLOW]
  if ! command -v mysql >/dev/null 2>&1; then
    log_error "未找到 mysql 命令，无法执行数据库清理。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  echo -e "${YELLOW}[注意]${NC} 将执行 DROP DATABASE / DROP USER，请确保已经备份。"
  echo

  local DB_HOST DB_PORT DB_NAME DB_USER ADMIN_USER ADMIN_PASS tmp

  read -rp "DB Host（默认 127.0.0.1）: " DB_HOST
  DB_HOST="${DB_HOST:-127.0.0.1}"

  read -rp "DB Port（默认 3306）: " DB_PORT
  DB_PORT="${DB_PORT:-3306}"

  read -rp "要删除的 DB 名称（例如: ols_wp）: " DB_NAME
  if [ -z "$DB_NAME" ]; then
    log_warn "DB 名称不能为空。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "要删除的 DB 用户名（例如: ols_user）: " DB_USER
  if [ -z "$DB_USER" ]; then
    log_warn "DB 用户名不能为空。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "用于执行 DROP 的管理账号（默认 root）: " ADMIN_USER
  ADMIN_USER="${ADMIN_USER:-root}"

  read -rsp "请输入管理账号密码（不会回显）: " ADMIN_PASS
  echo
  if [ -z "$ADMIN_PASS" ]; then
    log_warn "管理账号密码不能为空。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  echo
  echo "将要执行的大致 SQL："
  echo "  DROP DATABASE IF EXISTS \`$DB_NAME\`;"
  echo "  DROP USER IF EXISTS '$DB_USER'@'%';"
  echo "  FLUSH PRIVILEGES;"
  echo

  read -rp "为确认操作，请再次输入 DB 名称 ($DB_NAME): " tmp
  if [ "$tmp" != "$DB_NAME" ]; then
    log_warn "两次 DB 名称不一致，已取消。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "如需继续，请输入大写 'YES': " tmp
  if [ "$tmp" != "YES" ]; then
    log_warn "未输入 YES，已取消数据库清理。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  log_step "执行数据库清理: $DB_NAME / $DB_USER"

  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" \
    -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; DROP USER IF EXISTS '$DB_USER'@'%'; FLUSH PRIVILEGES;"

  log_info "数据库 $DB_NAME 与用户 $DB_USER 已尝试删除（如存在）。"
  read -rp "按回车返回“清理数据库 / Redis”菜单..." _
  cleanup_db_redis_menu
  return
}

cleanup_redis_interactive() {
  # [ANCHOR:REDIS_CLEANUP_FLOW]
  if ! command -v redis-cli >/dev/null 2>&1; then
    log_error "未找到 redis-cli，无法执行 Redis 清理。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  echo -e "${YELLOW}[注意]${NC} 将对指定 Redis DB 执行 FLUSHDB（清空所有 key），不可恢复。"
  echo

  local RH RP RD RD2 tmp

  read -rp "Redis Host（默认 127.0.0.1）: " RH
  RH="${RH:-127.0.0.1}"

  read -rp "Redis Port（默认 6379）: " RP
  RP="${RP:-6379}"

  read -rp "Redis DB index（例如: 1）: " RD
  if [ -z "$RD" ]; then
    log_warn "Redis DB index 不能为空。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "请再次输入 Redis DB index 确认: " RD2
  if [ "$RD" != "$RD2" ]; then
    log_warn "两次 DB index 不一致，已取消。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  echo
  echo "将对 Redis ${RH}:${RP} 的 DB ${RD} 执行 FLUSHDB。"
  read -rp "如需继续，请输入大写 'YES': " tmp
  if [ "$tmp" != "YES" ]; then
    log_warn "未输入 YES，已取消 Redis 清理。"
    read -rp "按回车返回“清理数据库 / Redis”菜单..." _
    cleanup_db_redis_menu
    return
  fi

  log_step "执行 Redis DB ${RD} 清空 (FLUSHDB)"

  redis-cli -h "$RH" -p "$RP" -n "$RD" FLUSHDB

  log_info "Redis DB ${RD} 已执行 FLUSHDB。"
  read -rp "按回车返回“清理数据库 / Redis”菜单..." _
  cleanup_db_redis_menu
  return
}

#######################
# 安装 OLS + WP 流程  #
#######################

prompt_site_info() {
  # [ANCHOR:SITE_INFO]
  echo
  echo "================ 站点基础信息 ================"
  while :; do
    read -rp "请输入站点域名（例如: example.com 或 blog.example.com）: " SITE_DOMAIN
    [ -n "$SITE_DOMAIN" ] && break
    log_warn "域名不能为空。"
  done

  read -rp "请输入站点 Slug（仅小写字母/数字，例如: ols，默认取域名第一个字段）: " SITE_SLUG
  if [ -z "$SITE_SLUG" ]; then
    SITE_SLUG="${SITE_DOMAIN%%.*}"
    SITE_SLUG="${SITE_SLUG//[^a-zA-Z0-9]/}"
    SITE_SLUG="$(echo "$SITE_SLUG" | tr 'A-Z' 'a-z')"
    [ -z "$SITE_SLUG" ] && SITE_SLUG="wpsite"
  fi

  DOC_ROOT="/var/www/${SITE_SLUG}/html"

  log_info "站点域名: ${SITE_DOMAIN}"
  log_info "站点 Slug: ${SITE_SLUG}"
  log_info "站点根目录: ${DOC_ROOT}"
}

prompt_db_info() {
  # [ANCHOR:DB_INFO_PROMPT]
  echo
  echo "================ 数据库设置（必须已在目标 DB 实例中创建） ================"
  echo "请先在你的数据库实例中『手动』创建好："
  echo "  - 独立数据库，例如: ${SITE_SLUG}_wp"
  echo "  - 独立数据库用户，例如: ${SITE_SLUG}_user，并分配该库全部权限"
  echo

  while :; do
    read -rp "DB Host（可带端口，例如: 100.82.140.65:3306 或 127.0.0.1）: " DB_HOST
    [ -n "$DB_HOST" ] && break
    log_warn "DB Host 不能为空。"
  done

  while :; do
    read -rp "DB 名称（必须与已创建数据库名称完全一致，例如: ${SITE_SLUG}_wp）: " DB_NAME
    [ -n "$DB_NAME" ] && break
    log_warn "DB 名称不能为空。"
  done

  while :; do
    read -rp "DB 用户名（必须与已创建的数据库用户一致，例如: ${SITE_SLUG}_user）: " DB_USER
    [ -n "$DB_USER" ] && break
    log_warn "DB 用户名不能为空。"
  done

  # 密码需要输入两次确认，防止手滑
  while :; do
    # [ANCHOR:READ_DB_PASSWORD]
    read -rsp "DB 密码（不会回显，请确保与该 DB 用户的真实密码一致）: " DB_PASSWORD
    echo
    if [ -z "$DB_PASSWORD" ]; then
      log_warn "DB 密码不能为空。"
      continue
    fi

    read -rsp "请再次输入 DB 密码进行确认: " DB_PASSWORD_CONFIRM
    echo
    if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
      log_error "两次输入的 DB 密码不一致，请重新输入。"
      continue
    fi

    unset DB_PASSWORD_CONFIRM
    break
  done
}

test_db_connection() {
  # [ANCHOR:DB_CONN_TEST]
  log_step "测试数据库连通性"

  local host="$DB_HOST"
  local port="3306"

  # 允许 DB_HOST 以 host:port 形式填写
  if [[ "$host" == *:* ]]; then
    port="${host##*:}"
    host="${host%%:*}"
  fi

  # 确保有 mysql/mariadb 客户端可用
  if ! command -v mysql >/dev/null 2>&1; then
    log_warn "未找到 mysql 客户端，将尝试安装 mariadb-client 用于数据库连通性测试。"
    apt update
    apt install -y mariadb-client
  fi

  if mysql -h "$host" -P "$port" -u "$DB_USER" "-p$DB_PASSWORD" -e "USE \`$DB_NAME\`; SELECT 1;" >/dev/null 2>&1; then
    log_info "成功连接到数据库：${DB_USER}@${host}:${port} / ${DB_NAME}"
    return 0
  else
    log_error "无法连接到数据库：${DB_USER}@${host}:${port} / ${DB_NAME}"
    log_warn "常见原因：密码错误 / 数据库未启动 / 网络或防火墙未放行 / 用户无该库权限。"
    return 1
  fi
}

install_packages() {
  # [ANCHOR:INSTALL_OLS]
  log_step "安装 / 检查 OpenLiteSpeed 与 PHP 组件"

  apt update
  apt install -y software-properties-common curl

  if ! dpkg -l | grep -q '^ii[[:space:]]\+openlitespeed[[:space:]]'; then
    log_info "安装 openlitespeed..."
    apt install -y openlitespeed
  else
    log_info "检测到 openlitespeed 已安装，跳过。"
  fi

  # [ANCHOR:INSTALL_PHP]
  if ! dpkg -l | grep -q '^ii[[:space:]]\+lsphp83[[:space:]]'; then
    log_info "安装 lsphp83 及常用扩展（common/mysql/opcache）..."
    apt install -y lsphp83 lsphp83-common lsphp83-mysql lsphp83-opcache
  else
    log_info "检测到 lsphp83 已安装，跳过。"
  fi

  systemctl enable lsws >/dev/null 2>&1 || true
  systemctl restart lsws
}

setup_vhost_config() {
  # [ANCHOR:SETUP_VHOST_CONFIG]
  log_step "配置 OpenLiteSpeed Virtual Host"

  local LSWS_ROOT="/usr/local/lsws"
  local HTTPD_CONF="${LSWS_ROOT}/conf/httpd_config.conf"
  local VH_CONF_DIR="${LSWS_ROOT}/conf/vhosts/${SITE_SLUG}"
  local VH_CONF_FILE="${VH_CONF_DIR}/vhconf.conf"
  local VH_ROOT="/var/www/${SITE_SLUG}"

  [ -d "$LSWS_ROOT" ] || { log_error "未找到 ${LSWS_ROOT}，请确认 OLS 安装成功。"; exit 1; }

  mkdir -p "$VH_CONF_DIR" "$DOC_ROOT" "${VH_ROOT}/logs"

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
    log_info "已在 httpd_config.conf 中添加 virtualhost ${SITE_SLUG}。"
  else
    log_info "virtualhost ${SITE_SLUG} 已存在，跳过。"
  fi

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
    log_info "已生成 vhost 配置文件: ${VH_CONF_FILE}"
  else
    log_info "vhost 配置文件已存在: ${VH_CONF_FILE}"
  fi

  # HTTP 监听器
  if ! grep -q "^listener http" "$HTTPD_CONF"; then
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
      awk -v vh="${SITE_SLUG}" -v dom="${SITE_DOMAIN}" '
        BEGIN{inh=0}
        {
          if($1=="listener" && $2=="http"){inh=1}
          if(inh && $0 ~ /^}/){ printf("  map                     %s %s\n", vh, dom); inh=0 }
          print
        }
      ' "$HTTPD_CONF" >"${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"
      log_info "已在 listener http 中追加 map ${SITE_SLUG} ${SITE_DOMAIN}。"
    else
      log_info "listener http 中已存在 ${SITE_SLUG}/${SITE_DOMAIN} 映射。"
    fi
  fi

  systemctl restart lsws
}

download_wordpress() {
  # [ANCHOR:DOWNLOAD_WORDPRESS]
  log_step "下载并部署 WordPress"

  if [ -f "${DOC_ROOT}/wp-config.php" ]; then
    log_warn "检测到 ${DOC_ROOT}/wp-config.php 已存在，将跳过 WordPress 下载。"
    return
  fi

  mkdir -p "$DOC_ROOT"
  local tmp
  tmp="$(mktemp -d)"
  pushd "$tmp" >/dev/null

  log_info "从官方源下载 WordPress..."
  curl -fsSL https://wordpress.org/latest.tar.gz -o wordpress.tar.gz
  tar -xzf wordpress.tar.gz
  [ -d wordpress ] || { log_error "解压 WordPress 失败。"; popd >/dev/null; rm -rf "$tmp"; exit 1; }

  cp -a wordpress/. "$DOC_ROOT"/

  popd >/dev/null
  rm -rf "$tmp"

  log_info "WordPress 已部署到 ${DOC_ROOT}。"
}

generate_wp_config() {
  # [ANCHOR:WP_CONFIG_GENERATE]
  log_step "生成 wp-config.php"

  local wp_config="${DOC_ROOT}/wp-config.php"
  local sample="${DOC_ROOT}/wp-config-sample.php"

  if [ -f "$wp_config" ]; then
    log_warn "检测到已存在 wp-config.php，将不覆盖。"
    return
  fi

  [ -f "$sample" ] || { log_error "未找到 ${sample}，无法生成 wp-config.php。"; exit 1; }

  # [ANCHOR:WRITE_WP_CONFIG]
  cp "$sample" "$wp_config"

  # 处理包含 & 或反斜杠等特殊字符的密码，避免被 sed 误替换
  local esc_db_password="$DB_PASSWORD"
  esc_db_password=${esc_db_password//\\/\\\\}
  esc_db_password=${esc_db_password//&/\\&}

  sed -i "s|database_name_here|${DB_NAME}|" "$wp_config"
  sed -i "s|username_here|${DB_USER}|" "$wp_config"
  sed -i "s|password_here|${esc_db_password}|" "$wp_config"
  sed -i "s|localhost|${DB_HOST}|" "$wp_config"

  log_info "已根据输入生成 wp-config.php（DB_* 信息已写入）。"
}

fix_permissions() {
  # [ANCHOR:SET_PERMISSIONS]
  log_step "修复站点目录权限"

  local base="/var/www/${SITE_SLUG}"
  if [ ! -d "$base" ]; then
    log_warn "未找到 ${base}，跳过权限修复。"
    return
  fi

  chown -R nobody:nogroup "$base"
  find "$base" -type d -exec chmod 755 {} \;
  find "$base" -type f -exec chmod 644 {} \;

  log_info "已将 ${base} 目录及文件权限统一为 nobody:nogroup + 755/644。"
}

env_self_check() {
  # [ANCHOR:ENV_SELF_CHECK]
  log_step "环境自检（lsws 状态 / 端口 / 防火墙）"

  echo "1) Web 服务进程状态"
  if systemctl is-active --quiet lsws; then
    log_info "lsws 服务状态: active (running)"
  else
    log_warn "lsws 当前不是 active。请检查: systemctl status lsws"
  fi

  echo
  # [ANCHOR:PORT_CHECK]
  echo "2) 本机监听端口（80 / 443）"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp | awk 'NR==1 || /:80 / || /:443 /'
  else
    netstat -lntp 2>/dev/null | awk 'NR==1 || /:80 / || /:443 /'
  fi

  if command -v ufw >/dev/null 2>&1; then
    # [ANCHOR:UFW_CHECK]
    echo
    echo "3) ufw 防火墙状态"
    ufw status verbose || true
  fi

  echo
  log_warn "排查 521 / 无法访问建议顺序："
  echo "  1) 确认本机有进程监听 80/443；"
  echo "  2) 确认本机防火墙（如 ufw）已放行 80/443；"
  echo "  3) 确认云厂商安全组 / 防火墙已放行 80/443 到本实例；"
  echo "  4) 如使用 CDN/加速服务，确认其 SSL 模式与源站证书是否匹配。"
}

configure_ssl() {
  # [ANCHOR:SSL_MENU]
  log_step "处理 SSL / HTTPS（可选）"

  local LSWS_ROOT="/usr/local/lsws"
  local HTTPD_CONF="${LSWS_ROOT}/conf/httpd_config.conf"
  local choice

  echo "请选择 HTTPS 方案："
  echo "  1) 暂不配置 SSL，仅使用 HTTP 80（推荐先确认站点正常）"
  echo "  2) 使用 Origin Certificate（手动粘贴证书和私钥）"
  echo "  3) 使用 Let’s Encrypt 自动申请证书（需域名已指向本机，灰云）"
  echo

  read -rp "请输入数字 [1-3，默认 1]: " choice
  choice="${choice:-1}"

  case "$choice" in
    1)
      log_warn "本次不配置 SSL，仅监听 80。若在 CDN 后台使用严格模式（类似 Full(strict)），源站无证书会导致 521。"
      ;;
    2)
      local cert_file key_file
      log_info "你选择了 Origin Certificate 模式。请先在 CDN/加速服务后台生成源站证书。"
      read -rp "请输入证书保存路径（例如: /usr/local/lsws/conf/ssl/${SITE_SLUG}.cert.pem）: " cert_file
      read -rp "请输入私钥保存路径（例如: /usr/local/lsws/conf/ssl/${SITE_SLUG}.key.pem）: " key_file
      if [ -z "$cert_file" ] || [ -z "$key_file" ]; then
        log_error "证书/私钥路径不能为空，跳过 SSL 配置。"; return
      fi
      mkdir -p "$(dirname "$cert_file")"
      echo; echo "请粘贴 Origin Certificate 内容，结束后 Ctrl+D："; cat >"$cert_file"
      echo; echo "请粘贴对应私钥内容，结束后 Ctrl+D："; cat >"$key_file"
      chmod 600 "$cert_file" "$key_file"

      if ! grep -q "^listener https" "$HTTPD_CONF"; then
        cat >>"$HTTPD_CONF" <<EOF

listener https {
  address                 *:443
  secure                  1
  keyFile                 ${key_file}
  certFile                ${cert_file}
  map                     ${SITE_SLUG} ${SITE_DOMAIN}
}
EOF
      else
        awk -v keyf="$key_file" -v certf="$cert_file" '
          BEGIN{inh=0}
          {
            if($1=="listener" && $2=="https"){inh=1}
            if(inh && $1=="keyFile"){ $2=keyf }
            if(inh && $1=="certFile"){ $2=certf }
            print
            if(inh && $0 ~ /^}/){inh=0}
          }
        ' "$HTTPD_CONF" >"${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"

        if ! awk "/^listener https /,/^}/" "$HTTPD_CONF" | grep -q "map[[:space:]]\+${SITE_SLUG}[[:space:]]\+${SITE_DOMAIN}"; then
          awk -v vh="${SITE_SLUG}" -v dom="${SITE_DOMAIN}" '
            BEGIN{inh=0}
            {
              if($1=="listener" && $2=="https"){inh=1}
              if(inh && $0 ~ /^}/){ printf("  map                     %s %s\n", vh, dom); inh=0 }
              print
            }
          ' "$HTTPD_CONF" >"${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"
        fi
      fi
      systemctl restart lsws
      # [ANCHOR:AFTER_SSL_SUMMARY]
      show_post_install_summary "${SITE_DOMAIN}"
      ;;
    3)
      # [ANCHOR:SSL_LE]
      log_info "你选择 Let’s Encrypt。请确保：域名 ${SITE_DOMAIN} 已指向本机，且 DNS 记录为灰云。"
      apt install -y certbot
      local email cert_path key_path
      read -rp "请输入用于 Let’s Encrypt 注册的邮箱: " email
      if [ -z "$email" ]; then log_error "邮箱不能为空，跳过 SSL 配置。"; return; fi
      certbot certonly --webroot -w "$DOC_ROOT" -d "$SITE_DOMAIN" --agree-tos -m "$email" --non-interactive || {
        log_error "Let’s Encrypt 申请失败，跳过 SSL 配置。"; return; }
      cert_path="/etc/letsencrypt/live/${SITE_DOMAIN}/fullchain.pem"
      key_path="/etc/letsencrypt/live/${SITE_DOMAIN}/privkey.pem"
      [ -f "$cert_path" ] && [ -f "$key_path" ] || { log_error "未找到 LE 证书文件，跳过 SSL 配置。"; return; }

      if ! grep -q "^listener https" "$HTTPD_CONF"; then
        cat >>"$HTTPD_CONF" <<EOF

listener https {
  address                 *:443
  secure                  1
  keyFile                 ${key_path}
  certFile                ${cert_path}
  map                     ${SITE_SLUG} ${SITE_DOMAIN}
}
EOF
      else
        awk -v keyf="$key_path" -v certf="$cert_path" '
          BEGIN{inh=0}
          {
            if($1=="listener" && $2=="https"){inh=1}
            if(inh && $1=="keyFile"){ $2=keyf }
            if(inh && $1=="certFile"){ $2=certf }
            print
            if(inh && $0 ~ /^}/){inh=0}
          }
        ' "$HTTPD_CONF" >"${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"

        if ! awk "/^listener https /,/^}/" "$HTTPD_CONF" | grep -q "map[[:space:]]\+${SITE_SLUG}[[:space:]]\+${SITE_DOMAIN}"; then
          awk -v vh="${SITE_SLUG}" -v dom="${SITE_DOMAIN}" '
            BEGIN{inh=0}
            {
              if($1=="listener" && $2=="https"){inh=1}
              if(inh && $0 ~ /^}/){ printf("  map                     %s %s\n", vh, dom); inh=0 }
              print
            }
          ' "$HTTPD_CONF" >"${HTTPD_CONF}.tmp" && mv "${HTTPD_CONF}.tmp" "$HTTPD_CONF"
        fi
      fi
      systemctl restart lsws
      # [ANCHOR:AFTER_SSL_SUMMARY]
      show_post_install_summary "${SITE_DOMAIN}"
      ;;
    *)
      log_warn "未知选项，暂不配置 SSL。";
      ;;
  esac
}

print_summary() {
  # [ANCHOR:SUMMARY]
  _detect_public_ip
  echo
  echo -e "${BOLD}安装完成（v${SCRIPT_VERSION}）${NC}"
  echo "====================================="
  echo "站点域名:    ${SITE_DOMAIN}"
  echo "站点 Slug:    ${SITE_SLUG}"
  echo "站点根目录:  ${DOC_ROOT}"
  echo "数据库主机:  ${DB_HOST}"
  echo "数据库名称:  ${DB_NAME}"
  echo "数据库用户:  ${DB_USER}"
  echo "服务器 IPv4: ${SERVER_IPV4:-未知 / 可能在内网或被防火墙阻挡}"
  echo "服务器 IPv6: ${SERVER_IPV6:-未检测到}"
  echo
  echo "请在域名 DNS / CDN 后台，将 ${SITE_DOMAIN} 的 A/AAAA 记录指向上述 IP。"
  echo "如使用严格 SSL 模式，请确保源站已正确配置证书，否则会出现 521。"
  echo
  echo "接下来建议操作："
  echo "  1) 在浏览器直接访问 http://${SITE_DOMAIN} 或 http://<服务器IP> 测试站点是否正常;"
  echo "  2) 确认云厂商安全组和本机防火墙均已放行 80/443;"
  echo "  3) 再在 CDN / 加速服务后台开启代理（橙云）和 HTTPS。"
  echo
}

install_lomp_flow() {
  # [ANCHOR:INSTALL_FLOW]
  local opt lomp_tier

  lomp_tier="$LOMP_DEFAULT_TIER"
  if ! is_valid_tier "$lomp_tier"; then
    log_error "内部档位标识无效，无法继续安装。"
    exit 1
  fi

  require_root
  check_os
  prompt_site_info

  # 循环输入 DB 信息并测试连通性，直到成功或用户选择退出
  while :; do
    prompt_db_info

    if test_db_connection; then
      break
    fi

    echo "-------------------------------------"
    echo "  1) 重新输入数据库信息"
    echo "  0) 退出脚本"
    echo "-------------------------------------"
    read -rp "请输入选项 [0-1]: " opt
    case "$opt" in
      1)
        # 回到 while 顶部，重新输入
        ;;
      0)
        log_info "已退出脚本。"
        exit 1
        ;;
      *)
        log_warn "输入无效，将默认重新输入数据库信息。"
        ;;
    esac
  done

  install_packages
  setup_vhost_config
  download_wordpress
  generate_wp_config
  fix_permissions
  env_self_check
  configure_ssl
  print_summary

  if [ "${POST_SUMMARY_SHOWN:-0}" -eq 0 ]; then
    show_post_install_summary "${SITE_DOMAIN}"
  fi

  echo "-------------------------------------"
  echo "  1) 返回主菜单"
  echo "  0) 退出脚本"
  echo "-------------------------------------"
  read -rp "请输入选项 [0-1]: " opt
  case "$opt" in
    1) show_main_menu ;;
    0) log_info "已退出脚本。"; exit 0 ;;
    *) log_warn "输入无效，默认退出脚本。"; exit 0 ;;
  esac
}

#######################
# 脚本入口            #
#######################

# [ANCHOR:ENTRYPOINT]
show_main_menu
