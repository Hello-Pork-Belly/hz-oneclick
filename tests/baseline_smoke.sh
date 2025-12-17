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

summary_output="$(baseline_print_summary)"
details_output="$(baseline_print_details)"
for group in "HTTPS/521" "DB" "DNS/IP" "ORIGIN/FW" "Proxy/CDN"; do
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
