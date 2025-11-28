#!/usr/bin/env bash
# 简单版 WordPress 备份 + systemd 定时器（支持 msmtp 报警）

set -euo pipefail

# 先声明变量，避免 set -u 报 “unbound variable”
SITE=""
WP_ROOT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
BACKUP_DIR=""
ALERT_EMAIL=""

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请用 ROOT 运行本脚本（需要写 /usr/local/bin 和 /etc/systemd/system）" >&2
  exit 1
fi

echo "=== 配置 WordPress 备份脚本（数据库 + 文件） ==="
echo

# 1) 站点代号
read -rp "站点代号（例如 google）: " SITE
SITE="${SITE:-wpdemo}"

# 2) WP 根目录
read -rp "WP 根目录（默认 /var/www/${SITE}/html）: " WP_ROOT
WP_ROOT="${WP_ROOT:-/var/www/${SITE}/html}"

# 3) 数据库信息
read -rp "数据库名（DB_NAME）: " DB_NAME
read -rp "数据库用户（DB_USER）: " DB_USER
read -rp "数据库密码（DB_PASSWORD）: " DB_PASS
read -rp "数据库主机和端口（DB_HOST，默认 127.0.0.1:3306）: " DB_HOST
DB_HOST="${DB_HOST:-127.0.0.1:3306}"

# 4) 备份根目录
read -rp "备份根目录（默认 /root/backups/${SITE}）: " BACKUP_DIR
BACKUP_DIR="${BACKUP_DIR:-/root/backups/${SITE}}"

# 5) 报警收件邮箱（可选）
read -rp "报警收件邮箱（留空则不发邮件）: " ALERT_EMAIL
ALERT_EMAIL="${ALERT_EMAIL:-}"

echo
echo "站点代号:          ${SITE}"
echo "WordPress 根目录:  ${WP_ROOT}"
echo "数据库名:          ${DB_NAME}"
echo "数据库用户:        ${DB_USER}"
echo "数据库主机:        ${DB_HOST}"
echo "备份根目录:        ${BACKUP_DIR}"
echo "报警收件邮箱:      ${ALERT_EMAIL:-<不发送>}"
echo

read -rp "请确认以上信息是否正确？(y/N): " CONFIRM
CONFIRM="${CONFIRM:-n}"
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "已取消。"
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# 拆分 DB_HOST
DB_HOST_ONLY="${DB_HOST%%:*}"
DB_PORT_ONLY="${DB_HOST##*:}"

# 将变量做 shell 安全转义，写进备份脚本
SITE_ESCAPED=$(printf '%q' "${SITE}")
WP_ROOT_ESCAPED=$(printf '%q' "${WP_ROOT}")
DB_NAME_ESCAPED=$(printf '%q' "${DB_NAME}")
DB_USER_ESCAPED=$(printf '%q' "${DB_USER}")
DB_PASS_ESCAPED=$(printf '%q' "${DB_PASS}")
DB_HOST_ONLY_ESCAPED=$(printf '%q' "${DB_HOST_ONLY}")
DB_PORT_ONLY_ESCAPED=$(printf '%q' "${DB_PORT_ONLY}")
BACKUP_DIR_ESCAPED=$(printf '%q' "${BACKUP_DIR}")
ALERT_EMAIL_ESCAPED=$(printf '%q' "${ALERT_EMAIL}")

BACKUP_SCRIPT="/usr/local/bin/wp-backup-${SITE}.sh"

cat >"${BACKUP_SCRIPT}" <<EOF
#!/usr/bin/env bash
# 自动生成的 WordPress 备份脚本（站点：${SITE}）

set -euo pipefail

SITE=${SITE_ESCAPED}
WP_ROOT=${WP_ROOT_ESCAPED}
DB_NAME=${DB_NAME_ESCAPED}
DB_USER=${DB_USER_ESCAPED}
DB_PASS=${DB_PASS_ESCAPED}
DB_HOST_ONLY=${DB_HOST_ONLY_ESCAPED}
DB_PORT_ONLY=${DB_PORT_ONLY_ESCAPED}
BACKUP_DIR=${BACKUP_DIR_ESCAPED}
ALERT_EMAIL=${ALERT_EMAIL_ESCAPED}

DATE="\$(date +%F-%H%M%S)"
TODAY_DIR="\${BACKUP_DIR}/\${DATE}"

mkdir -p "\${TODAY_DIR}"

DB_DUMP_FILE="\${TODAY_DIR}/\${SITE}-db-\${DATE}.sql"
DB_DUMP_GZ="\${DB_DUMP_FILE}.gz"
FILES_TAR="\${TODAY_DIR}/\${SITE}-files-\${DATE}.tar.gz"

echo "[\${DATE}] 开始备份站点 \${SITE}..."

# 1) 备份数据库
echo "  - 导出数据库 \${DB_NAME} ..."
mysqldump -h "\${DB_HOST_ONLY}" -P "\${DB_PORT_ONLY}" \\
  -u "\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" > "\${DB_DUMP_FILE}"

gzip "\${DB_DUMP_FILE}"

# 2) 备份 WP 文件
echo "  - 打包 WordPress 文件 ..."
tar -czf "\${FILES_TAR}" -C "\${WP_ROOT}" .

# 3) 清理旧备份（保留 14 天）
KEEP_DAYS=14
find "\${BACKUP_DIR}" -maxdepth 1 -mindepth 1 -type d -mtime +\${KEEP_DAYS} -exec rm -rf {} \; || true

echo "[\${DATE}] 站点 \${SITE} 备份完成。"
echo "  - 数据库备份: \${DB_DUMP_GZ}"
echo "  - 文件备份:   \${FILES_TAR}"

# 4) 可选：发送邮件通知（需要系统已配置 msmtp）
if [[ -n "\${ALERT_EMAIL}" ]] && command -v msmtp >/dev/null 2>&1; then
  MSG="这是来自 \${SITE} 的 WordPress 备份通知。\\n\\n时间：\${DATE}\\n数据库备份：\${DB_DUMP_GZ}\\n文件备份：\${FILES_TAR}"
  printf "%b\\n" "\${MSG}" | msmtp "\${ALERT_EMAIL}" || true
fi
EOF

chmod 700 "${BACKUP_SCRIPT}"

SERVICE_FILE="/etc/systemd/system/wp-backup-${SITE}.service"
TIMER_FILE="/etc/systemd/system/wp-backup-${SITE}.timer"

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=WordPress backup for ${SITE}
After=network.target

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
EOF

cat >"${TIMER_FILE}" <<EOF
[Unit]
Description=Daily WordPress backup timer for ${SITE}

[Timer]
OnCalendar=*-*-* 03:15:00
Unit=wp-backup-${SITE}.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "wp-backup-${SITE}.timer"

echo
echo "已生成备份脚本：${BACKUP_SCRIPT}"
echo "已创建并启用 systemd 定时任务：wp-backup-${SITE}.timer"
echo
echo "可以用以下命令查看："
echo "  systemctl list-timers | grep wp-backup-${SITE}"
echo "  journalctl -u wp-backup-${SITE}.service --no-pager"
