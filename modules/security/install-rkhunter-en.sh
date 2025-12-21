#!/usr/bin/env bash
# install-rkhunter-en.sh v0.1
# Install rkhunter and basic check (English)

set -euo pipefail
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL:-https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main}"
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL%/}"

### helpers ###

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }

info()  { green  "[INFO] $*"; }
warn()  { yellow "[WARN] $*"; }
erro()  { red    "[ERROR] $*"; }

press_enter_to_continue() {
  read -rp "Press Enter to continue ... " _
}

prompt_exit_hint() {
  yellow "You can type Ctrl+C at any time to abort this wizard."
  echo
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    erro "Please run this script as root (sudo)!"
    exit 1
  fi
}

step() {
  cyan "======================"
  cyan "$*"
  cyan "======================"
  echo
}

### main steps ###

step "Step 1/4 - Intro & environment check"
prompt_exit_hint
require_root

info "This wizard will:"
echo "  - Install or update rkhunter"
echo "  - Run a basic self-check"
echo "  - Optionally continue to schedule daily checks + email alerts"
echo

press_enter_to_continue

step "Step 2/4 - Install / update rkhunter"

if ! command -v apt-get >/dev/null 2>&1; then
  erro "This script currently supports Debian/Ubuntu (apt-get) only."
  exit 1
fi

info "Updating package index ..."
apt-get update -y

info "Installing rkhunter ..."
apt-get install -y rkhunter

if ! command -v rkhunter >/dev/null 2>&1; then
  erro "rkhunter command not found after installation. Please check manually."
  exit 1
fi

info "rkhunter executable: $(command -v rkhunter)"
echo
press_enter_to_continue

step "Step 3/4 - Quick rkhunter self-check"

info "Running: rkhunter --versioncheck ..."
if ! rkhunter --versioncheck --nocolors || true; then
  warn "rkhunter --versioncheck returned a non-zero exit code. This is not always critical."
fi
echo

info "Running: rkhunter --config-check ..."
if ! rkhunter --config-check --nocolors || true; then
  warn "rkhunter --config-check reported issues. Check the output and /etc/rkhunter.conf."
fi
echo

press_enter_to_continue

step "Step 4/4 - Summary & next steps"

info "rkhunter has been installed."
echo
echo "Recommended next steps:"
echo "  1) Configure a daily check + mail alert using:"
echo "     hz-oneclick  ->  Security  ->  rkhunter cron & mail (English)"
echo "     (script: modules/security/setup-rkhunter-cron-en.sh)"
echo
echo "Menu options:"
echo "  1) Run the scheduling wizard now (setup-rkhunter-cron-en.sh)"
echo "  2) Return to hz-oneclick main menu"
echo "  0) Exit this script"
echo

read -rp "Please enter your choice [1/2/0]: " choice
case "$choice" in
  1)
    info "Launching rkhunter scheduling wizard ..."
    bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/setup-rkhunter-cron-en.sh")
    ;;
  2)
    info "Returning to hz-oneclick main menu ..."
    ;;
  0)
    info "Exit."
    ;;
  *)
    warn "Invalid choice, exiting."
    ;;
esac
