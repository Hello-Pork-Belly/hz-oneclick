#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mode="${E2E_MODE:-preflight}"
confirm_install="${E2E_CONFIRM_INSTALL:-}"
notes="${E2E_NOTES:-}"
log_dir="$(mktemp -d -t hz-e2e-logs-XXXXXXXX)"
log_dir_file="${E2E_LOG_DIR_FILE:-}"
log_file="${log_dir}/e2e_real_machine.log"

if [ -n "$log_dir_file" ]; then
  echo "$log_dir" > "$log_dir_file"
fi

exec > >(tee -a "$log_file") 2>&1

cd "$repo_root"

echo "==> Real-machine E2E"
echo "mode: $mode"
echo "notes: ${notes:-<none>}"
echo "log_dir: $log_dir"

echo ""
echo "==> Environment info"
uname -a
bash --version
if command -v df >/dev/null 2>&1; then
  df -h
else
  echo "WARN: df not available"
fi
if command -v free >/dev/null 2>&1; then
  free -h
else
  echo "INFO: free not available"
fi

echo ""
echo "==> Run local CI parity (always)"
if [ "$mode" = "preflight" ]; then
  export HZ_SKIP_CI_TOOLS_INSTALL=1
fi
bash .github/scripts/run_ci_locally.sh 2>&1 | tee "$log_dir/run_ci_locally.log"

echo ""
if [ "$mode" = "preflight" ]; then
  echo "==> Preflight checks (non-destructive)"
  missing=0
  for cmd in bash curl git; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "OK: $cmd"
    else
      echo "MISSING: $cmd (install it before using install mode)"
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    echo "Preflight failed: missing required commands."
    exit 1
  fi

  echo "Preflight checks passed."
  exit 0
fi

if [ "$mode" != "install" ]; then
  echo "ERROR: unknown mode '$mode' (expected preflight or install)"
  exit 1
fi

if [ "$confirm_install" != "I_UNDERSTAND_THIS_WILL_MODIFY_THE_MACHINE" ]; then
  echo "ERROR: install mode requires confirm_install='I_UNDERSTAND_THIS_WILL_MODIFY_THE_MACHINE'"
  exit 1
fi

echo "==> Install mode (guarded)"
INSTALL_CMD_PLACEHOLDER="echo 'TODO: run installer here'"
echo "About to run: $INSTALL_CMD_PLACEHOLDER"

bash -c "$INSTALL_CMD_PLACEHOLDER" 2>&1 | tee "$log_dir/install.log"
