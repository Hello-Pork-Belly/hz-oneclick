#!/usr/bin/env bash
# Version: v2.2.1
# Build: 2026-01-01
set -euo pipefail

INSTALL_DIR="/opt/hz-oneclick"
REPO_URL="https://github.com/Hello-Pork-Belly/hz-oneclick.git"

if [[ ! -d "./.git" || ! -f "./lib/common.sh" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y
      apt-get install -y git
    elif command -v yum >/dev/null 2>&1; then
      yum install -y git
    else
      echo "Unsupported package manager. Please install git manually." >&2
      exit 1
    fi
  fi

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    git -C "${INSTALL_DIR}" pull --ff-only
  else
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi

  chmod +x "${INSTALL_DIR}/hz.sh"
  cd "${INSTALL_DIR}" || exit 1
  exec "${INSTALL_DIR}/hz.sh" "$@"
fi

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMON_SH="${REPO_ROOT}/lib/common.sh"
OPS_MENU_SH="${REPO_ROOT}/lib/ops_menu_lib.sh"

if [[ ! -f "${COMMON_SH}" ]]; then
  echo "Missing required file: ${COMMON_SH}" >&2
  echo "REPO_ROOT: ${REPO_ROOT}" >&2
  exit 1
fi

# shellcheck source=lib/common.sh
source "${COMMON_SH}"

if [[ ! -f "${OPS_MENU_SH}" ]]; then
  echo "Warning: Missing optional file: ${OPS_MENU_SH}" >&2
  show_ops_menu() {
    echo "Ops menu unavailable: ${OPS_MENU_SH} missing." >&2
  }
else
  # shellcheck source=lib/ops_menu_lib.sh
  source "${OPS_MENU_SH}"
fi

while true; do
  echo ""
  echo "==== hz-oneclick ===="
  echo "1) run WP module"
  echo "2) run ops center"
  echo "3) diagnostics"
  echo "0) exit"
  read -r -p "Select: " choice

  case "${choice}" in
    1)
      bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
      ;;
    2)
      show_ops_menu
      ;;
    3)
      bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh"
      ;;
    0)
      exit 0
      ;;
    *)
      echo "Invalid option. Please try again."
      ;;
  esac

done
