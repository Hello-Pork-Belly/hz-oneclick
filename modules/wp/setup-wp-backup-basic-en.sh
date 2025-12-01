#!/usr/bin/env bash
# WordPress backup setup script (English version)
# - Create /usr/local/bin/wp-backup-<SITE>.sh
# - Create systemd service + timer
# - Support rclone remote + optional msmtp email alerts

set -euo pipefail

CYAN="\e[36m"
YELLOW="\e[33m"
NC="\e[0m"

SITE=""
WP_ROOT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
DB_HOST_ONLY=""
DB_PORT_ONLY=""
BACKUP_BASE=""
RCLONE_REMOTE=""
LOCAL_KEEP_DAYS=""
REMOTE_KEEP_DAYS=""
BACKUP_TIME=""
ALERT_EMAIL_INPUT=""

#--------------------------------------------------
# 0) Must run as root
#--------------------------------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root (needs to write /usr/local/bin and /etc/systemd/system)." >&2
  exit 1
fi

echo "=============================================="
echo " WordPress backup setup (DB + files)"
echo "=============================================="
echo

# Short feature description
echo -e "${CYAN}Features${NC}"
echo "  - Local + remote (rclone) backups (default: local 7 days, remote 30 days)"
echo "  - Use rclone to push directly to OneDrive / Google Drive / other remotes"
echo "  - Create systemd service + timer to run daily backups"
echo "  - Optional: integrate msmtp + Brevo to send email alerts on failure"
echo

#--------------------------------------------------
# [1/7] Site info
#--------------------------------------------------
echo "[1/7] Site info"
echo "Site ID will be used as:"
echo "  - Backup script: /usr/local/bin/wp-backup-<SiteID>.sh"
echo "  - Local backup base: /root/backups/<SiteID>/..."
echo "Suggested: lowercase letters / digits / dash, for example: nzf / hz / blog1"
read -rp "Site ID: " SITE
SITE="${SITE// /}"   # strip spaces

if [[ -z "$SITE" ]]; then
  echo "[!] Site ID cannot be empty. Aborted." >&2
  exit 1
fi

DEFAULT_WP_ROOT="/var/www/${SITE}/html"
echo
echo "Example WordPress root: /var/www/your-site/html"
echo "Press Enter to use default: ${DEFAULT_WP_ROOT}"
read -rp "WordPress root [${DEFAULT_WP_ROOT}] : " WP_ROOT
WP_ROOT="${WP_ROOT:-$DEFAULT_WP_ROOT}"

if [[ ! -d "$WP_ROOT" ]]; then
  echo "[!] Directory not found: ${WP_ROOT}"
  echo "    Please double-check your WordPress path and run again."
  exit 1
fi

#--------------------------------------------------
# [2/7] Database settings
#--------------------------------------------------
echo
echo "[2/7] Database settings"
echo "Tip: On the server you can run:"
echo "  grep -E \"DB_(NAME|USER|PASSWORD|HOST)\" ${WP_ROOT}/wp-config.php"
echo "Then copy DB_NAME / DB_USER / DB_PASSWORD / DB_HOST from the output."
echo
echo "Password input will NOT be shown on screen. This is normal."
echo

read -rp "DB name (DB_NAME in wp-config.php): " DB_NAME
read -rp "DB username (DB_USER in wp-config.php): " DB_USER
read -rsp "DB password (DB_PASSWORD in wp-config.php): " DB_PASS
echo
echo "For DB host, please input exactly the value in DB_HOST, e.g.:"
echo "  127.0.0.1"
echo "  127.0.0.1:3306"
echo "The script will automatically split host and port. No need to modify manually."
read -rp "DB host (DB_HOST in wp-config.php): " DB_HOST

if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_HOST" ]]; then
  echo "[!] Incomplete DB info. Aborted." >&2
  exit 1
fi

DB_HOST_ONLY="$DB_HOST"
DB_PORT_ONLY="3306"
if [[ "$DB_HOST" == *:* ]]; then
  DB_HOST_ONLY="${DB_HOST%%:*}"
  DB_PORT_ONLY="${DB_HOST##*:}"
fi

#--------------------------------------------------
# [3/7] Local backup base
#--------------------------------------------------
echo
echo "[3/7] Local backup base"
DEFAULT_BACKUP_BASE="/root/backups/${SITE}"
echo "Local backups will be stored under date-based subdirectories, for example:"
echo "  ${DEFAULT_BACKUP_BASE}/2025-12-01_031500/"
echo "Press Enter to use default: ${DEFAULT_BACKUP_BASE}"
read -rp "Local backup base [${DEFAULT_BACKUP_BASE}] : " BACKUP_BASE
BACKUP_BASE="${BACKUP_BASE:-$DEFAULT_BACKUP_BASE}"
mkdir -p "$BACKUP_BASE"

#--------------------------------------------------
# [4/7] rclone remote path
#--------------------------------------------------
echo
echo "[4/7] rclone remote path"

if ! command -v rclone >/dev/null 2>&1; then
  echo "[!] rclone not found. Please install and configure at least one remote first:"
  echo "    rclone config"
  exit 1
fi

echo "Detected rclone remotes:"
rclone listremotes 2>/dev/null || echo "  (No remotes configured yet. Please run 'rclone config' first.)"
echo
echo "Examples:"
echo "  gdrive:${SITE}"
echo "  onedrive:${SITE}"
echo "  myremote:backups/${SITE}"
read -rp "rclone target (without date subdirectory) : " RCLONE_REMOTE

if [[ -z "$RCLONE_REMOTE" ]]; then
  echo "[!] rclone target cannot be empty. Aborted." >&2
  exit 1
fi

REMOTE_NAME="${RCLONE_REMOTE%%:*}"
if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
  echo -e "${YELLOW}[!] Warning: remote \"${REMOTE_NAME}:\" not found in rclone config. Please confirm.${NC}"
fi

#--------------------------------------------------
# [5/7] Retention policy
#--------------------------------------------------
echo
echo "[5/7] Retention policy"
echo "Default:"
echo "  - Local: keep 7 days"
echo "  - Remote: keep 30 days"
read -rp "Local retention days [7] : " LOCAL_KEEP_DAYS
read -rp "Remote retention days [30] : " REMOTE_KEEP_DAYS

LOCAL_KEEP_DAYS="${LOCAL_KEEP_DAYS:-7}"
REMOTE_KEEP_DAYS="${REMOTE_KEEP_DAYS:-30}"

if ! [[ "$LOCAL_KEEP_DAYS" =~ ^[0-9]+$ ]]; then
  echo -e "${YELLOW}[!] Invalid local retention. Use default 7 days.${NC}"
  LOCAL_KEEP_DAYS="7"
fi
if ! [[ "$REMOTE_KEEP_DAYS" =~ ^[0-9]+$ ]]; then
  echo -e "${YELLOW}[!] Invalid remote retention. Use default 30 days.${NC}"
  REMOTE_KEEP_DAYS="30"
fi

#--------------------------------------------------
# [6/7] Daily backup time (server time / usually UTC)
#--------------------------------------------------
echo
echo "[6/7] Daily backup time"
echo "Note: This is *server time*. On most VPS, this is UTC."
echo "Example:"
echo "  03:30  → backup runs every day at 03:30 (UTC)."
read -rp "Daily backup time (HH:MM, 24h) [03:30] : " BACKUP_TIME
BACKUP_TIME="${BACKUP_TIME:-03:30}"

if ! [[ "$BACKUP_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo -e "${YELLOW}[!] Invalid time format. Use default 03:30.${NC}"
  BACKUP_TIME="03:30"
fi

#--------------------------------------------------
# [7/7] Email alert (msmtp)
#--------------------------------------------------
echo
echo "[7/7] Email alert (msmtp)"

MSMTP_AVAILABLE="false"
if command -v msmtp >/dev/null 2>&1 && [[ -f /etc/msmtprc ]]; then
  MSMTP_AVAILABLE="true"
fi

if [[ "$MSMTP_AVAILABLE" == "true" ]]; then
  echo "msmtp is detected and /etc/msmtprc exists."
  echo "You can enable email alerts when backup fails."
  read -rp "Enable email alerts? [y/N] : " enable_alert
  if [[ "$enable_alert" =~ ^[Yy]$ ]]; then
    read -rp "Alert email address (e.g. you@example.com): " ALERT_EMAIL_INPUT
  else
    ALERT_EMAIL_INPUT=""
  fi
else
  echo -e "${YELLOW}[!] msmtp or /etc/msmtprc not found.${NC}"
  echo "It is recommended to install & configure email sending first"
  echo "(for example, via HorizonTech one-click menu: 7) Email alert (msmtp + Brevo))."
  read -rp "Continue and create backup script WITHOUT email alerts? [Y/n] : " cont
  if [[ "$cont" =~ ^[Nn]$ ]]; then
    echo "Cancelled WordPress backup module installation."
    exit 0
  fi
  ALERT_EMAIL_INPUT=""
fi

#--------------------------------------------------
# Generate backup script + systemd units
#--------------------------------------------------
BACKUP_SCRIPT="/usr/local/bin/wp-backup-${SITE}.sh"
SERVICE_FILE="/etc/systemd/system/wp-backup-${SITE}.service"
TIMER_FILE="/etc/systemd/system/wp-backup-${SITE}.timer"

cat >"$BACKUP_SCRIPT" <<EOF
#!/usr/bin/env bash
# Auto-generated WordPress backup script for site: ${SITE}

set -uo pipefail

SITE="${SITE}"
WP_ROOT="${WP_ROOT}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_HOST_ONLY="${DB_HOST_ONLY}"
DB_PORT_ONLY="${DB_PORT_ONLY}"
BACKUP_BASE="${BACKUP_BASE}"
RCLONE_REMOTE="${RCLONE_REMOTE}"
LOCAL_KEEP_DAYS="${LOCAL_KEEP_DAYS}"
REMOTE_KEEP_DAYS="${REMOTE_KEEP_DAYS}"

ALERT_EMAIL="${ALERT_EMAIL_INPUT}"    # Alert receiver (can be empty)
SEND_SUCCESS_MAIL="false"             # Default: send mail on FAILURE only; set true if you want OK mails too

LOG_FILE="/var/log/wp-backup-\${SITE}.log"
mkdir -p "\$(dirname "\${LOG_FILE}")"
touch "\${LOG_FILE}"

LOG_TAG="[wp-backup:\${SITE}]"
BACKUP_TIME_UTC="\$(date -u '+%Y-%m-%d %H:%M:%S (UTC)')"

STATUS=0

run() {
  echo "\${LOG_TAG} RUN: \$*" | tee -a "\${LOG_FILE}"
  "\$@" || {
    local rc=\$?
    echo "\${LOG_TAG} ERROR(rc=\${rc}): \$*" | tee -a "\${LOG_FILE}"
    STATUS=\${rc}
  }
}

send_mail() {
  local subject="\$1"
  local body="\$2"

  [ -z "\${ALERT_EMAIL}" ] && return 0
  if ! command -v msmtp >/dev/null 2>&1; then
    echo "\${LOG_TAG} msmtp not found, skip mail" | tee -a "\${LOG_FILE}"
    return 0
  fi

  printf "%b" "\$body" | msmtp "\${ALERT_EMAIL}" || echo "\${LOG_TAG} failed to send mail" | tee -a "\${LOG_FILE}"
}

echo "==== \${BACKUP_TIME_UTC} ====" >> "\${LOG_FILE}"

TIMESTAMP=\$(date +'%Y-%m-%d_%H%M%S')
WORK_DIR="\${BACKUP_BASE}/\${TIMESTAMP}"

DB_FILE="\${WORK_DIR}/db_\${TIMESTAMP}.sql.gz"
FILES_FILE="\${WORK_DIR}/html_\${TIMESTAMP}.tgz"

echo "\${LOG_TAG} create local directory: \${WORK_DIR}" | tee -a "\${LOG_FILE}"
mkdir -p "\${WORK_DIR}"

# Backup DB
run mysqldump -h "\${DB_HOST_ONLY}" -P "\${DB_PORT_ONLY}" -u "\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" | gzip -c > "\${DB_FILE}"

# Backup WordPress files
run tar -C "\${WP_ROOT}" -czf "\${FILES_FILE}" .

REMOTE_TARGET="\${RCLONE_REMOTE}/\${TIMESTAMP}"
# Copy to remote
run rclone copy "\${WORK_DIR}" "\${REMOTE_TARGET}" --create-empty-src-dirs

# Clean old remote backups
run rclone delete "\${RCLONE_REMOTE}" --min-age "\${REMOTE_KEEP_DAYS}d"
run rclone rmdirs "\${RCLONE_REMOTE}" --leave-root

# Clean old local backups
run find "\${BACKUP_BASE}" -maxdepth 1 -type d -name "20*" -mtime +\${LOCAL_KEEP_DAYS} -print -exec rm -rf {} \;

if [ "\${STATUS}" -eq 0 ]; then
  echo "\${LOG_TAG} backup finished OK." | tee -a "\${LOG_FILE}"

  if [ "\${SEND_SUCCESS_MAIL}" = "true" ]; then
    SUBJECT="[\${SITE}] WordPress backup OK"
    MAIL_BODY="WordPress backup COMPLETED (site: \${SITE}).

Backup time (UTC): \${BACKUP_TIME_UTC}
Local backup path: \${WORK_DIR}
Remote backup path: \${REMOTE_TARGET}
Local retention: latest \${LOCAL_KEEP_DAYS} days
Remote retention: latest \${REMOTE_KEEP_DAYS} days

---
WordPress 备份已完成（站点：\${SITE}）。

备份时间（UTC）：\${BACKUP_TIME_UTC}
本机备份位置：\${WORK_DIR}
远程备份位置：\${REMOTE_TARGET}
本机保留最近 \${LOCAL_KEEP_DAYS} 天；
远程保留最近 \${REMOTE_KEEP_DAYS} 天。
"
    send_mail "\${SUBJECT}" "\${MAIL_BODY}"
  fi
else
  echo "\${LOG_TAG} backup FAILED with status=\${STATUS}." | tee -a "\${LOG_FILE}"

  SUBJECT="[\${SITE}] WordPress backup FAILED"
  MAIL_BODY="WordPress backup FAILED (site: \${SITE}).

Backup time (UTC): \${BACKUP_TIME_UTC}
Please log in to the server and check:
  \${LOG_FILE}

---
WordPress 备份失败（站点：\${SITE}）。

备份时间（UTC）：\${BACKUP_TIME_UTC}
请登录服务器查看日志：
  \${LOG_FILE}

请尽快排查数据库连接、磁盘空间或 rclone 远程配置。
"
  send_mail "\${SUBJECT}" "\${MAIL_BODY}"
fi

exit "\${STATUS}"
EOF

chmod +x "$BACKUP_SCRIPT"

#--------------------------------------------------
# systemd service + timer
#--------------------------------------------------
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=WordPress backup for site ${SITE}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
EOF

cat >"$TIMER_FILE" <<EOF
[Unit]
Description=Daily WordPress backup for site ${SITE}

[Timer]
OnCalendar=*-*-* ${BACKUP_TIME}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "wp-backup-${SITE}.timer"

echo
echo "=================================================="
echo "Backup script:  $BACKUP_SCRIPT"
echo "systemd service: $SERVICE_FILE"
echo "systemd timer:   $TIMER_FILE"
echo
echo "Daily backup is enabled at ${BACKUP_TIME} (server time, usually UTC)."
echo
echo "Run a manual backup once:"
echo "  sudo $BACKUP_SCRIPT"
echo
echo "Check timer status:"
echo "  systemctl status wp-backup-${SITE}.timer"
echo "Check backup log:"
echo "  tail -n 50 /var/log/wp-backup-${SITE}.log"
echo "=================================================="
