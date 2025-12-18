#!/usr/bin/env bash

# Shared helpers for baseline diagnostic wrappers.

baseline_wrapper_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/../.." && pwd
}

baseline_wrapper_normalize_lang() {
  local lang
  lang="${1:-zh}"
  if [[ "${lang,,}" == en* ]]; then
    echo "en"
  else
    echo "zh"
  fi
}

baseline_wrapper_parse_inputs() {
  # Usage: baseline_wrapper_parse_inputs domain_ref lang_ref format_ref -- "$@"
  local -n _bw_domain_ref=$1
  local -n _bw_lang_ref=$2
  local -n _bw_format_ref=$3
  shift 3

  local lang_set=0

  _bw_domain_ref="${_bw_domain_ref:-${HZ_BASELINE_DOMAIN:-}}"
  _bw_lang_ref="${_bw_lang_ref:-${HZ_BASELINE_LANG:-${HZ_LANG:-zh}}}"
  _bw_format_ref="${_bw_format_ref:-${HZ_BASELINE_FORMAT:-text}}"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --format)
        _bw_format_ref="${2:-$_bw_format_ref}"
        shift 2
        ;;
      --format=*)
        _bw_format_ref="${1#--format=}"
        shift
        ;;
      --)
        shift
        continue
        ;;
      --help)
        echo "Usage: $0 [domain] [lang] [--format text|json]" >&2
        exit 0
        ;;
      *)
        if [ -z "$_bw_domain_ref" ]; then
          _bw_domain_ref="$1"
        elif [ $lang_set -eq 0 ]; then
          _bw_lang_ref="$1"
          lang_set=1
        fi
        shift
        ;;
    esac
  done

  _bw_lang_ref="$(baseline_wrapper_normalize_lang "$_bw_lang_ref")"
  _bw_format_ref="$(baseline_wrapper_normalize_format "$_bw_format_ref")"
}

baseline_wrapper_normalize_format() {
  local format
  format="${1:-text}"
  case "${format,,}" in
    json)
      echo "json"
      ;;
    *)
      echo "text"
      ;;
  esac
}

baseline_wrapper_load_libs() {
  local repo_root required libs_missing=()
  repo_root="$1"
  shift
  for required in "$@"; do
    if [ -r "$repo_root/lib/$required" ]; then
      # shellcheck disable=SC1090
      . "$repo_root/lib/$required"
    else
      libs_missing+=("$required")
    fi
  done

  if [ ${#libs_missing[@]} -gt 0 ]; then
    echo "Missing baseline libraries: ${libs_missing[*]}" >&2
    exit 1
  fi
}

baseline_wrapper_collect_keywords_line() {
  local total idx keyword key_item
  local -a keys=()
  local -a key_items=()
  local -A seen=()

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  total=${#BASELINE_RESULTS_STATUS[@]}
  for ((idx=0; idx<total; idx++)); do
    keyword="${BASELINE_RESULTS_KEYWORD[idx]}"
    if [ -z "$keyword" ]; then
      continue
    fi
    read -r -a key_items <<< "$keyword"
    for key_item in "${key_items[@]}"; do
      if [ -n "$key_item" ] && [ -z "${seen[$key_item]+x}" ]; then
        seen["$key_item"]=1
        keys+=("$key_item")
      fi
    done
  done

  if [ ${#keys[@]} -eq 0 ]; then
    echo "KEY: (none)"
  else
    echo "KEY: ${keys[*]}"
  fi
}

baseline_wrapper_collect_keywords() {
  local total idx keyword key_item
  local -a keys=()
  local -a key_items=()
  local -A seen=()

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  total=${#BASELINE_RESULTS_STATUS[@]}
  for ((idx=0; idx<total; idx++)); do
    keyword="${BASELINE_RESULTS_KEYWORD[idx]}"
    if [ -z "$keyword" ]; then
      continue
    fi
    read -r -a key_items <<< "$keyword"
    for key_item in "${key_items[@]}"; do
      if [ -n "$key_item" ] && [ -z "${seen[$key_item]+x}" ]; then
        seen["$key_item"]=1
        keys+=("$key_item")
      fi
    done
  done

  printf '%s\n' "${keys[@]}"
}

baseline_wrapper_status_merge() {
  local current incoming
  current="${1:-PASS}"
  incoming="${2:-PASS}"

  if [ "$current" = "FAIL" ] || [ "$incoming" = "FAIL" ]; then
    echo "FAIL"
  elif [ "$current" = "WARN" ] || [ "$incoming" = "WARN" ]; then
    echo "WARN"
  else
    echo "PASS"
  fi
}

baseline_wrapper_group_key() {
  local group_name normalized
  group_name="$1"
  case "$group_name" in
    "DNS/IP") normalized="dns-ip" ;;
    "ORIGIN/FW") normalized="origin-firewall" ;;
    "Proxy/CDN") normalized="proxy-cdn" ;;
    "TLS/HTTPS") normalized="tls-https" ;;
    "LSWS/OLS") normalized="lsws-ols" ;;
    "WP/APP") normalized="wp-app" ;;
    "CACHE/REDIS") normalized="cache-redis" ;;
    "SYSTEM/RESOURCE") normalized="system-resource" ;;
    *)
      normalized="$(printf '%s' "$group_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//')"
      ;;
  esac
  echo "$normalized"
}

baseline_wrapper_json_array_from_lines() {
  local data first=1 line escaped
  data="$1"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line="$(baseline_wrapper_sanitize_json_text "$line")"
    escaped="$(baseline_json_escape "$line")"
    if [ $first -eq 0 ]; then
      printf ','
    fi
    printf '"%s"' "$escaped"
    first=0
  done <<< "$data"
}

baseline_wrapper_first_reason() {
  local desired idx total
  desired="$1"
  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi
  total=${#BASELINE_RESULTS_STATUS[@]}
  for ((idx=0; idx<total; idx++)); do
    if [ "${BASELINE_RESULTS_STATUS[idx]}" = "$desired" ]; then
      echo "${BASELINE_RESULTS_ID[idx]}:${BASELINE_RESULTS_KEYWORD[idx]}"
      return
    fi
  done
  echo ""
}

baseline_wrapper_collect_keywords_joined() {
  local keys joined
  keys="$(baseline_wrapper_collect_keywords)"
  joined="$(printf '%s' "$keys" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  echo "$joined"
}

baseline_wrapper_sanitize_json_text() {
  local text
  text="$1"
  if declare -f baseline_json_sanitize_field >/dev/null 2>&1; then
    baseline_json_sanitize_field "$text"
  else
    text="$(printf "%s" "$text" | baseline_sanitize_text)"
    if declare -f baseline_vendor_scrub_text >/dev/null 2>&1; then
      text="$(printf "%s" "$text" | baseline_vendor_scrub_text)"
    fi
    printf "%s" "$text"
  fi
}

baseline_wrapper_write_json_report() {
  local payload path
  payload="$1"
  path="$2"
  umask 077
  printf "%s\n" "$payload" > "$path"
  chmod 600 "$path" 2>/dev/null || true
}

baseline_wrapper_build_json_payload() {
  local group domain lang verdict hint report_path report_json_path
  group="$1"
  domain="$2"
  lang="$3"
  verdict="$4"
  hint="$5"
  report_path="$6"
  report_json_path="$7"

  local total idx keyword evidence suggestions evidence_fmt suggestions_fmt
  local -a evidence_lines=() suggestion_lines=()
  local -A seen_ev=() seen_sug=()

  total=${#BASELINE_RESULTS_STATUS[@]}
  for ((idx=0; idx<total; idx++)); do
    evidence="${BASELINE_RESULTS_EVIDENCE[idx]}"
    suggestions="${BASELINE_RESULTS_SUGGESTIONS[idx]}"

    evidence_fmt=${evidence//\\n/$'\n'}
    while IFS= read -r evidence; do
      [ -z "$evidence" ] && continue
      evidence="$(baseline_wrapper_sanitize_json_text "$evidence")"
      if [ -z "${seen_ev[$evidence]+x}" ]; then
        seen_ev[$evidence]=1
        evidence_lines+=("$evidence")
      fi
    done <<< "$evidence_fmt"

    suggestions_fmt=${suggestions//\\n/$'\n'}
    while IFS= read -r suggestions; do
      [ -z "$suggestions" ] && continue
      suggestions="$(baseline_wrapper_sanitize_json_text "$suggestions")"
      if [ -z "${seen_sug[$suggestions]+x}" ]; then
        seen_sug[$suggestions]=1
        suggestion_lines+=("$suggestions")
      fi
    done <<< "$suggestions_fmt"
  done

  local key_joined evidence_json suggestions_json group_key domain_safe lang_safe key_safe report_safe report_json_safe
  key_joined="$(baseline_wrapper_collect_keywords_joined)"
  evidence_json="$(baseline_wrapper_json_array_from_lines "$(printf '%s\n' "${evidence_lines[@]}")")"
  suggestions_json="$(baseline_wrapper_json_array_from_lines "$(printf '%s\n' "${suggestion_lines[@]}")")"
  group_key="$(baseline_wrapper_group_key "$group")"

  domain_safe="$(baseline_wrapper_sanitize_json_text "$domain")"
  lang_safe="$(baseline_wrapper_sanitize_json_text "$lang")"
  key_safe="$(baseline_wrapper_sanitize_json_text "$key_joined")"
  group_key="$(baseline_wrapper_sanitize_json_text "$group_key")"
  verdict="$(baseline_wrapper_sanitize_json_text "$verdict")"
  hint="$(baseline_wrapper_sanitize_json_text "$hint")"
  report_safe="$(baseline_wrapper_sanitize_json_text "$report_path")"
  report_json_safe="$(baseline_wrapper_sanitize_json_text "$report_json_path")"

  local generated_at
  generated_at="$(baseline_wrapper_sanitize_json_text "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")"

  printf '{"schema_version":"1.0","generated_at":"%s","tool":"hz-oneclick","mode":"baseline-diagnostics","lang":"%s","domain":"%s","results":[{"group":"%s","key":"%s","verdict":"%s","hint":"%s","evidence":[%s],"suggestions":[%s],"report":"%s","report_json":"%s"}]}' \
    "$(baseline_json_escape "$generated_at")" \
    "$(baseline_json_escape "$lang_safe")" \
    "$(baseline_json_escape "$domain_safe")" \
    "$(baseline_json_escape "$group_key")" \
    "$(baseline_json_escape "$key_safe")" \
    "$(baseline_json_escape "$verdict")" \
    "$(baseline_json_escape "$hint")" \
    "$evidence_json" "$suggestions_json" \
    "$(baseline_json_escape "$report_safe")" \
    "$(baseline_json_escape "$report_json_safe")"
}

baseline_wrapper_write_report() {
  local group domain lang summary details key_line ts safe_domain safe_group report_path header
  group="$1"
  domain="$2"
  lang="$3"
  summary="$4"
  details="$5"
  key_line="$6"

  ts="$(date +%Y%m%d-%H%M%S)"
  safe_domain="${domain:-none}"
  safe_domain="${safe_domain//[^A-Za-z0-9._-]/_}"
  safe_group="${group//[^A-Za-z0-9._-]/_}"
  report_path="/tmp/hz-baseline-${safe_group}-${safe_domain}-${ts}.txt"

  header="=== HZ Baseline Diagnostics (${group}) ===\nTIMESTAMP: ${ts}\nDOMAIN: ${domain:-N/A}\nLANG: ${lang}\n"
  umask 077
  {
    printf "%s\n\n" "$header"
    printf "%s\n\n" "$summary"
    printf "%s\n\n" "$details"
    printf "%s\n" "$key_line"
  } | baseline_sanitize_text > "$report_path"
  chmod 600 "$report_path" 2>/dev/null || true
  echo "$report_path"
}

baseline_wrapper_missing_tools_warn() {
  local group lang tool missing_tools=()
  group="$1"
  lang="$2"
  shift 2
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done

  if [ ${#missing_tools[@]} -gt 0 ]; then
    local evidence suggestions
    evidence="Missing tools: ${missing_tools[*]}"
    if [ "$lang" = "en" ]; then
      suggestions="Install or enable the missing tools before re-running diagnostics."
    else
      suggestions="安装或启用缺失的工具后再运行诊断。"
    fi
    baseline_add_result "$group" "REQUIREMENTS" "WARN" "MISSING_TOOLS" "$evidence" "$suggestions"
  fi
}

baseline_wrapper_mark_domain_skipped() {
  local group lang
  group="$1"
  lang="$2"
  baseline_add_result "$group" "DOMAIN_REQUIRED" "WARN" "DOMAIN_SKIPPED" \
    "$([ "$lang" = "en" ] && echo "Domain not provided; network checks skipped." || echo "未提供域名，本组的域名检查已跳过。")" \
    "$([ "$lang" = "en" ] && echo "Provide a domain to run full diagnostics." || echo "填写域名后可执行完整诊断。")"
}

baseline_wrapper_print_verdict() {
  local overall reason key_line report_path
  overall="$1"
  reason="$2"
  key_line="$3"
  report_path="$4"

  if [ "$overall" = "PASS" ]; then
    echo "VERDICT: PASS (${reason})"
  else
    echo "VERDICT: ${overall} (${reason})"
  fi
  echo "$key_line"
  echo "REPORT: ${report_path}"
}

baseline_wrapper_finalize() {
  local group domain lang format summary_output details_output key_line overall reason report_path
  group="$1"
  domain="$2"
  lang="$3"
  format="$(baseline_wrapper_normalize_format "${4:-text}")"

  summary_output="$(baseline_print_summary)"
  details_output="$(baseline_print_details)"
  key_line="$(baseline_wrapper_collect_keywords_line)"
  overall="$(baseline__overall_state)"

  reason="all_checks_passed"
  case "$overall" in
    FAIL)
      reason="$(baseline_wrapper_first_reason "FAIL")"
      [ -z "$reason" ] && reason="issue_detected"
      ;;
    WARN)
      reason="$(baseline_wrapper_first_reason "WARN")"
      [ -z "$reason" ] && reason="warn_detected"
      ;;
    *)
      :
      ;;
  esac

  report_path="$(baseline_wrapper_write_report "$group" "$domain" "$lang" "$summary_output" "$details_output" "$key_line")"

  if [ "$format" = "json" ]; then
    local json_payload report_json_path
    report_json_path="${report_path%.txt}.json"
    json_payload="$(baseline_wrapper_build_json_payload "$group" "$domain" "$lang" "$overall" "$reason" "$report_path" "$report_json_path")"
    baseline_wrapper_write_json_report "$json_payload" "$report_json_path"
    printf '%s\n' "$json_payload"
    return
  fi

  printf "%s\n\n%s\n%s\n" "$summary_output" "$details_output" "$key_line"
  baseline_wrapper_print_verdict "$overall" "$reason" "$key_line" "$report_path"
}

# Fallback sanitizer when baseline_common is unavailable
if ! declare -f baseline_sanitize_text >/dev/null 2>&1; then
  baseline_sanitize_text() {
    sed -E \
      -e 's/((authorization|token|password|secret|apikey|api_key)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/Ig' \
      -e 's/((^|[[:space:]])key=)[^[:space:]]+/\1[REDACTED]/Ig' \
      -e 's/((bearer)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig'
  }
fi
