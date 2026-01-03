#!/usr/bin/env bash
# Horizon OneClick - Bootstrap Loader (v2.2.0)
set -Eeo pipefail

INSTALL_DIR="/opt/hz-oneclick"
REPO_URL="https://github.com/Hello-Pork-Belly/hz-oneclick.git"

# --- Bootstrap Logic (Curl Mode) ---
if [[ ! -d ".git" ]] && [[ ! -f "lib/common.sh" ]]; then
    echo ">>> Running in Bootstrap Mode..."
    if [[ $EUID -ne 0 ]]; then echo "Error: Run as root."; exit 1; fi

    # Install Git
    command -v git >/dev/null || {
        echo ">>> Installing Git..."
        if command -v apt-get >/dev/null; then apt-get update && apt-get install -y git; fi
        if command -v yum >/dev/null; then yum install -y git; fi
    }

    # Clone Repo
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        echo ">>> Updating repo..."
        git -C "$INSTALL_DIR" pull
    else
        echo ">>> Cloning repo..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi

    # Handover
    echo ">>> Launching installer..."
    chmod +x "$INSTALL_DIR/hz.sh"
    exec "$INSTALL_DIR/hz.sh" "$@"
fi

# --- Main Logic (Repo Mode) ---
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${REPO_ROOT}/lib/common.sh"
[[ -f "${REPO_ROOT}/lib/ops_menu_lib.sh" ]] && source "${REPO_ROOT}/lib/ops_menu_lib.sh"

show_header
echo "1) Install LOMP Stack"
echo "2) Ops & Security Center"
echo "3) Diagnostics"
echo "0) Exit"
read -r -p "Select: " choice

case "$choice" in
    1) bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh" ;;
    2) show_ops_menu ;;
    3) bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh" ;;
    0) exit 0 ;;
esac
