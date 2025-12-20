#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${FULL_REGRESSION_ARTIFACT_DIR:-${REPO_ROOT}/artifacts/full-regression}"
TIMEOUT_AVAILABLE=0

if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_AVAILABLE=1
fi

run_with_timeout() {
  local duration="$1"
  shift

  if [ "$TIMEOUT_AVAILABLE" -eq 1 ]; then
    timeout "$duration" "$@"
  else
    "$@"
  fi
}

mkdir -p "$ARTIFACT_DIR"

progress() {
  echo "[full-regression] $*"
}

progress "baseline regression (full mode)"
run_with_timeout 8m env CI=false HZ_CI_SMOKE=0 BASELINE_TEST_MODE=1 bash "${REPO_ROOT}/tests/baseline_smoke.sh"

progress "quick triage full run (json + text)"
triage_output="$(run_with_timeout 6m env \
  CI=false \
  BASELINE_TEST_MODE=1 \
  HZ_TRIAGE_TEST_MODE=1 \
  HZ_TRIAGE_USE_LOCAL=1 \
  HZ_TRIAGE_LOCAL_ROOT="${REPO_ROOT}" \
  HZ_TRIAGE_LANG=en \
  HZ_TRIAGE_TEST_DOMAIN="example.com" \
  bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh" --format json)"

printf "%s\n" "$triage_output" > "${ARTIFACT_DIR}/quick-triage-output.txt"

report_path="$(printf "%s\n" "$triage_output" | awk '/^REPORT:/ {print $2}')"
report_json_path="$(printf "%s\n" "$triage_output" | awk '/^REPORT_JSON:/ {print $2}')"

if [ -n "$report_path" ] && [ -f "$report_path" ]; then
  cp "$report_path" "${ARTIFACT_DIR}/"
fi

if [ -n "$report_json_path" ] && [ -f "$report_json_path" ]; then
  cp "$report_json_path" "${ARTIFACT_DIR}/"
fi

progress "full regression completed"
