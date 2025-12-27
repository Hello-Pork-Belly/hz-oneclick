#!/usr/bin/env bash

# Baseline "Quick Triage" orchestration (521/HTTPS/TLS first).
# This file only defines functions and does not execute any logic on load.

if ! declare -f baseline_sanitize_text >/dev/null 2>&1; then
  if [ -r "$(dirname "${BASH_SOURCE[0]}")/baseline_common.sh" ]; then
    # shellcheck source=/dev/null
    . "$(dirname "${BASH_SOURCE[0]}")/baseline_common.sh"
  else
    baseline_redact_enabled() { [ "${BASELINE_REDACT:-0}" = "1" ]; }
    baseline_redact_text() {
      if ! baseline_redact_enabled; then
        cat
        return
      fi
      sed -E \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted-email>/g' \
        -e 's#([0-9]{1,3}\.){3}[0-9]{1,3}#<redacted-ip>#g' \
        -e 's#([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}#<redacted-ip>#g' \
        -e 's#([A-Za-z0-9-]+\.)+[A-Za-z]{2,}#<redacted-domain>#g' \
        -e 's#(/[^[:space:]]+)#<redacted-path>#g' \
        -e 's#([A-Za-z]:\\\\[^[:space:]]+)#<redacted-path>#g'
    }
    baseline_sanitize_text() {
      sed -E \
        -e 's/((authorization|token|password|secret|apikey|api_key)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/Ig' \
        -e 's/((^|[[:space:]])key=)[^[:space:]]+/\1[REDACTED]/Ig' \
        -e 's/((bearer)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig' | \
        baseline_redact_text
    }
  fi
fi

if ! declare -f baseline_vendor_scrub_text >/dev/null 2>&1; then
  baseline_vendor_scrub_text() {
    local vendor_terms_b64=(
      "b3JhY2xl"
      "YXdz"
      "YW1hem9u"
      "YWxpeXVu"
      "dGVuY2VudA=="
      "YXp1cmU="
      "Z2Nw"
      "Z29vZ2xlIGNsb3Vk"
    )
    local vendor_terms=()
    local vendor_pattern=""
    local term

    for term_b64 in "${vendor_terms_b64[@]}"; do
      if term=$(printf '%s' "$term_b64" | base64 -d 2>/dev/null); then
        vendor_terms+=("$term")
      fi
    done

    if [ ${#vendor_terms[@]} -eq 0 ]; then
      cat
      return
    fi

    vendor_pattern=$(IFS='|'; echo "${vendor_terms[*]}")
    sed -E \
      -e "s/(${vendor_pattern})/cloud provider/Ig"
  }
fi

if ! declare -f baseline_json_escape >/dev/null 2>&1; then
  baseline_json_escape() {
    local input escaped
    input="$1"
    escaped=$(printf '%s' "$input" | \
      sed \
        -e 's/\\/\\\\/g' \
        -e 's/"/\\\"/g' \
        -e 's/\r/\\r/g' \
        -e 's/\t/\\t/g' | \
      tr '\n' '\n')
    escaped=$(printf '%s' "$escaped" | sed ':a;N;$!ba;s/\n/\\n/g')
    printf '%s' "$escaped"
  }
fi

baseline_triage__normalize_lang() {
  local lang
  lang="${1:-zh}"
  if [[ "${lang,,}" == en* ]]; then
    echo "en"
  else
    echo "zh"
  fi
}

baseline_triage__normalize_format() {
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

baseline_triage__smoke_enabled() {
  local arg env_value
  # Smoke mode is enabled via CLI flags (--smoke/--exit0/--no-fail) or
  # HZ_CI_SMOKE truthy values (1/true/yes/y/on, whitespace-insensitive).
  env_value="${HZ_CI_SMOKE:-0}"

  for arg in "$@"; do
    case "$arg" in
      --smoke|--exit0|--no-fail)
        return 0
        ;;
    esac
  done

  if baseline_triage__is_truthy "$env_value"; then
    return 0
  fi

  return 1
}

baseline_triage__is_truthy() {
  local env_value
  env_value="${1:-}"
  env_value="${env_value#"${env_value%%[![:space:]]*}"}"
  env_value="${env_value%"${env_value##*[![:space:]]}"}"
  case "${env_value,,}" in
    1|true|yes|y|on)
      return 0
      ;;
  esac
  return 1
}

baseline_triage_is_truthy() {
  baseline_triage__is_truthy "$@"
}

baseline_triage__smoke_strict_enabled() {
  baseline_triage__is_truthy "${HZ_SMOKE_STRICT:-0}"
}

baseline_triage__timestamp() {
  date +%Y%m%d-%H%M%S
}

baseline_triage__collect_keywords_line() {
  local total idx keyword status key_item
  local -a keys=()
  local -a key_items=()
  declare -A seen=()

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  total=${#BASELINE_RESULTS_STATUS[@]}
  for ((idx=0; idx<total; idx++)); do
    keyword="${BASELINE_RESULTS_KEYWORD[idx]}"
    status="${BASELINE_RESULTS_STATUS[idx]}"

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

baseline_triage__collect_keywords() {
  local total idx keyword key_item
  local -a keys=()
  local -a key_items=()
  declare -A seen=()

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

baseline_triage__sanitize_text() {
  baseline_sanitize_text
}

baseline_triage__sanitize_json_text() {
  local text
  text="$1"
  if declare -f baseline_json_sanitize_field >/dev/null 2>&1; then
    text="$(baseline_json_sanitize_field "$text")"
  else
    text="$(printf "%s" "$text" | baseline_triage__sanitize_text)"
    text="$(printf "%s" "$text" | baseline_vendor_scrub_text)"
  fi
  printf "%s" "$text"
}

baseline_triage__first_issue_reason() {
  local target_status status idx total keyword id
  target_status="$1"

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  total=${#BASELINE_RESULTS_STATUS[@]}
  for ((idx=0; idx<total; idx++)); do
    status="${BASELINE_RESULTS_STATUS[idx]}"
    keyword="${BASELINE_RESULTS_KEYWORD[idx]}"
    id="${BASELINE_RESULTS_ID[idx]}"
    if [ "$status" = "$target_status" ]; then
      if [ -n "$keyword" ]; then
        echo "${id}:${keyword}"
      else
        echo "$id"
      fi
      return 0
    fi
  done

  echo ""
}

baseline_triage__status_merge() {
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

baseline_triage__group_key() {
  local group_name
  group_name="$1"
  case "$group_name" in
    "DNS/IP") echo "dns_ip" ;;
    "ORIGIN/FW") echo "origin_firewall" ;;
    "Proxy/CDN") echo "proxy_cdn" ;;
    "TLS/CERT"|"HTTPS/521") echo "tls_https" ;;
    "LSWS/OLS") echo "lsws_ols" ;;
    "WP/APP") echo "wp_app" ;;
    "CACHE/REDIS") echo "cache_redis" ;;
    "SYSTEM/RESOURCE") echo "system_resource" ;;
    *) echo "" ;;
  esac
}

baseline_triage__json_array_from_lines() {
  local data first=1 line escaped
  data="$1"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line="$(baseline_triage__sanitize_json_text "$line")"
    escaped="$(baseline_json_escape "$line")"
    if [ $first -eq 0 ]; then
      printf ','
    fi
    printf '"%s"' "$escaped"
    first=0
  done <<< "$data"
}

baseline_triage__mock_tls_sclient_output() {
  cat <<'MOCK_TRIAGE_SCLIENT'
0
CONNECTED(00000003)
Certificate chain
 0 s:CN = mock.example.com
   i:CN = Mock Test CA
Server certificate
-----BEGIN CERTIFICATE-----
MIIBmockcertdata
-----END CERTIFICATE-----
subject=CN = mock.example.com
issuer=CN = Mock Test CA
Verify return code: 0 (ok)
MOCK_TRIAGE_SCLIENT
}

baseline_triage__setup_test_mode() {
  if [ "${BASELINE_TEST_MODE:-0}" != "1" ]; then
    return 0
  fi

  if [ -n "${BASELINE_TRIAGE_TEST_ACTIVE:-}" ]; then
    return 0
  fi

  BASELINE_TRIAGE_TEST_ACTIVE=1
  BASELINE_TRIAGE_OLD_PATH="$PATH"
  BASELINE_TRIAGE_MOCK_DIR="$(mktemp -d /tmp/baseline-triage-mock-XXXXXX)"
  PATH="${BASELINE_TRIAGE_MOCK_DIR}:$PATH"
  export PATH BASELINE_TRIAGE_MOCK_DIR BASELINE_TRIAGE_OLD_PATH

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/curl" <<'MOCKCURL'
#!/usr/bin/env bash
# Minimal curl mock for baseline test mode.
format=""
url=""
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -w)
      format="$2"
      shift 2
      ;;
    -w*)
      format="${1#-w}"
      shift
      ;;
    http://*|https://*)
      url="$1"
      args+=("$1")
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
if [ -z "$url" ] && [ ${#args[@]} -gt 0 ]; then
  url="${args[-1]}"
fi
case "$url" in
  *api.ipify.org*|*ifconfig.me*)
    if printf '%s\n' "${args[@]}" | grep -q -- '-4'; then
      echo "203.0.113.10"
    else
      echo "2001:db8::1"
    fi
    exit 0
    ;;
  *)
    :
    ;;
esac
if [ -n "$format" ] && [ "$format" != "%{http_code}" ]; then
  printf "%s" "$format"
  exit 0
fi
if [ "$format" = "%{http_code}" ]; then
  printf "200"
  exit 0
fi
if printf '%s\n' "${args[@]}" | grep -q -- ' -I '; then
  printf "HTTP/2 200\nserver: mock-edge\nvia: mock-gateway\n"
  exit 0
fi
if [ "${args[0]}" = "-I" ]; then
  printf "HTTP/2 200\nserver: mock-edge\nvia: mock-gateway\n"
  exit 0
fi
printf "mock-curl"
MOCKCURL
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/curl"

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/dig" <<'MOCKDIG'
#!/usr/bin/env bash
record_type="A"
domain=""
for arg in "$@"; do
  case "$arg" in
    A|AAAA)
      record_type="$arg"
      ;;
    +short)
      :
      ;;
    *)
      if [ -z "$domain" ]; then
        domain="$arg"
      fi
      ;;
  esac
done
if [ "$record_type" = "AAAA" ]; then
  echo "2001:db8::1"
else
  echo "203.0.113.10"
fi
MOCKDIG
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/dig"

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/nslookup" <<'MOCKNSLOOKUP'
#!/usr/bin/env bash
if echo "$*" | grep -qi "AAAA"; then
  echo "Address: 2001:db8::1"
else
  echo "Address: 203.0.113.10"
fi
MOCKNSLOOKUP
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/nslookup"

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/drill" <<'MOCKDRILL'
#!/usr/bin/env bash
if echo "$*" | grep -qi "AAAA"; then
  echo "2001:db8::1"
else
  echo "203.0.113.10"
fi
MOCKDRILL
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/drill"

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/openssl" <<'MOCKOPENSSL'
#!/usr/bin/env bash
cmd="$1"
shift || true
if [ "$cmd" = "s_client" ]; then
  cat <<'MOCK_SCLIENT'
CONNECTED(00000003)
---
Certificate chain
 0 s:CN = mock.example.com
   i:CN = Mock Test CA
 1 s:CN = Mock Test CA
   i:CN = Mock Test CA Root
---
Server certificate
-----BEGIN CERTIFICATE-----
MIIBmockcertdata
-----END CERTIFICATE-----
subject=CN = mock.example.com
issuer=CN = Mock Test CA
Verify return code: 0 (ok)
MOCK_SCLIENT
  exit 0
fi
if [ "$cmd" = "x509" ]; then
  if echo "$*" | grep -q "-subject"; then
    echo "subject=CN = mock.example.com"
    exit 0
  fi
  if echo "$*" | grep -q "-issuer"; then
    echo "issuer=CN = Mock Test CA"
    exit 0
  fi
  if echo "$*" | grep -q "-startdate"; then
    echo "notBefore=Jan  1 00:00:00 2024 GMT"
    exit 0
  fi
  if echo "$*" | grep -q "-enddate"; then
    echo "notAfter=Dec 31 23:59:59 2099 GMT"
    exit 0
  fi
  if echo "$*" | grep -q "-ext subjectAltName"; then
    echo "X509v3 Subject Alternative Name:\n                DNS:mock.example.com, DNS:*.example.com"
    exit 0
  fi
fi
exit 0
MOCKOPENSSL
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/openssl"

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/timeout" <<'MOCKTIMEOUT'
#!/usr/bin/env bash
# passthrough for mock environment
shift
"$@"
MOCKTIMEOUT
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/timeout"

  # Function overrides for deterministic hints
  # shellcheck disable=SC2317  # Test-mode mocks are defined conditionally and invoked via baseline_* entrypoints.
  baseline_check_listen_port() { echo "OK"; }
  # shellcheck disable=SC2317  # Test-mode mocks are defined conditionally and invoked via baseline_* entrypoints.
  baseline_db_check_tcp() { echo "OK"; }
  # shellcheck disable=SC2317  # Test-mode mocks are defined conditionally and invoked via baseline_* entrypoints.
  baseline_proxy__openssl_probe() {
    printf "0\nsubject=CN=mock.example.com\nissuer=CN=Mock Test CA\nVerify return code: 0 (ok)\n"
  }
  # shellcheck disable=SC2317  # Test-mode mocks are defined conditionally and invoked via baseline_* entrypoints.
  baseline_tls__run_sclient() {
    baseline_triage__mock_tls_sclient_output
  }
}

baseline_triage__teardown_test_mode() {
  if [ "${BASELINE_TEST_MODE:-0}" != "1" ]; then
    return 0
  fi

  if [ -n "${BASELINE_TRIAGE_OLD_PATH:-}" ]; then
    PATH="$BASELINE_TRIAGE_OLD_PATH"
    export PATH
  fi

  if [ -n "${BASELINE_TRIAGE_MOCK_DIR:-}" ] && [ -d "$BASELINE_TRIAGE_MOCK_DIR" ]; then
    rm -rf "$BASELINE_TRIAGE_MOCK_DIR"
  fi

  unset BASELINE_TRIAGE_TEST_ACTIVE BASELINE_TRIAGE_OLD_PATH BASELINE_TRIAGE_MOCK_DIR
}

baseline_triage__run_groups() {
  local domain lang smoke_mode
  domain="$1"
  lang="$2"
  smoke_mode="${3:-0}"

  if [ "$smoke_mode" -eq 1 ]; then
    if declare -F baseline_dns_run >/dev/null 2>&1; then
      baseline_dns_run "$domain" "$lang"
    fi
    return 0
  fi

  if declare -F baseline_dns_run >/dev/null 2>&1; then
    baseline_dns_run "$domain" "$lang"
  fi
  if declare -F baseline_origin_run >/dev/null 2>&1; then
    baseline_origin_run "$domain" "$lang"
  fi
  if declare -F baseline_proxy_run >/dev/null 2>&1; then
    baseline_proxy_run "$domain" "$lang"
  fi
  if declare -F baseline_tls_run >/dev/null 2>&1; then
    baseline_tls_run "$domain" "$lang"
  fi
  if declare -F baseline_https_run >/dev/null 2>&1; then
    baseline_https_run "$domain" "$lang"
  fi
  if declare -F baseline_lsws_run >/dev/null 2>&1; then
    baseline_lsws_run "$domain" "$lang"
  fi
  if declare -F baseline_wp_run >/dev/null 2>&1; then
    BASELINE_WP_NO_PROMPT=1 baseline_wp_run "$domain" "" "$lang"
  fi
  if [ "$smoke_mode" -ne 1 ]; then
    if declare -F baseline_cache_run >/dev/null 2>&1; then
      baseline_cache_run "" "$lang"
    fi
    if declare -F baseline_db_run >/dev/null 2>&1; then
      baseline_db_run "127.0.0.1" "3306" "triage_db" "triage_user" "placeholder" "$lang"
    fi
  fi
  if declare -F baseline_sys_run >/dev/null 2>&1; then
    baseline_sys_run "$lang"
  fi
}

baseline_triage__write_json_report() {
  local domain lang ts overall json_path report_path
  domain="$1"
  lang="$2"
  ts="$3"
  overall="$4"
  json_path="$5"
  report_path="$6"

  local json_path_raw report_path_raw json_path_display report_path_display
  json_path_raw="$json_path"
  report_path_raw="$report_path"

  local generated_at
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local -a groups_order=(dns_ip origin_firewall proxy_cdn tls_https lsws_ols wp_app cache_redis system_resource)
  local total idx group key_name status keyword evidence suggestions evidence_fmt suggestions_fmt token ev_line sug_line
  declare -A group_status=()
  declare -A group_key_items=()
  declare -A group_evidence=()
  declare -A group_suggestions=()
  declare -A seen_key_item=()
  declare -A seen_evidence=()
  declare -A seen_suggestion=()

  total=${#BASELINE_RESULTS_STATUS[@]}
  for ((idx=0; idx<total; idx++)); do
    group="${BASELINE_RESULTS_GROUP[idx]}"
    key_name="$(baseline_triage__group_key "$group")"
    if [ -z "$key_name" ]; then
      continue
    fi

    status="${BASELINE_RESULTS_STATUS[idx]}"
    keyword="${BASELINE_RESULTS_KEYWORD[idx]}"
    evidence="${BASELINE_RESULTS_EVIDENCE[idx]}"
    suggestions="${BASELINE_RESULTS_SUGGESTIONS[idx]}"

    group_status[$key_name]="$(baseline_triage__status_merge "${group_status[$key_name]:-PASS}" "$status")"

    read -r -a keywords <<< "$keyword"
    for token in "${keywords[@]}"; do
      [ -z "$token" ] && continue
      if [ -z "${seen_key_item[${key_name}|${token}]+x}" ]; then
        seen_key_item["${key_name}|${token}"]=1
        group_key_items[$key_name]="${group_key_items[$key_name]:-}${token}$'\n'"
      fi
    done

    evidence_fmt=${evidence//\\n/$'\n'}
    while IFS= read -r ev_line; do
      [ -z "$ev_line" ] && continue
      ev_line="$(baseline_triage__sanitize_json_text "$ev_line")"
      if [ -z "${seen_evidence[${key_name}|${ev_line}]+x}" ]; then
        seen_evidence["${key_name}|${ev_line}"]=1
        group_evidence[$key_name]="${group_evidence[$key_name]:-}${ev_line}$'\n'"
      fi
    done <<< "$evidence_fmt"

    suggestions_fmt=${suggestions//\\n/$'\n'}
    while IFS= read -r sug_line; do
      [ -z "$sug_line" ] && continue
      sug_line="$(baseline_triage__sanitize_json_text "$sug_line")"
      if [ -z "${seen_suggestion[${key_name}|${sug_line}]+x}" ]; then
        seen_suggestion["${key_name}|${sug_line}"]=1
        group_suggestions[$key_name]="${group_suggestions[$key_name]:-}${sug_line}$'\n'"
      fi
    done <<< "$suggestions_fmt"
  done

  domain="$(baseline_triage__sanitize_json_text "$domain")"
  lang="$(baseline_triage__sanitize_json_text "$lang")"
  ts="$(baseline_triage__sanitize_json_text "$ts")"
  generated_at="$(baseline_triage__sanitize_json_text "$generated_at")"
  overall="$(baseline_triage__sanitize_json_text "$overall")"
  json_path_display="$(baseline_triage__sanitize_json_text "$json_path_raw")"
  report_path_display="$(baseline_triage__sanitize_json_text "$report_path_raw")"

  umask 077
  {
    printf '{\n'
    printf '  "schema_version": "1.0",\n'
    printf '  "format": "json",\n'
    printf '  "generated_at": "%s",\n' "$(baseline_json_escape "$generated_at")"
    printf '  "lang": "%s",\n' "$(baseline_json_escape "$lang")"
    printf '  "domain": "%s",\n' "$(baseline_json_escape "$domain")"
    printf '  "report": "%s",\n' "$(baseline_json_escape "$report_path_display")"
    printf '  "report_json": "%s",\n' "$(baseline_json_escape "$json_path_display")"
    printf '  "verdict": "%s",\n' "$(baseline_json_escape "$overall")"
    printf '  "results": [\n'

    local result_index=0
    for key_name in "${groups_order[@]}"; do
      local key_id
      key_id="$key_name"
      status="${group_status[$key_id]:-PASS}"
      status="$(baseline_triage__sanitize_json_text "$status")"
      key_name="$(baseline_triage__sanitize_json_text "$key_name")"
      local key_line evidence_json suggestions_json hint_line
      key_line="$(printf '%s' "${group_key_items[$key_id]:-}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
      key_line="$(baseline_triage__sanitize_json_text "$key_line")"
      evidence_json="$(baseline_triage__json_array_from_lines "${group_evidence[$key_id]:-}")"
      suggestions_json="$(baseline_triage__json_array_from_lines "${group_suggestions[$key_id]:-}")"

      hint_line="$(printf '%s' "${group_suggestions[$key_id]:-}" | sed -n '1p')"
      if [ -z "$hint_line" ]; then
        hint_line="$(printf '%s' "${group_evidence[$key_id]:-}" | sed -n '1p')"
      fi
      if [ -z "$hint_line" ]; then
        hint_line="$status"
      fi
      hint_line="$(baseline_triage__sanitize_json_text "$hint_line")"

      if [ $result_index -gt 0 ]; then
        printf ',\n'
      fi
      printf '    {"group": "%s", "key": "%s", "keyword": "%s", "state": "%s", "verdict": "%s", "hint": "%s", "evidence": [%s], "suggestions": [%s]}' \
        "$(baseline_json_escape "$key_name")" \
        "$(baseline_json_escape "$key_line")" \
        "$(baseline_json_escape "$key_line")" \
        "$(baseline_json_escape "$status")" \
        "$(baseline_json_escape "$status")" \
        "$(baseline_json_escape "$hint_line")" \
        "$evidence_json" \
        "$suggestions_json"
      result_index=$((result_index + 1))
    done

    printf '\n  ]\n'
    printf '}\n'
  } > "$json_path_raw"
  chmod 600 "$json_path_raw" 2>/dev/null || true
}

baseline_triage_run() {
  # Usage: baseline_triage_run "<domain>" "<lang>" "[format|--format <val>|--format=<val>]" "[--smoke|--exit0|--no-fail]"
  local domain lang format ts overall verdict_reason key_line report_path report_json_path summary_output details_output header_text safe_domain
  local smoke_mode errexit_set format_arg format_set report_dir
  local -a triage_args
  domain="$1"
  lang="$(baseline_triage__normalize_lang "$2")"
  shift 2 || true
  triage_args=("$@")
  format_arg="text"
  format_set=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --format)
        format_arg="${2:-$format_arg}"
        format_set=1
        shift 2
        ;;
      --format=*)
        format_arg="${1#--format=}"
        format_set=1
        shift
        ;;
      --smoke|--exit0|--no-fail)
        shift
        ;;
      json|text)
        if [ "$format_set" -eq 0 ]; then
          format_arg="$1"
          format_set=1
        fi
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  format="$(baseline_triage__normalize_format "$format_arg")"
  report_json_path=""
  smoke_mode=0
  errexit_set=0
  report_dir=""

  BASELINE_LAST_REPORT_PATH=""
  BASELINE_LAST_REPORT_JSON_PATH=""

  if [ -z "$domain" ]; then
    if [ "$lang" = "en" ]; then
      echo "VERDICT: FAIL (domain required)"
    else
      echo "VERDICT: FAIL（需要提供域名）"
    fi
    return 1
  fi

  baseline_init
  baseline_triage__setup_test_mode

  if baseline_triage__smoke_enabled "${triage_args[@]}"; then
    smoke_mode=1
    case $- in
      *e*)
        errexit_set=1
        set +e
        ;;
    esac
    baseline_triage__run_groups "$domain" "$lang" "$smoke_mode" || true
    if [ "$errexit_set" -eq 1 ]; then
      set -e
    fi
  else
    baseline_triage__run_groups "$domain" "$lang" "$smoke_mode"
  fi

  summary_output="$(baseline_print_summary)"
  details_output="$(baseline_print_details)"
  key_line="$(baseline_triage__collect_keywords_line)"

  overall="$(baseline__overall_state)"
  verdict_reason=""
  case "$overall" in
    FAIL)
      verdict_reason="$(baseline_triage__first_issue_reason "FAIL")"
      [ -z "$verdict_reason" ] && verdict_reason="issue_detected"
      ;;
    WARN)
      verdict_reason="$(baseline_triage__first_issue_reason "WARN")"
      [ -z "$verdict_reason" ] && verdict_reason="warn_detected"
      ;;
    *)
      verdict_reason="all_checks_passed"
      ;;
  esac

  ts="$(baseline_triage__timestamp)"
  safe_domain="${domain//[^A-Za-z0-9._-]/_}"

  if [ "$smoke_mode" -eq 1 ]; then
    if [ -z "${HZ_SMOKE_REPORT_DIR:-}" ]; then
      HZ_SMOKE_REPORT_DIR="$(mktemp -d -t hz-smoke-XXXXXXXX)"
      export HZ_SMOKE_REPORT_DIR
    fi
    report_dir="$HZ_SMOKE_REPORT_DIR"
    mkdir -p "$report_dir"
    report_path="${report_dir}/smoke-report.txt"
  else
    report_path="/tmp/hz-baseline-triage-${safe_domain}-${ts}.txt"
  fi

  header_text="=== HZ Quick Triage Report ===\nTIMESTAMP: ${ts}\nDOMAIN: ${domain}\nLANG: ${lang}\n"
  umask 077
  {
    printf "%s\n\n" "$header_text"
    printf "%s\n\n" "$summary_output"
    printf "%s\n" "$details_output"
    printf "\n%s\n" "$key_line"
  } | baseline_triage__sanitize_text > "$report_path"
  chmod 600 "$report_path" 2>/dev/null || true

  key_line="$(printf "%s" "$key_line" | baseline_triage__sanitize_text)"

  if [ "$format" = "json" ]; then
    if [ -n "$report_dir" ]; then
      report_json_path="${report_dir}/smoke-report.json"
    else
      report_json_path="/tmp/hz-baseline-triage-${safe_domain}-${ts}.json"
    fi
    baseline_triage__write_json_report "$domain" "$lang" "$ts" "$overall" "$report_json_path" "$report_path"
  fi

  BASELINE_LAST_REPORT_PATH="$report_path"
  BASELINE_LAST_REPORT_JSON_PATH="${report_json_path:-}"
  export BASELINE_LAST_REPORT_PATH BASELINE_LAST_REPORT_JSON_PATH

  local display_report_path display_report_json_path display_key_line display_reason
  display_report_path="$report_path"
  display_report_json_path="$report_json_path"
  display_key_line="$key_line"
  display_reason="$verdict_reason"

  if baseline_redact_enabled; then
    display_report_path="$(printf "%s" "$display_report_path" | baseline_triage__sanitize_text)"
    if [ -n "$display_report_json_path" ]; then
      display_report_json_path="$(printf "%s" "$display_report_json_path" | baseline_triage__sanitize_text)"
    fi
    display_key_line="$(printf "%s" "$display_key_line" | baseline_triage__sanitize_text)"
    display_reason="$(printf "%s" "$display_reason" | baseline_triage__sanitize_text)"
  fi

  if [ "$overall" = "PASS" ]; then
    echo "VERDICT: PASS (${display_reason})"
  else
    echo "VERDICT: ${overall} (${display_reason})"
  fi
  echo "$display_key_line"
  echo "REPORT: ${display_report_path}"
  if [ "$format" = "json" ]; then
    echo "REPORT_JSON: ${display_report_json_path}"
  fi

  local exit_status
  exit_status=0
  if [ "$overall" = "FAIL" ]; then
    exit_status=1
  elif [ "$overall" = "WARN" ]; then
    if [ "$smoke_mode" -eq 1 ] && ! baseline_triage__smoke_strict_enabled; then
      exit_status=0
    else
      exit_status=1
    fi
  fi

  baseline_triage__teardown_test_mode
  return "$exit_status"
}
