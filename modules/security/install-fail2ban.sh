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

detect_ols_access_logs() {
  local logs=()
  local path
  local found=false

  if [[ -r /usr/local/lsws/logs/access.log ]]; then
    logs+=("/usr/local/lsws/logs/access.log")
    found=true
  fi

  if [[ "${found}" == false ]]; then
    while IFS= read -r path; do
      if [[ -r "${path}" ]]; then
        logs+=("${path}")
      fi
    done < <(find /var/www -maxdepth 4 -type f -name "access.log" 2>/dev/null)

    while IFS= read -r path; do
      if [[ -r "${path}" ]]; then
        logs+=("${path}")
      fi
    done < <(find /usr/local/lsws -maxdepth 6 -type f -name "access.log" 2>/dev/null)
  fi

  declare -A seen=()
  local filtered=()
  local count=0
  local non_empty=()
  local readable=()

  for path in "${logs[@]}"; do
    if [[ -n "${path}" && -z "${seen["${path}"]+x}" ]]; then
      seen["${path}"]=1
      if [[ -s "${path}" ]]; then
        non_empty+=("${path}")
      else
        readable+=("${path}")
      fi
    fi
  done

  if [[ ${#non_empty[@]} -gt 0 ]]; then
    for path in "${non_empty[@]}"; do
      filtered+=("${path}")
      count=$((count + 1))
      if [[ ${count} -ge 5 ]]; then
        break
      fi
    done
  fi

  if [[ ${#filtered[@]} -lt 5 && ${#readable[@]} -gt 0 ]]; then
    for path in "${readable[@]}"; do
      filtered+=("${path}")
      count=$((count + 1))
      if [[ ${count} -ge 5 ]]; then
        break
      fi
    done
  fi

  if [[ ${#filtered[@]} -gt 0 ]]; then
    OLS_LOGS_FOUND=true
  else
    log_warn "No readable OLS access logs detected. Falling back to /usr/local/lsws/logs/access.log."
    filtered+=("/usr/local/lsws/logs/access.log")
  fi

  printf '%s\n' "${filtered[@]}"
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
  local jail_local="/etc/fail2ban/jail.local"
  local marker_begin="# HZ-ONECLICK FAIL2BAN BEGIN"
  local marker_end="# HZ-ONECLICK FAIL2BAN END"
  local tmp_file
  local timestamp
  local banaction
  local backend
  local logpaths
  local logpath_lines=""

  timestamp=$(date +%Y%m%d%H%M%S)
  banaction=$(detect_banaction)
  backend=$(is_systemd_backend)

  if [[ -f "${jail_local}" ]]; then
    cp "${jail_local}" "${jail_local}.${timestamp}.bak"
    log_info "Backed up existing jail.local to ${jail_local}.${timestamp}.bak"
  fi

  logpaths=$(detect_ols_access_logs)
  while IFS= read -r path; do
    if [[ -n "${path}" ]]; then
      logpath_lines+="logpath = ${path}"$'\n'
    fi
  done <<< "${logpaths}"

  tmp_file=$(mktemp)
  if [[ -f "${jail_local}" ]]; then
    awk -v begin="${marker_begin}" -v end="${marker_end}" '
      $0 == begin {inblock=1; next}
      $0 == end {inblock=0; next}
      !inblock {print}
    ' "${jail_local}" > "${tmp_file}"
  fi

  {
    if [[ -s "${tmp_file}" ]]; then
      cat "${tmp_file}"
      echo
    fi
    cat <<EOF
${marker_begin}
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
banaction = ${banaction}
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
enabled = true
port = http,https
filter = wordpress-hard
maxretry = 5
findtime = 10m
bantime = 1h
${logpath_lines}${marker_end}
EOF
  } > "${jail_local}"

  rm -f "${tmp_file}"
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
  restart_fail2ban_service

  log_info "Detected OLS access logs:"
  detect_ols_access_logs | sed 's/^/  - /'

  if [[ "${OLS_LOGS_FOUND}" == false ]]; then
    log_warn "wordpress-hard jail enabled but no readable OLS access log found. Please verify OLS access log path and rerun."
  fi

  print_status
}

main "$@"
