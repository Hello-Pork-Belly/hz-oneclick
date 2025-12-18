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
for term_b64 in "${forbidden_terms_b64[@]}"; do
  if decoded_term=$(printf '%s' "$term_b64" | base64 -d 2>/dev/null); then
    forbidden_terms+=("$decoded_term")
  fi
done

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

  triage_output="$( ( BASELINE_TEST_MODE=1 baseline_triage_run "triage.example.com" "en" ) )"
  echo "$triage_output" | grep -q "^VERDICT:"
  echo "$triage_output" | grep -q "^KEY:"
  report_path="$(echo "$triage_output" | awk '/^REPORT:/ {print $2}')"
  if [ -z "$report_path" ] || [ ! -f "$report_path" ]; then
    echo "[smoke] triage report not generated" >&2
    exit 1
  fi
  grep -q "HZ Quick Triage Report" "$report_path"
  grep -q "Baseline Diagnostics Summary" "$report_path"

  triage_json_output="$( ( BASELINE_TEST_MODE=1 baseline_triage_run "triage.example.com" "en" "json" ) )"
  echo "$triage_json_output" | grep -q "^REPORT_JSON:"
  json_report_path="$(echo "$triage_json_output" | awk '/^REPORT_JSON:/ {print $2}')"
  if [ -z "$json_report_path" ] || [ ! -f "$json_report_path" ]; then
    echo "[smoke] triage JSON report not generated" >&2
    exit 1
  fi
  head -n1 "$json_report_path" | grep -q "^{"
  grep -q '"metadata"' "$json_report_path"
  grep -q '"summary"' "$json_report_path"
  grep -q '"groups"' "$json_report_path"

  if ! python3 -m json.tool "$json_report_path" >/dev/null; then
    echo "[smoke] triage JSON report is not valid JSON" >&2
    exit 1
  fi

  if [ ${#forbidden_terms[@]} -gt 0 ]; then
    regex=$(IFS='|'; echo "${forbidden_terms[*]}")
    if matches=$(grep -Eina "$regex" "$json_report_path" || true) && [ -n "$matches" ]; then
      echo "[smoke] forbidden vendor terms found in triage JSON" >&2
      printf "%s\n" "$matches" >&2
      exit 1
    fi
  fi
else
  echo "[smoke] baseline_triage libraries not found; skipping triage smoke"
fi

echo "[smoke] quick triage standalone runner"
if [ -r "./modules/diagnostics/quick-triage.sh" ]; then
  triage_output="$(HZ_TRIAGE_TEST_MODE=1 BASELINE_TEST_MODE=1 HZ_TRIAGE_USE_LOCAL=1 HZ_TRIAGE_LOCAL_ROOT="$(pwd)" HZ_TRIAGE_LANG=en HZ_TRIAGE_TEST_DOMAIN="abc.yourdomain.com" bash ./modules/diagnostics/quick-triage.sh)"
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

  triage_output_json="$(HZ_TRIAGE_TEST_MODE=1 BASELINE_TEST_MODE=1 HZ_TRIAGE_USE_LOCAL=1 HZ_TRIAGE_LOCAL_ROOT="$(pwd)" HZ_TRIAGE_LANG=en HZ_TRIAGE_TEST_DOMAIN="abc.yourdomain.com" bash ./modules/diagnostics/quick-triage.sh --format json)"
  echo "$triage_output_json" | grep -q "^REPORT_JSON:"
  standalone_json_report="$(echo "$triage_output_json" | awk '/^REPORT_JSON:/ {print $2}')"
  if [ -z "$standalone_json_report" ] || [ ! -f "$standalone_json_report" ]; then
    echo "[smoke] standalone triage JSON report missing" >&2
    exit 1
  fi
  head -n1 "$standalone_json_report" | grep -q "^{"
  grep -q '"summary"' "$standalone_json_report"
  if ! python3 -m json.tool "$standalone_json_report" >/dev/null; then
    echo "[smoke] quick-triage JSON report is not valid JSON" >&2
    exit 1
  fi
  if [ ${#forbidden_terms[@]} -gt 0 ]; then
    regex=$(IFS='|'; echo "${forbidden_terms[*]}")
    if matches=$(grep -Eina "$regex" "$standalone_json_report" || true) && [ -n "$matches" ]; then
      echo "[smoke] forbidden vendor terms found in quick-triage JSON" >&2
      printf "%s\n" "$matches" >&2
      exit 1
    fi
  fi
else
  echo "[smoke] quick triage runner not found; skipping"
fi

echo "[smoke] baseline regression suite"
bash tests/baseline_smoke.sh

echo "[smoke] OK"
