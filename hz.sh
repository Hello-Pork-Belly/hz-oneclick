#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This bootstrap must be run as root." >&2
    exit 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      apt-get install -y git
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y git
    elif command -v yum >/dev/null 2>&1; then
      yum install -y git
    elif command -v pacman >/dev/null 2>&1; then
      pacman -Sy --noconfirm git
    else
      echo "No supported package manager found to install git." >&2
      exit 1
    fi
  fi

  if [[ -d "/opt/hz-oneclick/.git" ]]; then
    exec "/opt/hz-oneclick/hz.sh"
  fi

  git clone https://github.com/Hello-Pork-Belly/hz-oneclick.git /opt/hz-oneclick
  exec "/opt/hz-oneclick/hz.sh"
fi

export REPO_ROOT="${SCRIPT_DIR}"

source "${REPO_ROOT}/lib/common.sh"
source "${REPO_ROOT}/lib/ops_menu_lib.sh"

main_menu() {
  local choice

  while true; do
    echo
    echo "=== HZ OneClick 主菜单 ==="
    echo "  1) Install LOMP"
    echo "  2) Ops Center"
    echo "  3) Triage"
    echo "  0) Exit"
    read -r -p "请输入选项 [0-3]: " choice

    case "$choice" in
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
        echo "无效选项，请重试。"
        ;;
    esac
  done
}

main_menu
