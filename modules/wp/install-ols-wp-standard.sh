#!/usr/bin/env bash
set -Eeo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
if [[ "$SCRIPT_SOURCE" != /* ]]; then
  SCRIPT_SOURCE="$(pwd)/${SCRIPT_SOURCE}"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMON_LIB="${REPO_ROOT}/lib/common.sh"
# [ANCHOR:CH20_BASELINE_SOURCE]
BASELINE_LIB="${REPO_ROOT}/lib/baseline.sh"
BASELINE_HTTPS_LIB="${REPO_ROOT}/lib/baseline_https.sh"
BASELINE_TLS_LIB="${REPO_ROOT}/lib/baseline_tls.sh"
BASELINE_DB_LIB="${REPO_ROOT}/lib/baseline_db.sh"
BASELINE_DNS_LIB="${REPO_ROOT}/lib/baseline_dns.sh"
BASELINE_ORIGIN_LIB="${REPO_ROOT}/lib/baseline_origin.sh"
BASELINE_PROXY_LIB="${REPO_ROOT}/lib/baseline_proxy.sh"
BASELINE_WP_LIB="${REPO_ROOT}/lib/baseline_wp.sh"
BASELINE_LSWS_LIB="${REPO_ROOT}/lib/baseline_lsws.sh"
BASELINE_CACHE_LIB="${REPO_ROOT}/lib/baseline_cache.sh"
BASELINE_SYS_LIB="${REPO_ROOT}/lib/baseline_sys.sh"
BASELINE_TRIAGE_LIB="${REPO_ROOT}/lib/baseline_triage.sh"

cd /

# install-lomp-lnmp-standard.sh
# 更新记录:
# - v0.9:
#   - 完成"彻底移除本机 OLS""按 slug 清理站点"后，不再直接退出脚本，
#     而是提示已完成并返回「清理本机 OLS / WordPress」菜单。
#   - 完成"清理数据库 / Redis"后，不再直接退出脚本，而是返回「清理数据库 / Redis」菜单。
#   - 安装流程完成后，在总结信息下方新增简单菜单：1) 返回主菜单  0) 退出脚本。
# - v0.8:
#   - 修复: 不再安装不存在的 lsphp83-xml / lsphp83-zip 包，避免 apt 报错中断。
#   - 新增: 顶层主菜单 (0/1/2/3/4)，支持安装、LNMP 占位、本机 OLS/WordPress 清理、DB/Redis 清理。
#   - 新增: "清理本机 OLS / WordPress" 二级菜单:
#         1) 彻底移除本机 OLS (apt purge openlitespeed + lsphp83*，删除 /usr/local/lsws)
#         2) 按 slug 清理某个站点 (删除 vhost + /var/www/<slug>)。
#   - 新增: "清理数据库 / Redis" 二级菜单:
#         1) 清理数据库 (DROP DATABASE + DROP USER，需多次确认)
#         2) 清理 Redis (按 DB index 执行 FLUSHDB，需双重确认 + YES)
#   - 调整: 内存不足提示整合进主菜单; 安装流程封装为 install_lomp_flow()。

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
NC="\033[0m"

POST_SUMMARY_SHOWN=0
SYS_PROFILE_SHOWN=0
HTTPS_CHECKS_SHOWN=0
SSL_MODE="none"
SITE_SIZE_LIMIT_ENABLED="no"
SITE_SIZE_LIMIT_GB=""
SITE_SIZE_CHECK_SCRIPT=""
SITE_SIZE_CHECK_SERVICE=""
SITE_SIZE_CHECK_TIMER=""
LSPHP_EXTENSIONS_APT_UPDATED=0

if [ -r "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  . "$COMMON_LIB"
fi

if [ -r "$BASELINE_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_LIB"
fi

if [ -r "$BASELINE_HTTPS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_HTTPS_LIB"
fi

if [ -r "$BASELINE_TLS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_TLS_LIB"
fi

if [ -r "$BASELINE_DB_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_DB_LIB"
fi

if [ -r "$BASELINE_DNS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_DNS_LIB"
fi

if [ -r "$BASELINE_ORIGIN_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_ORIGIN_LIB"
fi

if [ -r "$BASELINE_PROXY_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_PROXY_LIB"
fi

if [ -r "$BASELINE_WP_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_WP_LIB"
fi

if [ -r "$BASELINE_LSWS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_LSWS_LIB"
fi
if [ -r "$BASELINE_CACHE_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_CACHE_LIB"
fi
if [ -r "$BASELINE_SYS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_SYS_LIB"
fi
if [ -r "$BASELINE_TRIAGE_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BASELINE_TRIAGE_LIB"
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

normalize_wp_profile() {
  local profile
  profile="${1:-}"
  profile="${profile,,}"

  case "$profile" in
    lomp-lite|lomp-standard)
      printf "%s" "$profile"
      ;;
    *)
      return 1
      ;;
  esac
}

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

get_recommended_lomp_tier() {
  # [ANCHOR:GET_RECOMMENDED_TIER]
  local raw_tier normalized

  detect_system_profile
  detect_recommended_tier

  raw_tier="${RECOMMENDED_TIER:-}"
  normalized="$(normalize_tier "${raw_tier,,}")" || true

  if [ -z "$normalized" ]; then
    normalized="$LOMP_DEFAULT_TIER"
  fi

  printf "%s" "$normalized"
}

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

is_menu_context() {
  if [ "${HZ_ENTRY:-}" = "menu" ]; then
    return 0
  fi

  if [ -n "${HZ_WP_PROFILE:-}" ]; then
    return 0
  fi

  return 1
}

get_finish_lang() {
  local lang
  lang="${HZ_LANG:-${LANG:-zh}}"
  if [[ "${lang,,}" == en* ]]; then
    echo "en"
  else
    echo "zh"
  fi
}

get_install_base_url() {
  local base="${HZ_INSTALL_BASE_URL:-https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main}"
  base="${base%/}"
  printf "%s" "$base"
}

print_optimize_rerun_command() {
  local base installer envs=()
  base="$(get_install_base_url)"
  installer="${base}/modules/wp/install-ols-wp-standard.sh"

  envs+=("HZ_PHASE=optimize")
  if [ -n "${HZ_ENTRY:-}" ]; then
    envs+=("HZ_ENTRY=${HZ_ENTRY}")
  fi
  if [ -n "${HZ_LANG:-}" ]; then
    envs+=("HZ_LANG=${HZ_LANG}")
  fi
  if [ -n "${HZ_WP_PROFILE:-}" ]; then
    envs+=("HZ_WP_PROFILE=${HZ_WP_PROFILE}")
  fi
  if [ -n "${HZ_INSTALL_BASE_URL:-}" ]; then
    envs+=("HZ_INSTALL_BASE_URL=${HZ_INSTALL_BASE_URL}")
  fi
  if [ -n "${SITE_DOMAIN:-}" ]; then
    envs+=("SITE_DOMAIN=${SITE_DOMAIN}")
  fi
  if [ -n "${SITE_SLUG:-}" ]; then
    envs+=("SITE_SLUG=${SITE_SLUG}")
  fi
  if [ -n "${DOC_ROOT:-}" ]; then
    envs+=("DOC_ROOT=${DOC_ROOT}")
  fi

  printf "%s bash <(curl -fsSL \"%s\")\n" "${envs[*]}" "$installer"
}

resolve_optimize_site_context() {
  local detected_doc_root=""
  local slug=""
  local domain=""
  local wp_config_path=""
  local site_url=""

  if [ -n "${DOC_ROOT:-}" ] && [ -d "$DOC_ROOT" ]; then
    detected_doc_root="$DOC_ROOT"
  fi

  if [ -z "$detected_doc_root" ] && [ -n "${SITE_SLUG:-}" ]; then
    if [ -d "/var/www/${SITE_SLUG}/html" ]; then
      detected_doc_root="/var/www/${SITE_SLUG}/html"
    fi
  fi

  if [ -z "$detected_doc_root" ] && [ -n "${SITE_DOMAIN:-}" ]; then
    slug="${SITE_DOMAIN%%.*}"
    if [ -n "$slug" ] && [ -d "/var/www/${slug}/html" ]; then
      detected_doc_root="/var/www/${slug}/html"
      SITE_SLUG="${SITE_SLUG:-$slug}"
    fi
  fi

  if [ -z "$detected_doc_root" ]; then
    wp_config_path="$(find /var/www -maxdepth 4 -type f -name wp-config.php -print -quit 2>/dev/null || true)"
    if [ -n "$wp_config_path" ]; then
      detected_doc_root="$(dirname "$wp_config_path")"
    fi
  fi

  if [ -n "$detected_doc_root" ]; then
    DOC_ROOT="$detected_doc_root"
    if [ -z "${SITE_SLUG:-}" ]; then
      slug="$(basename "$(dirname "$detected_doc_root")")"
      if [ -n "$slug" ] && [ "$slug" != "/" ]; then
        SITE_SLUG="$slug"
      fi
    fi
  fi

  if [ -z "${SITE_DOMAIN:-}" ] && command -v wp >/dev/null 2>&1; then
    if [ -n "${DOC_ROOT:-}" ] && [ -d "$DOC_ROOT" ]; then
      site_url="$(wp --path="$DOC_ROOT" --allow-root option get home --skip-plugins --skip-themes 2>/dev/null || true)"
      if [ -z "$site_url" ]; then
        site_url="$(wp --path="$DOC_ROOT" --allow-root option get siteurl --skip-plugins --skip-themes 2>/dev/null || true)"
      fi
      site_url="${site_url%/}"
      site_url="${site_url#http://}"
      site_url="${site_url#https://}"
      site_url="${site_url%%/*}"
      domain="$site_url"
      if [ -n "$domain" ]; then
        SITE_DOMAIN="$domain"
      fi
    fi
  fi
}

is_openlitespeed_active() {
  if [ -d /usr/local/lsws ]; then
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | grep -q '^lsws\.service'; then
      return 0
    fi
  fi

  if command -v dpkg >/dev/null 2>&1; then
    if dpkg -l | grep -q '^ii[[:space:]]\+openlitespeed[[:space:]]'; then
      return 0
    fi
  fi

  return 1
}

optimize_finish_menu() {
  local lang choice
  lang="$(get_finish_lang)"

  if [ ! -t 0 ]; then
    return 0
  fi

  while true; do
    echo
    if [ "$lang" = "en" ]; then
      echo "=== Optimize Complete ==="
      echo "  1) Return to main menu"
      echo "  0) Exit"
      read -rp "Choose [0-1]: " choice
    else
      echo "=== Optimize 完成 ==="
      echo "  1) 返回主菜单"
      echo "  0) 退出"
      read -rp "请输入选项 [0-1]: " choice
    fi

    case "$choice" in
      1)
        if is_menu_context; then
          show_main_menu
          return
        fi
        if [ "$lang" = "en" ]; then
          echo "Not in menu mode, exiting."
        else
          echo "当前不是菜单模式，退出。"
        fi
        exit 0
        ;;
      0)
        exit 0
        ;;
      *)
        if [ "$lang" = "en" ]; then
          echo "Invalid choice, please try again."
        else
          echo "无效选项，请重试。"
        fi
        ;;
    esac
  done
}

opt_prepare_context() {
  local lang
  local wp_path
  lang="$(get_finish_lang)"

  resolve_optimize_site_context
  wp_path="${DOC_ROOT:-}"

  if [ -z "$wp_path" ] || [ ! -d "$wp_path" ]; then
    if [ "$lang" = "en" ]; then
      log_warn "Site root not detected; skip optimize."
    else
      log_warn "未检测到站点目录，跳过 Optimize。"
    fi
    return 1
  fi

  if ! ensure_wp_cli; then
    if [ "$lang" = "en" ]; then
      log_warn "wp-cli not ready; skip optimize."
    else
      log_warn "wp-cli 未就绪，跳过 Optimize。"
    fi
    return 1
  fi

  if ! wp --path="$wp_path" --allow-root core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    if [ "$lang" = "en" ]; then
      log_warn "WordPress not installed yet; please finish /wp-admin/install.php first, then re-run Optimize."
      echo "Re-run command:"
    else
      log_warn "WordPress 尚未安装；请先完成 /wp-admin/install.php，然后重新运行 Optimize。"
      echo "重新运行命令："
    fi
    print_optimize_rerun_command
    return 1
  fi

  if [ "$lang" = "en" ]; then
    log_info "Detected site root: ${wp_path}"
  else
    log_info "已检测站点目录：${wp_path}"
  fi
  if [ -n "${SITE_DOMAIN:-}" ]; then
    if [ "$lang" = "en" ]; then
      log_info "Detected domain: ${SITE_DOMAIN}"
    else
      log_info "已检测域名：${SITE_DOMAIN}"
    fi
  fi

  OPT_WP_PATH="$wp_path"
  return 0
}

opt_task_lscwp() {
  local lang
  local wp_path
  lang="$(get_finish_lang)"

  log_step "Optimize: LSCWP"
  if ! opt_prepare_context; then
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  if ! is_openlitespeed_active; then
    if [ "$lang" = "en" ]; then
      log_warn "OpenLiteSpeed not detected; skip LSCWP."
    else
      log_warn "未检测到 OpenLiteSpeed，跳过 LSCWP。"
    fi
    return 1
  fi

  if wp --path="$wp_path" --allow-root plugin is-installed litespeed-cache --skip-plugins --skip-themes >/dev/null 2>&1; then
    if wp --path="$wp_path" --allow-root plugin activate litespeed-cache --skip-plugins --skip-themes >/dev/null 2>&1; then
      if [ "$lang" = "en" ]; then
        log_info "LiteSpeed Cache activated (settings unchanged)."
      else
        log_info "LiteSpeed Cache 已启用（设置未更改）。"
      fi
    else
      if [ "$lang" = "en" ]; then
        log_warn "LiteSpeed Cache activation failed."
      else
        log_warn "LiteSpeed Cache 启用失败。"
      fi
      return 1
    fi
  else
    if wp --path="$wp_path" --allow-root plugin install litespeed-cache --activate --skip-plugins --skip-themes >/dev/null 2>&1; then
      if [ "$lang" = "en" ]; then
        log_info "LiteSpeed Cache installed and activated (settings unchanged)."
      else
        log_info "LiteSpeed Cache 已安装并启用（设置未更改）。"
      fi
    else
      if [ "$lang" = "en" ]; then
        log_warn "LiteSpeed Cache install/activation failed."
      else
        log_warn "LiteSpeed Cache 安装/启用失败。"
      fi
      return 1
    fi
  fi

  return 0
}

opt_task_baseline_cleanup() {
  local lang
  local wp_path
  local post_ids_raw page_ids_raw comment_ids_raw
  local post_ids=()
  local page_ids=()
  local comment_ids=()
  lang="$(get_finish_lang)"

  log_step "Optimize: baseline cleanup"
  if ! opt_prepare_context; then
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  post_ids_raw="$(wp --path="$wp_path" --allow-root post list --post_type=post --format=ids --skip-plugins --skip-themes 2>/dev/null || true)"
  read -r -a post_ids <<<"$post_ids_raw"
  if [ "${#post_ids[@]}" -gt 0 ]; then
    wp --path="$wp_path" --allow-root post delete "${post_ids[@]}" --force --skip-plugins --skip-themes
  else
    if [ "$lang" = "en" ]; then
      log_info "No posts to delete."
    else
      log_info "无可删除文章。"
    fi
  fi

  page_ids_raw="$(wp --path="$wp_path" --allow-root post list --post_type=page --format=ids --skip-plugins --skip-themes 2>/dev/null || true)"
  read -r -a page_ids <<<"$page_ids_raw"
  if [ "${#page_ids[@]}" -gt 0 ]; then
    wp --path="$wp_path" --allow-root post delete "${page_ids[@]}" --force --skip-plugins --skip-themes
  else
    if [ "$lang" = "en" ]; then
      log_info "No pages to delete."
    else
      log_info "无可删除页面。"
    fi
  fi

  comment_ids_raw="$(wp --path="$wp_path" --allow-root comment list --format=ids --skip-plugins --skip-themes 2>/dev/null || true)"
  read -r -a comment_ids <<<"$comment_ids_raw"
  if [ "${#comment_ids[@]}" -gt 0 ]; then
    wp --path="$wp_path" --allow-root comment delete "${comment_ids[@]}" --force --skip-plugins --skip-themes
  else
    if [ "$lang" = "en" ]; then
      log_info "No comments to delete."
    else
      log_info "无可删除评论。"
    fi
  fi

  apply_wp_site_health_baseline
  if [ "$lang" = "en" ]; then
    log_info "Baseline cleanup done."
  else
    log_info "基线清理完成。"
  fi
}

opt_task_theme_cleanup() {
  local lang wp_path active_theme
  local inactive_themes_raw inactive_themes=()
  local candidates=()
  local theme
  lang="$(get_finish_lang)"

  log_step "Optimize: Theme cleanup (default themes)"
  if ! opt_prepare_context; then
    return 1
  fi

  if ! ensure_wp_cli; then
    if [ "$lang" = "en" ]; then
      log_warn "wp-cli not ready; skip theme cleanup."
    else
      log_warn "wp-cli 未就绪，跳过主题清理。"
    fi
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  active_theme="$(wp --path="$wp_path" --allow-root theme list --status=active --field=stylesheet --skip-plugins --skip-themes 2>/dev/null | head -n 1)"
  if [ -z "$active_theme" ]; then
    if [ "$lang" = "en" ]; then
      log_warn "Unable to detect active theme; skip cleanup."
    else
      log_warn "无法检测当前启用主题，跳过清理。"
    fi
    return 1
  fi

  inactive_themes_raw="$(wp --path="$wp_path" --allow-root theme list --status=inactive --field=stylesheet --skip-plugins --skip-themes 2>/dev/null || true)"
  if [ -n "$inactive_themes_raw" ]; then
    mapfile -t inactive_themes <<<"$inactive_themes_raw"
  fi

  for theme in "${inactive_themes[@]}"; do
    if [[ "$theme" =~ ^twentytwenty ]] && [ "$theme" != "$active_theme" ]; then
      candidates+=("$theme")
    fi
  done

  if [ "${#candidates[@]}" -eq 0 ]; then
    if [ "$lang" = "en" ]; then
      log_info "No inactive default themes to remove."
    else
      log_info "无可清理的默认主题。"
    fi
    return 0
  fi

  if wp --path="$wp_path" --allow-root theme delete "${candidates[@]}" --skip-plugins --skip-themes; then
    if [ "$lang" = "en" ]; then
      log_ok "Removed inactive default themes: ${candidates[*]}"
    else
      log_ok "已清理默认主题：${candidates[*]}"
    fi
    return 0
  fi

  if [ "$lang" = "en" ]; then
    log_warn "Theme cleanup failed."
  else
    log_warn "主题清理失败。"
  fi
  return 1
}

opt_task_plugin_cleanup() {
  local lang wp_path
  local inactive_plugins_raw inactive_plugins=()
  lang="$(get_finish_lang)"

  log_step "Optimize: Plugin cleanup (inactive plugins)"
  if ! opt_prepare_context; then
    return 1
  fi

  if ! ensure_wp_cli; then
    if [ "$lang" = "en" ]; then
      log_warn "wp-cli not ready; skip plugin cleanup."
    else
      log_warn "wp-cli 未就绪，跳过插件清理。"
    fi
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  inactive_plugins_raw="$(wp --path="$wp_path" --allow-root plugin list --status=inactive --field=name --skip-plugins --skip-themes 2>/dev/null || true)"
  read -r -a inactive_plugins <<<"$inactive_plugins_raw"
  if [ "${#inactive_plugins[@]}" -eq 0 ]; then
    if [ "$lang" = "en" ]; then
      log_info "No inactive plugins to delete."
    else
      log_info "无可删除的未启用插件。"
    fi
    return 0
  fi

  if wp --path="$wp_path" --allow-root plugin uninstall "${inactive_plugins[@]}" --delete --skip-plugins --skip-themes --quiet; then
    if [ "$lang" = "en" ]; then
      log_ok "Inactive plugins removed: ${inactive_plugins[*]}"
    else
      log_ok "未启用插件已清理：${inactive_plugins[*]}"
    fi
    return 0
  fi

  if [ "$lang" = "en" ]; then
    log_warn "Plugin cleanup failed."
  else
    log_warn "插件清理失败。"
  fi
  return 1
}

opt_task_permalinks() {
  local lang
  lang="$(get_finish_lang)"

  log_step "Optimize: permalinks"
  if ! opt_prepare_context; then
    return 1
  fi

  ensure_wp_permalink_structure
  if [ "$lang" = "en" ]; then
    log_info "Permalinks checked."
  else
    log_info "固定链接已检查。"
  fi
}

opt_task_indexing_policy() {
  local lang
  lang="$(get_finish_lang)"

  log_step "Optimize: indexing policy"
  if ! opt_prepare_context; then
    return 1
  fi

  ensure_wp_indexing_policy
  if [ "$lang" = "en" ]; then
    log_info "Indexing policy checked."
  else
    log_info "索引策略已检查。"
  fi
}

opt_task_rest_api_check() {
  local lang wp_path site_url scheme host url http_code
  lang="$(get_finish_lang)"

  log_step "Optimize: REST API /wp-json"
  if ! opt_prepare_context; then
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  site_url="$(wp --path="$wp_path" --allow-root option get home --skip-plugins --skip-themes 2>/dev/null || true)"
  if [ -z "$site_url" ]; then
    site_url="$(wp --path="$wp_path" --allow-root option get siteurl --skip-plugins --skip-themes 2>/dev/null || true)"
  fi
  site_url="${site_url%/}"

  if [ -z "$site_url" ]; then
    if [ "$lang" = "en" ]; then
      log_warn "Unable to read site URL via wp-cli; skip REST API check."
    else
      log_warn "无法通过 wp-cli 读取站点 URL，跳过 REST API 检查。"
    fi
    return 1
  fi

  scheme="$(printf '%s' "$site_url" | awk -F:// '{print $1}')"
  host="$(printf '%s' "$site_url" | sed -E 's#^[a-zA-Z]+://##; s#/.*##')"
  if [ "$scheme" = "$site_url" ] || [ -z "$scheme" ]; then
    scheme="http"
  fi
  if [ -z "$host" ]; then
    host="$site_url"
  fi

  url="${scheme}://127.0.0.1/wp-json/"
  if [ "$lang" = "en" ]; then
    log_info "Checking REST API: ${url} (Host: ${host})"
  else
    log_info "检查 REST API：${url}（Host：${host}）"
  fi

  if [ "$scheme" = "https" ]; then
    http_code="$(curl -sS -o /dev/null -w "%{http_code}" -L --max-redirs 5 -H "Host: ${host}" -k "${url}" 2>/dev/null || true)"
  else
    http_code="$(curl -sS -o /dev/null -w "%{http_code}" -L --max-redirs 5 -H "Host: ${host}" "${url}" 2>/dev/null || true)"
  fi

  if [ "$lang" = "en" ]; then
    log_info "HTTP status: ${http_code}"
  else
    log_info "HTTP 状态：${http_code}"
  fi

  case "$http_code" in
    200)
      if [ "$lang" = "en" ]; then
        log_ok "REST API reachable (HTTP 200)."
      else
        log_ok "REST API 可访问（HTTP 200）。"
      fi
      ;;
    000)
      if [ "$lang" = "en" ]; then
        log_warn "No HTTP response from loopback. Check web server, firewall, or local loopback access."
      else
        log_warn "Loopback 未收到 HTTP 响应，请检查 Web 服务、防火墙或本机回环访问。"
      fi
      ;;
    *)
      if [ "$lang" = "en" ]; then
        log_warn "REST API check returned HTTP ${http_code}."
        log_info "Check permalinks (pretty permalinks), security/caching rules blocking /wp-json/, and rewrite rules."
        log_info "If using LiteSpeed/LSCWP, review REST API blocking options."
      else
        log_warn "REST API 检查返回 HTTP ${http_code}。"
        log_info "请检查固定链接（美观链接）、安全/缓存规则是否拦截 /wp-json/，以及重写规则。"
        log_info "如使用 LiteSpeed/LSCWP，请检查是否启用了 REST API 阻止选项。"
      fi
      ;;
  esac
}

opt_task_site_health_snapshot() {
  local lang wp_path status_json_path status_txt_path good_count recommended_count critical_count
  lang="$(get_finish_lang)"

  log_step "Optimize: Site Health snapshot"
  if ! opt_prepare_context; then
    return 1
  fi

  if ! ensure_wp_cli; then
    if [ "$lang" = "en" ]; then
      log_warn "wp-cli not ready; skip Site Health snapshot."
    else
      log_warn "wp-cli 未就绪，跳过站点健康快照。"
    fi
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  status_json_path="/tmp/hz-site-health-status.json"
  status_txt_path="/tmp/hz-site-health-status.txt"

  if wp --path="$wp_path" --allow-root site-health status --format=json --skip-plugins --skip-themes >"$status_json_path" 2>/dev/null; then
    if [ -s "$status_json_path" ]; then
      good_count="$(grep -o '"status":"good"' "$status_json_path" | wc -l | tr -d ' ')"
      recommended_count="$(grep -o '"status":"recommended"' "$status_json_path" | wc -l | tr -d ' ')"
      critical_count="$(grep -o '"status":"critical"' "$status_json_path" | wc -l | tr -d ' ')"

      if [ "$lang" = "en" ]; then
        log_info "Site Health snapshot saved: ${status_json_path}"
        log_info "Summary: good ${good_count}, recommended ${recommended_count}, critical ${critical_count}"
      else
        log_info "站点健康快照已保存：${status_json_path}"
        log_info "概要：良好 ${good_count}，建议 ${recommended_count}，严重 ${critical_count}"
      fi
      return 0
    fi
  fi

  if wp --path="$wp_path" --allow-root site-health status --skip-plugins --skip-themes >"$status_txt_path" 2>/dev/null; then
    if [ -s "$status_txt_path" ]; then
      if [ "$lang" = "en" ]; then
        log_info "Site Health snapshot saved: ${status_txt_path}"
      else
        log_info "站点健康快照已保存：${status_txt_path}"
      fi
      return 0
    fi
  fi

  if [ "$lang" = "en" ]; then
    log_warn "Unable to generate Site Health snapshot."
  else
    log_warn "无法生成站点健康快照。"
  fi
  return 1
}

opt_task_core_checksums() {
  local lang wp_path checksum_path
  lang="$(get_finish_lang)"

  log_step "Optimize: WP core integrity"
  if ! opt_prepare_context; then
    return 1
  fi

  if ! ensure_wp_cli; then
    if [ "$lang" = "en" ]; then
      log_warn "wp-cli not ready; skip core integrity check."
    else
      log_warn "wp-cli 未就绪，跳过核心完整性检查。"
    fi
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  checksum_path="/tmp/hz-wp-checksums.txt"

  if wp --path="$wp_path" --allow-root core verify-checksums --skip-plugins --skip-themes >"$checksum_path" 2>&1; then
    if [ "$lang" = "en" ]; then
      log_ok "WP core checksums verified."
      log_info "Saved output: ${checksum_path}"
    else
      log_ok "WP 核心校验完成。"
      log_info "输出已保存：${checksum_path}"
    fi
    return 0
  fi

  if [ "$lang" = "en" ]; then
    log_warn "WP core checksum verification reported issues."
    log_info "Core files may be modified/corrupted; review ${checksum_path}"
  else
    log_warn "WP 核心校验发现异常。"
    log_info "核心文件可能被修改/损坏，请查看 ${checksum_path}"
  fi
  return 1
}

opt_task_security_snapshot() {
  local lang wp_path report_path
  local wp_version site_url home_url permalink_structure
  local blog_public users_can_register
  local admin_users_raw admin_users_count
  lang="$(get_finish_lang)"

  log_step "Optimize: Security snapshot"
  if ! opt_prepare_context; then
    return 1
  fi

  if ! ensure_wp_cli; then
    if [ "$lang" = "en" ]; then
      log_warn "wp-cli not ready; skip Security snapshot."
    else
      log_warn "wp-cli 未就绪，跳过安全快照。"
    fi
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  report_path="/tmp/hz-wp-security-snapshot.txt"

  : >"$report_path"

  wp_version="$(wp --path="$wp_path" --allow-root core version --skip-plugins --skip-themes 2>/dev/null || true)"
  site_url="$(wp --path="$wp_path" --allow-root option get siteurl --skip-plugins --skip-themes 2>/dev/null || true)"
  home_url="$(wp --path="$wp_path" --allow-root option get home --skip-plugins --skip-themes 2>/dev/null || true)"
  permalink_structure="$(wp --path="$wp_path" --allow-root option get permalink_structure --skip-plugins --skip-themes 2>/dev/null || true)"
  blog_public="$(wp --path="$wp_path" --allow-root option get blog_public --skip-plugins --skip-themes 2>/dev/null || true)"
  users_can_register="$(wp --path="$wp_path" --allow-root option get users_can_register --skip-plugins --skip-themes 2>/dev/null || true)"
  admin_users_raw="$(wp --path="$wp_path" --allow-root user list --role=administrator --fields=user_login,roles --skip-plugins --skip-themes 2>/dev/null || true)"
  admin_users_count="$(printf '%s\n' "$admin_users_raw" | sed '/^$/d' | wc -l | tr -d ' ')"

  {
    echo "=== WordPress Security Snapshot ==="
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Site path: ${wp_path}"
    echo
    echo "WordPress version: ${wp_version:-unknown}"
    echo "Site URL: ${site_url:-unknown}"
    echo "Home URL: ${home_url:-unknown}"
    echo "Permalink structure: ${permalink_structure:-empty}"
    echo
    echo "REST API reachability: see Optimize: REST API /wp-json check output (console logs)."
    echo "Core integrity checksums: /tmp/hz-wp-checksums.txt (if run)."
    echo
    echo "Discourage search engines (blog_public): ${blog_public:-unknown}"
    echo "User registration enabled (users_can_register): ${users_can_register:-unknown}"
    echo
    echo "Admin users (user_login, roles):"
    if [ -n "$admin_users_raw" ]; then
      printf '%s\n' "$admin_users_raw"
    else
      echo "No admin users found or wp-cli failed."
    fi
    echo
    echo "File/dir permissions snapshot:"
  } >>"$report_path"

  for path in "$wp_path/wp-config.php" "$wp_path/wp-content" "$wp_path/wp-content/uploads"; do
    if [ -e "$path" ]; then
      if stat -c '%a %U:%G %n' "$path" >/dev/null 2>&1; then
        stat -c '%a %U:%G %n' "$path" >>"$report_path"
      elif stat -f '%Lp %Su:%Sg %N' "$path" >/dev/null 2>&1; then
        stat -f '%Lp %Su:%Sg %N' "$path" >>"$report_path"
      else
        echo "stat unavailable for ${path}" >>"$report_path"
      fi
    else
      echo "Missing: ${path}" >>"$report_path"
    fi
  done

  {
    echo
    echo "Presence checks:"
    if [ -f "$wp_path/xmlrpc.php" ]; then
      echo "xmlrpc.php: present"
    else
      echo "xmlrpc.php: missing"
    fi
    if [ -f "$wp_path/wp-config-sample.php" ]; then
      echo "wp-config-sample.php: present"
    else
      echo "wp-config-sample.php: missing"
    fi
  } >>"$report_path"

  if [ "$lang" = "en" ]; then
    log_ok "Security snapshot saved."
    log_info "Saved output: ${report_path}"
    log_info "Summary: blog_public=${blog_public:-unknown}, users_can_register=${users_can_register:-unknown}, admin_users=${admin_users_count:-0}"
  else
    log_ok "安全快照已保存。"
    log_info "输出已保存：${report_path}"
    log_info "概要：blog_public=${blog_public:-unknown}，users_can_register=${users_can_register:-unknown}，管理员数量=${admin_users_count:-0}"
  fi
  return 0
}

opt_task_hardening_check() {
  local lang wp_path report_path wp_version site_url home_url
  local admin_users_raw admin_users_count wp_config_path
  local const value const_line world_writable_count world_writable_list
  lang="$(get_finish_lang)"

  log_step "Optimize: Hardening check"
  if ! opt_prepare_context; then
    return 1
  fi

  if ! ensure_wp_cli; then
    if [ "$lang" = "en" ]; then
      log_warn "wp-cli not ready; skip Hardening check."
    else
      log_warn "wp-cli 未就绪，跳过加固检查。"
    fi
    return 1
  fi

  wp_path="${OPT_WP_PATH:-}"
  report_path="/tmp/hz-wp-hardening-check.txt"
  wp_config_path="${wp_path}/wp-config.php"

  : >"$report_path"

  wp_version="$(wp --path="$wp_path" --allow-root core version --skip-plugins --skip-themes 2>/dev/null || true)"
  site_url="$(wp --path="$wp_path" --allow-root option get siteurl --skip-plugins --skip-themes 2>/dev/null || true)"
  home_url="$(wp --path="$wp_path" --allow-root option get home --skip-plugins --skip-themes 2>/dev/null || true)"
  admin_users_raw="$(wp --path="$wp_path" --allow-root user list --role=administrator --fields=user_login --skip-plugins --skip-themes 2>/dev/null || true)"
  admin_users_count="$(printf '%s\n' "$admin_users_raw" | sed '/^$/d' | wc -l | tr -d ' ')"

  {
    echo "=== WordPress Hardening Check ==="
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Site path: ${wp_path}"
    echo
    echo "WordPress version: ${wp_version:-unknown}"
    echo "Site URL: ${site_url:-unknown}"
    echo "Home URL: ${home_url:-unknown}"
    echo
    echo "Admin users (user_login):"
    if [ -n "$admin_users_raw" ]; then
      printf '%s\n' "$admin_users_raw"
    else
      echo "No admin users found or wp-cli failed."
    fi
    echo "Admin user count: ${admin_users_count:-0}"
    echo
    echo "wp-config.php:"
  } >>"$report_path"

  if [ -e "$wp_config_path" ]; then
    if stat -c '%a %U:%G %n' "$wp_config_path" >/dev/null 2>&1; then
      stat -c '%a %U:%G %n' "$wp_config_path" >>"$report_path"
    elif stat -f '%Lp %Su:%Sg %N' "$wp_config_path" >/dev/null 2>&1; then
      stat -f '%Lp %Su:%Sg %N' "$wp_config_path" >>"$report_path"
    else
      echo "stat unavailable for ${wp_config_path}" >>"$report_path"
    fi
  else
    echo "Missing: ${wp_config_path}" >>"$report_path"
  fi

  {
    echo
    echo "wp-config constants (best-effort):"
  } >>"$report_path"

  for const in DISALLOW_FILE_EDIT WP_DEBUG WP_DEBUG_DISPLAY WP_AUTO_UPDATE_CORE AUTOMATIC_UPDATER_DISABLED; do
    const_line=""
    value=""
    if [ -f "$wp_config_path" ]; then
      const_line="$(grep -E "^[[:space:]]*define\\(\\s*['\"]${const}['\"]" "$wp_config_path" | head -n 1 || true)"
      if [ -n "$const_line" ]; then
        value="$(printf '%s' "$const_line" | sed -E "s/.*define\\(\\s*['\"]${const}['\"]\\s*,\\s*([^)]*)\\).*/\\1/")"
        if [ -z "$value" ] || [ "$value" = "$const_line" ]; then
          value="set (unable to parse)"
        fi
      fi
    fi
    if [ -n "$const_line" ]; then
      echo "${const}: ${value}" >>"$report_path"
    else
      echo "${const}: not set" >>"$report_path"
    fi
  done

  {
    echo
    echo "World-writable paths (other-writable bit) under site root:"
  } >>"$report_path"

  if [ -d "$wp_path" ]; then
    world_writable_count="$(find "$wp_path" -xdev -perm -0002 2>/dev/null | wc -l | tr -d ' ')"
    world_writable_list="$(find "$wp_path" -xdev -perm -0002 2>/dev/null | head -n 20)"
    echo "Count: ${world_writable_count:-0}" >>"$report_path"
    if [ -n "$world_writable_list" ]; then
      echo "Paths (up to 20):" >>"$report_path"
      printf '%s\n' "$world_writable_list" >>"$report_path"
    else
      echo "Paths (up to 20): none found" >>"$report_path"
    fi
  else
    echo "Site path not found: ${wp_path}" >>"$report_path"
  fi

  if [ "$lang" = "en" ]; then
    log_ok "Hardening check report saved: /tmp/hz-wp-hardening-check.txt"
  else
    log_ok "加固检查报告已保存：/tmp/hz-wp-hardening-check.txt"
  fi
  return 0
}

show_optimize_menu() {
  local lang choice
  lang="$(get_finish_lang)"

  if [ ! -t 0 ]; then
    if [ "$lang" = "en" ]; then
      echo "Optimize menu requires interactive mode. Re-run with:"
    else
      echo "Optimize 菜单需要交互模式，请重新运行："
    fi
    print_optimize_rerun_command
    return 0
  fi

  while true; do
    echo
    if [ "$lang" = "en" ]; then
      echo "=== Optimize Menu ==="
      echo "  1) Optimize: LSCWP (enable)"
      echo "  2) Optimize: baseline cleanup (coming soon)"
      echo "  3) Optimize: Permalinks"
      echo "  4) Optimize: Indexing policy"
      echo "  5) Optimize: REST API /wp-json check"
      echo "  6) Optimize: Site Health snapshot"
      echo "  7) Optimize: WP core integrity (verify checksums)"
      echo "  8) Optimize: Theme cleanup (default themes)"
      echo "  9) Optimize: Plugin cleanup (inactive plugins)"
      echo " 10) Optimize: Security snapshot"
      echo " 11) Optimize: Hardening check"
      echo "  0) Back / Exit"
      read -rp "Choose [0-11]: " choice
    else
      echo "=== Optimize 菜单 ==="
      echo "  1) Optimize：LSCWP（启用）"
      echo "  2) Optimize：基线清理（即将推出）"
      echo "  3) Optimize：固定链接"
      echo "  4) Optimize：索引策略"
      echo "  5) Optimize：REST API /wp-json 检查"
      echo "  6) Optimize：站点健康快照"
      echo "  7) Optimize：WP 核心完整性（校验）"
      echo "  8) Optimize：主题清理（默认主题）"
      echo "  9) Optimize：清理插件（未启用插件）"
      echo " 10) Optimize：安全快照"
      echo " 11) Optimize：加固检查"
      echo "  0) 返回 / 退出"
      read -rp "请输入选项 [0-11]: " choice
    fi

    case "$choice" in
      1)
        if opt_task_lscwp; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      3)
        if opt_task_permalinks; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      4)
        if opt_task_indexing_policy; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      5)
        if opt_task_rest_api_check; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      6)
        if opt_task_site_health_snapshot; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      7)
        if opt_task_core_checksums; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      8)
        if opt_task_theme_cleanup; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      9)
        if opt_task_plugin_cleanup; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      10)
        if opt_task_security_snapshot; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      11)
        if opt_task_hardening_check; then
          optimize_finish_menu
          return 0
        fi
        optimize_finish_menu
        return 1
        ;;
      2)
        if [ "$lang" = "en" ]; then
          echo "Coming soon."
        else
          echo "即将推出。"
        fi
        ;;
      0)
        if is_menu_context; then
          show_main_menu
          return
        fi
        exit 0
        ;;
      *)
        if [ "$lang" = "en" ]; then
          echo "Invalid choice, please try again."
        else
          echo "无效选项，请重试。"
        fi
        ;;
    esac
  done
}

# [ANCHOR:OPTIMIZE_PHASE]
run_optimize_phase() {
  show_optimize_menu
}

# [ANCHOR:FINISH_MENU]
finish_menu() {
  local lang choice
  lang="$(get_finish_lang)"

  if [ ! -t 0 ]; then
    if [ "$lang" = "en" ]; then
      echo "Install finished (non-interactive). To run optimize, re-run with HZ_PHASE=optimize:"
    else
      echo "安装完成（非交互）。如需运行 Optimize，请重新运行并加 HZ_PHASE=optimize："
    fi
    print_optimize_rerun_command
    exit 0
  fi

  while true; do
    echo
    if [ "$lang" = "en" ]; then
      echo "=== Finish Menu ==="
      if is_menu_context; then
        echo "  1) Return to main menu"
      else
        echo "  1) Return to main menu (menu mode only)"
      fi
      echo "  2) Optimize (post-install)"
      echo "  0) Exit"
      read -rp "Choose [0-2]: " choice
    else
      echo "=== 安装完成菜单 ==="
      if is_menu_context; then
        echo "  1) 返回主菜单"
      else
        echo "  1) 返回主菜单（仅菜单模式）"
      fi
      echo "  2) Optimize（安装后）"
      echo "  0) 退出"
      read -rp "请输入选项 [0-2]: " choice
    fi

    case "$choice" in
      1)
        if is_menu_context; then
          show_main_menu
          return
        fi
        if [ "$lang" = "en" ]; then
          echo "Not in menu mode, exiting."
        else
          echo "当前不是菜单模式，退出。"
        fi
        exit 0
        ;;
      2)
        show_optimize_menu
        optimize_finish_menu
        return
        ;;
      0)
        exit 0
        ;;
      *)
        if [ "$lang" = "en" ]; then
          echo "Invalid choice, please try again."
        else
          echo "无效选项，请重试。"
        fi
        ;;
    esac
  done
}

finish_install_flow() {
  finish_menu
}

run_optimize_only_flow() {
  run_optimize_phase
  optimize_finish_menu
}

trap 'log_error "脚本执行中断（行号: $LINENO）。"; exit 1' ERR

require_root() {
  # [ANCHOR:ENV_PRECHECK]
  if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 root 运行本脚本。"
    exit 1
  fi
}

ensure_wp_cli() {
  # [ANCHOR:WP_CLI_SETUP]
  if command -v wp >/dev/null 2>&1; then
    if ! ensure_php_cmd_for_wpcli; then
      return 1
    fi
    if wp --info >/dev/null 2>&1; then
      log_info "检测到 wp-cli：$(command -v wp)"
      return 0
    fi
    log_warn "检测到 wp-cli，但无法运行，尝试重新安装。"
  fi

  log_step "安装 wp-cli"
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq || true
      apt-get install -y curl
    fi
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_error "未找到 curl，无法安装 wp-cli。"
    return 1
  fi

  if curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; then
    chmod +x /usr/local/bin/wp
  else
    log_error "下载 wp-cli 失败，请检查网络连接。"
    return 1
  fi

  if command -v wp >/dev/null 2>&1; then
    if ! ensure_php_cmd_for_wpcli; then
      return 1
    fi
    if wp --info >/dev/null 2>&1; then
      log_info "wp-cli 已安装。"
      return 0
    fi
  fi

  log_error "wp-cli 安装失败，请手动检查 /usr/local/bin/wp。"
  return 1
}

ensure_php_cmd_for_wpcli() {
  local php_bin=""
  local created=0

  if command -v php >/dev/null 2>&1; then
    return 0
  fi

  if [ -n "${LSPHP_BIN:-}" ] && [ -x "$LSPHP_BIN" ]; then
    php_bin="$LSPHP_BIN"
  else
    php_bin="$(detect_lsphp_bin 2>/dev/null || true)"
  fi

  if [ -n "$php_bin" ] && [ -x "$php_bin" ]; then
    if [ ! -e /usr/local/bin/php ]; then
      ln -s "$php_bin" /usr/local/bin/php 2>/dev/null && created=1
    fi
    if [ ! -e /usr/bin/php ] && [ -x /usr/local/bin/php ]; then
      ln -s /usr/local/bin/php /usr/bin/php 2>/dev/null && created=1
    fi
    if [ "$created" -eq 1 ]; then
      log_info "Created php symlink for wp-cli (${php_bin})."
    fi
  fi

  if command -v php >/dev/null 2>&1 && php -v >/dev/null 2>&1; then
    return 0
  fi

  log_error "未检测到可用的 php 命令，wp-cli 无法运行。请确认已安装 LSPHP 并提供 php 可执行文件。"
  return 1
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

detect_system_profile() {
  local arch vcpu mem_kb mem_mb mem_gb disk_total_raw disk_avail_raw os_version

  arch="$(uname -m 2>/dev/null || true)"
  if [ -z "$arch" ]; then
    arch="N/A"
  fi

  if command -v nproc >/dev/null 2>&1; then
    vcpu="$(nproc 2>/dev/null || true)"
  fi
  if ! echo "$vcpu" | grep -Eq '^[0-9]+$'; then
    vcpu="$(lscpu 2>/dev/null | awk -F: '/^CPU\(s\)/{gsub(/ /,"",$2); print $2}' | head -n1)"
  fi
  if ! echo "$vcpu" | grep -Eq '^[0-9]+$'; then
    vcpu="N/A"
  fi

  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if echo "$mem_kb" | grep -Eq '^[0-9]+$'; then
    mem_mb=$((mem_kb / 1024))
    mem_gb="$(awk -v kb="$mem_kb" 'BEGIN {printf "%.1f", kb/1024/1024}')"
  else
    mem_mb="N/A"
    mem_gb="N/A"
  fi

  if command -v df >/dev/null 2>&1; then
    read -r disk_total_raw disk_avail_raw <<EOF
$(df -B1 / 2>/dev/null | awk 'NR==2 {print $2, $4}')
EOF
  fi

  if echo "$disk_total_raw" | grep -Eq '^[0-9]+$'; then
    SYSTEM_DISK_TOTAL="$(awk -v b="$disk_total_raw" 'BEGIN {printf "%.1f GB", b/1024/1024/1024}')"
  else
    SYSTEM_DISK_TOTAL="N/A"
  fi

  if echo "$disk_avail_raw" | grep -Eq '^[0-9]+$'; then
    SYSTEM_DISK_AVAILABLE="$(awk -v b="$disk_avail_raw" 'BEGIN {printf "%.1f GB", b/1024/1024/1024}')"
  else
    SYSTEM_DISK_AVAILABLE="N/A"
  fi

  SYSTEM_ARCH="$arch"
  SYSTEM_VCPU="$vcpu"
  SYSTEM_MEM_MB="$mem_mb"
  SYSTEM_MEM_GB="$mem_gb"

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_version="${VERSION_ID:-${PRETTY_NAME:-}}"
  fi
  if [ -z "$os_version" ]; then
    os_version="N/A"
  fi
  SYSTEM_OS_VERSION="$os_version"
}

# [ANCHOR:CH20_BASELINE_ENTRY]
baseline_print_keywords() {
  local total idx keyword status key_items key_item
  declare -A seen=()

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  echo "=== Baseline Diagnostics KEY ==="
  total=${#BASELINE_RESULTS_STATUS[@]}

  for ((idx=0; idx<total; idx++)); do
    keyword="${BASELINE_RESULTS_KEYWORD[idx]}"
    status="${BASELINE_RESULTS_STATUS[idx]}"

    if [ -z "$keyword" ] || [ "$status" = "PASS" ]; then
      continue
    fi

    # Support multiple keywords separated by spaces.
    read -r -a key_items <<< "$keyword"
    for key_item in "${key_items[@]}"; do
      if [ -n "$key_item" ] && [ -z "${seen[$key_item]+x}" ]; then
        seen["$key_item"]=1
        echo "- $key_item"
      fi
    done
  done

  if [ ${#seen[@]} -eq 0 ]; then
    echo "- (none)"
  fi
}

run_lomp_baseline_diagnostics() {
  local domain lang choice db_host db_port db_name db_user db_pass
  lang="${LANG:-zh}"
  if [[ "${lang,,}" == en* ]]; then
    lang="en"
  else
    lang="zh"
  fi

  while true; do
    if [ "$lang" = "en" ]; then
      echo "=== Baseline Diagnostics ==="
      echo "Advisory checks only: no external configs will be modified and passwords are not stored."
      echo "Select a group to diagnose:"
      echo "  1) Quick Triage (521/HTTPS/TLS)"
      echo "  2) HTTPS/521"
      echo "  3) DB"
      echo "  4) DNS/IP"
      echo "  5) Origin/Firewall (ports/service/UFW)"
      echo "  6) Step20-7 Proxy/CDN (521/TLS)"
      echo "  7) Step20-8 TLS/CERT (SNI/SAN/chain/expiry)"
      echo "  8) Step20-9 WP/App (runtime + HTTP)"
      echo "  9) Step20-10 LOMP/LNMP Web (service/port/config/logs)"
      echo " 10) Step20-11 Cache/Redis/OPcache"
      echo " 11) Step20-12 System/Resource (CPU/RAM/Disk/Swap/Logs)"
      echo "  0) Return to main menu"
      read -rp "Choose [0-11]: " choice
    else
      echo "=== 基线诊断（Baseline） ==="
      echo "仅做连通性诊断，不会修改外部配置，也不会保存密码。"
      echo "请选择要诊断的组："
      echo "  1) 一键快排查（521/HTTPS/TLS）"
      echo "  2) HTTPS/521"
      echo "  3) DB"
      echo "  4) DNS/IP"
      echo "  5) Origin/Firewall（端口/服务/UFW）"
      echo "  6) Step20-7 反代/CDN（521/TLS）"
      echo "  7) Step20-8 TLS/证书（SNI/SAN/链/到期）"
      echo "  8) Step20-9 WP/App（运行态 + HTTP）"
      echo "  9) Step20-10 LOMP/LNMP Web（服务/端口/配置/日志）"
      echo " 10) Step20-11 Cache/Redis/OPcache"
      echo " 11) Step20-12 System/Resource（CPU/内存/磁盘/Swap/日志）"
      echo "  0) 返回主菜单"
      read -rp "请输入选项 [0-11]: " choice
    fi
    echo

    case "$choice" in
      1)
        baseline_init
        domain="${SITE_DOMAIN:-}"
        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            read -rp "Enter the domain to triage (e.g., abc.yourdomain.com): " domain
          else
            read -rp "请输入要排查的域名（例如: abc.yourdomain.com）: " domain
          fi
          domain="${domain//[[:space:]]/}"
        fi

        if [ "$lang" = "en" ]; then
          read -rp "Language [en/zh] (default: ${lang}): " lang_choice
        else
          read -rp "选择语言 [en/zh]（默认: ${lang}）: " lang_choice
        fi
        lang_choice="${lang_choice//[[:space:]]/}"
        lang_choice="${lang_choice,,}"
        if [[ "$lang_choice" =~ ^(en|zh)$ ]]; then
          lang="$lang_choice"
        fi

        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            log_error "Domain is required to run Quick Triage."
          else
            log_error "未提供域名，无法执行一键排查。"
          fi
          continue
        fi

        if declare -F baseline_triage_run >/dev/null 2>&1; then
          baseline_triage_run "$domain" "$lang"
        else
          echo "baseline_triage_run not available"
        fi

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      2)
        baseline_init
        domain="${SITE_DOMAIN:-}"
        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            read -rp "Enter the domain to diagnose (e.g., abc.yourdomain.com): " domain
          else
            read -rp "请输入要诊断的域名（例如: abc.yourdomain.com）: " domain
          fi
          domain="${domain//[[:space:]]/}"
        fi

        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            log_error "Domain is required to run baseline diagnostics."
          else
            log_error "未提供域名，无法执行诊断。"
          fi
          continue
        fi

        if [ "$lang" = "en" ]; then
          echo "Target domain: ${domain}"
        else
          echo "诊断域名: ${domain}"
        fi

        baseline_https_run "$domain" "$lang"

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      3)
        baseline_init
        if [ "$lang" = "en" ]; then
          read -rp "DB host [127.0.0.1]: " db_host
        else
          read -rp "请输入数据库地址 [127.0.0.1]: " db_host
        fi
        db_host="${db_host//[[:space:]]/}"
        if [ -z "$db_host" ]; then
          db_host="127.0.0.1"
        fi

        if [ "$lang" = "en" ]; then
          read -rp "DB port [3306]: " db_port
        else
          read -rp "请输入数据库端口 [3306]: " db_port
        fi
        db_port="${db_port//[[:space:]]/}"
        if [ -z "$db_port" ]; then
          db_port="3306"
        fi

        if [ "$lang" = "en" ]; then
          read -rp "DB name (optional, e.g., wordpress): " db_name
        else
          read -rp "数据库名（可选，建议填写，例如 wordpress）: " db_name
        fi
        db_name="${db_name//[[:space:]]/}"

        while true; do
          if [ "$lang" = "en" ]; then
            read -rp "DB user (required): " db_user
          else
            read -rp "数据库用户名（必填）: " db_user
          fi
          db_user="${db_user//[[:space:]]/}"
          if [ -n "$db_user" ]; then
            break
          fi
          if [ "$lang" = "en" ]; then
            log_warn "DB user is required."
          else
            log_warn "数据库用户名不能为空。"
          fi
        done

        while true; do
          if [ "$lang" = "en" ]; then
            read -srp "DB password (required, hidden): " db_pass
          else
            read -srp "数据库密码（必填，输入不回显）: " db_pass
          fi
          echo
          if [ -n "$db_pass" ]; then
            break
          fi
          if [ "$lang" = "en" ]; then
            log_warn "DB password is required."
          else
            log_warn "数据库密码不能为空。"
          fi
        done

        echo
        baseline_db_run "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass" "$lang"

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        unset db_pass
        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      4)
        baseline_init
        if [ "$lang" = "en" ]; then
          read -rp "Enter the domain to diagnose (e.g., abc.yourdomain.com): " domain
        else
          read -rp "请输入要诊断的域名（例如: abc.yourdomain.com）: " domain
        fi
        domain="${domain//[[:space:]]/}"

        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            log_error "Domain is required to run baseline diagnostics."
          else
            log_error "未提供域名，无法执行诊断。"
          fi
          continue
        fi

        if [ "$lang" = "en" ]; then
          echo "Target domain: ${domain}"
        else
          echo "诊断域名: ${domain}"
        fi

        baseline_dns_run "$domain" "$lang"

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      5)
        baseline_init
        domain="${SITE_DOMAIN:-}"
        if [ "$lang" = "en" ]; then
    read -rp "Enter domain for Host header (optional, e.g., abc.yourdomain.com): " input_domain
        else
    read -rp "请输入 Host 头域名（可留空，例如 abc.yourdomain.com）: " input_domain
        fi
        input_domain="${input_domain//[[:space:]]/}"
        if [ -n "$input_domain" ]; then
          domain="$input_domain"
        fi

        if [ -n "$domain" ]; then
          if [ "$lang" = "en" ]; then
            echo "Target domain (Host header): ${domain}"
          else
            echo "诊断域名（Host 头）: ${domain}"
          fi
        fi

        baseline_origin_run "$domain" "$lang"

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      6)
        baseline_init
        if [ "$lang" = "en" ]; then
          read -rp "Enter the domain to diagnose (e.g., abc.yourdomain.com): " domain
        else
          read -rp "请输入要诊断的域名（例如: abc.yourdomain.com）: " domain
        fi
        domain="${domain//[[:space:]]/}"

        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            log_error "Domain is required to run baseline diagnostics."
          else
            log_error "未提供域名，无法执行诊断。"
          fi
          continue
        fi

        if [ "$lang" = "en" ]; then
          echo "Target domain: ${domain}"
        else
          echo "诊断域名: ${domain}"
        fi

        baseline_proxy_run "$domain" "$lang"

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      7)
        baseline_init
        domain="${SITE_DOMAIN:-}"
        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            read -rp "Enter the domain to diagnose (e.g., abc.yourdomain.com): " domain
          else
            read -rp "请输入要诊断的域名（例如: abc.yourdomain.com）: " domain
          fi
          domain="${domain//[[:space:]]/}"
        fi

        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            log_error "Domain is required to run baseline diagnostics."
          else
            log_error "未提供域名，无法执行诊断。"
          fi
          continue
        fi

        if [ "$lang" = "en" ]; then
          echo "Target domain: ${domain}"
        else
          echo "诊断域名: ${domain}"
        fi

        baseline_tls_run "$domain" "$lang"

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      8)
        baseline_init
        domain="${SITE_DOMAIN:-}"
        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            read -rp "Enter the domain to diagnose (e.g., abc.yourdomain.com): " domain
          else
            read -rp "请输入要诊断的域名（例如: abc.yourdomain.com）: " domain
          fi
          domain="${domain//[[:space:]]/}"
        fi

        if [ "$lang" = "en" ]; then
          read -rp "WordPress path (optional, e.g., /var/www/html): " wp_path
        else
          read -rp "请输入 WordPress 路径（可留空，例如 /var/www/html）: " wp_path
        fi
        wp_path="${wp_path//[[:space:]]/}"

        if [ -z "$domain" ]; then
          if [ "$lang" = "en" ]; then
            log_error "Domain is required to run baseline diagnostics."
          else
            log_error "未提供域名，无法执行诊断。"
          fi
          continue
        fi

        if [ "$lang" = "en" ]; then
          echo "Target domain: ${domain}"
        else
          echo "诊断域名: ${domain}"
        fi

        if declare -F baseline_wp_run >/dev/null 2>&1; then
          baseline_wp_run "$domain" "$wp_path" "$lang"
        else
          baseline_add_result "WP/APP" "WP_BASELINE" "WARN" "wp_module_missing" "module not loaded" ""
        fi

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
        read -rp "按回车返回 Baseline 菜单..." _
      fi
        ;;
      9)
        baseline_init
        if [ "$lang" = "en" ]; then
          read -rp "Domain to probe (optional, leave blank to skip): " domain
        else
          read -rp "请输入要探测的域名（可留空）: " domain
        fi
        domain="${domain//[[:space:]]/}"

        if declare -F baseline_lsws_run >/dev/null 2>&1; then
          baseline_lsws_run "$domain" "$lang"
        else
          baseline_add_result "LOMP/LNMP Web" "LSWS_BASELINE" "WARN" "module_missing" "baseline_lsws.sh not loaded" ""
        fi

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      10)
        baseline_init
        wp_path=""
        redis_pass=""
        if [ "$lang" = "en" ]; then
          read -rp "Auto-detect WordPress path? [Y/n]: " auto_wp
        else
          read -rp "是否自动探测 WordPress 路径？[Y/n]: " auto_wp
        fi
        auto_wp="${auto_wp,,}"
        if [[ "$auto_wp" =~ ^n ]]; then
          if [ "$lang" = "en" ]; then
            read -rp "Enter WordPress path (optional): " wp_path
          else
            read -rp "请输入 WordPress 路径（可留空）: " wp_path
          fi
          wp_path="${wp_path//[[:space:]]/}"
        fi

        if [ "$lang" = "en" ]; then
          read -rp "Need Redis password? [y/N]: " need_redis_pass
        else
          read -rp "Redis 是否需要密码？[y/N]: " need_redis_pass
        fi
        need_redis_pass="${need_redis_pass,,}"
        if [[ "$need_redis_pass" =~ ^y ]]; then
          if [ "$lang" = "en" ]; then
            read -srp "Enter Redis password (hidden, not stored): " redis_pass
          else
            read -srp "请输入 Redis 密码（不回显、不保存）: " redis_pass
          fi
          echo
        fi

        if declare -F baseline_cache_run >/dev/null 2>&1; then
          baseline_cache_run "$wp_path" "$lang" "$redis_pass"
        else
          baseline_add_result "CACHE/REDIS" "CACHE_BASELINE" "WARN" "cache_module_missing" "baseline_cache.sh not loaded" ""
        fi

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        unset redis_pass
        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      11)
        baseline_init
        if declare -F baseline_sys_run >/dev/null 2>&1; then
          baseline_sys_run "$lang"
        else
          baseline_add_result "SYSTEM/RESOURCE" "SYS_BASELINE" "WARN" "module_missing" "baseline_sys.sh not loaded" ""
        fi

        baseline_print_summary
        baseline_print_details
        baseline_print_keywords

        echo
        if [ "$lang" = "en" ]; then
          read -rp "Press Enter to return to Baseline menu..." _
        else
          read -rp "按回车返回 Baseline 菜单..." _
        fi
        ;;
      0)
        show_main_menu
        return
        ;;
      *)
        if [ "$lang" = "en" ]; then
          log_warn "Invalid input, please choose 0-11."
        else
          log_warn "无效输入，请选择 0-11。"
        fi
        ;;
    esac

    echo
  done
}

detect_public_ip() {
  local ipv4 ipv6

  ipv4="$(curl -fsS4 --max-time 3 https://api.ipify.org 2>/dev/null || curl -fsS4 --max-time 3 https://ifconfig.me 2>/dev/null || true)"
  ipv4="$(echo "$ipv4" | tr -d ' \t\r\n')"
  if ! echo "$ipv4" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    if command -v ip >/dev/null 2>&1; then
      ipv4="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    fi
  fi
  if ! echo "$ipv4" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    ipv4="N/A"
  fi

  ipv6="$(curl -fsS6 --max-time 3 https://api64.ipify.org 2>/dev/null || curl -fsS6 --max-time 3 https://ifconfig.me 2>/dev/null || true)"
  ipv6="$(echo "$ipv6" | tr -d ' \t\r\n')"
  if ! echo "$ipv6" | grep -qiE '^[0-9a-f:]+$'; then
    if command -v ip >/dev/null 2>&1; then
      ipv6="$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    fi
  fi
  if ! echo "$ipv6" | grep -qiE '^[0-9a-f:]+$'; then
    ipv6="N/A"
  fi

  DETECTED_IPV4="$ipv4"
  DETECTED_IPV6="$ipv6"
}

detect_recommended_tier() {
  local mem_mb tier reason next_step tier_label

  mem_mb="$SYSTEM_MEM_MB"
  if ! echo "$mem_mb" | grep -Eq '^[0-9]+$'; then
    mem_mb="$(get_ram_mb)"
  fi

  if echo "$mem_mb" | grep -Eq '^[0-9]+$'; then
    if [ "$mem_mb" -lt 4000 ]; then
      tier="$TIER_LITE"
      reason="内存 <4G，推荐 Lite（Frontend-only，仅部署前端），数据库/Redis 放到其他高配机器，通过内网或 Tailscale 等隧道访问。"
      next_step="先准备可通过内网/隧道访问的数据库与 Redis，当前节点只跑前端，降低内存占用。"
    elif [ "$mem_mb" -lt 16000 ]; then
      tier="$TIER_STANDARD"
      reason="内存 4G-<16G，适合 Standard 档（前后端一体），也可外置数据库/Redis 提升稳定性。"
      next_step="如需在本机跑数据库/Redis，请关注资源占用；更推荐放到同内网或隧道可达的专用机器。"
    else
      tier="$TIER_HUB"
      reason="内存 ≥16G，可选择 Hub 档集中承载数据库/Redis，多站复用，也可按需跑 Standard。"
      next_step="如计划集中管理多站点，可选 Hub 档并预留数据库/Redis 资源；单站需求也可保持 Standard。"
    fi
  else
    tier="N/A"
    reason="未能识别内存容量，无法推荐档位。"
    next_step="可手动检查 /proc/meminfo 或 free -m，确认后再选择安装方案。"
  fi

  case "$tier" in
    "$TIER_LITE") tier_label="Lite（Frontend-only）" ;;
    "$TIER_STANDARD") tier_label="Standard" ;;
    "$TIER_HUB") tier_label="Hub" ;;
    *) tier_label="N/A" ;;
  esac

  RECOMMENDED_TIER="$tier_label"
  RECOMMENDED_REASON="$reason"
  RECOMMENDED_NEXT_STEP="$next_step"
}

print_system_summary() {
  detect_system_profile
  detect_public_ip
  detect_recommended_tier

  local arch_display vcpu_display mem_display disk_display os_display ipv4_display ipv6_display

  arch_display="$SYSTEM_ARCH"
  vcpu_display="$SYSTEM_VCPU"
  mem_display="${SYSTEM_MEM_MB} MB / ${SYSTEM_MEM_GB} GB"
  disk_display="总计 ${SYSTEM_DISK_TOTAL} / 可用 ${SYSTEM_DISK_AVAILABLE}"
  os_display="$SYSTEM_OS_VERSION"

  if [ "$arch_display" = "N/A" ]; then
    arch_display="N/A（可用 uname -m 手动查询）"
  fi
  if [ "$vcpu_display" = "N/A" ]; then
    vcpu_display="N/A（可用 nproc 手动查询）"
  fi
  if echo "$mem_display" | grep -q 'N/A'; then
    mem_display="N/A（可查看 /proc/meminfo 或 free -m）"
  fi
  if echo "$disk_display" | grep -q 'N/A'; then
    disk_display="N/A（可用 df -h / 手动查询）"
  fi
  if [ -z "$os_display" ] || [ "$os_display" = "N/A" ]; then
    os_display="N/A（可查看 /etc/os-release）"
  fi

  ipv4_display="$DETECTED_IPV4"
  ipv6_display="$DETECTED_IPV6"
  if [ "$ipv4_display" = "N/A" ]; then
    ipv4_display="N/A（可使用 curl -4 ifconfig.me 手动查询）"
  fi
  if [ "$ipv6_display" = "N/A" ]; then
    ipv6_display="N/A（可使用 curl -6 ifconfig.me 手动查询）"
  fi

  echo -e "${CYAN}---- 机器摘要 ----${NC}"
  echo "CPU 架构: ${arch_display}"
  echo "vCPU 核心: ${vcpu_display}"
  echo "内存总量: ${mem_display}"
  echo "磁盘: ${disk_display}"
  echo "系统版本: ${os_display}"

  echo -e "${CYAN}---- 网络摘要 ----${NC}"
  echo "公网 IPv4: ${ipv4_display}"
  echo "公网 IPv6: ${ipv6_display}"
  echo -e "${RED}提示：如需绑定域名请配置 A/AAAA 记录指向上述公网 IP。${NC}"

  echo -e "${CYAN}---- 建议结论 ----${NC}"
  echo "推荐档位: ${RECOMMENDED_TIER}"
  echo "原因: ${RECOMMENDED_REASON}"
  echo -e "${RED}下一步建议: ${RECOMMENDED_NEXT_STEP}${NC}"
}

print_system_details() {
  local lang os_display ipv4_display ipv6_display

  detect_system_profile
  detect_public_ip

  lang="$(get_finish_lang)"
  os_display="$SYSTEM_OS_VERSION"
  if [ -z "$os_display" ] || [ "$os_display" = "N/A" ]; then
    if [ "$lang" = "en" ]; then
      os_display="N/A (check /etc/os-release)"
    else
      os_display="N/A（可查看 /etc/os-release）"
    fi
  fi

  ipv4_display="$DETECTED_IPV4"
  ipv6_display="$DETECTED_IPV6"
  if [ "$ipv4_display" = "N/A" ]; then
    if [ "$lang" = "en" ]; then
      ipv4_display="N/A (use curl -4 ifconfig.me)"
    else
      ipv4_display="N/A（可使用 curl -4 ifconfig.me 手动查询）"
    fi
  fi
  if [ "$ipv6_display" = "N/A" ]; then
    if [ "$lang" = "en" ]; then
      ipv6_display="N/A (use curl -6 ifconfig.me)"
    else
      ipv6_display="N/A（可使用 curl -6 ifconfig.me 手动查询）"
    fi
  fi

  if [ "$lang" = "en" ]; then
    echo -e "${CYAN}---- System details ----${NC}"
    echo "OS version: ${os_display}"
    echo "Public IPv4: ${ipv4_display}"
    echo "Public IPv6: ${ipv6_display}"
  else
    echo -e "${CYAN}---- 系统信息（System details） ----${NC}"
    echo "系统版本: ${os_display}"
    echo "公网 IPv4: ${ipv4_display}"
    echo "公网 IPv6: ${ipv6_display}"
  fi
}

# Canonical machine profile + recommendation is owned by hz.sh.
show_system_profile_once() {
  if [ "${SYS_PROFILE_SHOWN}" -ne 0 ]; then
    return
  fi

  if [ "${HZ_SUPPRESS_MACHINE_PROFILE:-0}" -eq 1 ]; then
    print_system_details
    SYS_PROFILE_SHOWN=1
    return
  fi

  local ram
  ram="$(get_ram_mb)"
  if [ "$ram" -gt 0 ]; then
    echo -e "当前检测到内存约: ${BOLD}${ram} MB${NC}"
    if [ "$ram" -lt 3800 ]; then
      log_warn "内存 < 4G，推荐选择 LOMP-Lite（Frontend-only），数据库/Redis 放到其他高配机器，通过内网或隧道访问。"
    else
      log_info "内存 ≥ 4G，可按需选择 Lite（Frontend-only）、Standard 或 Hub。"
    fi
  fi

  detect_recommended_tier
  print_system_summary
  SYS_PROFILE_SHOWN=1
}

show_lnmp_placeholder() {
  local tier_label
  tier_label="$1"
  log_step "${tier_label} 档位（占位）"
  log_warn "LNMP 档位暂未开放，目前仅提供提示，后续将补齐安装流程。"
  read -rp "按回车返回主菜单..." _
  show_main_menu
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
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|127.*|100[.]6[4-9].*|100[.][7-9][0-9].*|100[.]1[01][0-9].*|100[.]12[0-7].*)
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

  print_https_post_install "${domain}"

  echo
  echo -e "${CYAN}=========================================================${NC}"
  echo
}

########################
#  顶层主菜单         #
########################

show_main_menu() {
  # [ANCHOR:MENU_MAIN]
  echo
  echo -e "${BOLD}== LOMP / LNMP 安装模块 ==${NC}"
  show_system_profile_once

  echo
  echo "安装档位（LOMP / LNMP）："
  echo "  1) LOMP-Lite（Frontend-only，仅部署前端，DB/Redis 外置）"
  echo "  2) LOMP-Standard（前后端一体，含本地 DB/Redis）"
  echo "  3) LOMP-Hub（集中式 Hub，本机 DB/Redis + 本地站点）"
  echo "  4) LNMP-Lite（占位/仅提示）"
  echo "  5) LNMP-Standard（占位/仅提示）"
  echo "  6) LNMP-Hub（占位/仅提示）"
  echo
  echo "维护 / 清理："
  echo "  7) 清理本机 LOMP/LNMP / WordPress（危险操作，慎用）"
  echo "  8) 清理数据库 / Redis（需在 DB/Redis 所在机器执行）"
  echo "  9) Baseline 诊断 / 验收"
  echo "  0) 退出脚本"
  echo

  local choice
  read -rp "请输入选项 [0-9]: " choice
  echo

  case "$choice" in
    1) install_frontend_only_flow ;;
    2) install_standard_flow ;;
    3) install_hub_flow ;;
    4) show_lnmp_placeholder "LNMP-Lite" ;;
    5) show_lnmp_placeholder "LNMP-Standard" ;;
    6) show_lnmp_placeholder "LNMP-Hub" ;;
    7) cleanup_lomp_menu ;;
    8) cleanup_db_redis_menu ;;
    9) run_lomp_baseline_diagnostics ;;
    0)
      # [ANCHOR:EXIT]
      log_info "已退出脚本。"
      exit 0
      ;;
      *)
        log_warn "无效输入，请重新运行脚本并选择 0-9。"
        exit 1
        ;;
  esac
}

################################
# 3: 清理本机 LOMP/LNMP / WordPress #
################################

cleanup_lomp_menu() {
  # [ANCHOR:CLEANUP_MENU]
  echo -e "${YELLOW}[危险]${NC} 本菜单会在本机删除 LOMP/LNMP 或站点，请确认已备份。"
  echo
  echo "3) 清理本机 LOMP/LNMP / WordPress："
  echo "  1) 彻底移除本机 LOMP Web（卸载 openlitespeed + lsphp83*，删除 /usr/local/lsws）"
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
  echo -e "${YELLOW}[警告]${NC} 即将 ${BOLD}彻底移除本机 LOMP Web${NC}"
  echo "本操作将："
  echo "  - systemctl 停止/禁用 lsws;"
  echo "  - apt remove/purge openlitespeed 与 lsphp83 相关组件;"
  echo "  - 删除 /usr/local/lsws 目录;"
  echo "  - 不会自动删除 /var/www 下的站点目录。"
  echo
  local c
  read -rp "如需继续，请输入大写 'REMOVE_LOMP' 确认: " c
  if [ "$c" != "REMOVE_LOMP" ]; then
    log_warn "确认字符串不匹配，已取消。"
    cleanup_lomp_menu
    return
  fi

  log_step "停止并卸载 LOMP Web（OpenLiteSpeed）"

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

  log_info "本机 LOMP Web 卸载流程已完成。"
  read -rp "按回车返回\"清理本机 LOMP/LNMP / WordPress\"菜单..." _
  cleanup_lomp_menu
  return
}

remove_wp_by_slug() {
  # [ANCHOR:REMOVE_WP_BY_SLUG]
  local LSWS_ROOT="/usr/local/lsws"
  local HTTPD_CONF="${LSWS_ROOT}/conf/httpd_config.conf"

  if [ ! -d "$LSWS_ROOT" ] || [ ! -f "$HTTPD_CONF" ]; then
    log_error "未找到 ${LSWS_ROOT} 或 ${HTTPD_CONF}，似乎尚未安装 LOMP Web。"
    read -rp "按回车返回\"清理本机 LOMP/LNMP / WordPress\"菜单..." _
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
    if [ -z "${VH_CONF_DIR:-}" ] || [ "$VH_CONF_DIR" = "/" ]; then
      log_warn "跳过删除 vhost 目录（路径无效）。"
    else
      log_info "删除 vhost 目录: ${VH_CONF_DIR}"
      rm -rf -- "${VH_CONF_DIR:?}"
    fi
  else
    log_warn "未找到 vhost 目录: ${VH_CONF_DIR}，可能已被删除。"
  fi

  if [ -d "$DOC_ROOT_BASE" ]; then
    if [ -z "${DOC_ROOT_BASE:-}" ] || [ "$DOC_ROOT_BASE" = "/" ]; then
      log_warn "跳过删除站点目录（路径无效）。"
    else
      log_info "删除站点目录: ${DOC_ROOT_BASE}"
      rm -rf -- "${DOC_ROOT_BASE:?}"
    fi
  else
    log_warn "未找到站点目录: ${DOC_ROOT_BASE}，可能已被删除。"
  fi

  if systemctl list-unit-files | grep -q '^lsws\.service'; then
    systemctl restart lsws || true
  fi

  log_info "按 slug 清理站点完成。"
  read -rp "按回车返回\"清理本机 LOMP/LNMP / WordPress\"菜单..." _
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
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
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
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "要删除的 DB 用户名（例如: ols_user）: " DB_USER
  if [ -z "$DB_USER" ]; then
    log_warn "DB 用户名不能为空。"
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "用于执行 DROP 的管理账号（默认 root）: " ADMIN_USER
  ADMIN_USER="${ADMIN_USER:-root}"

  read -rsp "请输入管理账号密码（不会回显）: " ADMIN_PASS
  echo
  if [ -z "$ADMIN_PASS" ]; then
    log_warn "管理账号密码不能为空。"
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
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
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "如需继续，请输入大写 'YES': " tmp
  if [ "$tmp" != "YES" ]; then
    log_warn "未输入 YES，已取消数据库清理。"
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
    cleanup_db_redis_menu
    return
  fi

  log_step "执行数据库清理: $DB_NAME / $DB_USER"

  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" \
    -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; DROP USER IF EXISTS '$DB_USER'@'%'; FLUSH PRIVILEGES;"

  log_info "数据库 $DB_NAME 与用户 $DB_USER 已尝试删除（如存在）。"
  read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
  cleanup_db_redis_menu
  return
}

cleanup_redis_interactive() {
  # [ANCHOR:REDIS_CLEANUP_FLOW]
  if ! command -v redis-cli >/dev/null 2>&1; then
    log_error "未找到 redis-cli，无法执行 Redis 清理。"
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
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
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
    cleanup_db_redis_menu
    return
  fi

  read -rp "请再次输入 Redis DB index 确认: " RD2
  if [ "$RD" != "$RD2" ]; then
    log_warn "两次 DB index 不一致，已取消。"
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
    cleanup_db_redis_menu
    return
  fi

  echo
  echo "将对 Redis ${RH}:${RP} 的 DB ${RD} 执行 FLUSHDB。"
  read -rp "如需继续，请输入大写 'YES': " tmp
  if [ "$tmp" != "YES" ]; then
    log_warn "未输入 YES，已取消 Redis 清理。"
    read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
    cleanup_db_redis_menu
    return
  fi

  log_step "执行 Redis DB ${RD} 清空 (FLUSHDB)"

  redis-cli -h "$RH" -p "$RP" -n "$RD" FLUSHDB

  log_info "Redis DB ${RD} 已执行 FLUSHDB。"
  read -rp "按回车返回 '清理数据库 / Redis' 菜单..." _
  cleanup_db_redis_menu
  return
}

#######################
# 安装 LOMP/LNMP + WordPress 流程  #
#######################

prompt_site_info() {
  # [ANCHOR:SITE_INFO]
  echo
  echo "================ 站点基础信息 ================"
  while :; do
    read -rp "请输入站点域名（例如: abc.yourdomain.com）: " SITE_DOMAIN
    [ -n "$SITE_DOMAIN" ] && break
    log_warn "域名不能为空。"
  done

  read -rp "请输入站点 Slug（仅小写字母/数字，例如: ols，默认取域名第一个字段）: " SITE_SLUG
  if [ -z "$SITE_SLUG" ]; then
    SITE_SLUG="${SITE_DOMAIN%%.*}"
    SITE_SLUG="${SITE_SLUG//[^a-zA-Z0-9]/}"
    SITE_SLUG="$(echo "$SITE_SLUG" | tr '[:upper:]' '[:lower:]')"
    [ -z "$SITE_SLUG" ] && SITE_SLUG="wpsite"
  fi

  DOC_ROOT="/var/www/${SITE_SLUG}/html"

  log_info "站点域名: ${SITE_DOMAIN}"
  log_info "站点 Slug: ${SITE_SLUG}"
  log_info "站点根目录: ${DOC_ROOT}"
}

extract_db_host_only() {
  local host="${1:-}"

  if [[ "$host" == *:* ]]; then
    echo "${host%%:*}"
  else
    echo "$host"
  fi
}

is_tailscale_ipv4() {
  local ip="${1:-}"

  if [ -z "$ip" ]; then
    return 1
  fi

  echo "$ip" | grep -Eq '^100(\.[0-9]{1,3}){3}$'
}

detect_tailscale_ipv4() {
  local ts_ip=""

  if command -v tailscale >/dev/null 2>&1; then
    ts_ip="$(tailscale ip -4 2>/dev/null | head -n1 | tr -d '[:space:]')"
    if is_tailscale_ipv4 "$ts_ip"; then
      echo "$ts_ip"
      return 0
    fi
  fi

  ts_ip="$(ip -4 addr show 2>/dev/null | grep -oE '100(\.[0-9]{1,3}){3}' | head -n1)"
  if is_tailscale_ipv4 "$ts_ip"; then
    echo "$ts_ip"
    return 0
  fi

  return 1
}

init_suggested_db_grant_host() {
  local ts_ip=""

  if [ -n "${SUGGESTED_DB_GRANT_HOST:-}" ]; then
    return 0
  fi

  if ts_ip="$(detect_tailscale_ipv4)"; then
    SUGGESTED_DB_GRANT_HOST="$ts_ip"
    return 0
  fi

  SUGGESTED_DB_GRANT_HOST="%"
  return 0
}

is_local_db_host() {
  local host="${1:-}"

  case "$host" in
    localhost|127.0.0.1|::1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

prompt_db_user_host() {
  # [ANCHOR:DB_USER_HOST_PROMPT]
  local choice host_input

  echo
  echo "请选择数据库用户来源（DB_USER_HOST）策略："
  echo "  1) 默认 '%'（允许任意来源，需确保防火墙/Tailscale 仍有限制）"
  echo "  2) 安全模式：输入前端机器的 Tailscale IP 或主机名"
  echo "  3) 高级：自定义 MySQL Host 模式（例如: 10.0.% 或 db-gateway.example.com）"
  read -rp "请输入选项 [1-3] (默认 1): " choice
  choice="${choice:-1}"

  case "$choice" in
    1)
      DB_USER_HOST="%"
      log_warn "DB_USER_HOST 已设置为 '%'，请确认防火墙/Tailscale 仅允许可信来源访问数据库。"
      return 0
      ;;
    2|3)
      while :; do
        if [ "$choice" = "2" ]; then
          read -rp "请输入前端机器的 Tailscale IP 或主机名（不支持 CIDR）: " host_input
        else
          read -rp "请输入 MySQL Host 模式（不支持 CIDR）: " host_input
        fi

        if [ -z "$host_input" ]; then
          log_warn "DB_USER_HOST 不能为空。"
          continue
        fi
        if [[ "$host_input" == *"/"* ]]; then
          log_error "CIDR 不是 MySQL Host 支持的格式，例如 10.0.0.0/24 无法使用。"
          log_warn "请改用 MySQL Host 模式，例如单个 IP、主机名或通配符 (10.0.%)。"
          continue
        fi
        if echo "$host_input" | grep -Eq "[[:space:]'\";]"; then
          log_warn "DB_USER_HOST 不能包含空格或引号等特殊字符。"
          continue
        fi

        DB_USER_HOST="$host_input"
        break
      done
      return 0
      ;;
    *)
      log_warn "输入无效，将默认使用 '%'。"
      DB_USER_HOST="%"
      return 0
      ;;
  esac
}

prompt_db_info() {
  # [ANCHOR:DB_INFO_PROMPT]
  init_suggested_db_grant_host
  echo
  echo "================ 数据库设置（必须已在目标 DB 实例中创建） ================"
  echo "请先在你的数据库实例中『手动』创建好："
  echo "  - 独立数据库，例如: ${SITE_SLUG}_wp"
  echo "  - 独立数据库用户，例如: ${SITE_SLUG}_user，并分配该库全部权限"
  echo

  while :; do
    read -rp "DB Host（可带端口，例如: db.internal.example:3306 或 127.0.0.1）: " DB_HOST
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

  local host_only
  host_only="$(extract_db_host_only "$DB_HOST")"
  if is_local_db_host "$host_only"; then
    DB_USER_HOST="localhost"
    log_info "检测到本机数据库，DB_USER_HOST 已设置为 localhost。"
  else
    prompt_db_user_host
  fi

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
  local port="${DB_PORT:-3306}"
  local tcp_err=""
  local mysql_err=""
  local db_client=""
  local install_choice=""

  # 允许 DB_HOST 以 host:port 形式填写
  if [[ "$host" == *:* ]]; then
    port="${host##*:}"
    host="${host%%:*}"
    if [ -z "$host" ]; then
      log_error "DB Host 格式无效（host 不能为空）。"
      return 1
    fi
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    log_error "DB 端口必须为数字（当前: ${port}）。"
    if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
      LITE_DB_TCP_STATUS="FAIL"
      LITE_DB_AUTH_STATUS="SKIPPED"
    fi
    return 1
  fi
  DB_PORT="$port"

  if ! is_ip_address "$host"; then
    log_info "DNS 解析检测: ${host}"
    if ! getent hosts "$host" >/dev/null 2>&1; then
      log_error "DNS 解析失败：${host}"
      log_warn "可能原因：域名未解析、解析记录未生效、或本机 DNS 无法访问。"
      log_warn "建议检查：域名解析是否指向正确内网/隧道出口、以及本机 /etc/resolv.conf。"
      if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
        LITE_DB_TCP_STATUS="FAIL"
        LITE_DB_AUTH_STATUS="SKIPPED"
        print_lite_db_host_fix_guide
      fi
      return 1
    fi
  fi

  log_info "TCP 连通性检测: ${host}:${port}"
  if ! tcp_err="$(timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>&1 >/dev/null)"; then
    log_error "无法连接到 ${host}:${port}（TCP 不可达）。"
    log_warn "可能原因：防火墙/安全组未放行端口、服务未监听、内网或隧道未连接、地址填写错误。"
    if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
      LITE_DB_TCP_STATUS="FAIL"
      LITE_DB_AUTH_STATUS="SKIPPED"
      log_warn "补充提示：端口未对外暴露、bind-address 限制、或安全组/UFW 未放行也会导致失败。"
      print_lite_db_host_fix_guide
    fi
    [ -n "$tcp_err" ] && log_warn "系统提示: ${tcp_err}"
    return 1
  fi
  if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
    LITE_DB_TCP_STATUS="PASS"
  fi

  # 确保有 mysql/mariadb 客户端可用
  if command -v mysql >/dev/null 2>&1; then
    db_client="mysql"
  elif command -v mariadb >/dev/null 2>&1; then
    db_client="mariadb"
  else
    log_warn "未检测到 mysql/mariadb 客户端，需安装以完成数据库认证检查。"
    read -rp "是否立即安装 default-mysql-client 或 mariadb-client？[y/N]: " install_choice
    install_choice="${install_choice:-N}"
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
      if ! apt-get update -qq; then
        log_warn "apt-get update 失败，后续安装可能无法完成。"
      fi
      if ! apt-get install -y default-mysql-client; then
        log_warn "default-mysql-client 安装失败，尝试 mariadb-client。"
        if ! apt-get install -y mariadb-client; then
          log_error "mariadb-client 安装失败，无法完成数据库认证检查。"
          if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
            LITE_DB_AUTH_STATUS="FAIL"
          fi
          return 1
        fi
      fi
    else
      log_error "缺少 MySQL/MariaDB 客户端，无法完成数据库认证检查。"
      if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
        LITE_DB_AUTH_STATUS="FAIL"
      fi
      return 1
    fi

    if command -v mysql >/dev/null 2>&1; then
      db_client="mysql"
    elif command -v mariadb >/dev/null 2>&1; then
      db_client="mariadb"
    else
      log_error "未找到 mysql/mariadb 客户端，无法完成数据库认证检查。"
      if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
        LITE_DB_AUTH_STATUS="FAIL"
      fi
      return 1
    fi
  fi

  if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ] && [ -n "$db_client" ]; then
    LITE_DB_CLIENT="$db_client"
  fi

  if mysql_err="$( { "$db_client" -h "$host" -P "$port" -u "$DB_USER" "-p$DB_PASSWORD" -e "SELECT 1;" >/dev/null; } 2>&1 )"; then
    log_info "认证通过：${DB_USER}@${host}:${port}"
    if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
      LITE_DB_AUTH_STATUS="PASS"
      diagnose_lite_db_grants_host_mismatch "$db_client" "$host" "$port" || true
    fi
    return 0
  fi

  log_error "数据库认证失败：${DB_USER}@${host}:${port}"
  if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
    LITE_DB_AUTH_STATUS="FAIL"
  fi
  if echo "$mysql_err" | grep -qi "Access denied"; then
    log_warn "可能原因：用户名/密码错误，或该用户未被授权从此主机连接。"
    if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
      log_warn "常见情况：账号存在但仅允许 'user'@'%' 或 'user'@'DB_USER_HOST'，与当前来源不匹配。"
    fi
  elif echo "$mysql_err" | grep -qi "Unknown MySQL server host\|Unknown host"; then
    log_warn "可能原因：DB Host 无法解析，或地址拼写有误。"
  elif echo "$mysql_err" | grep -qi "Can't connect to MySQL server"; then
    log_warn "可能原因：端口未放行/服务未启动/绑定地址限制。"
  else
    [ -n "$mysql_err" ] && log_warn "系统提示: ${mysql_err}"
  fi
  if [ "${LITE_PREFLIGHT_MODE:-0}" -eq 1 ]; then
    print_lite_db_host_fix_guide
  fi
  return 1
}

is_ip_address() {
  local host="${1:-}"

  if echo "$host" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    return 0
  fi

  if echo "$host" | grep -qiE '^[0-9a-f:]+$'; then
    return 0
  fi

  return 1
}

diagnose_lite_db_grants_host_mismatch() {
  # [ANCHOR:LITE_DB_GRANTS_DIAG]
  local db_client="$1"
  local host="$2"
  local port="$3"
  local whoami hosts host_entry grants_output grants_err client_info client_user current_user client_host current_host

  if [ -z "$db_client" ]; then
    return 0
  fi

  client_info="$("$db_client" -h "$host" -P "$port" -u "$DB_USER" "-p$DB_PASSWORD" -N -s \
    -e "SELECT USER(), CURRENT_USER();" 2>/dev/null)" || true
  if [ -z "$client_info" ]; then
    return 0
  fi

  client_user="${client_info%%$'\t'*}"
  current_user="${client_info#*$'\t'}"
  client_host="${client_user#*@}"
  current_host="${current_user#*@}"

  if grants_err="$( { "$db_client" -h "$host" -P "$port" -u "$DB_USER" "-p$DB_PASSWORD" \
    -e "SHOW GRANTS FOR '${DB_USER}'@'${client_host}';" >/dev/null; } 2>&1 )"; then
    return 0
  fi

  if ! echo "$grants_err" | grep -qi "There is no such grant\|not allowed"; then
    return 0
  fi

  hosts="$("$db_client" -h "$host" -P "$port" -u "$DB_USER" "-p$DB_PASSWORD" -N -s \
    -e "SELECT Host FROM mysql.user WHERE User='${DB_USER}' ORDER BY LENGTH(Host), Host;" 2>/dev/null)" || true

  if [ -z "$hosts" ]; then
    log_warn "未能读取 mysql.user 中的 Host 列表（可能缺少权限），请在 DB 主机上使用管理员账号排查。"
    log_warn "提示：SHOW GRANTS FOR '${DB_USER}'@'${client_host}' 报错并不一定代表账号不存在。"
    return 0
  fi

  log_warn "检测到 DB 用户 ${DB_USER} 在以下 Host 规则中存在："
  while read -r whoami; do
    [ -n "$whoami" ] && echo "  - ${DB_USER}@${whoami}"
  done <<<"$hosts"

  if echo "$hosts" | grep -qx "$current_host"; then
    host_entry="$current_host"
  elif echo "$hosts" | grep -qx "%"; then
    host_entry="%"
  else
    host_entry="$(printf '%s\n' "$hosts" | head -n1)"
  fi

  log_warn "说明：你的 DB 用户实际定义为 '${DB_USER}'@'${host_entry}'，因此对 '${DB_USER}'@'${client_host}' 执行 SHOW GRANTS 失败是预期行为。"

  grants_output="$("$db_client" -h "$host" -P "$port" -u "$DB_USER" "-p$DB_PASSWORD" -N -s \
    -e "SHOW GRANTS FOR '${DB_USER}'@'${host_entry}';" 2>/dev/null)" || true

  if [ -n "$grants_output" ]; then
    echo "匹配到的 GRANTS（${DB_USER}@${host_entry}）："
    printf '%s\n' "$grants_output" | sed 's/^/  /'
  else
    log_warn "未能读取 '${DB_USER}'@'${host_entry}' 的 GRANTS（可能缺少权限）。"
  fi

  return 0
}

warn_lite_db_non_empty() {
  # [ANCHOR:LITE_DB_READINESS]
  local db_client="${1:-}"
  local table_count=""
  local prompt_choice=""

  if [ -z "$db_client" ]; then
    if command -v mysql >/dev/null 2>&1; then
      db_client="mysql"
    elif command -v mariadb >/dev/null 2>&1; then
      db_client="mariadb"
    else
      log_warn "未检测到 mysql/mariadb 客户端，无法检查目标数据库是否为空。"
      return 0
    fi
  fi

  table_count="$("$db_client" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "-p$DB_PASSWORD" -N -s \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null)" || true

  if ! [[ "$table_count" =~ ^[0-9]+$ ]]; then
    log_warn "无法获取目标数据库的表数量，已跳过非空检查。"
    return 0
  fi

  if [ "$table_count" -eq 0 ]; then
    return 0
  fi

  echo
  echo -e "${YELLOW}[WARNING]${NC} 目标数据库 ${DB_NAME} 已存在 ${table_count} 张表。"
  echo "WordPress 安装到非空数据库可能失败，或覆盖已有数据。"
  echo
  echo -e "${CYAN}---- Host-side Fix Hint（仅供参考，不会自动执行） ----${NC}"
  cat <<'EOF'
列出表（安全）：
  SHOW TABLES FROM `<DB_NAME>`;
  SELECT table_name FROM information_schema.tables WHERE table_schema='<DB_NAME>';

可选（⚠️ 可破坏性操作）生成 DROP 语句：
  SELECT CONCAT('DROP TABLE `', table_name, '`;') AS drop_sql
  FROM information_schema.tables WHERE table_schema='<DB_NAME>';
  -- 请确认后手动执行生成的 DROP TABLE 语句
EOF
  echo
  echo "请选择："
  echo "  1) 中止安装，先手动清理数据库"
  echo "  2) 继续安装（我已知风险）"
  read -rp "请输入选项 [1-2] (默认 1): " prompt_choice
  prompt_choice="${prompt_choice:-1}"
  case "$prompt_choice" in
    2) log_warn "已选择继续安装，风险由用户承担。" ;;
    *) log_warn "已中止安装，请手动清理数据库后重试。"; exit 1 ;;
  esac
}

prompt_db_info_lite() {
  # [ANCHOR:DB_INFO_PROMPT_LITE]
  init_suggested_db_grant_host
  echo
  echo "================ LOMP-Lite（Frontend-only）：外部数据库配置 ================"
  echo "请先在目标 MariaDB/MySQL 实例中『手动』创建好："
  echo "  - 独立数据库，例如: ${SITE_SLUG}_wp"
  echo "  - 独立数据库用户，例如: ${SITE_SLUG}_user，并分配该库全部权限"
  echo

  while :; do
    read -rp "DB Host（例如: db.internal.example 或 192.0.2.10）: " DB_HOST
    [ -n "$DB_HOST" ] && break
    log_warn "DB Host 不能为空。"
  done

  while :; do
    read -rp "DB Port [3306]: " DB_PORT
    DB_PORT="${DB_PORT:-3306}"
    if [[ "$DB_PORT" =~ ^[0-9]+$ ]]; then
      break
    fi
    log_warn "DB 端口必须为数字。"
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

  prompt_db_user_host

  while :; do
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

prompt_redis_info_lite() {
  # [ANCHOR:REDIS_INFO_PROMPT_LITE]
  local choice

  REDIS_ENABLED="no"
  REDIS_HOST=""
  REDIS_PORT=""
  REDIS_PASSWORD=""

  read -rp "是否配置 Redis 对象缓存？[y/N]: " choice
  choice="${choice:-N}"
  if ! [[ "$choice" =~ ^[Yy] ]]; then
    return
  fi

  REDIS_ENABLED="yes"

  while :; do
    read -rp "Redis Host（例如: redis.internal.example 或 192.0.2.20）: " REDIS_HOST
    [ -n "$REDIS_HOST" ] && break
    log_warn "Redis Host 不能为空。"
  done

  while :; do
    read -rp "Redis Port [6379]: " REDIS_PORT
    REDIS_PORT="${REDIS_PORT:-6379}"
    if [[ "$REDIS_PORT" =~ ^[0-9]+$ ]]; then
      break
    fi
    log_warn "Redis 端口必须为数字。"
  done

  read -rsp "Redis 密码（可留空）: " REDIS_PASSWORD
  echo
}

test_redis_connection_lite() {
  # [ANCHOR:REDIS_CONN_TEST_LITE]
  log_step "测试 Redis 连通性"

  local host="$REDIS_HOST"
  local port="${REDIS_PORT:-6379}"
  local tcp_err=""
  local ping_err=""
  local install_choice=""

  if [ -z "$host" ]; then
    log_error "Redis Host 不能为空。"
    LITE_REDIS_TCP_STATUS="FAIL"
    LITE_REDIS_AUTH_STATUS="SKIPPED"
    return 1
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    log_error "Redis 端口必须为数字（当前: ${port}）。"
    LITE_REDIS_TCP_STATUS="FAIL"
    LITE_REDIS_AUTH_STATUS="SKIPPED"
    return 1
  fi

  if ! is_ip_address "$host"; then
    log_info "DNS 解析检测: ${host}"
    if ! getent hosts "$host" >/dev/null 2>&1; then
      log_error "DNS 解析失败：${host}"
      log_warn "可能原因：域名未解析、解析记录未生效、或本机 DNS 无法访问。"
      log_warn "建议检查：域名解析是否指向正确内网/隧道出口、以及本机 /etc/resolv.conf。"
      LITE_REDIS_TCP_STATUS="FAIL"
      LITE_REDIS_AUTH_STATUS="SKIPPED"
      return 1
    fi
  fi

  log_info "TCP 连通性检测: ${host}:${port}"
  if ! tcp_err="$(timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>&1 >/dev/null)"; then
    log_error "无法连接到 ${host}:${port}（TCP 不可达）。"
    log_warn "可能原因：防火墙/安全组未放行端口、服务未监听、内网或隧道未连接、地址填写错误。"
    [ -n "$tcp_err" ] && log_warn "系统提示: ${tcp_err}"
    LITE_REDIS_TCP_STATUS="FAIL"
    LITE_REDIS_AUTH_STATUS="SKIPPED"
    return 1
  fi
  LITE_REDIS_TCP_STATUS="PASS"

  if ! command -v redis-cli >/dev/null 2>&1; then
    log_warn "Redis test requires redis-cli. Install now? (y/N)"
    read -rp "选择 [y/N]: " install_choice
    install_choice="${install_choice:-N}"
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
      if ! apt-get install -y redis-tools; then
        log_warn "redis-tools 安装失败，将跳过 Redis PING 检查。"
        LITE_REDIS_AUTH_STATUS="SKIPPED"
        return 0
      fi
    else
      log_warn "已跳过 Redis PING 检查。"
      LITE_REDIS_AUTH_STATUS="SKIPPED"
      return 0
    fi

    if ! command -v redis-cli >/dev/null 2>&1; then
      log_warn "未找到 redis-cli，将跳过 Redis PING 检查。"
      LITE_REDIS_AUTH_STATUS="SKIPPED"
      return 0
    fi
  fi

  if [ -n "$REDIS_PASSWORD" ]; then
    ping_err="$(redis-cli -h "$host" -p "$port" -a "$REDIS_PASSWORD" PING 2>&1 || true)"
  else
    ping_err="$(redis-cli -h "$host" -p "$port" PING 2>&1 || true)"
  fi

  if echo "$ping_err" | grep -qi "PONG"; then
    log_info "Redis PING 成功：${host}:${port}"
    LITE_REDIS_AUTH_STATUS="PASS"
    return 0
  fi

  log_error "Redis PING 失败：${host}:${port}"
  LITE_REDIS_AUTH_STATUS="FAIL"
  if echo "$ping_err" | grep -qi "NOAUTH"; then
    log_warn "可能原因：Redis 密码错误或未授权。"
  elif echo "$ping_err" | grep -qi "Connection refused"; then
    log_warn "可能原因：端口未放行/服务未启动/绑定地址限制。"
  else
    [ -n "$ping_err" ] && log_warn "系统提示: ${ping_err}"
  fi
  return 1
}

print_lite_preflight_summary() {
  # [ANCHOR:LITE_PREFLIGHT_SUMMARY]
  local redis_status="未启用"
  local redis_pass_status="未设置"
  local redis_tcp_status="未启用"
  local redis_auth_status="未启用"
  local db_tcp_status="${LITE_DB_TCP_STATUS:-未知}"
  local db_auth_status="${LITE_DB_AUTH_STATUS:-未知}"

  if [ "${REDIS_ENABLED:-no}" = "yes" ]; then
    redis_status="${REDIS_HOST}:${REDIS_PORT}"
    if [ -n "$REDIS_PASSWORD" ]; then
      redis_pass_status="已设置"
    fi
    redis_tcp_status="${LITE_REDIS_TCP_STATUS:-未知}"
    redis_auth_status="${LITE_REDIS_AUTH_STATUS:-未知}"
  fi

  echo
  echo -e "${CYAN}==== LOMP-Lite (Frontend-only): external DB/Redis ====${NC}"
  echo "数据库主机:  ${DB_HOST}:${DB_PORT}"
  echo "数据库名称:  ${DB_NAME}"
  echo "数据库用户:  ${DB_USER}"
  echo "用户来源:    ${DB_USER_HOST:-%}"
  echo "数据库密码:  已设置（已隐藏）"
  echo "DB TCP 检测: ${db_tcp_status}"
  echo "DB 认证检测: ${db_auth_status}"
  echo "Redis 配置:  ${redis_status}"
  if [ "${REDIS_ENABLED:-no}" = "yes" ]; then
    echo "Redis 密码:  ${redis_pass_status}"
    echo "Redis TCP 检测: ${redis_tcp_status}"
    echo "Redis PING 检测: ${redis_auth_status}"
  fi
  echo
}

print_lite_db_host_fix_guide() {
  # [ANCHOR:LITE_DB_HOST_FIX_GUIDE]
  local suggested_host=""

  init_suggested_db_grant_host
  suggested_host="${SUGGESTED_DB_GRANT_HOST:-%}"
  echo
  echo -e "${CYAN}---- DB host-side fix guide (run on the DB server) ----${NC}"
  echo "请先确认数据库监听在预期接口/端口（例如 ${DB_HOST}:${DB_PORT}），且防火墙已放行。"
  echo "建议的 DB_USER_HOST：${suggested_host}（仅供参考，'%' 代表更广泛的来源访问）"
  cat <<EOF
SQL 模板：
  CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
  CREATE USER '${DB_USER}'@'${suggested_host}' IDENTIFIED BY '<DB_PASSWORD>';
  GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${suggested_host}';
  FLUSH PRIVILEGES;

验证：
  SHOW DATABASES LIKE '${DB_NAME}';
  SELECT User,Host FROM mysql.user WHERE User='${DB_USER}';
  SHOW GRANTS FOR '${DB_USER}'@'<DB_USER_HOST>';
EOF
  echo
  echo "说明：'user'@'%' 与 'user'@'IP' 是不同账号，SHOW GRANTS 的 Host 必须精确匹配。"
  echo "如使用容器部署数据库，请确认端口已发布到预期接口，并放行防火墙。"
  echo
}

get_wp_db_host_value() {
  local host="${DB_HOST:-}"
  local port="${DB_PORT:-3306}"

  if [[ "$host" == *:* ]]; then
    printf "%s" "$host"
    return 0
  fi

  if [ -n "$port" ] && [ "$port" != "3306" ]; then
    printf "%s:%s" "$host" "$port"
    return 0
  fi

  printf "%s" "$host"
}

update_wp_config_define() {
  local wp_config="$1"
  local key="$2"
  local value="$3"
  local mode="${4:-string}"
  local line="$value"
  local tmp

  if [ "$mode" = "string" ]; then
    line="${value//\\/\\\\}"
    line="${line//\'/\\\'}"
    line="define('${key}', '${line}');"
  else
    line="define('${key}', ${value});"
  fi

  if grep -q "define([\"']${key}[\"']" "$wp_config"; then
    tmp="${wp_config}.tmp"
    awk -v key="$key" -v newline="$line" '
      $0 ~ "define\\([\"\\047]" key "[\"\\047]" { print newline; next }
      { print }
    ' "$wp_config" >"$tmp" && mv "$tmp" "$wp_config"
  else
    tmp="${wp_config}.tmp"
    awk -v newline="$line" '
      NR==1 { print; print newline; next }
      { print }
    ' "$wp_config" >"$tmp" && mv "$tmp" "$wp_config"
  fi
}

get_site_domain() {
  local domain=""

  if [ -n "${SITE_DOMAIN:-}" ]; then
    domain="$SITE_DOMAIN"
  elif [ -n "${PRIMARY_DOMAIN:-}" ]; then
    domain="$PRIMARY_DOMAIN"
  elif [ -n "${DOMAIN:-}" ]; then
    domain="$DOMAIN"
  fi

  printf "%s" "$domain"
}

detect_lsphp_bin() {
  local bins=()
  local bin

  for bin in /usr/local/lsws/lsphp*/bin/php; do
    if [ -x "$bin" ]; then
      bins+=("$bin")
    fi
  done

  if [ "${#bins[@]}" -gt 0 ]; then
    printf "%s\n" "${bins[@]}" | sort -V | tail -n1
    return 0
  fi

  if command -v php >/dev/null 2>&1; then
    command -v php
    return 0
  fi

  return 1
}

get_lsphp_pkg_suffix() {
  local php_bin="$1"
  local version suffix

  version="$("$php_bin" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)" || true
  suffix="${version//./}"

  if [ -n "$suffix" ]; then
    printf "%s" "$suffix"
    return 0
  fi

  printf "83"
}

get_lsphp_ini_path() {
  local php_bin="$1"
  local ini

  ini="$("$php_bin" -i 2>/dev/null | awk -F'=> ' '/Loaded Configuration File/ {print $2; exit}')"
  if [ -n "$ini" ] && [ "$ini" != "(none)" ]; then
    printf "%s" "$ini"
    return 0
  fi

  return 1
}

update_php_ini_value() {
  local ini="$1"
  local key="$2"
  local value="$3"

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$ini"; then
    if grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*$" "$ini"; then
      return 1
    fi
    sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$ini"
    return 0
  fi

  echo "${key} = ${value}" >>"$ini"
  return 0
}

ensure_lsphp_extensions() {
  local php_bin="$1"
  local pkg_suffix
  local modules
  local missing=()
  local missing_names=()
  local has_mysql="no"

  modules="$("$php_bin" -m 2>/dev/null | tr '[:upper:]' '[:lower:]')" || modules=""
  pkg_suffix="$(get_lsphp_pkg_suffix "$php_bin")"

  if ! printf '%s\n' "$modules" | grep -qx "curl"; then
    missing+=("lsphp${pkg_suffix}-curl")
    missing_names+=("curl")
  fi
  if ! printf '%s\n' "$modules" | grep -qx "intl"; then
    missing+=("lsphp${pkg_suffix}-intl")
    missing_names+=("intl")
  fi
  if ! printf '%s\n' "$modules" | grep -qx "zip"; then
    missing+=("lsphp${pkg_suffix}-zip")
    missing_names+=("zip")
  fi
  if ! printf '%s\n' "$modules" | grep -qx "gd"; then
    missing+=("lsphp${pkg_suffix}-gd")
    missing_names+=("gd")
  fi
  if ! printf '%s\n' "$modules" | grep -qx "mbstring"; then
    missing+=("lsphp${pkg_suffix}-mbstring")
    missing_names+=("mbstring")
  fi
  if printf '%s\n' "$modules" | grep -qx "mysqli"; then
    has_mysql="yes"
  elif printf '%s\n' "$modules" | grep -qx "pdo_mysql"; then
    has_mysql="yes"
  fi
  if [ "$has_mysql" != "yes" ]; then
    missing+=("lsphp${pkg_suffix}-mysql")
    missing_names+=("mysql")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    log_info "安装缺失的 PHP 扩展（${missing_names[*]}）..."
    apt install -y "${missing[@]}"
    return 0
  fi

  return 1
}

safe_remove_path() {
  local target="$1"
  local base="$2"

  if [ -z "$target" ] || [ -z "$base" ]; then
    log_warn "清理路径为空，跳过。"
    return 1
  fi

  case "$target" in
    "$base"/*) ;;
    *)
      log_warn "清理路径不在预期目录内，跳过：$target"
      return 1
      ;;
  esac

  if [ -d "$target" ]; then
    rm -rf -- "$target"
    return 0
  fi

  if [ -f "$target" ]; then
    rm -f -- "$target"
    return 0
  fi

  return 1
}

apply_wp_site_health_baseline() {
  # [ANCHOR:WP_SITE_HEALTH_BASELINE]
  local wp_config="${DOC_ROOT}/wp-config.php"
  local wp_content="${DOC_ROOT}/wp-content"
  local summary=()
  local tier="${BASELINE_TIER:-$TIER_STANDARD}"
  local domain https_url
  local php_bin php_ini
  local ini_hash_before ini_hash_after
  local php_ini_changed=0
  local php_ext_changed=0
  local cleanup_plugins="no"
  local cleanup_themes="no"
  local cache_applied="no"
  local memory_applied="no"
  local https_applied="no"

  if [ ! -f "$wp_config" ]; then
    log_warn "未找到 ${wp_config}，跳过 Site Health baseline。"
    return
  fi

  domain="$(get_site_domain)"
  if [ -n "$domain" ]; then
    https_url="https://${domain}"
    update_wp_config_define "$wp_config" "WP_HOME" "$https_url" "string"
    update_wp_config_define "$wp_config" "WP_SITEURL" "$https_url" "string"
    https_applied="yes"
  else
    log_warn "未检测到域名，跳过 HTTPS URL 写入。"
  fi

  update_wp_config_define "$wp_config" "WP_MEMORY_LIMIT" "128M" "string"
  update_wp_config_define "$wp_config" "WP_MAX_MEMORY_LIMIT" "256M" "string"
  memory_applied="yes"

  if lscwp_is_active; then
    update_wp_config_define "$wp_config" "WP_CACHE" "true" "raw"
    cache_applied="yes"
  else
    update_wp_config_define "$wp_config" "WP_CACHE" "false" "raw"
  fi

  php_bin="$(detect_lsphp_bin)" || php_bin=""
  if [ -n "$php_bin" ]; then
    LSPHP_BIN="$php_bin"
  fi
  if [ -n "$php_bin" ]; then
    if ensure_lsphp_extensions "$php_bin"; then
      php_ext_changed=1
    fi

    if php_ini="$(get_lsphp_ini_path "$php_bin")" && [ -f "$php_ini" ]; then
      ini_hash_before="$(sha256sum "$php_ini" | awk '{print $1}')"

      if [ "$tier" = "$TIER_LITE" ]; then
        update_php_ini_value "$php_ini" "upload_max_filesize" "32M" || true
        update_php_ini_value "$php_ini" "post_max_size" "64M" || true
      else
        update_php_ini_value "$php_ini" "upload_max_filesize" "64M" || true
        update_php_ini_value "$php_ini" "post_max_size" "128M" || true
      fi

      ini_hash_after="$(sha256sum "$php_ini" | awk '{print $1}')"
      if [ "$ini_hash_before" != "$ini_hash_after" ]; then
        php_ini_changed=1
      fi
    else
      log_warn "未检测到有效的 php.ini，跳过上传限制调整。"
    fi
  else
    log_warn "未检测到 LSPHP，可执行 PHP 配置与扩展检查已跳过。"
  fi

  if [ -d "$wp_content/plugins" ]; then
    if safe_remove_path "${wp_content}/plugins/akismet" "$wp_content"; then
      cleanup_plugins="yes"
    fi
    if safe_remove_path "${wp_content}/plugins/hello" "$wp_content"; then
      cleanup_plugins="yes"
    fi
    if safe_remove_path "${wp_content}/plugins/hello.php" "$wp_content"; then
      cleanup_plugins="yes"
    fi
  else
    log_warn "未找到 ${wp_content}/plugins，跳过插件清理。"
  fi

  if [ -d "$wp_content/themes" ]; then
    local theme_dir theme_name
    local themes=()
    local latest_theme=""
    for theme_dir in "${wp_content}/themes"/twentytwenty*; do
      [ -d "$theme_dir" ] || continue
      theme_name="$(basename "$theme_dir")"
      themes+=("$theme_name")
    done

    if [ "${#themes[@]}" -gt 0 ]; then
      latest_theme="$(printf "%s\n" "${themes[@]}" | sort -V | tail -n1)"
      for theme_name in "${themes[@]}"; do
        if [ "$theme_name" = "$latest_theme" ]; then
          continue
        fi
        if safe_remove_path "${wp_content}/themes/${theme_name}" "$wp_content"; then
          cleanup_themes="yes"
        fi
      done
    fi
  else
    log_warn "未找到 ${wp_content}/themes，跳过主题清理。"
  fi

  if [ "$php_ini_changed" -eq 1 ] || [ "$php_ext_changed" -eq 1 ]; then
    systemctl restart lsws
  fi

  if [ "$https_applied" = "yes" ]; then
    summary+=("HTTPS URL 固定")
  fi
  if [ "$cache_applied" = "yes" ]; then
    summary+=("缓存开关")
  fi
  if [ "$memory_applied" = "yes" ]; then
    summary+=("WP 内存限制")
  fi
  if [ "$php_ini_changed" -eq 1 ]; then
    summary+=("上传限制")
  fi
  if [ "$php_ext_changed" -eq 1 ]; then
    summary+=("PHP 扩展")
  fi
  if [ "$cleanup_plugins" = "yes" ]; then
    summary+=("插件清理")
  fi
  if [ "$cleanup_themes" = "yes" ]; then
    summary+=("主题清理")
  fi

  if [ "${#summary[@]}" -gt 0 ]; then
    log_info "Baseline applied: ${summary[*]}"
  else
    log_info "Baseline applied: 无需更改"
  fi
}

wp_cli_base() {
  wp --path="$DOC_ROOT" --allow-root
}

lscwp_is_active() {
  if ! command -v wp >/dev/null 2>&1; then
    return 1
  fi

  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    return 1
  fi

  if ! wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    return 1
  fi

  if wp_cli_base plugin is-installed litespeed-cache >/dev/null 2>&1 \
    && wp_cli_base plugin is-active litespeed-cache >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

ensure_lscache_only() {
  # [ANCHOR:WP_LSCACHE_ONLY]
  if ! command -v wp >/dev/null 2>&1; then
    log_warn "未找到 wp-cli，跳过 LiteSpeed Cache 安装/清理。"
    return
  fi

  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，跳过 LiteSpeed Cache 安装/清理。"
    return
  fi

  if ! wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    log_warn "WordPress 尚未完成安装，跳过插件安装/清理。"
    return
  fi

  if ! wp_cli_base plugin install litespeed-cache --activate >/dev/null 2>&1; then
    log_warn "LiteSpeed Cache 安装/启用失败。"
  else
    log_info "LiteSpeed Cache 已安装并启用。"
  fi

  wp_cli_base plugin delete akismet hello >/dev/null 2>&1 || true

  local plugins plugin
  plugins="$(wp_cli_base plugin list --field=name --skip-plugins --skip-themes 2>/dev/null)" || plugins=""
  for plugin in $plugins; do
    if [ "$plugin" = "litespeed-cache" ]; then
      continue
    fi
    wp_cli_base plugin delete "$plugin" >/dev/null 2>&1 || true
  done
}

ensure_wp_cache() {
  # [ANCHOR:WP_CACHE_ENABLE]
  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，跳过 WP_CACHE 设置。"
    return
  fi

  if [ ! -f "${DOC_ROOT}/wp-config.php" ]; then
    log_warn "未找到 wp-config.php，跳过 WP_CACHE 设置。"
    return
  fi

  if lscwp_is_active; then
    if command -v wp >/dev/null 2>&1; then
      if wp_cli_base config set WP_CACHE true --raw >/dev/null 2>&1; then
        log_info "已设置 WP_CACHE=true（LiteSpeed Cache 已启用）。"
        return
      fi

      log_warn "wp-cli 写入 WP_CACHE 失败，尝试直接更新 wp-config.php。"
    else
      log_warn "未找到 wp-cli，尝试直接更新 wp-config.php。"
    fi

    update_wp_config_define "${DOC_ROOT}/wp-config.php" "WP_CACHE" "true" "raw"
    log_info "已写入 WP_CACHE=true（fallback）。"
    return
  fi

  update_wp_config_define "${DOC_ROOT}/wp-config.php" "WP_CACHE" "false" "raw"
  log_info "LiteSpeed Cache 未启用，已设置 WP_CACHE=false。"
}

ensure_uploads_fonts_dir() {
  # [ANCHOR:UPLOADS_FONTS_DIR]
  local uploads_basedir=""
  local fonts_dir=""
  local uploads_owner_group=""
  local uploads_mode=""
  local fonts_mode=""
  local owner_digit=""
  local group_digit=""
  local writable="no"

  if command -v wp >/dev/null 2>&1; then
    if [ -n "${DOC_ROOT:-}" ] && [ -d "$DOC_ROOT" ]; then
      if wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
        uploads_basedir="$(wp_cli_base eval 'echo wp_upload_dir()["basedir"];' 2>/dev/null || true)"
      fi
    fi
  fi

  if [ -z "$uploads_basedir" ]; then
    if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
      return
    fi
    uploads_basedir="${DOC_ROOT}/wp-content/uploads"
  fi

  mkdir -p "$uploads_basedir" >/dev/null 2>&1 || true
  uploads_owner_group="$(stat -c '%u:%g' "$uploads_basedir" 2>/dev/null || true)"
  uploads_mode="$(stat -c '%a' "$uploads_basedir" 2>/dev/null || true)"
  fonts_dir="${uploads_basedir}/fonts"

  if mkdir -p "$fonts_dir" 2>/dev/null; then
    if [ -n "$uploads_owner_group" ]; then
      chown "$uploads_owner_group" "$fonts_dir" >/dev/null 2>&1 || true
    elif id -u www-data >/dev/null 2>&1; then
      chown www-data:www-data "$fonts_dir" >/dev/null 2>&1 || true
    elif id -u nobody >/dev/null 2>&1 && getent group nogroup >/dev/null 2>&1; then
      chown nobody:nogroup "$fonts_dir" >/dev/null 2>&1 || true
    fi

    if [ -n "$uploads_mode" ]; then
      chmod "$uploads_mode" "$fonts_dir" >/dev/null 2>&1 || true
    else
      chmod 775 "$fonts_dir" >/dev/null 2>&1 || true
    fi
    log_info "已确保 fonts 目录存在：${fonts_dir}"
  else
    log_warn "fonts 目录创建失败：${fonts_dir}"
    return
  fi

  fonts_mode="$(stat -c '%a' "$fonts_dir" 2>/dev/null || true)"
  owner_digit="${fonts_mode:0:1}"
  group_digit="${fonts_mode:1:1}"
  if echo "$owner_digit" | grep -Eq '^[0-9]$' && [ "$owner_digit" -ge 2 ]; then
    writable="yes"
  elif echo "$group_digit" | grep -Eq '^[0-9]$' && [ "$group_digit" -ge 2 ]; then
    writable="yes"
  fi

  if [ "$writable" = "yes" ]; then
    log_info "fonts 目录可写：${fonts_dir}"
  else
    log_warn "fonts 目录不可写：${fonts_dir}（权限 ${fonts_mode:-unknown}）"
  fi
}

ensure_wp_indexing_policy() {
  # [ANCHOR:WP_INDEXING_POLICY]
  local choice policy_value

  if ! command -v wp >/dev/null 2>&1; then
    log_warn "未找到 wp-cli，跳过搜索引擎索引策略设置。"
    return
  fi

  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，跳过搜索引擎索引策略设置。"
    return
  fi

  if ! wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    log_warn "WordPress 尚未完成安装，跳过搜索引擎索引策略设置。"
    return
  fi

  if [ -t 0 ] && [ -t 1 ]; then
    read -rp "Allow search engines to index this site? (recommended for production) [Y/n] " choice
  else
    log_info "非交互模式，默认允许搜索引擎索引（blog_public=1）。"
    choice="Y"
  fi

  choice="${choice:-Y}"
  case "$choice" in
    [Nn]*)
      policy_value="0"
      ;;
    *)
      policy_value="1"
      ;;
  esac

  if wp_cli_base option update blog_public "$policy_value" >/dev/null 2>&1; then
    log_info "已设置 blog_public=${policy_value}。"
  else
    log_warn "blog_public 写入失败，跳过。"
  fi
}

ensure_wp_debug_display() {
  # [ANCHOR:WP_DEBUG_DISPLAY]
  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，跳过 WP_DEBUG_DISPLAY 设置。"
    return
  fi

  if [ ! -f "${DOC_ROOT}/wp-config.php" ]; then
    log_warn "未找到 wp-config.php，跳过 WP_DEBUG_DISPLAY 设置。"
    return
  fi

  update_wp_config_define "${DOC_ROOT}/wp-config.php" "WP_DEBUG_DISPLAY" "false" "raw"
  log_info "已设置 WP_DEBUG_DISPLAY=false。"
}

ensure_wp_permalink_structure() {
  # [ANCHOR:WP_PERMALINKS]
  local structure="/%postname%/"

  if ! command -v wp >/dev/null 2>&1; then
    log_warn "未找到 wp-cli，跳过固定链接设置。"
    return
  fi

  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，跳过固定链接设置。"
    return
  fi

  if ! wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    log_warn "WordPress 尚未完成安装，跳过固定链接设置。"
    return
  fi

  if wp_cli_base option update permalink_structure "$structure" >/dev/null 2>&1; then
    if wp_cli_base rewrite flush --hard >/dev/null 2>&1; then
      log_info "固定链接已设置为 ${structure} 并刷新规则。"
    else
      log_warn "固定链接已设置为 ${structure}，但刷新规则失败。"
    fi
  else
    log_warn "固定链接设置失败，跳过。"
  fi
}

ensure_lscwp_page_cache_detect() {
  # [ANCHOR:LSCWP_PAGE_CACHE_DETECT]
  # [ANCHOR:LSCWP_DROPIN]
  local wp_config wp_content advanced_cache plugin_dir source_cache
  local owner_group wp_content_perm
  local lscwp_ready="no"

  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，跳过 Page Cache 检测辅助。"
    return
  fi

  wp_config="${DOC_ROOT}/wp-config.php"
  wp_content="${DOC_ROOT}/wp-content"
  advanced_cache="${wp_content}/advanced-cache.php"
  plugin_dir="${wp_content}/plugins/litespeed-cache"

  if [ ! -f "$wp_config" ]; then
    log_warn "未找到 wp-config.php，跳过 Page Cache 检测辅助。"
    return
  fi

  if ! grep -Eq "define\\(['\"]WP_CACHE['\"],\\s*true\\)" "$wp_config"; then
    ensure_wp_cache
  fi

  if command -v wp >/dev/null 2>&1; then
    if wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
      if wp_cli_base plugin is-installed litespeed-cache >/dev/null 2>&1 \
        && wp_cli_base plugin is-active litespeed-cache >/dev/null 2>&1; then
        lscwp_ready="yes"
      else
        log_warn "LiteSpeed Cache 未安装或未启用，跳过 advanced-cache.php 补充。"
        return
      fi
    else
      log_warn "WordPress 尚未完成安装，跳过 advanced-cache.php 补充。"
      return
    fi
  else
    log_warn "未找到 wp-cli，无法确认 LiteSpeed Cache 状态，跳过 advanced-cache.php 补充。"
    return
  fi

  if [ "$lscwp_ready" != "yes" ]; then
    return
  fi

  if [ ! -d "$wp_content" ]; then
    log_warn "未找到 wp-content，跳过 advanced-cache.php 检测。"
    return
  fi

  if [ ! -f "$advanced_cache" ]; then
    if [ -d "$plugin_dir" ]; then
      if [ -f "${plugin_dir}/advanced-cache.php" ]; then
        source_cache="${plugin_dir}/advanced-cache.php"
      elif [ -f "${plugin_dir}/data/advanced-cache.php" ]; then
        source_cache="${plugin_dir}/data/advanced-cache.php"
      else
        source_cache="$(find "$plugin_dir" -maxdepth 4 -type f -name advanced-cache.php -print -quit 2>/dev/null || true)"
      fi

      if [ -n "$source_cache" ] && cp -f "$source_cache" "$advanced_cache" 2>/dev/null; then
        log_info "已补充 advanced-cache.php：${advanced_cache}"
      else
        log_warn "未找到 LiteSpeed Cache 提供的 advanced-cache.php，跳过复制。"
        return
      fi
    else
      log_warn "未找到 LiteSpeed Cache 目录，无法补充 advanced-cache.php。"
      return
    fi
  fi

  owner_group="$(stat -c '%u:%g' "$wp_content" 2>/dev/null || true)"
  if [ -n "$owner_group" ]; then
    chown "$owner_group" "$advanced_cache" >/dev/null 2>&1 || true
  fi
  wp_content_perm="$(stat -c '%a' "$wp_content" 2>/dev/null || true)"
  if [ -n "$wp_content_perm" ]; then
    chmod "$wp_content_perm" "$advanced_cache" >/dev/null 2>&1 || true
  fi
}

ensure_lsphp_modules_recommended() {
  # [ANCHOR:LSPHP_EXTENSIONS]
  local php_bin="${1:-${LSPHP_BIN:-}}"
  local bin candidates=()
  local pkg_suffix modules
  local missing=()
  local missing_names=()
  local verified="no"

  if [ -n "$php_bin" ] && [ ! -x "$php_bin" ]; then
    php_bin=""
  fi

  if [ -z "$php_bin" ]; then
    for bin in /usr/local/lsws/lsphp*/bin/php; do
      if [ -x "$bin" ]; then
        candidates+=("$bin")
      fi
    done
    if [ "${#candidates[@]}" -gt 0 ]; then
      php_bin="$(printf "%s\n" "${candidates[@]}" | sort -V | tail -n1)"
    fi
  fi

  if [ -z "$php_bin" ]; then
    log_warn "未检测到 LSPHP 可执行文件，推荐模块安装已跳过。"
    return 1
  fi

  modules="$("$php_bin" -m 2>/dev/null | tr '[:upper:]' '[:lower:]')" || modules=""
  pkg_suffix="$(get_lsphp_pkg_suffix "$php_bin")"

  if ! printf '%s\n' "$modules" | grep -qx "imagick"; then
    missing+=("lsphp${pkg_suffix}-imagick")
    missing_names+=("imagick")
  fi
  if ! printf '%s\n' "$modules" | grep -qx "intl"; then
    missing+=("lsphp${pkg_suffix}-intl")
    missing_names+=("intl")
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    log_info "推荐 PHP 模块已安装（imagick/intl）。"
    verified="yes"
  fi

  if [ "$verified" = "no" ]; then
    if ! command -v apt-get >/dev/null 2>&1; then
      log_warn "未检测到 apt-get，推荐模块安装已跳过。"
      return 1
    fi

    if [ "${LSPHP_EXTENSIONS_APT_UPDATED:-0}" -eq 0 ]; then
      if ! apt-get update -qq; then
        log_warn "apt-get update 失败，推荐模块安装可能无法完成。"
      fi
      LSPHP_EXTENSIONS_APT_UPDATED=1
    fi

    log_info "尝试安装推荐 PHP 模块（${missing_names[*]}）..."
    if ! apt-get install -y "${missing[@]}"; then
      log_warn "推荐模块安装失败（${missing_names[*]}），继续执行。"
      return 1
    fi

    if systemctl restart lsws >/dev/null 2>&1; then
      log_info "OpenLiteSpeed 已重启以加载推荐 PHP 模块。"
    else
      log_warn "OpenLiteSpeed 重启失败，请手动检查。"
    fi

    log_info "已安装推荐 PHP 扩展（${missing_names[*]}）。"
  fi

  modules="$("$php_bin" -m 2>/dev/null | tr '[:upper:]' '[:lower:]')" || modules=""
  if ! printf '%s\n' "$modules" | grep -qx "imagick"; then
    log_warn "imagick 仍不可用（lsphp${pkg_suffix}-imagick）。"
    log_warn "请确认安装的模块版本匹配当前 LSPHP（${pkg_suffix}），并重启 lsws/lsphp。"
    return 1
  fi

  log_info "imagick 扩展已可用。"
  return 0
}

resolve_default_theme_slug() {
  local year suffix
  year="$(date +%Y)"
  case "$year" in
    2020) suffix="base";;
    2021) suffix="one";;
    2022) suffix="two";;
    2023) suffix="three";;
    2024) suffix="four";;
    2025) suffix="five";;
    2026) suffix="six";;
    2027) suffix="seven";;
    2028) suffix="eight";;
    2029) suffix="nine";;
    2030) suffix="ten";;
    2031) suffix="eleven";;
    2032) suffix="twelve";;
    2033) suffix="thirteen";;
    2034) suffix="fourteen";;
    2035) suffix="fifteen";;
    *) suffix="";;
  esac

  if [ -z "$suffix" ]; then
    printf ""
    return
  fi

  if [ "$suffix" = "base" ]; then
    printf "twentytwenty"
  else
    printf "twentytwenty%s" "$suffix"
  fi
}

ensure_default_theme_policy() {
  # [ANCHOR:WP_DEFAULT_THEME_POLICY]
  if ! command -v wp >/dev/null 2>&1; then
    log_warn "未找到 wp-cli，跳过默认主题设置。"
    return
  fi

  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，跳过默认主题设置。"
    return
  fi

  if ! wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    log_warn "WordPress 尚未完成安装，跳过默认主题设置。"
    return
  fi

  local target_theme fallback_theme selected_theme
  local installed_themes theme

  target_theme="$(resolve_default_theme_slug)"
  if [ -n "$target_theme" ]; then
    log_info "按年份选择默认主题：$(date +%Y) -> ${target_theme}"
  fi

  if [ -n "$target_theme" ]; then
    if wp_cli_base theme install "$target_theme" --activate >/dev/null 2>&1; then
      selected_theme="$target_theme"
    else
      log_warn "默认主题 ${target_theme} 安装/启用失败，尝试回退已安装主题。"
    fi
  fi

  installed_themes="$(wp_cli_base theme list --field=name --skip-plugins --skip-themes 2>/dev/null)" || installed_themes=""
  if [ -z "$selected_theme" ]; then
    fallback_theme="$(printf '%s\n' "$installed_themes" | awk '/^twentytwenty/ {print}' | sort -V | tail -n1)"
    if [ -n "$fallback_theme" ]; then
      if wp_cli_base theme activate "$fallback_theme" >/dev/null 2>&1; then
        selected_theme="$fallback_theme"
      else
        log_warn "默认主题回退激活失败：${fallback_theme}"
      fi
    else
      log_warn "未找到可用的 Twenty* 主题，跳过默认主题设置。"
      return
    fi
  fi

  for theme in $installed_themes; do
    if [[ "$theme" != twentytwenty* ]]; then
      continue
    fi
    if [ "$theme" = "$selected_theme" ]; then
      continue
    fi
    wp_cli_base theme delete "$theme" >/dev/null 2>&1 || true
  done

  log_info "默认主题已设置为 ${selected_theme}（保留最新年度主题）。"
}

verify_wp_baseline() {
  # [ANCHOR:WP_BASELINE_VERIFY]
  local verifier="${REPO_ROOT}/tools/wp-baseline-verify.sh"

  if [ ! -x "$verifier" ]; then
    log_warn "未找到 WP baseline 验证脚本：${verifier}"
    return
  fi

  if ! "$verifier" --doc-root "${DOC_ROOT:-}"; then
    log_warn "WP baseline verification reported unmet requirements."
  fi
}

apply_wp_lomp_baseline() {
  # [ANCHOR:WP_LOMP_BASELINE]
  # [ANCHOR:WP_BASELINE_START]
  local php_bin

  ensure_lscache_only
  ensure_wp_cache
  ensure_wp_debug_display
  ensure_wp_indexing_policy
  ensure_wp_permalink_structure
  ensure_uploads_fonts_dir
  ensure_lscwp_page_cache_detect
  php_bin="$(detect_lsphp_bin)" || php_bin=""
  ensure_lsphp_modules_recommended "$php_bin"
  ensure_default_theme_policy
  verify_wp_baseline
  # [ANCHOR:WP_BASELINE_END]
}

random_wp_salt() {
  local salt=""

  if command -v openssl >/dev/null 2>&1; then
    salt="$(openssl rand -base64 48 2>/dev/null | tr -d '\n' | head -c 64)"
  fi

  if [ -z "$salt" ]; then
    salt="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_[]{}<>~`+=,.;:?' </dev/urandom | head -c 64)"
  fi

  printf "%s" "$salt"
}

random_wp_password() {
  local password=""

  if command -v openssl >/dev/null 2>&1; then
    password="$(openssl rand -base64 18 2>/dev/null | tr -d '\n')"
  fi

  if [ -z "$password" ]; then
    password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 18)"
  fi

  printf "%s" "$password"
}

fetch_wp_salts() {
  local salts=""
  local key
  local keys=(
    AUTH_KEY
    SECURE_AUTH_KEY
    LOGGED_IN_KEY
    NONCE_KEY
    AUTH_SALT
    SECURE_AUTH_SALT
    LOGGED_IN_SALT
    NONCE_SALT
  )

  for key in "${keys[@]}"; do
    salts+="define('${key}', '$(random_wp_salt)');"$'\n'
  done

  printf "%s" "$salts"
}

apply_wp_salts() {
  local wp_config="$1"
  local salts="$2"
  local fallback_used=0
  local key value
  local keys=(
    AUTH_KEY
    SECURE_AUTH_KEY
    LOGGED_IN_KEY
    NONCE_KEY
    AUTH_SALT
    SECURE_AUTH_SALT
    LOGGED_IN_SALT
    NONCE_SALT
  )

  for key in "${keys[@]}"; do
    value=""
    if [ -n "$salts" ]; then
      value="$(printf '%s\n' "$salts" | awk -F"'" -v target="$key" '$2==target {print $4; exit}')"
    fi
    if [ -z "$value" ]; then
      value="$(random_wp_salt)"
      fallback_used=1
    fi
    update_wp_config_define "$wp_config" "$key" "$value" "string"
  done

  if [ "$fallback_used" -eq 1 ]; then
    log_warn "Salt 生成使用本地随机值。"
  else
    log_info "已写入 WordPress 安全密钥（salt）。"
  fi
}

ensure_wp_core_installed() {
  # [ANCHOR:WP_CORE_INSTALL]
  local site_url site_title admin_user admin_pass admin_email choice admin_pass_input

  if ! command -v wp >/dev/null 2>&1; then
    log_warn "未找到 wp-cli，无法自动初始化 WordPress。"
    return 1
  fi

  if [ -z "${DOC_ROOT:-}" ] || [ ! -d "$DOC_ROOT" ]; then
    log_warn "未找到站点目录，无法初始化 WordPress。"
    return 1
  fi

  if wp_cli_base core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    return 0
  fi

  if [ "${SSL_MODE:-http-only}" = "http-only" ]; then
    site_url="http://${SITE_DOMAIN}"
  else
    site_url="https://${SITE_DOMAIN}"
  fi

  if [ -t 0 ] && [ -t 1 ]; then
    read -rp "使用 wp-cli 初始化 WordPress？[Y/n] " choice
    choice="${choice:-Y}"
  else
    choice="Y"
  fi

  case "$choice" in
    [Nn]*)
      log_warn "已跳过 WordPress 初始化，WP baseline 将延后至安装完成后。"
      return 1
      ;;
    *)
      ;;
  esac

  site_title="${SITE_DOMAIN:-WordPress Site}"
  admin_user="admin"
  admin_email="admin@localhost"
  admin_pass="$(random_wp_password)"

  if [ -t 0 ] && [ -t 1 ]; then
    read -rp "站点标题（默认 ${site_title}）: " site_title
    site_title="${site_title:-${SITE_DOMAIN:-WordPress Site}}"
    read -rp "管理员用户名（默认 ${admin_user}）: " admin_user
    admin_user="${admin_user:-admin}"
    read -rp "管理员邮箱（默认 ${admin_email}）: " admin_email
    admin_email="${admin_email:-admin@localhost}"
    read -rsp "管理员密码（留空自动生成）: " admin_pass_input
    echo
    if [ -n "$admin_pass_input" ]; then
      admin_pass="$admin_pass_input"
    fi
  fi

  if wp_cli_base core install \
    --url="$site_url" \
    --title="$site_title" \
    --admin_user="$admin_user" \
    --admin_password="$admin_pass" \
    --admin_email="$admin_email" >/dev/null 2>&1; then
    log_info "WordPress 已初始化完成。"
    log_info "管理员账号: ${admin_user}"
    log_info "管理员密码: ${admin_pass}"
    log_info "管理员邮箱: ${admin_email}"
    return 0
  fi

  log_warn "WordPress 初始化失败，请手动完成安装后再执行 baseline。"
  return 1
}

ensure_wp_redis_config() {
  # [ANCHOR:WP_REDIS_CONFIG]
  if [ "${REDIS_ENABLED:-no}" != "yes" ]; then
    return
  fi

  local wp_config="${DOC_ROOT}/wp-config.php"
  if [ ! -f "$wp_config" ]; then
    log_warn "未找到 ${wp_config}，无法写入 Redis 配置。"
    return
  fi

  update_wp_config_define "$wp_config" "WP_CACHE" "true" "raw"
  update_wp_config_define "$wp_config" "WP_REDIS_HOST" "$REDIS_HOST" "string"
  update_wp_config_define "$wp_config" "WP_REDIS_PORT" "$REDIS_PORT" "raw"
  if [ -n "$REDIS_PASSWORD" ]; then
    update_wp_config_define "$wp_config" "WP_REDIS_PASSWORD" "$REDIS_PASSWORD" "string"
  fi

  log_info "已写入 wp-config.php Redis 连接信息（WP_REDIS_*）。"
}

install_packages() {
  # [ANCHOR:INSTALL_OLS]
  log_step "安装 / 检查 LOMP Web/PHP 组件（OpenLiteSpeed）"

  apt update
  apt install -y software-properties-common curl

  if ! dpkg -l | grep -q '^ii[[:space:]]\+openlitespeed[[:space:]]'; then
    log_info "安装 LOMP Web（openlitespeed）..."
    apt install -y openlitespeed
  else
    log_info "检测到 LOMP Web（openlitespeed）已安装，跳过。"
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
  log_step "配置 LOMP Web Virtual Host（OpenLiteSpeed）"

  local LSWS_ROOT="/usr/local/lsws"
  local HTTPD_CONF="${LSWS_ROOT}/conf/httpd_config.conf"
  local VH_CONF_DIR="${LSWS_ROOT}/conf/vhosts/${SITE_SLUG}"
  local VH_CONF_FILE="${VH_CONF_DIR}/vhconf.conf"
  local VH_ROOT="/var/www/${SITE_SLUG}"

  [ -d "$LSWS_ROOT" ] || { log_error "未找到 ${LSWS_ROOT}，请确认 LOMP Web 安装成功。"; exit 1; }

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
  [ -d wordpress ] || { log_error "解压 WordPress 失败。"; popd >/dev/null; rm -rf -- "${tmp:?}"; exit 1; }

  cp -a wordpress/. "$DOC_ROOT"/

  popd >/dev/null
  rm -rf -- "${tmp:?}"

  log_info "WordPress 已部署到 ${DOC_ROOT}。"
}

prompt_site_size_limit() {
  # [ANCHOR:SITE_SIZE_LIMIT_PROMPT]
  local choice

  SITE_SIZE_LIMIT_ENABLED="no"
  SITE_SIZE_LIMIT_GB=""

  read -rp "是否启用站点容量软限制监控？[Y/n]（默认不启用）: " choice
  choice="${choice:-N}"

  case "$choice" in
    [Yy]*)
      SITE_SIZE_LIMIT_ENABLED="yes"
      while :; do
        read -rp "请输入容量上限（单位 GB，例如 5）: " SITE_SIZE_LIMIT_GB
        if [[ "$SITE_SIZE_LIMIT_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] \
          && awk -v v="$SITE_SIZE_LIMIT_GB" 'BEGIN{exit (v>0)?0:1}'; then
          break
        fi
        log_warn "容量上限必须为大于 0 的数字。"
      done
      ;;
    *)
      SITE_SIZE_LIMIT_ENABLED="no"
      ;;
  esac
}

setup_site_size_limit_monitor() {
  # [ANCHOR:SITE_SIZE_LIMIT_SETUP]
  if [ "${SITE_SIZE_LIMIT_ENABLED:-no}" != "yes" ]; then
    return
  fi

  local slug="${SITE_SLUG}"
  local site_dir="${DOC_ROOT}"
  local limit_gb="${SITE_SIZE_LIMIT_GB}"

  SITE_SIZE_CHECK_SCRIPT="/usr/local/bin/wp-site-size-check-${slug}.sh"
  SITE_SIZE_CHECK_SERVICE="/etc/systemd/system/wp-site-size-check-${slug}.service"
  SITE_SIZE_CHECK_TIMER="/etc/systemd/system/wp-site-size-check-${slug}.timer"

  cat >"$SITE_SIZE_CHECK_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeo pipefail

SITE_DIR="${site_dir}"
LIMIT_GB="${limit_gb}"
ALERT_SCRIPT="/usr/local/bin/send-alert-mail.sh"
ALERT_EMAIL="\${WP_SITE_SIZE_ALERT_EMAIL:-}"

log_warn() { echo "[WARN][\$(date +'%Y-%m-%d %H:%M:%S')] \$*" >&2; }

if [ ! -d "\$SITE_DIR" ]; then
  log_warn "Site directory not found: \$SITE_DIR"
  exit 0
fi

size_mb="\$(du -sm "\$SITE_DIR" 2>/dev/null | awk '{print \$1}')"
if [[ -z "\$size_mb" || ! "\$size_mb" =~ ^[0-9]+$ ]]; then
  log_warn "Unable to measure site size for \$SITE_DIR"
  exit 0
fi

limit_mb="\$(awk -v limit="\$LIMIT_GB" 'BEGIN{printf "%.0f", limit*1024}')"
if [[ -z "\$limit_mb" || ! "\$limit_mb" =~ ^[0-9]+$ ]]; then
  log_warn "Invalid size limit (GB): \$LIMIT_GB"
  exit 0
fi

if [ "\$size_mb" -gt "\$limit_mb" ]; then
  msg="Site size limit exceeded for ${slug}: \${size_mb}MB > \${limit_mb}MB (limit \${LIMIT_GB}GB). Path: \$SITE_DIR"
  if [ -x "\$ALERT_SCRIPT" ] && [ -n "\$ALERT_EMAIL" ]; then
    "\$ALERT_SCRIPT" "[ALERT] WordPress site size limit exceeded (${slug})" "\$msg" "\$ALERT_EMAIL" \
      || log_warn "Failed to send alert via \$ALERT_SCRIPT"
  else
    log_warn "\$msg"
  fi
fi
EOF

  chmod +x "$SITE_SIZE_CHECK_SCRIPT"

  cat >"$SITE_SIZE_CHECK_SERVICE" <<EOF
[Unit]
Description=WordPress site size check (${slug})

[Service]
Type=oneshot
ExecStart=${SITE_SIZE_CHECK_SCRIPT}
EOF

  cat >"$SITE_SIZE_CHECK_TIMER" <<EOF
[Unit]
Description=Run WordPress site size check (${slug}) hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "wp-site-size-check-${slug}.timer"

  log_info "已启用站点容量监控: ${SITE_SIZE_CHECK_SCRIPT}"
}

print_site_size_limit_summary() {
  # [ANCHOR:SITE_SIZE_LIMIT_SUMMARY]
  echo
  echo -e "${CYAN}站点容量监控（可选）${NC}"
  if [ "${SITE_SIZE_LIMIT_ENABLED:-no}" != "yes" ]; then
    echo "未启用站点容量监控。"
    return
  fi

  echo "容量上限: ${SITE_SIZE_LIMIT_GB} GB（仅监控告警，不阻止写入）"
  echo "检查脚本: ${SITE_SIZE_CHECK_SCRIPT}"
  echo "systemd service: ${SITE_SIZE_CHECK_SERVICE}"
  echo "systemd timer: ${SITE_SIZE_CHECK_TIMER}"
  echo
  echo "禁用/移除："
  echo "  systemctl disable --now wp-site-size-check-${SITE_SLUG}.timer"
  echo "  rm -f ${SITE_SIZE_CHECK_SERVICE} ${SITE_SIZE_CHECK_TIMER} ${SITE_SIZE_CHECK_SCRIPT}"
  echo "  systemctl daemon-reload"
}

generate_wp_config() {
  # [ANCHOR:WP_CONFIG_GENERATE]
  log_step "生成 wp-config.php"

  local wp_config="${DOC_ROOT}/wp-config.php"
  local sample="${DOC_ROOT}/wp-config-sample.php"

  if [ -f "$wp_config" ]; then
    local overwrite
    read -rp "检测到已存在 wp-config.php，是否覆盖？[y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      log_warn "保留现有 wp-config.php，跳过生成。"
      return
    fi
  fi

  [ -f "$sample" ] || { log_error "未找到 ${sample}，无法生成 wp-config.php。"; exit 1; }

  # [ANCHOR:WRITE_WP_CONFIG]
  cp "$sample" "$wp_config"

  # 处理包含 & 或反斜杠等特殊字符的密码，避免被 sed 误替换
  local esc_db_password="$DB_PASSWORD"
  esc_db_password=${esc_db_password//\\/\\\\}
  esc_db_password=${esc_db_password//&/\\&}

  local db_host_value
  db_host_value="$(get_wp_db_host_value)"

  sed -i "s|database_name_here|${DB_NAME}|" "$wp_config"
  sed -i "s|username_here|${DB_USER}|" "$wp_config"
  sed -i "s|password_here|${esc_db_password}|" "$wp_config"
  sed -i "s|localhost|${db_host_value}|" "$wp_config"

  local salt_block
  salt_block="$(fetch_wp_salts)"
  apply_wp_salts "$wp_config" "$salt_block"

  log_info "已根据输入生成 wp-config.php（DB_* 信息已写入）。"
}

ensure_wp_https_urls() {
  # [ANCHOR:WP_HTTPS_URLS]
  if [ "${SSL_MODE:-http-only}" = "http-only" ]; then
    return
  fi

  local domain=""
  if [ -n "${SITE_DOMAIN:-}" ]; then
    domain="$SITE_DOMAIN"
  elif [ -n "${PRIMARY_DOMAIN:-}" ]; then
    domain="$PRIMARY_DOMAIN"
  elif [ -n "${DOMAIN:-}" ]; then
    domain="$DOMAIN"
  fi

  if [ -z "$domain" ]; then
    log_warn "未检测到域名，无法自动设置 WordPress HTTPS 地址。"
    echo "  可在安装后执行："
    echo "  wp option update home \"https://abc.yourdomain.com\" --path=\"${DOC_ROOT}\" --skip-plugins --skip-themes"
    echo "  wp option update siteurl \"https://abc.yourdomain.com\" --path=\"${DOC_ROOT}\" --skip-plugins --skip-themes"
    echo "  或在 ${DOC_ROOT}/wp-config.php 中加入："
    echo "  define('WP_HOME', 'https://abc.yourdomain.com');"
    echo "  define('WP_SITEURL', 'https://abc.yourdomain.com');"
    echo "HTTPS URL 更新: 需要手动设置"
    return
  fi

  local https_url="https://${domain}"
  local wp_path="${DOC_ROOT}"
  local wp_config="${DOC_ROOT}/wp-config.php"

  if command -v wp >/dev/null 2>&1; then
    if wp core is-installed --path="$wp_path" --skip-plugins --skip-themes >/dev/null 2>&1; then
      if wp option update home "$https_url" --path="$wp_path" --skip-plugins --skip-themes >/dev/null 2>&1 \
        && wp option update siteurl "$https_url" --path="$wp_path" --skip-plugins --skip-themes >/dev/null 2>&1; then
        log_info "已设置 WordPress HTTPS 地址为 ${https_url}。"
        echo "HTTPS URL 更新: 已自动设置"
        return
      fi
      log_warn "使用 wp-cli 更新 HTTPS 地址失败，尝试写入 wp-config.php。"
    fi
  fi

  if [ -f "$wp_config" ]; then
    local has_home has_siteurl
    if grep -q "define([\"']WP_HOME[\"']" "$wp_config"; then
      has_home=1
    fi
    if grep -q "define([\"']WP_SITEURL[\"']" "$wp_config"; then
      has_siteurl=1
    fi

    if [ -n "${has_home:-}" ]; then
      awk -v url="$https_url" '
        $0 ~ /^[[:space:]]*define\([[:space:]]*['\''"]WP_HOME['\''"]/ {
          print "define('\''WP_HOME'\'', '\''" url "'\'');"
          next
        }
        {print}
      ' "$wp_config" >"${wp_config}.tmp" && mv "${wp_config}.tmp" "$wp_config"
    fi

    if [ -n "${has_siteurl:-}" ]; then
      awk -v url="$https_url" '
        $0 ~ /^[[:space:]]*define\([[:space:]]*['\''"]WP_SITEURL['\''"]/ {
          print "define('\''WP_SITEURL'\'', '\''" url "'\'');"
          next
        }
        {print}
      ' "$wp_config" >"${wp_config}.tmp" && mv "${wp_config}.tmp" "$wp_config"
    fi

    if [ -z "${has_home:-}" ] || [ -z "${has_siteurl:-}" ]; then
      awk -v url="$https_url" -v add_home="${has_home:-}" -v add_site="${has_siteurl:-}" '
        NR==1 {
          print
          if(add_home==""){print "define('\''WP_HOME'\'', '\''" url "'\'');"}
          if(add_site==""){print "define('\''WP_SITEURL'\'', '\''" url "'\'');"}
          next
        }
        {print}
      ' "$wp_config" >"${wp_config}.tmp" && mv "${wp_config}.tmp" "$wp_config"
    fi

    log_info "已在 wp-config.php 中设置 WP_HOME/WP_SITEURL 为 ${https_url}。"
    echo "HTTPS URL 更新: 已自动设置"
    return
  fi

  log_warn "未找到 ${wp_config}，无法自动设置 HTTPS 地址。"
  echo "  可在安装后执行："
  echo "  wp option update home \"${https_url}\" --path=\"${DOC_ROOT}\" --skip-plugins --skip-themes"
  echo "  wp option update siteurl \"${https_url}\" --path=\"${DOC_ROOT}\" --skip-plugins --skip-themes"
  echo "HTTPS URL 更新: 需要手动设置"
}

ensure_wp_loopback_and_rest_health() {
  # [ANCHOR:WP_LOOPBACK_REST_HEALTH]
  local doc_root="${DOC_ROOT:-}"
  local domain="${SITE_DOMAIN:-}"
  local site_url=""
  local scheme="https"
  local base_url=""
  local wp_json_code ajax_code
  local curl_exit=0

  if ! command -v wp >/dev/null 2>&1; then
    log_warn "未找到 wp-cli，跳过 REST/loopback 检查。"
    return
  fi

  if [ -z "$doc_root" ] || [ ! -d "$doc_root" ]; then
    log_warn "未找到站点目录，跳过 REST/loopback 检查。"
    return
  fi

  if ! wp --path="$doc_root" --allow-root core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    log_info "Skipping REST/loopback check: WordPress not installed yet."
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_warn "未找到 curl，跳过 REST/loopback 检查。"
    return
  fi

  if [ -z "$domain" ]; then
    site_url="$(wp --path="$doc_root" --allow-root option get home --skip-plugins --skip-themes 2>/dev/null || true)"
    if [ -z "$site_url" ]; then
      site_url="$(wp --path="$doc_root" --allow-root option get siteurl --skip-plugins --skip-themes 2>/dev/null || true)"
    fi
    site_url="${site_url%/}"
    site_url="${site_url#http://}"
    site_url="${site_url#https://}"
    site_url="${site_url%%/*}"
    domain="$site_url"
  fi

  if [ -z "$domain" ]; then
    log_warn "未检测到域名，跳过 REST/loopback 检查。"
    return
  fi

  if [ "${SSL_MODE:-http-only}" = "http-only" ]; then
    scheme="http"
  fi

  base_url="${scheme}://${domain}"

  curl_exit=0
  wp_json_code="$(curl -kfsS -o /dev/null -w "%{http_code}" "${base_url}/wp-json/" 2>/dev/null)" || curl_exit=$?
  if [ "$curl_exit" -ne 0 ]; then
    log_warn "REST API 请求失败：${base_url}/wp-json/"
  elif printf '%s' "$wp_json_code" | grep -Eq '^(2|3)[0-9]{2}$'; then
    log_info "REST API 正常：HTTP ${wp_json_code}"
  else
    log_warn "REST API 返回异常：HTTP ${wp_json_code:-未知}"
  fi

  curl_exit=0
  ajax_code="$(curl -kfsS -o /dev/null -w "%{http_code}" "${base_url}/wp-admin/admin-ajax.php" 2>/dev/null)" || curl_exit=$?
  if [ "$curl_exit" -ne 0 ]; then
    log_warn "Loopback 请求失败：${base_url}/wp-admin/admin-ajax.php"
  elif printf '%s' "$ajax_code" | grep -Eq '^(2|3)[0-9]{2}$'; then
    log_info "Loopback 正常：HTTP ${ajax_code}"
  else
    log_warn "Loopback 返回异常：HTTP ${ajax_code:-未知}"
  fi
}

loopback_hosts_block_present() {
  local begin_marker="$1"
  local end_marker="$2"

  [ -f /etc/hosts ] || return 1
  if grep -qFx "$begin_marker" /etc/hosts && grep -qFx "$end_marker" /etc/hosts; then
    return 0
  fi

  return 1
}

loopback_host_conflict_exists() {
  local domain="$1"
  local begin_marker="$2"
  local end_marker="$3"

  awk -v domain="$domain" -v begin="$begin_marker" -v end="$end_marker" '
    BEGIN {in_block=0; conflict=0}
    $0 == begin {in_block=1; next}
    $0 == end {in_block=0; next}
    in_block {next}
    {
      line=$0
      sub(/#.*/, "", line)
      if (line ~ /^[[:space:]]*$/) next
      n=split(line, fields, /[[:space:]]+/)
      for (i=2; i<=n; i++) {
        if (fields[i] == domain) {
          conflict=1
          exit
        }
      }
    }
    END {exit conflict ? 0 : 1}
  ' /etc/hosts
}

apply_loopback_hosts_override() {
  local domain="$1"
  local www_domain="${2:-}"
  local begin_marker="# hz-oneclick loopback begin"
  local end_marker="# hz-oneclick loopback end"
  local host_lines tmp_file

  if [ -z "$domain" ]; then
    log_warn "未检测到域名，跳过 hosts 修改。"
    return 1
  fi

  if [ ! -f /etc/hosts ]; then
    log_warn "/etc/hosts 不存在，跳过 hosts 修改。"
    return 1
  fi

  if loopback_host_conflict_exists "$domain" "$begin_marker" "$end_marker"; then
    log_warn "检测到 ${domain} 已在 /etc/hosts 中自定义映射，已跳过自动修改。"
    return 1
  fi
  if [ -n "$www_domain" ] && loopback_host_conflict_exists "$www_domain" "$begin_marker" "$end_marker"; then
    log_warn "检测到 ${www_domain} 已在 /etc/hosts 中自定义映射，已跳过自动修改。"
    return 1
  fi

  host_lines="$(printf "127.0.0.1 %s\n" "$domain")"
  if [ -n "$www_domain" ]; then
    host_lines="${host_lines}$(printf "127.0.0.1 %s\n" "$www_domain")"
  fi

  tmp_file="$(mktemp)"

  if loopback_hosts_block_present "$begin_marker" "$end_marker"; then
    awk -v begin="$begin_marker" -v end="$end_marker" -v lines="$host_lines" '
      $0 == begin {
        print begin
        printf "%s", lines
        in_block=1
        next
      }
      $0 == end {
        in_block=0
        print end
        next
      }
      !in_block {print}
    ' /etc/hosts >"$tmp_file"
  else
    cat /etc/hosts >"$tmp_file"
    {
      echo "$begin_marker"
      printf "%s" "$host_lines"
      echo "$end_marker"
    } >>"$tmp_file"
  fi

  if ! cmp -s /etc/hosts "$tmp_file"; then
    cp "$tmp_file" /etc/hosts
  fi

  rm -f "$tmp_file"

  log_info "已更新 /etc/hosts loopback 映射。"
  log_info "如需撤销，可删除 /etc/hosts 中以下标记区块："
  echo "  ${begin_marker}"
  echo "  ${end_marker}"
  return 0
}

run_loopback_preflight() {
  # [ANCHOR:LOOPBACK_PREFLIGHT]
  local domain="${SITE_DOMAIN:-}"
  local doc_root="${DOC_ROOT:-}"
  local check_failed=0
  local openssl_exit=0
  local curl_output curl_exit
  local www_domain=""
  local add_www=""

  if [ -z "$domain" ]; then
    log_warn "未检测到域名，跳过 Loopback/REST API 预检。"
    return 0
  fi

  if [ -z "$doc_root" ] || [ ! -d "$doc_root" ]; then
    log_warn "未找到站点目录，跳过 Loopback/REST API 预检。"
    return 0
  fi

  log_step "Loopback/REST API 预检"

  echo "1) 端口监听检查（80/443）"
  if command -v ss >/dev/null 2>&1; then
    if ss -lntp | grep -q ":443 "; then
      log_info "检测到 443 监听。"
    else
      log_warn "未检测到 443 监听。"
      check_failed=1
    fi
    if ss -lntp | grep -q ":80 "; then
      log_info "检测到 80 监听。"
    else
      log_warn "未检测到 80 监听。"
    fi
  else
    if netstat -lntp 2>/dev/null | grep -q ":443 "; then
      log_info "检测到 443 监听。"
    else
      log_warn "未检测到 443 监听。"
      check_failed=1
    fi
    if netstat -lntp 2>/dev/null | grep -q ":80 "; then
      log_info "检测到 80 监听。"
    else
      log_warn "未检测到 80 监听。"
    fi
  fi

  echo
  echo "2) 本机 TLS/SNI 握手检查"
  if command -v openssl >/dev/null 2>&1; then
    openssl s_client -connect 127.0.0.1:443 -servername "$domain" -brief </dev/null >/dev/null 2>&1
    openssl_exit=$?
    if [ "$openssl_exit" -eq 0 ]; then
      log_info "TLS/SNI 握手成功。"
    else
      log_warn "TLS/SNI 握手失败。"
      check_failed=1
    fi
  else
    log_warn "未找到 openssl，跳过 TLS/SNI 检查。"
  fi

  echo
  echo "3) 本机 HTTPS 回环请求检查（Host/SNI）"
  if command -v curl >/dev/null 2>&1; then
    curl_exit=0
    curl_output="$(curl -kfsSIL --resolve "${domain}:443:127.0.0.1" "https://${domain}/" 2>&1)" || curl_exit=$?
    if [ "${curl_exit:-0}" -eq 0 ]; then
      log_info "HTTPS 回环请求成功。"
    else
      log_warn "HTTPS 回环请求失败：${curl_output}"
      check_failed=1
    fi
  else
    log_warn "未找到 curl，跳过 HTTPS 回环检查。"
  fi

  if [ -f "${doc_root}/wp-config.php" ] || [ -f "${doc_root}/wp-settings.php" ]; then
    echo
    echo "4) WordPress REST API 回环检查"
    if command -v curl >/dev/null 2>&1; then
      curl_exit=0
      curl_output="$(curl -kfsS --resolve "${domain}:443:127.0.0.1" "https://${domain}/wp-json/" 2>&1)" || curl_exit=$?
      if [ "${curl_exit:-0}" -eq 0 ]; then
        log_info "wp-json 回环请求成功。"
      else
        log_warn "wp-json 回环请求失败：${curl_output}"
        check_failed=1
      fi
    else
      log_warn "未找到 curl，跳过 wp-json 回环检查。"
    fi
  fi

  if [ "$check_failed" -ne 0 ]; then
    log_warn "Local HTTPS loopback check failed; WordPress REST/loopback may report critical issues."
  fi

  if [ "$check_failed" -eq 0 ]; then
    return 0
  fi

  echo
  log_warn "部分环境无法从服务器自身稳定访问 HTTPS 域名，这会导致 REST API/loopback 检查报错。"
  echo "  1) 应用本地 hosts loopback 修复（推荐）"
  echo "  2) 跳过（仅提供手动指引）"
  echo
  read -rp "请选择 [1-2，默认 2]: " loopback_choice
  loopback_choice="${loopback_choice:-2}"

  case "$loopback_choice" in
    1)
      if [[ "$domain" != www.* ]]; then
        read -rp "是否同时映射 www.${domain}？[y/N]: " add_www
        add_www="${add_www:-N}"
        if [[ "$add_www" =~ ^[Yy]$ ]]; then
          www_domain="www.${domain}"
        fi
      fi
      if apply_loopback_hosts_override "$domain" "$www_domain"; then
        echo
        echo "5) 修复后回环复检（curl --resolve）"
        curl_exit=0
        curl_output="$(curl -kfsSIL --resolve "${domain}:443:127.0.0.1" "https://${domain}/" 2>&1)" || curl_exit=$?
        if [ "${curl_exit:-0}" -eq 0 ]; then
          log_info "Loopback 修复复检通过。"
        else
          log_warn "Loopback 修复复检失败：${curl_output}"
        fi
      else
        log_warn "hosts 更新未完成，已跳过复检。"
      fi
      ;;
    *)
      echo "手动指引："
      echo "  1) 在 /etc/hosts 添加以下区块："
      echo "     # hz-oneclick loopback begin"
      echo "     127.0.0.1 ${domain}"
      if [[ "$domain" != www.* ]]; then
        echo "     127.0.0.1 www.${domain}  (如你使用 www 域名)"
      fi
      echo "     # hz-oneclick loopback end"
      echo "  2) 重新执行：curl -kfsSIL --resolve \"${domain}:443:127.0.0.1\" \"https://${domain}/\""
      ;;
  esac
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
  echo "  2) 使用 Origin Certificate（手动粘贴证书和 Private Key）"
  echo "  3) 使用 Let's Encrypt 自动申请证书（需域名已指向本机，灰云）"
  echo

  read -rp "请输入数字 [1-3，默认 1]: " choice
  choice="${choice:-1}"

  case "$choice" in
    1)
      SSL_MODE="http-only"
      log_warn "本次不配置 SSL，仅监听 80。若在 CDN 后台使用严格模式（类似 Full(strict)），源站无证书会导致 521。"
      ;;
    2)
      SSL_MODE="origin-cert"
      local cert_file key_file ssl_prefix ssl_prefix_sanitized
      log_info "你选择了 Origin Certificate 模式。请先在 CDN/加速服务后台生成源站证书。"
      echo "默认证书路径: /usr/local/lsws/conf/ssl/${SITE_SLUG}.cert.pem"
      echo "默认 Private Key 路径: /usr/local/lsws/conf/ssl/${SITE_SLUG}.key.pem"
      echo "默认前缀: ${SITE_SLUG}（直接回车接受默认）"
      echo "Default: ${SITE_SLUG} (Press Enter to accept default)"
      read -rp "请输入证书/Private Key 文件名前缀（例如: example）: " ssl_prefix
      ssl_prefix="${ssl_prefix:-$SITE_SLUG}"
      ssl_prefix_sanitized="$(printf '%s' "$ssl_prefix" | tr -cd 'A-Za-z0-9._-')"
      if [ -z "$ssl_prefix_sanitized" ]; then
        ssl_prefix_sanitized="$SITE_SLUG"
      fi
      cert_file="/usr/local/lsws/conf/ssl/${ssl_prefix_sanitized}.cert.pem"
      key_file="/usr/local/lsws/conf/ssl/${ssl_prefix_sanitized}.key.pem"
      if [ -z "$cert_file" ] || [ -z "$key_file" ]; then
        log_error "证书/Private Key 路径不能为空，跳过 SSL 配置。"; return
      fi
      mkdir -p "$(dirname "$cert_file")"
      echo; echo "请粘贴 Origin Certificate 内容，结束后 Ctrl+D："; cat >"$cert_file"
      echo; echo "请粘贴对应 Private Key 内容，结束后 Ctrl+D："; cat >"$key_file"
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
      SSL_MODE="letsencrypt"
      # [ANCHOR:SSL_LE]
      log_info "你选择 Let's Encrypt。请确保：域名 ${SITE_DOMAIN} 已指向本机，且 DNS 记录为灰云。"
      apt install -y certbot
      local email cert_path key_path
      read -rp "请输入用于 Let's Encrypt 注册的邮箱: " email
      if [ -z "$email" ]; then log_error "邮箱不能为空，跳过 SSL 配置。"; return; fi
      certbot certonly --webroot -w "$DOC_ROOT" -d "$SITE_DOMAIN" --agree-tos -m "$email" --non-interactive || {
        log_error "Let's Encrypt 申请失败，跳过 SSL 配置。"; return; }
      cert_path="/etc/letsencrypt/live/${SITE_DOMAIN}/fullchain.pem"
      key_path="/etc/letsencrypt/live/${SITE_DOMAIN}/privkey.pem"
      if ! { [ -f "$cert_path" ] && [ -f "$key_path" ]; }; then
        log_error "未找到 LE 证书文件，跳过 SSL 配置。"
        return
      fi

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
      SSL_MODE="unknown"
      log_warn "未知选项，暂不配置 SSL。";
      ;;
  esac
}

print_https_post_install() {
  local domain="$1"

  if [ "${HTTPS_CHECKS_SHOWN:-0}" -eq 1 ]; then
    return
  fi

  HTTPS_CHECKS_SHOWN=1

  echo
  echo -e "${CYAN}HTTPS/SSL checklist（安装后自查）:${NC}"
  echo "  - DNS A/AAAA 记录指向当前服务器公网 IP。"
  echo "  - 如在反向代理/CDN 后面终止 TLS："
  echo "    - 确认代理模式已开启（如适用）。"
  echo "    - 确认边缘证书已签发并处于生效状态（可能需要时间）。"
  echo "    - 确认边缘到源站连通（按需开放 80/443）。"
  echo "    - 建议选择'加密到源站'的安全模式（类似严格/完全验证概念），并确保源站证书可用。"
  if [ "${SSL_MODE:-}" = "letsencrypt" ]; then
    echo "  - 你选择了本机 TLS（Let's Encrypt）："
    echo "    - 确认 80/443 对公网可达，DNS 已正确解析。"
    echo "    - 查看证书签发日志与续期任务是否正常。"
  fi
  echo "  - 示例：访问 https://abc.yourdomain.com 验证浏览器锁标识。"

  echo
  echo -e "${CYAN}HTTPS/SSL 自动检查（不影响安装）:${NC}"
  if ! command -v curl >/dev/null 2>&1; then
    log_warn "未找到 curl，跳过 HTTPS 检查。"
    return
  fi

  if [ -n "$domain" ]; then
    local curl_output curl_exit
    curl_output="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "https://${domain}" 2>&1)" || curl_exit=$?

    if [ -n "${curl_exit:-}" ] && [ "$curl_exit" -ne 0 ]; then
      log_warn "HTTPS 访问 ${domain} 失败（curl 退出码: ${curl_exit}）。"
      echo "  - 常见原因：DNS 未生效/未指向本机、代理未开启、边缘证书未生效、源站 443 未开放或源站证书无效。"
      echo "  - 可重试命令：curl -sSIk --max-time 5 \"https://${domain}\""
    elif printf '%s' "$curl_output" | grep -Eq '^(2|3)[0-9]{2}$'; then
      log_info "HTTPS 访问 ${domain} 正常（HTTP ${curl_output}）。"
    elif [ -n "$curl_output" ]; then
      log_warn "HTTPS 访问 ${domain} 返回异常（HTTP ${curl_output}）。"
      echo "  - 可重试命令：curl -sSIk --max-time 5 \"https://${domain}\""
    else
      log_warn "HTTPS 访问 ${domain} 未获取到状态行。"
      echo "  - 可重试命令：curl -sSIk --max-time 5 \"https://${domain}\""
    fi
  else
    log_warn "未检测到域名，跳过 https 域名检查。"
  fi

  local local_status local_exit
  local_status="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 3 -k "https://127.0.0.1" 2>&1)" || local_exit=$?
  if [ -n "${local_exit:-}" ] && [ "$local_exit" -ne 0 ]; then
    log_warn "本机 443 未能建立 TLS 连接，可能尚未启用源站 HTTPS（curl 退出码: ${local_exit}）。"
    echo "  - 如需源站 HTTPS，请确认 443 监听、证书路径和防火墙配置。"
  elif printf '%s' "$local_status" | grep -Eq '^(2|3)[0-9]{2}$'; then
    log_info "本机 443 TLS 连接正常（https://127.0.0.1，HTTP ${local_status}）。"
  else
    log_warn "本机 443 TLS 返回异常（https://127.0.0.1，HTTP ${local_status}）。"
    echo "  - 如需源站 HTTPS，请确认 443 监听、证书路径和防火墙配置。"
  fi
}

print_summary() {
  # [ANCHOR:SUMMARY]
  _detect_public_ip
  echo
  echo -e "${BOLD}安装完成${NC}"
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
  echo "  4) 如未自动初始化 WordPress，请访问 http://${SITE_DOMAIN}/wp-admin/install.php 完成站点初始化。"
  echo

  print_https_post_install "${SITE_DOMAIN}"
}

install_frontend_only_flow() {
  # [ANCHOR:INSTALL_FLOW_LITE]
  local opt

  require_root
  check_os
  LITE_PREFLIGHT_MODE=1
  BASELINE_TIER="$TIER_LITE"
  log_step "LOMP-Lite (Frontend-only): external DB/Redis"
  show_system_profile_once
  prompt_site_info

  while :; do
    prompt_db_info_lite
    if test_db_connection; then
      if [ "${LITE_DB_AUTH_STATUS:-}" = "PASS" ]; then
        warn_lite_db_non_empty "${LITE_DB_CLIENT:-}"
      fi
      break
    fi

    echo "-------------------------------------"
    echo "  1) 重新输入数据库信息"
    echo "  0) 退出脚本"
    echo "-------------------------------------"
    read -rp "请输入选项 [0-1]: " opt
    case "$opt" in
      1) ;;
      0) log_info "已退出脚本。"; exit 1 ;;
      *) log_warn "输入无效，将默认重新输入数据库信息。" ;;
    esac
  done

  while :; do
    prompt_redis_info_lite
    if [ "${REDIS_ENABLED:-no}" != "yes" ]; then
      break
    fi

    if test_redis_connection_lite; then
      break
    fi

    echo "-------------------------------------"
    echo "  1) 重新输入 Redis 信息"
    echo "  2) 跳过 Redis 配置"
    echo "  0) 退出脚本"
    echo "-------------------------------------"
    read -rp "请输入选项 [0-2]: " opt
    case "$opt" in
      1) ;;
      2) REDIS_ENABLED="no"; REDIS_HOST=""; REDIS_PORT=""; REDIS_PASSWORD=""; break ;;
      0) log_info "已退出脚本。"; exit 1 ;;
      *) log_warn "输入无效，将默认重新输入 Redis 信息。" ;;
    esac
  done

  print_lite_preflight_summary

  install_packages
  ensure_wp_cli || { log_error "wp-cli 未就绪，无法继续 LOMP-Lite baseline。"; exit 1; }
  setup_vhost_config
  download_wordpress
  prompt_site_size_limit
  setup_site_size_limit_monitor
  generate_wp_config
  ensure_wp_redis_config
  apply_wp_site_health_baseline
  fix_permissions
  env_self_check
  configure_ssl
  ensure_wp_https_urls
  ensure_wp_core_installed || true
  apply_wp_lomp_baseline
  log_step "WordPress REST/loopback 自检"
  ensure_wp_loopback_and_rest_health
  run_loopback_preflight
  print_summary
  print_site_size_limit_summary

  if [ "${POST_SUMMARY_SHOWN:-0}" -eq 0 ]; then
    show_post_install_summary "${SITE_DOMAIN}"
  fi

  finish_install_flow
}

install_standard_flow() {
  # [ANCHOR:INSTALL_FLOW_STANDARD]
  local opt

  require_root
  check_os
  LITE_PREFLIGHT_MODE=0
  BASELINE_TIER="$TIER_STANDARD"
  log_step "LOMP-Standard: local DB/Redis"
  show_system_profile_once
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
  ensure_wp_cli || { log_error "wp-cli 未就绪，无法继续 LOMP baseline。"; exit 1; }
  setup_vhost_config
  download_wordpress
  prompt_site_size_limit
  setup_site_size_limit_monitor
  generate_wp_config
  apply_wp_site_health_baseline
  fix_permissions
  env_self_check
  configure_ssl
  ensure_wp_https_urls
  ensure_wp_core_installed || true
  apply_wp_lomp_baseline
  log_step "WordPress REST/loopback 自检"
  ensure_wp_loopback_and_rest_health
  run_loopback_preflight
  print_summary
  print_site_size_limit_summary

  if [ "${POST_SUMMARY_SHOWN:-0}" -eq 0 ]; then
    show_post_install_summary "${SITE_DOMAIN}"
  fi

  finish_install_flow
}

is_private_ip() {
  local ip="${1:-}"

  if [[ "$ip" == "127.0.0.1" ]]; then
    return 0
  fi

  if [[ "$ip" =~ ^10\. ]] \
    || [[ "$ip" =~ ^192\.168\. ]] \
    || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] \
    || [[ "$ip" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]]; then
    return 0
  fi

  return 1
}

prompt_hub_bind_host() {
  while :; do
    read -rp "请输入 Hub 服务绑定地址（默认 127.0.0.1，如需内网访问可填写内网 IP）: " HUB_BIND_HOST
    HUB_BIND_HOST="${HUB_BIND_HOST:-127.0.0.1}"

    if is_private_ip "$HUB_BIND_HOST"; then
      break
    fi

    log_warn "仅允许绑定到 127.0.0.1 或内网 IP。请重新输入。"
  done
}

prompt_secret_confirm() {
  local prompt="$1"
  local secret confirm

  while :; do
    read -rsp "$prompt" secret
    echo
    if [ -z "$secret" ]; then
      log_warn "输入不能为空，请重试。"
      continue
    fi

    read -rsp "请再次输入确认: " confirm
    echo
    if [ "$secret" != "$confirm" ]; then
      log_error "两次输入不一致，请重新输入。"
      continue
    fi

    printf "%s" "$secret"
    return 0
  done
}

ensure_docker_installed() {
  if command -v docker >/dev/null 2>&1; then
    log_info "检测到 Docker 已安装。"
  else
    log_step "安装 Docker"
    apt update
    apt install -y docker.io
  fi

  if systemctl is-enabled docker >/dev/null 2>&1; then
    :
  else
    systemctl enable docker
  fi
  systemctl start docker
}

ensure_container_running() {
  local name="$1"

  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
      docker start "$name" >/dev/null
    fi
    return 0
  fi

  return 1
}

wait_for_mariadb() {
  local name="$1"
  local root_pass="$2"

  for _ in {1..30}; do
    if docker exec "$name" mariadb-admin -uroot -p"$root_pass" ping --silent >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

ensure_hub_containers() {
  local main_db_port=3306
  local tenant_db_port=3307
  local main_redis_port=6379
  local tenant_redis_port=6380

  log_step "检查/初始化 Hub 数据库与 Redis 容器"

  if ! ensure_container_running "main-db"; then
    log_info "初始化 main-db 容器"
    MAIN_DB_ROOT_PASS="$(prompt_secret_confirm "设置 main-db root 密码（仅用于初始化，不会回显）: ")"
    docker volume create main-db-data >/dev/null
    docker run -d \
      --name main-db \
      -e MARIADB_ROOT_PASSWORD="$MAIN_DB_ROOT_PASS" \
      -p "${HUB_BIND_HOST}:${main_db_port}:3306" \
      -v main-db-data:/var/lib/mysql \
      --restart unless-stopped \
      mariadb:10.11 >/dev/null
  else
    log_info "main-db 容器已存在。"
  fi

  if ! ensure_container_running "tenant-db"; then
    log_info "初始化 tenant-db 容器"
    TENANT_DB_ROOT_PASS="$(prompt_secret_confirm "设置 tenant-db root 密码（仅用于初始化，不会回显）: ")"
    docker volume create tenant-db-data >/dev/null
    docker run -d \
      --name tenant-db \
      -e MARIADB_ROOT_PASSWORD="$TENANT_DB_ROOT_PASS" \
      -p "${HUB_BIND_HOST}:${tenant_db_port}:3306" \
      -v tenant-db-data:/var/lib/mysql \
      --restart unless-stopped \
      mariadb:10.11 >/dev/null
  else
    log_info "tenant-db 容器已存在。"
  fi

  if ! ensure_container_running "main-redis"; then
    log_info "初始化 main-redis 容器"
    docker volume create main-redis-data >/dev/null
    docker run -d \
      --name main-redis \
      -p "${HUB_BIND_HOST}:${main_redis_port}:6379" \
      -v main-redis-data:/data \
      --restart unless-stopped \
      redis:7-alpine redis-server --appendonly yes >/dev/null
  else
    log_info "main-redis 容器已存在。"
  fi

  if ! ensure_container_running "tenant-redis"; then
    log_info "初始化 tenant-redis 容器"
    docker volume create tenant-redis-data >/dev/null
    docker run -d \
      --name tenant-redis \
      -p "${HUB_BIND_HOST}:${tenant_redis_port}:6379" \
      -v tenant-redis-data:/data \
      --restart unless-stopped \
      redis:7-alpine redis-server --appendonly yes >/dev/null
  else
    log_info "tenant-redis 容器已存在。"
  fi
}

setup_hub_local_db() {
  local opt
  local esc_db_password
  local default_db_name="${SITE_SLUG}_wp"
  local default_db_user="${SITE_SLUG}_user"

  log_step "初始化本机站点数据库（main-db）"

  while :; do
    read -rp "DB 名称（默认 ${default_db_name}）: " DB_NAME
    DB_NAME="${DB_NAME:-${default_db_name}}"
    [ -n "$DB_NAME" ] && break
  done

  while :; do
    read -rp "DB 用户名（默认 ${default_db_user}）: " DB_USER
    DB_USER="${DB_USER:-${default_db_user}}"
    [ -n "$DB_USER" ] && break
  done

  DB_PASSWORD="$(prompt_secret_confirm "DB 密码（不会回显，请牢记）: ")"

  while :; do
    if [ -z "${MAIN_DB_ROOT_PASS:-}" ]; then
      read -rsp "请输入 main-db root 密码（不会回显）: " MAIN_DB_ROOT_PASS
      echo
      if [ -z "$MAIN_DB_ROOT_PASS" ]; then
        log_warn "main-db root 密码不能为空。"
        continue
      fi
    fi

    if ! wait_for_mariadb "main-db" "$MAIN_DB_ROOT_PASS"; then
      log_error "main-db 未就绪，请稍后重试。"
      MAIN_DB_ROOT_PASS=""
    else
      break
    fi
  done

  esc_db_password="${DB_PASSWORD//\\/\\\\}"
  esc_db_password="${esc_db_password//\'/\\\'}"

  if docker exec -i main-db mariadb -uroot -p"$MAIN_DB_ROOT_PASS" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${esc_db_password}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
  then
    log_info "已在 main-db 中创建/校验 ${DB_NAME} 与用户 ${DB_USER}。"
  else
    log_error "创建数据库或用户失败，请检查 root 密码是否正确。"
    MAIN_DB_ROOT_PASS=""
    echo "-------------------------------------"
    echo "  1) 重新输入 main-db root 密码"
    echo "  0) 退出脚本"
    echo "-------------------------------------"
    read -rp "请输入选项 [0-1]: " opt
    case "$opt" in
      1) setup_hub_local_db ; return ;;
      0) log_info "已退出脚本。"; exit 1 ;;
      *) log_warn "输入无效，默认退出脚本。"; exit 1 ;;
    esac
  fi

  if docker exec -i main-db mariadb -u"$DB_USER" -p"$DB_PASSWORD" -e "USE \`${DB_NAME}\`; SELECT 1;" >/dev/null 2>&1; then
    log_info "数据库连通性检查通过：${DB_USER}@main-db/${DB_NAME}。"
  else
    log_warn "数据库连通性检查失败，请确认密码正确。"
  fi

  DB_HOST="$HUB_BIND_HOST"
}

print_hub_summary() {
  echo
  echo -e "${BOLD}Hub 服务摘要${NC}"
  echo "====================================="
  echo "main-db:     ${HUB_BIND_HOST}:3306"
  echo "main-redis:  ${HUB_BIND_HOST}:6379"
  echo "tenant-db:   ${HUB_BIND_HOST}:3307"
  echo "tenant-redis:${HUB_BIND_HOST}:6380"
  echo
  echo "Next steps（前端节点连接信息）："
  echo "  - DB_HOST: ${HUB_BIND_HOST}"
  echo "  - DB_PORT: 3306（main-db）或 3307（tenant-db）"
  echo "  - Redis Host: ${HUB_BIND_HOST}"
  echo "  - Redis Port: 6379（main）或 6380（tenant）"
  echo "  - 仅填写 host/port，DB 密码与 Redis 密码请在各节点自行保存。"
  echo
}

install_hub_flow() {
  # [ANCHOR:INSTALL_FLOW_HUB]
  local opt

  require_root
  check_os
  BASELINE_TIER="$TIER_HUB"
  prompt_site_info
  prompt_hub_bind_host

  ensure_docker_installed
  ensure_hub_containers
  setup_hub_local_db

  install_packages
  ensure_wp_cli || { log_error "wp-cli 未就绪，无法继续 LOMP baseline。"; exit 1; }
  setup_vhost_config
  download_wordpress
  prompt_site_size_limit
  setup_site_size_limit_monitor
  generate_wp_config
  apply_wp_site_health_baseline
  fix_permissions
  env_self_check
  configure_ssl
  ensure_wp_core_installed || true
  apply_wp_lomp_baseline
  log_step "WordPress REST/loopback 自检"
  ensure_wp_loopback_and_rest_health
  run_loopback_preflight
  print_summary
  print_hub_summary
  print_site_size_limit_summary

  if [ "${POST_SUMMARY_SHOWN:-0}" -eq 0 ]; then
    show_post_install_summary "${SITE_DOMAIN}"
  fi

  finish_install_flow
}

run_wp_profile_override() {
  local profile normalized

  profile="${HZ_WP_PROFILE:-}"
  if [ -z "$profile" ]; then
    return 1
  fi

  normalized="$(normalize_wp_profile "$profile")" || return 1

  case "$normalized" in
    lomp-lite)
      install_frontend_only_flow
      ;;
    lomp-standard)
      install_standard_flow
      ;;
  esac

  return 0
}

install_lomp_flow() {
  # [ANCHOR:INSTALL_FLOW]
  local selected_tier

  selected_tier="$(get_recommended_lomp_tier)"

  case "$selected_tier" in
    "$TIER_LITE")
      install_frontend_only_flow
      ;;
    *)
      install_standard_flow
      ;;
  esac
}

#######################
# 脚本入口            #
#######################

# [ANCHOR:ENTRYPOINT]
if [ "${HZ_PHASE:-}" = "optimize" ]; then
  run_optimize_only_flow
  exit 0
fi

if ! run_wp_profile_override; then
  show_main_menu
fi
