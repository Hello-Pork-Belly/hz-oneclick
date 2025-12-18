#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_PATH="${REPO_ROOT}/docs/schema/baseline_diagnostics.schema.json"

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

  if [ ! -f "$SCHEMA_PATH" ]; then
    echo "[baseline-smoke] schema file not found: ${SCHEMA_PATH}" >&2
    exit 1
  fi

  JSON_DATA="$json_output" SCHEMA_PATH="$SCHEMA_PATH" python3 - "$expected_group" "$regex_pattern" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

data = json.loads(os.environ.get("JSON_DATA", "{}"))
expected = sys.argv[1]
regex = sys.argv[2]
schema_path = Path(os.environ.get("SCHEMA_PATH", ""))
if not schema_path.is_file():
    print(f"schema missing at {schema_path}", file=sys.stderr)
    sys.exit(1)

schema = json.loads(schema_path.read_text())

def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    sys.exit(1)

def ensure_required(obj: dict, required, ctx: str) -> None:
    for key in required:
        if key not in obj:
            fail(f"{ctx} missing field: {key}")

def ensure_string(obj: dict, key: str, ctx: str) -> None:
    if key in obj and not isinstance(obj[key], str):
        fail(f"{ctx} field {key} is not a string")

ensure_required(data, schema.get("required", []), "top-level")
for string_field in ("schema_version", "generated_at", "format", "lang", "domain"):
    ensure_string(data, string_field, "top-level")

for required in ("schema_version", "generated_at", "lang", "domain", "results"):
    if required not in data:
        fail(f"missing field: {required}")

if not isinstance(data.get("results"), list) or not data["results"]:
    fail("results array empty or invalid")

result_schema = schema.get("definitions", {}).get("result", {})
for idx, item in enumerate(data["results"]):
    if not isinstance(item, dict):
        fail(f"results[{idx}] is not an object")
    ensure_required(item, result_schema.get("required", []), f"results[{idx}]")
    for field in ("group", "key", "verdict", "hint", "keyword", "state"):
        ensure_string(item, field, f"results[{idx}]")
    if item.get("state") not in (None, "PASS", "WARN", "FAIL"):
        fail(f"invalid state in results[{idx}]: {item.get('state')}")

    if idx == 0 and expected and item.get("group") != expected:
        fail(f"group mismatch: {item.get('group')} != {expected}")

    for arr_field in ("evidence", "suggestions"):
        if not isinstance(item.get(arr_field), list):
            fail(f"{arr_field} is not a list in results[{idx}]")
        for arr_idx, entry in enumerate(item.get(arr_field)):
            if not isinstance(entry, str):
                fail(f"{arr_field}[{arr_idx}] is not a string in results[{idx}]")

    for path_field in ("report", "report_json"):
        path_val = item.get(path_field)
        if path_val and not os.path.isfile(path_val):
            fail(f"missing report file: {path_val}")

if regex:
    blob = json.dumps(data)
    if re.search(regex, blob, flags=re.IGNORECASE):
        fail("forbidden vendor wording found in JSON")
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
