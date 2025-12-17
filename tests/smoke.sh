#!/usr/bin/env bash
set -euo pipefail

echo "[smoke] collecting shell scripts (excluding modules/)"
mapfile -d '' files < <(find . -type f -name '*.sh' -not -path './modules/*' -print0)

echo "[smoke] bash -n syntax check"
for f in "${files[@]}"; do
  bash -n "$f"
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "[smoke] shellcheck structural pass (non-blocking)"
  shellcheck -x "${files[@]}" || true
else
  echo "[smoke] shellcheck not available; skipping static lint"
fi

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

echo "[smoke] baseline regression suite"
bash tests/baseline_smoke.sh

echo "[smoke] OK"
