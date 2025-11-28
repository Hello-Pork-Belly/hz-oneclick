#!/usr/bin/env bash
# 安装 WordPress 备份脚本 + systemd 定时器（支持 msmtp 报警）

set -euo pipefail

# 先初始化变量，避免 set -u 报 “unbound variable”
SITE=""
WP_ROOT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
BACKUP_DIR=""

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请用 root 运行本脚本（需要写 /usr/local/bin 和 /etc/systemd/system）" >&2
  exit 1
fi

echo "=== 配置 WordPress 备份脚本（数据库 + 文件） ==="
echo

read -rp "站点代号（如 nzfreeman）: " SITE
SITE="${SITE:-wpdemo}"

read -rp "WP 根目录 [/var/www/${SITE}/html]: " WP_ROOT
WP_ROOT="${WP_ROOT:-/var/www/${SITE}/html}"

read -rp "数据库名（DB_NAME）: " DB_NAME
read -rp "数据库用户（DB_USER）: " DB_USER
read -srp "数据库密码（DB_PASSWORD，不会回显）: " DB_PASS
echo
read -rp "数据库主机:端口 [127.0.0.1:3306]: " DB_HOST
DB_HOST="${DB_HOST:-127.0.0.1:3306}"

read -rp "备份保存目录 [/root/backups/${SITE}]: " BACKUP_DIR
BACKUP_DIR="${BACKUP_DIR:-/root/backups/${SITE}}"

mkdir -p "${BACKUP_DIR}"

DB_HOST_ONLY="${DB_HOST%:*}"
DB_PORT_ONLY="${DB_HOST#*:}"

BACKUP_SCRIPT="/usr/local/bin/wp-backup-${SITE}.sh"

cat >"${BACKUP_SCRIPT}" <<EOF
#!/usr/bin/env bash
# 自动生成：WordPress 备份脚本（${SITE}）

set -euo pipefail

SITE="${SITE}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_HOST="${DB_HOST_ONLY}"
DB_PORT="${DB_PORT_ONLY}"
BACKUP_DIR="${BACKUP_DIR}"
WP_ROOT="${WP_ROOT}"

DATE=\$(date +%F_%H-%M-%S)
mkdir -p "\${BACKUP_DIR}"

SQL_FILE="\${BACKUP_DIR}/\${SITE}-db-\${DATE}.sql.gz"
FILES_FILE="\${BACKUP_DIR}/\${SITE}-files-\${DATE}.tar.gz"

# 数据库备份
mysqldump -h "\${DB_HOST}" -P "\${DB_PORT}" -u "\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" | gzip >"\${SQL_FILE}"

# 站点文件备份（整个 WP 根目录）
tar -czf "\${FILES_FILE}" -C "\${WP_ROOT%/*}" "\${WP_ROOT##*/}"

# 清理 7 天前的旧备份
find "\${BACKUP_DIR}" -type f -mtime +7 -delete

# 邮件通知（如果 send-alert-mail.sh 存在）
if command -v send-alert-mail.sh >/dev/null 2>&1; then
  BODY="数据库备份: \${SQL_FILE}\\n文件备份: \${FILES_FILE}\\n\\n时间: \$(date -u '+%Y-%m-%d %H:%M:%S (UTC)')"
  send-alert-mail.sh "[\${SITE}] WP backup OK" "\${BODY}" "freemankkw@gmail.com"
fi
EOF

chmod 700 "${BACKUP_SCRIPT}"

echo "已生成备份脚本：${BACKUP_SCRIPT}"

SERVICE_FILE="/etc/systemd/system/wp-backup-${SITE}.service"
TIMER_FILE="/etc/systemd/system/wp-backup-${SITE}.timer"

cat >"\${SERVICE_FILE}" <<EOF
[Unit]
Description=WordPress backup for ${SITE}

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
EOF

cat >"\${TIMER_FILE}" <<EOF
[Unit]
Description=Daily WordPress backup for ${SITE}

[Timer]
OnCalendar=*-*-* 11:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "wp-backup-${SITE}.timer"

echo
echo "已启用 systemd 定时器：wp-backup-${SITE}.timer"
echo "每天 11:00 运行一次备份；你可以用以下命令手动测试："
echo "  systemctl start wp-backup-${SITE}.service"
echo "  journalctl -u wp-backup-${SITE}.service -n 50 --no-pager"
