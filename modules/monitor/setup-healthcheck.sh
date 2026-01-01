#!/usr/bin/env bash
set -Eeuo pipefail

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok() { printf '[OK] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }
log_err() { printf '[ERR] %s\n' "$*"; }

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log_err "请以 root 身份运行该脚本。"
    exit 1
  fi
}

ensure_mail() {
  if command -v mail >/dev/null 2>&1; then
    return 0
  fi
  log_warn "未检测到 mail 命令，正在安装 mailutils..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y mailutils
  if ! command -v mail >/dev/null 2>&1; then
    log_err "mail 命令仍不可用，请检查系统。"
    exit 1
  fi
  log_ok "mailutils 安装完成。"
}

discover_admin_email() {
  local detected=""
  if [[ -f /usr/local/bin/hz-backup.sh ]]; then
    detected=$(awk -F= '/^ADMIN_EMAIL=/{gsub(/"/"",$2);print $2;exit}' /usr/local/bin/hz-backup.sh || true)
  fi
  if [[ -z "$detected" && -f /etc/hz-oneclick/backup.conf ]]; then
    detected=$(awk -F= '/^ADMIN_EMAIL=/{gsub(/"/"",$2);print $2;exit}' /etc/hz-oneclick/backup.conf || true)
  fi
  printf '%s' "$detected"
}

prompt_admin_email() {
  local detected="$1"
  local prompt_default=""
  if [[ -n "$detected" ]]; then
    prompt_default="default: $detected"
  fi
  while true; do
    if [[ -n "$prompt_default" ]]; then
      read -r -p "告警收件人邮箱 Admin Email [$prompt_default]: " admin_email
    else
      read -r -p "告警收件人邮箱 Admin Email [default: ]: " admin_email
    fi
    if [[ -z "$admin_email" && -n "$detected" ]]; then
      admin_email="$detected"
    fi
    if [[ -n "$admin_email" && "$admin_email" == *"@"* && "$admin_email" == *"."* ]]; then
      printf '%s' "$admin_email"
      return 0
    fi
    log_warn "邮箱格式不正确，请重新输入。"
  done
}

install_runner() {
  local admin_email="$1"

  cat <<'RUNNER_EOF' > /usr/local/bin/hz-healthcheck.sh
#!/usr/bin/env bash
set -Eeuo pipefail

ADMIN_EMAIL="__ADMIN_EMAIL__"
LOG_FILE="/var/log/hz-healthcheck.log"
DISK_FAIL_PCT=90
LOAD_WARN_MULT=2
DOCKER_CRITICAL_CONTAINERS=("mariadb" "redis")
TAILSCALE_REQUIRED=0

if [[ -f /etc/hz-oneclick/healthcheck.conf ]]; then
  # 可在此文件中覆盖上述变量，例如 DOCKER_CRITICAL_CONTAINERS 与 TAILSCALE_REQUIRED
  # shellcheck disable=SC1091
  source /etc/hz-oneclick/healthcheck.conf
fi

log_line() {
  local message="$1"
  printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "$LOG_FILE"
}

acquire_lock() {
  exec 200>/var/lock/hz-healthcheck.lock
  if ! flock -n 200; then
    log_line "已有健康检查在运行，退出。"
    exit 0
  fi
}

STATUS="OK"
DETAILS=()

set_status() {
  local new_status="$1"
  if [[ "$STATUS" == "FAILURE" ]]; then
    return 0
  fi
  if [[ "$STATUS" == "WARNING" && "$new_status" == "OK" ]]; then
    return 0
  fi
  STATUS="$new_status"
}

add_detail() {
  DETAILS+=("$1")
}

check_disk() {
  local pct
  pct=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  if [[ -z "$pct" || ! "$pct" =~ ^[0-9]+$ ]]; then
    set_status "FAILURE"
    add_detail "磁盘使用率获取失败。"
    return
  fi
  if (( pct >= DISK_FAIL_PCT )); then
    set_status "FAILURE"
    add_detail "Disk usage /: ${pct}% >= ${DISK_FAIL_PCT}%"
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi
  if ! docker info >/dev/null 2>&1; then
    set_status "FAILURE"
    add_detail "Docker daemon not reachable"
    return 0
  fi

  local name
  for name in "${DOCKER_CRITICAL_CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -Fx "$name" >/dev/null 2>&1; then
      continue
    fi
    if docker ps --format '{{.Image}}' | grep -i "$name" >/dev/null 2>&1; then
      continue
    fi
    set_status "FAILURE"
    add_detail "Docker container missing/not running: ${name}"
  done
}

check_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    return 0
  fi
  local status_output
  if ! status_output=$(tailscale status 2>&1 | head -n 5); then
    if [[ "$TAILSCALE_REQUIRED" -eq 1 ]]; then
      set_status "FAILURE"
    else
      set_status "WARNING"
    fi
    add_detail "Tailscale 状态异常：\n${status_output}"
    return
  fi
  if printf '%s' "$status_output" | grep -qiE 'stopped|logged out|no peers'; then
    if [[ "$TAILSCALE_REQUIRED" -eq 1 ]]; then
      set_status "FAILURE"
    else
      set_status "WARNING"
    fi
    add_detail "Tailscale 状态异常：\n${status_output}"
  fi
}

check_load() {
  local cores load15 threshold
  cores=$(nproc)
  load15=$(awk '{print $3}' /proc/loadavg)
  threshold=$((cores * LOAD_WARN_MULT))
  if awk "BEGIN{exit !($load15 > $threshold)}"; then
    set_status "WARNING"
    add_detail "Load15 ${load15} > threshold ${threshold}"
  fi
}

send_alert() {
  if [[ -z "$ADMIN_EMAIL" ]]; then
    log_line "未设置 ADMIN_EMAIL，无法发送邮件。"
    exit 2
  fi
  if ! command -v mail >/dev/null 2>&1; then
    log_line "mail 命令不可用，无法发送邮件。"
    exit 2
  fi

  local subject body
  subject="Health Check Alert: $(hostname) [${STATUS}]"
  body=$(cat <<BODY
主机：$(hostname)
时间：$(date '+%F %T')
运行时间：$(uptime -p)
内核：$(uname -r)
IP：$(hostname -I 2>/dev/null || true)

异常详情：
$(printf '%s\n' "${DETAILS[@]}")

日志末尾（80 行）：
$(tail -n 80 "$LOG_FILE" 2>/dev/null || true)
BODY
)

  mail -s "$subject" "$ADMIN_EMAIL" <<< "$body"
}

main() {
  acquire_lock

  check_disk
  check_docker
  check_tailscale
  check_load

  if [[ "$STATUS" == "OK" ]]; then
    log_line "OK"
    exit 0
  fi

  log_line "${STATUS}: ${DETAILS[*]}"
  send_alert

  if [[ "$STATUS" == "WARNING" ]]; then
    exit 1
  fi
  exit 2
}

main "$@"
RUNNER_EOF

  sed -i "s|__ADMIN_EMAIL__|${admin_email}|" /usr/local/bin/hz-healthcheck.sh
  chmod 755 /usr/local/bin/hz-healthcheck.sh
}

ensure_log_file() {
  touch /var/log/hz-healthcheck.log
  if chown root:adm /var/log/hz-healthcheck.log 2>/dev/null; then
    chmod 640 /var/log/hz-healthcheck.log
  else
    chown root:root /var/log/hz-healthcheck.log
    chmod 640 /var/log/hz-healthcheck.log
  fi
}

setup_cron() {
  local cron_line="0 8 * * * /usr/local/bin/hz-healthcheck.sh"
  local current
  current=$(crontab -l 2>/dev/null || true)
  if ! printf '%s\n' "$current" | grep -F '/usr/local/bin/hz-healthcheck.sh' >/dev/null 2>&1; then
    printf '%s\n%s\n' "$current" "$cron_line" | crontab -
  fi
  printf '%s' "$cron_line"
}

main() {
  require_root
  ensure_mail

  local detected admin_email cron_line
  detected=$(discover_admin_email)
  admin_email=$(prompt_admin_email "$detected")

  install_runner "$admin_email"
  ensure_log_file
  cron_line=$(setup_cron)

  log_ok "已配置 Cron：${cron_line}"
  /usr/local/bin/hz-healthcheck.sh || true
  log_ok "健康检查已部署：仅在异常时发送邮件（Silence is golden）"
  log_ok "日志路径：/var/log/hz-healthcheck.log"
}

main "$@"
