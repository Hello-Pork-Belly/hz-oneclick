#!/usr/bin/env bash
set -euo pipefail

forbidden_terms_b64=(
  "Q2xvdWRmbGFyZQ=="
  "T3JhY2xl"
  "T0NJ"
  "QVdT"
  "R0NQ"
  "QXp1cmU="
)
forbidden_terms=()
SCHEMA_PATH="./docs/schema/baseline_diagnostics.schema.json"
timeout_available=0
for term_b64 in "${forbidden_terms_b64[@]}"; do
  if decoded_term=$(printf '%s' "$term_b64" | base64 -d 2>/dev/null); then
    forbidden_terms+=("$decoded_term")
  fi
done
if command -v timeout >/dev/null 2>&1; then
  timeout_available=1
fi

run_with_timeout() {
  local duration="30s"
  if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+[smhd]?$ ]]; then
    duration="$1"
    shift
  fi

  if [ "$timeout_available" -eq 1 ]; then
    timeout "$duration" "$@"
  else
    "$@"
  fi
}

validate_json_file() {
  local json_path expected_group
  json_path="$1"
  expected_group="${2:-}"

  if [ ! -f "$SCHEMA_PATH" ]; then
    echo "[smoke] schema file missing at ${SCHEMA_PATH}" >&2
    exit 1
  fi

  JSON_PATH="$json_path" SCHEMA_PATH="$SCHEMA_PATH" python3 - "$expected_group" <<'PY'
import json
import os
import sys
from pathlib import Path

json_path = Path(os.environ.get("JSON_PATH", ""))
schema_path = Path(os.environ.get("SCHEMA_PATH", ""))
expected = sys.argv[1] if len(sys.argv) > 1 else ""

if not json_path.is_file():
    print(f"json report missing: {json_path}", file=sys.stderr)
    sys.exit(1)
if not schema_path.is_file():
    print(f"schema missing: {schema_path}", file=sys.stderr)
    sys.exit(1)

data = json.loads(json_path.read_text())
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
for field in ("schema_version", "generated_at", "format", "lang", "domain"):
    ensure_string(data, field, "top-level")

if not isinstance(data.get("results"), list) or not data["results"]:
    fail("results array empty or invalid")

result_schema = schema.get("definitions", {}).get("result", {})
for idx, item in enumerate(data["results"]):
    if not isinstance(item, dict):
        fail(f"results[{idx}] is not an object")
    ensure_required(item, result_schema.get("required", []), f"results[{idx}]")
    for field in ("group", "key", "keyword", "state", "verdict", "hint"):
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

if expected and data.get("results"):
    if data["results"][0].get("group") != expected:
        fail(f"expected group {expected}, got {data['results'][0].get('group')}")
PY
}

assert_json_valid() {
  local json_path
  json_path="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -e . "$json_path" >/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$json_path" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
if not json_path.is_file():
    raise SystemExit(1)
json.loads(json_path.read_text())
PY
  else
    grep -q "^{.*" "$json_path"
  fi
}

find_latest_triage_json() {
  find /tmp -maxdepth 1 -type f -name 'hz-baseline-triage-*.json' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1{print $2}'
}

echo "[smoke] collecting shell scripts (excluding modules/)"
mapfile -d '' files < <(find . -type f -name '*.sh' -not -path './modules/*' -print0)

echo "[smoke] bash -n syntax check"
for f in "${files[@]}"; do
  bash -n "$f"
done

echo "[smoke] bash -n syntax check (modules/diagnostics)"
if [ -d "./modules/diagnostics" ]; then
  mapfile -d '' diag_files < <(find ./modules/diagnostics -type f -name '*.sh' -print0)
  for f in "${diag_files[@]}"; do
    bash -n "$f"
  done
fi

if command -v shellcheck >/dev/null 2>&1; then
  echo "[smoke] shellcheck structural pass (non-blocking)"
  shellcheck -x "${files[@]}" || true
else
  echo "[smoke] shellcheck not available; skipping static lint"
fi

echo "[smoke] baseline diagnostics menu entries"
grep -q "Baseline Diagnostics" hz.sh
grep -q "基础诊断" hz.sh

echo "[smoke] baseline_dns diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_dns.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_dns.sh

  baseline_init
  baseline_dns_run "abc.yourdomain.com" "en"
  details_output="$(baseline_print_details)"

  for field in PUBLIC_IPV4 PUBLIC_IPV6 DNS_A_RECORD DNS_AAAA_RECORD A_MATCH AAAA_MATCH; do
    echo "$details_output" | grep -q "$field"
  done
else
  echo "[smoke] baseline libraries not found; skipping baseline_dns smoke"
fi

echo "[smoke] baseline_origin diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_origin.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_origin.sh

  baseline_init
  baseline_origin_run "demo.example.com" "en"
  summary_output="$(baseline_print_summary)"
  echo "$summary_output" | grep -q "ORIGIN/FW"
else
  echo "[smoke] baseline_origin libraries not found; skipping baseline_origin smoke"
fi

echo "[smoke] baseline_proxy diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_proxy.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_proxy.sh

  baseline_init
  baseline_proxy_run "example.com" "en"
  proxy_summary="$(baseline_print_summary)"
  proxy_details="$(baseline_print_details)"
  echo "$proxy_summary" | grep -q "Proxy/CDN"
  echo "$proxy_details" | grep -q "Group: Proxy/CDN"
  echo "$proxy_details" | grep -q "Evidence:"
  echo "$proxy_details" | grep -q "Suggestions:"
else
  echo "[smoke] baseline_proxy libraries not found; skipping baseline_proxy smoke"
fi

echo "[smoke] baseline_tls diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_tls.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_tls.sh

  baseline_init
  baseline_tls_run "example.com" "en"
  tls_summary="$(baseline_print_summary)"
  tls_details="$(baseline_print_details)"
  echo "$tls_summary" | grep -q "TLS/CERT"
  echo "$tls_details" | grep -q "Group: TLS/CERT"
  echo "$tls_details" | grep -q "CERT_EXPIRY"
else
  echo "[smoke] baseline_tls libraries not found; skipping baseline_tls smoke"
fi

echo "[smoke] baseline_wp diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_wp.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_wp.sh

  baseline_init
  BASELINE_WP_NO_PROMPT=1 baseline_wp_run "example.invalid" "" "en"
  wp_summary="$(baseline_print_summary)"
  wp_details="$(baseline_print_details)"
  echo "$wp_summary" | grep -q "WP/APP"
  echo "$wp_details" | grep -q "Group: WP/APP"
  echo "$wp_details" | grep -q "HTTP_ROOT"
else
  echo "[smoke] baseline_wp libraries not found; skipping baseline_wp smoke"
fi

echo "[smoke] baseline_lsws diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_lsws.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_lsws.sh

  baseline_init
  baseline_lsws_run "" "en"
  lsws_details="$(baseline_print_details)"
  echo "$lsws_details" | grep -q "Group: LSWS/OLS"
  echo "$lsws_details" | grep -Eq "\[(PASS|WARN|FAIL)\]"
else
  echo "[smoke] baseline_lsws libraries not found; skipping baseline_lsws smoke"
fi

echo "[smoke] baseline_cache diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_cache.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_cache.sh

  tmp_wp="$(mktemp -d)"
  mkdir -p "$tmp_wp/wp-content"
  cat > "$tmp_wp/wp-config.php" <<'EOF'
<?php
define('WP_CACHE', true);
define('WP_REDIS_HOST', '127.0.0.1');
EOF
  touch "$tmp_wp/wp-content/object-cache.php"

  baseline_init
  baseline_cache_run "$tmp_wp" "en"
  cache_details="$(baseline_print_details)"
  echo "$cache_details" | grep -q "Group: CACHE/REDIS"
  echo "$cache_details" | grep -q "redis_service"
  rm -rf "$tmp_wp"
else
  echo "[smoke] baseline_cache libraries not found; skipping baseline_cache smoke"
fi

echo "[smoke] baseline_sys diagnostics smoke"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_sys.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_sys.sh

  baseline_init
  baseline_sys_run "en"
  sys_details="$(baseline_print_details)"
  echo "$sys_details" | grep -q "Group: SYSTEM/RESOURCE"
  echo "$sys_details" | grep -q "KEY:DISK_USAGE_ROOT"
  echo "$sys_details" | grep -q "KEY:SWAP_PRESENT"
else
  echo "[smoke] baseline_sys libraries not found; skipping baseline_sys smoke"
fi

echo "[smoke] baseline_triage quick run"
if [ -r "./lib/baseline.sh" ] && [ -r "./lib/baseline_triage.sh" ]; then
  # shellcheck source=/dev/null
  . ./lib/baseline.sh
  # shellcheck source=/dev/null
  . ./lib/baseline_triage.sh
  for lib in ./lib/baseline_https.sh ./lib/baseline_tls.sh ./lib/baseline_db.sh \
    ./lib/baseline_dns.sh ./lib/baseline_origin.sh ./lib/baseline_proxy.sh \
    ./lib/baseline_wp.sh ./lib/baseline_lsws.sh ./lib/baseline_cache.sh ./lib/baseline_sys.sh; do
  if [ -r "$lib" ]; then
      # shellcheck source=/dev/null
      . "$lib"
    fi
  done

  echo "[smoke] baseline_triage exit-code regression"
  (
    baseline_triage__run_groups() {
      baseline_add_result "TEST" "test_warn" "WARN" "TEST_WARN" "warn detected" "review warning"
      return 2
    }

    if (set -e; BASELINE_TEST_MODE=1 baseline_triage_run "triage.example.com" "en"); then
      echo "[smoke] baseline_triage normal mode should allow non-zero exit" >&2
      exit 1
    fi

    if ! (set -e; HZ_CI_SMOKE=1 BASELINE_TEST_MODE=1 baseline_triage_run "triage.example.com" "en" --smoke); then
      echo "[smoke] baseline_triage smoke mode should exit 0" >&2
      exit 1
    fi
  )

  echo "[smoke] baseline_triage report output"
  triage_output="$( ( HZ_CI_SMOKE=1 BASELINE_TEST_MODE=1 baseline_triage_run "triage.example.com" "en" --smoke ) )"
  echo "$triage_output" | grep -q "^VERDICT:"
  echo "$triage_output" | grep -q "^KEY:"
  report_path="$(echo "$triage_output" | awk '/^REPORT:/ {print $2}')"
  if [ -z "$report_path" ] || [ ! -f "$report_path" ]; then
    echo "[smoke] triage report not generated" >&2
    exit 1
  fi
  grep -q "HZ Quick Triage Report" "$report_path"
  grep -q "Baseline Diagnostics Summary" "$report_path"

  echo "[smoke] baseline_triage json output"
  triage_json_output="$( ( HZ_CI_SMOKE=1 BASELINE_TEST_MODE=1 baseline_triage_run "triage.example.com" "en" "json" --smoke ) )"
  echo "$triage_json_output" | grep -q "^REPORT_JSON:"
  json_report_path="$(echo "$triage_json_output" | awk '/^REPORT_JSON:/ {print $2}')"
  if [ -z "$json_report_path" ] || [ ! -f "$json_report_path" ]; then
    echo "[smoke] triage JSON report not generated" >&2
    exit 1
  fi
  head -n1 "$json_report_path" | grep -q "^{"
  assert_json_valid "$json_report_path"
  validate_json_file "$json_report_path"

  if [ ${#forbidden_terms[@]} -gt 0 ]; then
    regex=$(IFS='|'; echo "${forbidden_terms[*]}")
    if matches=$(grep -Eina "$regex" "$json_report_path" || true) && [ -n "$matches" ]; then
      echo "[smoke] forbidden vendor terms found in triage JSON" >&2
      printf "%s\n" "$matches" >&2
      exit 1
    fi
  fi

  echo "[smoke] baseline_triage redacted json run"
  redacted_output_file="$(mktemp)"
  if ! HZ_CI_SMOKE=1 BASELINE_TEST_MODE=1 BASELINE_REDACT=1 baseline_triage_run "triage.example.com" "en" "json" --smoke > "$redacted_output_file"; then
    echo "[smoke] smoke triage should exit 0 for redacted JSON run" >&2
    exit 1
  fi
  grep -q "^REPORT_JSON:" "$redacted_output_file"
  redacted_json_path="${BASELINE_LAST_REPORT_JSON_PATH:-}"
  if [ -z "$redacted_json_path" ] || [ ! -f "$redacted_json_path" ]; then
    echo "[smoke] redacted triage JSON report missing" >&2
    exit 1
  fi
  assert_json_valid "$redacted_json_path"
  validate_json_file "$redacted_json_path"
  grep -qi "<redacted" "$redacted_json_path"
  rm -f "$redacted_output_file"
else
  echo "[smoke] baseline_triage libraries not found; skipping triage smoke"
fi

echo "[smoke] quick triage standalone runner"
if [ -r "./modules/diagnostics/quick-triage.sh" ]; then
  triage_output="$(run_with_timeout 90s env HZ_CI_SMOKE=1 HZ_TRIAGE_TEST_MODE=1 BASELINE_TEST_MODE=1 HZ_TRIAGE_USE_LOCAL=1 HZ_TRIAGE_LOCAL_ROOT="$(pwd)" HZ_TRIAGE_LANG=en HZ_TRIAGE_TEST_DOMAIN="abc.yourdomain.com" bash ./modules/diagnostics/quick-triage.sh --smoke)"
  echo "$triage_output" | grep -q "^VERDICT:"
  echo "$triage_output" | grep -q "^KEY:"
  echo "$triage_output" | grep -q "^REPORT:"
  standalone_report="$(echo "$triage_output" | awk '/^REPORT:/ {print $2}')"
  if [ -z "$standalone_report" ] || [ ! -f "$standalone_report" ]; then
    echo "[smoke] standalone triage report missing" >&2
    exit 1
  fi
  grep -q "HZ Quick Triage Report" "$standalone_report"
  grep -q "Baseline Diagnostics Summary" "$standalone_report"

  triage_output_json="$(run_with_timeout 90s env HZ_CI_SMOKE=1 HZ_TRIAGE_TEST_MODE=1 BASELINE_TEST_MODE=1 HZ_TRIAGE_USE_LOCAL=1 HZ_TRIAGE_LOCAL_ROOT="$(pwd)" HZ_TRIAGE_LANG=en HZ_TRIAGE_TEST_DOMAIN="abc.yourdomain.com" bash ./modules/diagnostics/quick-triage.sh --format json --smoke)"
  echo "$triage_output_json" | grep -q "^REPORT_JSON:"
  standalone_json_report="$(echo "$triage_output_json" | awk '/^REPORT_JSON:/ {print $2}')"
  if [ -z "$standalone_json_report" ] || [ ! -f "$standalone_json_report" ]; then
    echo "[smoke] standalone triage JSON report missing" >&2
    exit 1
  fi
  head -n1 "$standalone_json_report" | grep -q "^{"
  assert_json_valid "$standalone_json_report"
  validate_json_file "$standalone_json_report"
  if [ ${#forbidden_terms[@]} -gt 0 ]; then
    regex=$(IFS='|'; echo "${forbidden_terms[*]}")
    if matches=$(grep -Eina "$regex" "$standalone_json_report" || true) && [ -n "$matches" ]; then
      echo "[smoke] forbidden vendor terms found in quick-triage JSON" >&2
      printf "%s\n" "$matches" >&2
      exit 1
    fi
  fi

  echo "[smoke] quick triage standalone runner (redact mode)"
  before_latest_json="$(find_latest_triage_json)"
  triage_output_json_redacted="$(run_with_timeout 90s env HZ_TRIAGE_TEST_MODE=1 BASELINE_TEST_MODE=1 HZ_TRIAGE_USE_LOCAL=1 HZ_TRIAGE_LOCAL_ROOT="$(pwd)" HZ_TRIAGE_LANG=en HZ_TRIAGE_TEST_DOMAIN="abc.yourdomain.com" HZ_TRIAGE_REDACT=1 HZ_CI_SMOKE=1 bash ./modules/diagnostics/quick-triage.sh --format json --redact --smoke)"
  echo "$triage_output_json_redacted" | grep -qi "<redacted"
  latest_json="$(find_latest_triage_json)"
  if [ -z "$latest_json" ] || { [ -n "$before_latest_json" ] && [ "$latest_json" = "$before_latest_json" ]; }; then
    echo "[smoke] no new redacted triage JSON report found" >&2
    exit 1
  fi
  assert_json_valid "$latest_json"
  validate_json_file "$latest_json"
  grep -qi "<redacted" "$latest_json"
else
  echo "[smoke] quick triage runner not found; skipping"
fi

echo "[smoke] baseline regression suite"
run_with_timeout 90s env HZ_CI_SMOKE=1 bash tests/baseline_smoke.sh

echo "[smoke] OK"
