#!/usr/bin/env bash
set -euo pipefail

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    log_error "Please run this script as root."
    exit 1
  fi
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    echo ""
  fi
}

install_fail2ban() {
  local pm
  pm=$(detect_package_manager)

  if [[ -z "${pm}" ]]; then
    log_error "No supported package manager found (apt-get/dnf/yum)."
    exit 1
  fi

  if command -v fail2ban-client >/dev/null 2>&1; then
    log_info "fail2ban already installed. Skipping installation."
    return
  fi

  log_info "Installing fail2ban using ${pm}..."
  case "${pm}" in
    apt-get)
      apt-get update -y
      apt-get install -y fail2ban
      ;;
    dnf)
      dnf install -y fail2ban
      ;;
    yum)
      yum install -y fail2ban
      ;;
    *)
      log_error "Unsupported package manager: ${pm}"
      exit 1
      ;;
  esac
}

enable_fail2ban_service() {
  if command -v systemctl >/dev/null 2>&1; then
    log_info "Enabling and starting fail2ban service."
    systemctl enable --now fail2ban
  elif command -v service >/dev/null 2>&1; then
    log_info "Starting fail2ban service via service command."
    service fail2ban start
  else
    log_warn "No service manager detected; cannot enable fail2ban automatically."
  fi
}

restart_fail2ban_service() {
  if command -v systemctl >/dev/null 2>&1; then
    log_info "Restarting fail2ban service."
    systemctl restart fail2ban
  elif command -v service >/dev/null 2>&1; then
    log_info "Restarting fail2ban service via service command."
    service fail2ban restart
  else
    log_warn "No service manager detected; cannot restart fail2ban automatically."
  fi
}

is_systemd_backend() {
  if [[ -d /run/systemd/system ]]; then
    echo "systemd"
  else
    echo "auto"
  fi
}

detect_banaction() {
  if command -v nft >/dev/null 2>&1; then
    echo "nftables-multiport"
  else
    echo "iptables-multiport"
  fi
}

OLS_LOGS_FOUND=false
OLS_LOG_SELECTED=""

detect_ols_access_logs() {
  local primary_log="/usr/local/lsws/logs/access.log"
  local path
  local selected=""

  if [[ -r "${primary_log}" ]]; then
    selected="${primary_log}"
  fi

  if [[ -z "${selected}" ]]; then
    for path in /usr/local/lsws/conf/vhosts/*/logs/access.log; do
      if [[ -e "${path}" && -r "${path}" ]]; then
        selected="${path}"
        break
      fi
    done
  fi

  if [[ -z "${selected}" ]]; then
    for path in /var/www/*/logs/access.log; do
      if [[ -e "${path}" && -r "${path}" ]]; then
        selected="${path}"
        break
      fi
    done
  fi

  if [[ -n "${selected}" ]]; then
    OLS_LOGS_FOUND=true
    OLS_LOG_SELECTED="${selected}"
    log_info "Selected OLS access log: ${selected}"
    printf '%s\n' "${selected}"
    return 0
  fi

  OLS_LOGS_FOUND=false
  OLS_LOG_SELECTED="${primary_log}"
  log_warn "OLS access log could not be auto-detected using standard paths."
  log_warn "Falling back to default log path: ${primary_log}"
  printf '%s\n' "${primary_log}"
  return 0
}

write_wordpress_filter() {
  local filter_dir="/etc/fail2ban/filter.d"
  local filter_file="${filter_dir}/wordpress-hard.conf"

  log_info "Writing WordPress hard filter to ${filter_file}."
  mkdir -p "${filter_dir}"
  cat > "${filter_file}" <<'EOF'
[Definition]
failregex = ^<HOST>\s+\S+\s+\S+\s+\[[^\]]+\]\s+"POST\s+/(wp-login\.php|xmlrpc\.php)(\?[^\s"]*)?\s+HTTP/[^\"]+"\s+\d{3}\s+
ignoreregex =
EOF
}

write_jail_local() {
  local jail_local="/etc/fail2ban/jail.d/99-hz-oneclick.local"
  local banaction
  local backend
  local logpath=""
  local wordpress_enabled="false"
  local wordpress_logpath_line="# logpath = /path/to/ols/access.log"
  local wordpress_note="# NOTE: set logpath and enabled=true to activate wordpress-hard jail."

  banaction=$(detect_banaction)
  backend=$(is_systemd_backend)

  if detect_ols_access_logs; then
    logpath="${OLS_LOG_SELECTED}"
  fi

  if [[ -n "${logpath}" ]]; then
    wordpress_enabled="true"
    wordpress_logpath_line="logpath = ${logpath}"
    wordpress_note=""
  fi

  log_info "Writing fail2ban overlay to ${jail_local}."
  mkdir -p "$(dirname "${jail_local}")"
  cat > "${jail_local}" <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
banaction = ${banaction}
action = ${banaction}
backend = ${backend}
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 3
bantime = 1h
findtime = 10m

[wordpress-hard]
enabled = ${wordpress_enabled}
port = http,https
filter = wordpress-hard
maxretry = 5
findtime = 10m
bantime = 1h
${wordpress_note}
${wordpress_logpath_line}
EOF
}

print_status() {
  log_info "fail2ban-client ping:"
  if fail2ban-client ping; then
    :
  else
    log_warn "fail2ban-client ping failed."
  fi

  log_info "fail2ban-client status:"
  if fail2ban-client status; then
    :
  else
    log_warn "fail2ban-client status failed."
  fi

  log_info "fail2ban-client status sshd:"
  if fail2ban-client status sshd; then
    :
  else
    log_warn "sshd jail status not available."
  fi

  log_info "fail2ban-client status wordpress-hard:"
  if fail2ban-client status wordpress-hard; then
    :
  else
    log_warn "wordpress-hard jail status not available."
  fi
}

main() {
  require_root

  install_fail2ban
  enable_fail2ban_service
  write_wordpress_filter
  write_jail_local

  log_info "Reloading fail2ban configuration."
  if fail2ban-client reload; then
    :
  else
    log_warn "fail2ban-client reload failed; restarting service."
    restart_fail2ban_service
  fi

  print_status
}

main "$@"
