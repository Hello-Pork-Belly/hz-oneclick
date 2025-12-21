#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

install_status="SKIP"
lint_status=1
selftest_status=1
smoke_exit_code=1
smoke_verdict="FAIL"
smoke_report_path="unknown"
smoke_report_json_path="unknown"
enforce_status=1
enforce_verdict="FAIL"
enforce_strict="false"
smoke_strict="${HZ_SMOKE_STRICT:-0}"

echo "==> CI parity runner (local)"
cd "$repo_root"

echo ""
echo "==> Install CI tools (best effort)"
if [ "${HZ_SKIP_CI_TOOLS_INSTALL:-0}" = "1" ]; then
  install_status="SKIP"
  echo "INFO: skipping CI tools installation (HZ_SKIP_CI_TOOLS_INSTALL=1)"
elif command -v apt-get >/dev/null 2>&1; then
  set +e
  bash .github/scripts/install_ci_tools.sh
  install_exit=$?
  set -e
  if [ "$install_exit" -eq 0 ]; then
    install_status="OK"
  else
    install_status="WARN"
    echo "WARN: tool installation failed; continuing with available tools"
  fi
else
  install_status="SKIP"
  echo "WARN: apt-get not available; install shellcheck/shfmt manually if needed"
fi

echo ""
echo "==> Bash lint"
set +e
bash .github/scripts/lint_bash.sh
lint_status=$?
set -e

echo ""
echo "==> Smoke selftest"
set +e
HZ_SMOKE_SELFTEST=1 bash tests/smoke.sh
selftest_status=$?
set -e

echo ""
echo "==> Smoke test (safe run)"
smoke_output_file="$(mktemp)"
set +e
GITHUB_OUTPUT="$smoke_output_file" HZ_CI_SMOKE=1 HZ_SMOKE_STRICT="$smoke_strict" bash tests/smoke.sh
smoke_exit_code=$?
set -e

if [ -f "$smoke_output_file" ]; then
  smoke_verdict="$(awk -F= '/^HZ_SMOKE_VERDICT=/ {print $2; exit}' "$smoke_output_file")"
  smoke_report_path="$(awk -F= '/^smoke_report_path=/ {print $2; exit}' "$smoke_output_file")"
  smoke_report_json_path="$(awk -F= '/^smoke_report_json_path=/ {print $2; exit}' "$smoke_output_file")"
fi

smoke_verdict="${smoke_verdict:-FAIL}"
smoke_report_path="${smoke_report_path:-unknown}"
smoke_report_json_path="${smoke_report_json_path:-unknown}"
rm -f "$smoke_output_file"

echo ""
echo "==> Enforce smoke verdict"
set +e
enforce_output="$(bash .github/scripts/smoke_gating.sh enforce --verdict "$smoke_verdict" --exit-code "$smoke_exit_code" --strict "$smoke_strict")"
enforce_status=$?
set -e

enforce_verdict="$(printf '%s' "$enforce_output" | sed -n 's/.*verdict=\([^ ]*\).*/\1/p')"
enforce_strict="$(printf '%s' "$enforce_output" | sed -n 's/.*strict=\([^ ]*\).*/\1/p')"
enforce_verdict="${enforce_verdict:-FAIL}"
enforce_strict="${enforce_strict:-false}"

final_verdict="$enforce_verdict"
final_exit="$enforce_status"
if [ "$lint_status" -ne 0 ] || [ "$selftest_status" -ne 0 ] || [ "$enforce_status" -ne 0 ]; then
  final_verdict="FAIL"
  final_exit=1
fi

echo ""
echo "==> CI parity summary"
echo "- install_tools: ${install_status}"
if [ "$lint_status" -eq 0 ]; then
  echo "- lint_bash: PASS"
else
  echo "- lint_bash: FAIL (exit=${lint_status})"
fi
if [ "$selftest_status" -eq 0 ]; then
  echo "- smoke_selftest: PASS"
else
  echo "- smoke_selftest: FAIL (exit=${selftest_status})"
fi
echo "- smoke_safe_run: verdict=${smoke_verdict} exit_code=${smoke_exit_code}"
echo "- smoke_reports: path=${smoke_report_path} json=${smoke_report_json_path}"
echo "- smoke_gate: verdict=${enforce_verdict} strict=${enforce_strict} exit_code=${enforce_status}"
echo "Result: ${final_verdict} (exit=${final_exit})"

exit "$final_exit"
