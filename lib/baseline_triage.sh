#!/usr/bin/env bash

# Baseline "Quick Triage" orchestration (521/HTTPS/TLS first).
# This file only defines functions and does not execute any logic on load.

baseline_triage__normalize_lang() {
  local lang
  lang="${1:-zh}"
  if [[ "${lang,,}" == en* ]]; then
    echo "en"
  else
    echo "zh"
  fi
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

baseline_triage__sanitize_text() {
  # Redact common sensitive keys before writing to report/output.
  # Matches token/authorization/password/secret/apikey patterns.
  sed -E 's/((token|authorization|password|secret|apikey)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig'
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
  echo "2001:db8::10"
else
  echo "203.0.113.20"
fi
MOCKDIG
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/dig"

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/nslookup" <<'MOCKNSLOOKUP'
#!/usr/bin/env bash
if echo "$*" | grep -qi "AAAA"; then
  echo "Address: 2001:db8::10"
else
  echo "Address: 203.0.113.20"
fi
MOCKNSLOOKUP
  chmod +x "${BASELINE_TRIAGE_MOCK_DIR}/nslookup"

  cat > "${BASELINE_TRIAGE_MOCK_DIR}/drill" <<'MOCKDRILL'
#!/usr/bin/env bash
if echo "$*" | grep -qi "AAAA"; then
  echo "2001:db8::10"
else
  echo "203.0.113.20"
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
  baseline_check_listen_port() { echo "OK"; }
  baseline_db_check_tcp() { echo "OK"; }
  baseline_proxy__openssl_probe() {
    printf "0\nsubject=CN=mock.example.com\nissuer=CN=Mock Test CA\nVerify return code: 0 (ok)\n"
  }
  baseline_tls__run_sclient() {
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
  local domain lang
  domain="$1"
  lang="$2"

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
  if declare -F baseline_cache_run >/dev/null 2>&1; then
    baseline_cache_run "" "$lang"
  fi
  if declare -F baseline_db_run >/dev/null 2>&1; then
    baseline_db_run "127.0.0.1" "3306" "triage_db" "triage_user" "placeholder" "$lang"
  fi
  if declare -F baseline_sys_run >/dev/null 2>&1; then
    baseline_sys_run "$lang"
  fi
}

baseline_triage_run() {
  # Usage: baseline_triage_run "<domain>" "<lang>"
  local domain lang ts overall verdict_reason key_line report_path summary_output details_output header_text safe_domain
  domain="$1"
  lang="$(baseline_triage__normalize_lang "$2")"

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

  baseline_triage__run_groups "$domain" "$lang"

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
  report_path="/tmp/hz-baseline-triage-${safe_domain}-${ts}.txt"

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

  if [ "$overall" = "PASS" ]; then
    echo "VERDICT: PASS (${verdict_reason})"
  else
    echo "VERDICT: ${overall} (${verdict_reason})"
  fi
  echo "$key_line"
  echo "REPORT: ${report_path}"

  baseline_triage__teardown_test_mode
}

