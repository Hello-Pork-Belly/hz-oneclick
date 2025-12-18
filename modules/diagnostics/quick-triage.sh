#!/usr/bin/env bash
set -euo pipefail

HZ_TRIAGE_RAW_BASE="${HZ_TRIAGE_RAW_BASE:-https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main}"
HZ_TRIAGE_TMP="$(mktemp -d /tmp/hz-oneclick-triage-XXXXXX)"
HZ_TRIAGE_KEEP_TMP="${HZ_TRIAGE_KEEP_TMP:-0}"
HZ_TRIAGE_USE_LOCAL="${HZ_TRIAGE_USE_LOCAL:-0}"
HZ_TRIAGE_LOCAL_ROOT="${HZ_TRIAGE_LOCAL_ROOT:-$(pwd)}"
HZ_TRIAGE_FORMAT="${HZ_TRIAGE_FORMAT:-text}"
HZ_TRIAGE_REDACT="${HZ_TRIAGE_REDACT:-0}"

if [ "${HZ_TRIAGE_TEST_MODE:-0}" = "1" ] && [ "${BASELINE_TEST_MODE:-0}" != "1" ]; then
  BASELINE_TEST_MODE=1
  export BASELINE_TEST_MODE
fi

cleanup() {
  if [ "$HZ_TRIAGE_KEEP_TMP" != "1" ] && [ -n "$HZ_TRIAGE_TMP" ] && [ -d "$HZ_TRIAGE_TMP" ]; then
    rm -rf "$HZ_TRIAGE_TMP"
  fi
}
trap cleanup EXIT

info() { printf '[triage] %s\n' "$*"; }

fetch_file() {
  local rel_path dest_path
  rel_path="$1"
  dest_path="$2"

  mkdir -p "$(dirname "$dest_path")"
  if [ "$HZ_TRIAGE_USE_LOCAL" = "1" ] && [ -r "$HZ_TRIAGE_LOCAL_ROOT/$rel_path" ]; then
    cp "$HZ_TRIAGE_LOCAL_ROOT/$rel_path" "$dest_path"
  else
    curl -fsSL "$HZ_TRIAGE_RAW_BASE/$rel_path" -o "$dest_path"
  fi
}

prompt_lang() {
  local default_lang prompt_lang
  default_lang="${HZ_TRIAGE_LANG:-zh}"

  if [ "${HZ_TRIAGE_TEST_MODE:-0}" = "1" ] || [ "${BASELINE_TEST_MODE:-0}" = "1" ]; then
    printf "%s" "${default_lang}"
    return
  fi

  echo "Please select language / 请选择语言 [en/zh] (default: ${default_lang}):"
  read -r prompt_lang
  prompt_lang="${prompt_lang:-$default_lang}"
  if [[ "${prompt_lang,,}" == en* ]]; then
    printf "en"
  else
    printf "zh"
  fi
}

prompt_domain() {
  local default_domain input_domain
  default_domain="${HZ_TRIAGE_DOMAIN:-${HZ_TRIAGE_TEST_DOMAIN:-abc.yourdomain.com}}"

  if [ "${HZ_TRIAGE_TEST_MODE:-0}" = "1" ] || [ "${BASELINE_TEST_MODE:-0}" = "1" ]; then
    printf "%s" "$default_domain"
    return
  fi

  if [ "$1" = "en" ]; then
    echo "Enter domain to diagnose (e.g., abc.yourdomain.com). Press Enter to use default: ${default_domain}"
  else
    echo "请输入需要诊断的域名（例如 abc.yourdomain.com），直接回车使用默认：${default_domain}"
  fi
  read -r input_domain
  input_domain="${input_domain:-$default_domain}"
  printf "%s" "$input_domain"
}

load_libs() {
  local libs=(
    "lib/baseline_common.sh"
    "lib/baseline.sh"
    "lib/baseline_triage.sh"
    "lib/baseline_dns.sh"
    "lib/baseline_origin.sh"
    "lib/baseline_proxy.sh"
    "lib/baseline_tls.sh"
    "lib/baseline_https.sh"
    "lib/baseline_lsws.sh"
    "lib/baseline_wp.sh"
    "lib/baseline_cache.sh"
    "lib/baseline_db.sh"
    "lib/baseline_sys.sh"
  )

  for lib in "${libs[@]}"; do
    fetch_file "$lib" "$HZ_TRIAGE_TMP/$lib"
    # shellcheck disable=SC1090
    . "$HZ_TRIAGE_TMP/$lib"
  done
}

sanitize_output() {
  if declare -f baseline_sanitize_text >/dev/null 2>&1; then
    baseline_sanitize_text
  else
    sed -E \
      -e 's/((authorization|token|password|secret|apikey|api_key)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/Ig' \
      -e 's/((^|[[:space:]])key=)[^[:space:]]+/\1[REDACTED]/Ig' \
      -e 's/((bearer)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig'
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --format)
        HZ_TRIAGE_FORMAT="${2:-$HZ_TRIAGE_FORMAT}"
        shift 2
        ;;
      --format=*)
        HZ_TRIAGE_FORMAT="${1#--format=}"
        shift
        ;;
      --redact)
        HZ_TRIAGE_REDACT=1
        shift
        ;;
      --help)
        echo "Usage: $0 [--format text|json] [--redact]"
        exit 0
        ;;
      *)
        # Ignore unknown args for forward compatibility
        shift
        ;;
    esac
  done
}

run_triage() {
  local lang domain format output report_path sanitized_output
  lang="$1"
  domain="$2"
  format="$3"

  BASELINE_REDACT="$HZ_TRIAGE_REDACT"
  export BASELINE_REDACT

  BASELINE_WP_NO_PROMPT=1 export BASELINE_WP_NO_PROMPT

  output="$(baseline_triage_run "$domain" "$lang" "$format")"
  sanitized_output="$(printf "%s" "$output" | sanitize_output)"
  echo "$sanitized_output"

  report_path="${BASELINE_LAST_REPORT_PATH:-$(printf "%s" "$output" | awk '/^REPORT:/ {print $2}' | head -n1)}"
  if [ -n "$report_path" ] && [ -f "$report_path" ]; then
    chmod 600 "$report_path" 2>/dev/null || true
    tmp_sanitized="${report_path}.sanitized"
    if sanitize_output < "$report_path" > "$tmp_sanitized"; then
      mv "$tmp_sanitized" "$report_path"
    else
      rm -f "$tmp_sanitized"
    fi
  fi
}

main() {
  info "Bootstrapping quick triage runner (read-only checks)"
  load_libs

  parse_args "$@"

  local lang domain
  lang="$(prompt_lang)"
  echo
  domain="$(prompt_domain "$lang")"
  echo

  run_triage "$lang" "$domain" "$HZ_TRIAGE_FORMAT"
}

main "$@"
