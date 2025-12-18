#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local haystack needle
  haystack="$1"
  needle="$2"
  if ! echo "$haystack" | grep -Fq "$needle"; then
    echo "[baseline-smoke] expected to find: $needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack needle
  haystack="$1"
  needle="$2"
  if echo "$haystack" | grep -Fq "$needle"; then
    echo "[baseline-smoke] found forbidden content: $needle" >&2
    exit 1
  fi
}

if [ ! -r "${REPO_ROOT}/lib/baseline.sh" ]; then
  echo "[baseline-smoke] baseline library not found; skipping"
  exit 0
fi

if [ -r "${REPO_ROOT}/lib/baseline_common.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_common.sh"
else
  baseline_sanitize_text() {
    sed -E \
      -e 's/((authorization|token|password|secret|apikey|api_key)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/Ig' \
      -e 's/((^|[[:space:]])key=)[^[:space:]]+/\1[REDACTED]/Ig' \
      -e 's/((bearer)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig'
  }
fi

# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/baseline.sh"

if [ -r "${REPO_ROOT}/lib/baseline_https.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_https.sh"
fi

if [ -r "${REPO_ROOT}/lib/baseline_db.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_db.sh"
fi

if [ -r "${REPO_ROOT}/lib/baseline_dns.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_dns.sh"
fi

if [ -r "${REPO_ROOT}/lib/baseline_origin.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_origin.sh"
fi

if [ -r "${REPO_ROOT}/lib/baseline_proxy.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_proxy.sh"
fi

if [ -r "${REPO_ROOT}/lib/baseline_tls.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_tls.sh"
fi

if [ -r "${REPO_ROOT}/lib/baseline_wp.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_wp.sh"
fi
if [ -r "${REPO_ROOT}/lib/baseline_lsws.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_lsws.sh"
fi
if [ -r "${REPO_ROOT}/lib/baseline_cache.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_cache.sh"
fi
if [ -r "${REPO_ROOT}/lib/baseline_sys.sh" ]; then
  # shellcheck source=/dev/null
  . "${REPO_ROOT}/lib/baseline_sys.sh"
fi

echo "[baseline-smoke] vendor-neutral wording check"
search_paths=("${REPO_ROOT}/README.md" "${REPO_ROOT}/lib" "${REPO_ROOT}/modules" "${REPO_ROOT}/hz.sh")
filtered_paths=()
for path in "${search_paths[@]}"; do
  if [ -e "$path" ]; then
    filtered_paths+=("$path")
  fi
done

forbidden_terms_b64=(
  "Q2xvdWRmbGFyZQ=="
  "T3JhY2xl"
  "T0NJ"
  "QVdT"
  "R0NQ"
  "QXp1cmU="
)
forbidden_terms=()
vendor_regex=""
for term_b64 in "${forbidden_terms_b64[@]}"; do
  if decoded_term=$(printf '%s' "$term_b64" | base64 -d 2>/dev/null); then
    forbidden_terms+=("$decoded_term")
  fi
done

if [ ${#forbidden_terms[@]} -gt 0 ]; then
  vendor_regex=$(IFS='|'; echo "${forbidden_terms[*]}")
fi

if [ ${#filtered_paths[@]} -gt 0 ] && [ -n "$vendor_regex" ]; then
  if grep -RIn -Ei "$vendor_regex" "${filtered_paths[@]}"; then
    echo "[baseline-smoke] vendor names should not appear in repository" >&2
    exit 1
  fi
fi

echo "[baseline-smoke] sanitization coverage"
sanitize_input=$'Authorization: Bearer abc123\npassword=xyz\napi_key: token123\nquery key=value\nTOKEN=raw'
sanitized_output="$(printf "%s" "$sanitize_input" | baseline_sanitize_text)"
assert_not_contains "$sanitized_output" "abc123"
assert_not_contains "$sanitized_output" "xyz"
assert_not_contains "$sanitized_output" "token123"
assert_not_contains "$sanitized_output" "key=value"
assert_contains "$sanitized_output" "[REDACTED]"

echo "[baseline-smoke] framework API availability"
baseline_init
baseline_add_result "FRAMEWORK" "HELLO" "PASS" "KW_HELLO" "evidence-line" "suggestion-line"
baseline_add_result "FRAMEWORK" "WARN_CASE" "WARN" "KW_WARN" "warn-evidence" ""
summary_output="$(baseline_print_summary)"
details_output="$(baseline_print_details)"
assert_contains "$summary_output" "Overall:"
assert_contains "$summary_output" "Group:"
assert_contains "$details_output" "Evidence:"
assert_contains "$details_output" "Suggestions"

echo "[baseline-smoke] group registration and structural regression"
baseline_init
if declare -F baseline_https_run >/dev/null 2>&1; then
  baseline_https_run "abc.yourdomain.com" "en"
fi
if declare -F baseline_db_run >/dev/null 2>&1; then
  baseline_db_run "127.0.0.1" "3306" "abc_db" "abc_user" "placeholder-password" "en"
fi
if declare -F baseline_dns_run >/dev/null 2>&1; then
  baseline_dns_run "123.yourdomain.com" "en"
fi
if declare -F baseline_origin_run >/dev/null 2>&1; then
  baseline_origin_run "abc.yourdomain.com" "en"
fi
if declare -F baseline_proxy_run >/dev/null 2>&1; then
  baseline_proxy_run "example.com" "en"
fi
if declare -F baseline_tls_run >/dev/null 2>&1; then
  baseline_tls_run "example.com" "en"
fi
if declare -F baseline_wp_run >/dev/null 2>&1; then
  BASELINE_WP_NO_PROMPT=1 baseline_wp_run "example.invalid" "" "en"
fi
if declare -F baseline_lsws_run >/dev/null 2>&1; then
  baseline_lsws_run "" "en"
fi
if declare -F baseline_cache_run >/dev/null 2>&1; then
  tmp_wp="$(mktemp -d)"
  mkdir -p "$tmp_wp/wp-content"
  cat > "$tmp_wp/wp-config.php" <<'EOF'
<?php
define('WP_CACHE', true);
EOF
  baseline_cache_run "$tmp_wp" "en"
  rm -rf "$tmp_wp"
fi
if declare -F baseline_sys_run >/dev/null 2>&1; then
  baseline_sys_run "en"
fi

summary_output="$(baseline_print_summary)"
details_output="$(baseline_print_details)"
for group in "HTTPS/521" "DB" "DNS/IP" "ORIGIN/FW" "Proxy/CDN" "TLS/CERT" "WP/APP" "LSWS/OLS" "CACHE/REDIS" "SYSTEM/RESOURCE"; do
  assert_contains "$summary_output" "$group"
done
assert_contains "$details_output" "Group: HTTPS/521"
assert_contains "$details_output" "LISTEN_80"
assert_contains "$details_output" "Group: DB"
assert_contains "$details_output" "DB_TCP_CONNECT"
assert_contains "$details_output" "Group: DNS/IP"
assert_contains "$details_output" "DNS_A_RECORD"
assert_contains "$details_output" "Group: ORIGIN/FW"
assert_contains "$details_output" "SERVICE_OLS"
assert_contains "$details_output" "Group: Proxy/CDN"
assert_contains "$details_output" "HTTPS_STATUS"
assert_contains "$details_output" "Group: TLS/CERT"
assert_contains "$details_output" "CERT_CHAIN"
assert_contains "$details_output" "Group: WP/APP"
assert_contains "$summary_output" "LSWS/OLS"
assert_contains "$details_output" "Group: LSWS/OLS"
assert_contains "$details_output" "lsws_active"
assert_contains "$details_output" "Group: CACHE/REDIS"
assert_contains "$details_output" "redis_"
assert_contains "$details_output" "Group: SYSTEM/RESOURCE"
assert_contains "$details_output" "KEY:DISK_USAGE_ROOT"
assert_contains "$details_output" "KEY:LOAD1_PER_CORE"

echo "[baseline-smoke] wrapper quick verdict check"
if [ -x "${REPO_ROOT}/modules/diagnostics/baseline-dns-ip.sh" ]; then
  wrapper_output="$(BASELINE_TEST_MODE=1 HZ_BASELINE_LANG=en bash "${REPO_ROOT}/modules/diagnostics/baseline-dns-ip.sh" "example.com" "en")"
  assert_contains "$wrapper_output" "VERDICT:"
  assert_contains "$wrapper_output" "KEY:"
fi

echo "[baseline-smoke] wrapper json output"
validate_wrapper_json() {
  local json_output expected_group regex_pattern pretty
  json_output="$1"
  expected_group="$2"
  regex_pattern="$3"

  pretty="$(echo "$json_output" | python3 -m json.tool)"

  printf "%s" "$pretty" | grep -Eq '"schema_version"' || { echo "[baseline-smoke] schema_version missing" >&2; exit 1; }
  printf "%s" "$pretty" | grep -Eq '"generated_at"' || { echo "[baseline-smoke] generated_at missing" >&2; exit 1; }
  printf "%s" "$pretty" | grep -Eq '"results"' || { echo "[baseline-smoke] results array missing" >&2; exit 1; }
  printf "%s" "$pretty" | grep -Eq '"hint"' || { echo "[baseline-smoke] hint field missing" >&2; exit 1; }

  JSON_DATA="$json_output" python3 - "$expected_group" "$regex_pattern" <<'PY'
import json
import os
import re
import sys

data = json.loads(os.environ.get("JSON_DATA", "{}"))
expected = sys.argv[1]
regex = sys.argv[2]

for required in ("schema_version", "generated_at", "lang", "domain", "results"):
    if required not in data:
        print(f"missing field: {required}", file=sys.stderr)
        sys.exit(1)

if not isinstance(data.get("results"), list) or not data["results"]:
    print("results array empty or invalid", file=sys.stderr)
    sys.exit(1)

item = data["results"][0]
for field in ("group", "key", "verdict", "hint", "evidence", "suggestions"):
    if field not in item:
        print(f"missing result field: {field}", file=sys.stderr)
        sys.exit(1)

if expected and item.get("group") != expected:
    print(f"group mismatch: {item.get('group')} != {expected}", file=sys.stderr)
    sys.exit(1)

for arr_field in ("evidence", "suggestions"):
    if not isinstance(item.get(arr_field), list):
        print(f"{arr_field} is not a list", file=sys.stderr)
        sys.exit(1)

for path_field in ("report", "report_json"):
    path_val = item.get(path_field)
    if path_val and not os.path.isfile(path_val):
        print(f"missing report file: {path_val}", file=sys.stderr)
        sys.exit(1)

if regex:
    blob = json.dumps(data)
    if re.search(regex, blob, flags=re.IGNORECASE):
        print("forbidden vendor wording found in JSON", file=sys.stderr)
        sys.exit(1)
PY

  if [ -n "$vendor_regex" ]; then
    if printf "%s" "$json_output" | grep -Eiq "$vendor_regex"; then
      echo "[baseline-smoke] vendor wording found in JSON output" >&2
      exit 1
    fi
  fi
}

if [ -x "${REPO_ROOT}/modules/diagnostics/baseline-dns-ip.sh" ]; then
  dns_json_output="$(BASELINE_TEST_MODE=1 HZ_BASELINE_LANG=en HZ_BASELINE_FORMAT=json bash "${REPO_ROOT}/modules/diagnostics/baseline-dns-ip.sh" "example.com" "en" --format json)"
  validate_wrapper_json "$dns_json_output" "dns-ip" "$vendor_regex"
fi

if [ -x "${REPO_ROOT}/modules/diagnostics/baseline-tls-https.sh" ]; then
  tls_json_output="$(BASELINE_TEST_MODE=1 HZ_BASELINE_LANG=en HZ_BASELINE_FORMAT=json bash "${REPO_ROOT}/modules/diagnostics/baseline-tls-https.sh" "example.com" "en" --format json)"
  validate_wrapper_json "$tls_json_output" "tls-https" "$vendor_regex"
fi

if [ -x "${REPO_ROOT}/modules/diagnostics/baseline-cache.sh" ]; then
  cache_json_output="$(BASELINE_TEST_MODE=1 HZ_BASELINE_LANG=en HZ_BASELINE_FORMAT=json bash "${REPO_ROOT}/modules/diagnostics/baseline-cache.sh" --format json)"
  validate_wrapper_json "$cache_json_output" "cache-redis" "$vendor_regex"
fi


echo "[baseline-smoke] secrets leak guard"
TEST_DB_PASS="SuperSecret123!DoNotLeak"
TEST_REDIS_PASS="AnotherSecret456!DoNotLeak"

baseline_init
secret_output="$(
  {
    if declare -F baseline_db_run >/dev/null 2>&1; then
      baseline_db_run "127.0.0.1" "3306" "abc_db" "abc_user" "$TEST_DB_PASS" "en"
    fi
    if declare -F baseline_https_run >/dev/null 2>&1; then
      baseline_https_run "abc.yourdomain.com" "en"
    fi
    baseline_print_summary
    baseline_print_details
  } 2>&1
)"

assert_not_contains "$secret_output" "$TEST_DB_PASS"
assert_not_contains "$secret_output" "$TEST_REDIS_PASS"
assert_not_contains "$secret_output" "DB_PASSWORD="


echo "[baseline-smoke] tier entry regression (Lite/Standard/Hub reachability)"
for tier in Lite Standard Hub; do
  baseline_init
  if declare -F baseline_https_run >/dev/null 2>&1; then
    baseline_https_run "127.0.0.1" "en"
  else
    baseline_add_result "HTTPS/521" "LISTEN_80" "WARN" "LISTEN_80" "placeholder" ""
  fi
  tier_summary="$(baseline_print_summary)"
  tier_details="$(baseline_print_details)"
  assert_contains "$tier_summary" "Overall:"
  assert_contains "$tier_details" "Group: HTTPS/521"
  assert_contains "$tier_details" "Evidence:"
  assert_contains "$tier_details" "Suggestions:"
  echo "[baseline-smoke] tier ${tier} summary ready"
done

echo "[baseline-smoke] completed"
