#!/usr/bin/env bash
# WordPress 备份安装脚本（公共版）
# - 生成 /usr/local/bin/wp-backup-<SITE>.sh
# - 生成 systemd service + timer
# - 支持 rclone 远程 + 可选 msmtp 邮件报警

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
# 0) 必须用 root
#--------------------------------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "本脚本需要以 root 身份运行（要写 /usr/local/bin 和 /etc/systemd/system）。" >&2
  exit 1
fi

echo "=============================================="
echo " WordPress backup setup (DB + files)"
echo "=============================================="
echo

# 简短特性说明
echo -e "${CYAN}特性 / Features${NC}"
echo "  - 本机 + 网盘 双重备份（默认：本机 7 天，远端 30 天）"
echo "  - 使用 rclone 直接推送 OneDrive / Google Drive 等远端"
echo "  - 生成 systemd service + timer，每天定时备份"
echo "  - 可选：结合 msmtp + Brevo，仅在失败时发送邮件报警"
echo

#--------------------------------------------------
# [1/7] 站点信息 / Site info
#--------------------------------------------------
echo "[1/7] 站点基本信息 / Site info"
echo "Site ID 将用于："
echo "  - 备份脚本名：/usr/local/bin/wp-backup-<SiteID>.sh"
echo "  - 本机备份目录：/root/backups/<SiteID>/..."
echo "建议用小写字母/数字/连字符，例如：nzf / hz / blog1"
read -rp "Site ID: " SITE
SITE="${SITE// /}"   # 去掉空格

if [[ -z "$SITE" ]]; then
  echo "[!] Site ID 不能为空，退出。" >&2
  exit 1
fi

DEFAULT_WP_ROOT="/var/www/${SITE}/html"
echo
echo "WordPress 根目录示例：/var/www/your-site/html"
echo "直接回车使用默认：${DEFAULT_WP_ROOT}"
read -rp "WordPress 根目录 [${DEFAULT_WP_ROOT}] : " WP_ROOT
WP_ROOT="${WP_ROOT:-$DEFAULT_WP_ROOT}"

if [[ ! -d "$WP_ROOT" ]]; then
  echo "[!] 目录不存在：${WP_ROOT}"
  echo "    请确认 WordPress 安装路径后重试。"
  exit 1
fi

#--------------------------------------------------
# [2/7] 数据库信息 / DB settings
#--------------------------------------------------
echo
echo "[2/7] 数据库设置 / Database settings"
echo "小提示 / Tip：可以先在服务器上执行："
echo "  grep -E \"DB_(NAME|USER|PASSWORD|HOST)\" ${WP_ROOT}/wp-config.php"
echo "然后把输出中的 DB_NAME / DB_USER / DB_PASSWORD / DB_HOST 复制到下面。"
echo
echo "密码输入时不会显示在屏幕上，这是正常现象。"
echo "Tip: Password input will be hidden (no characters shown)."
echo

read -rp "DB 名称（wp-config.php 中 DB_NAME）: " DB_NAME
read -rp "DB 用户名（wp-config.php 中 DB_USER）: " DB_USER
read -rsp "DB 密码（wp-config.php 中 DB_PASSWORD）: " DB_PASS
echo
echo "DB 主机请\"原样输入\" wp-config.php 中 DB_HOST，例如："
echo "  127.0.0.1"
echo "  127.0.0.1:3306"
echo "脚本会自动拆分主机和端口，无需手动修改。"
read -rp "DB 主机（wp-config.php 中 DB_HOST）: " DB_HOST

if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_HOST" ]]; then
  echo "[!] 数据库信息不完整，退出。" >&2
  exit 1
fi

DB_HOST_ONLY="$DB_HOST"
DB_PORT_ONLY="3306"
if [[ "$DB_HOST" == *:* ]]; then
  DB_HOST_ONLY="${DB_HOST%%:*}"
  DB_PORT_ONLY="${DB_HOST##*:}"
fi

#--------------------------------------------------
# [3/7] 本机备份目录 / Local backup base
#--------------------------------------------------
echo
echo "[3/7] 本机备份目录 / Local backup base"
DEFAULT_BACKUP_BASE="/root/backups/${SITE}"
echo "本机备份会按日期创建子目录，例如："
echo "  ${DEFAULT_BACKUP_BASE}/2025-12-01_031500/"
echo "直接回车使用默认路径：${DEFAULT_BACKUP_BASE}"
read -rp "本机备份根目录 [${DEFAULT_BACKUP_BASE}] : " BACKUP_BASE
BACKUP_BASE="${BACKUP_BASE:-$DEFAULT_BACKUP_BASE}"
mkdir -p "$BACKUP_BASE"

#--------------------------------------------------
# [4/7] rclone 远程路径 / rclone remote path
#--------------------------------------------------
echo
echo "[4/7] rclone 远程路径 / rclone remote path"

if ! command -v rclone >/dev/null 2>&1; then
  echo "[!] 未检测到 rclone，请先安装并配置至少一个 remote："
  echo "    rclone config"
  exit 1
fi

echo "已检测到的 rclone remotes："
rclone listremotes 2>/dev/null || echo "  （尚未配置任何 remote，请先运行 rclone config）"
echo
echo "示例 Example："
echo "  gdrive:${SITE}"
echo "  onedrive:${SITE}"
echo "  myremote:backups/${SITE}"
read -rp "请输入 rclone 目标（不含日期子目录）: " RCLONE_REMOTE

if [[ -z "$RCLONE_REMOTE" ]]; then
  echo "[!] rclone 目标不能为空，退出。" >&2
  exit 1
fi

REMOTE_NAME="${RCLONE_REMOTE%%:*}"
if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
  echo -e "${YELLOW}[!] 提示：没有找到名为 \"${REMOTE_NAME}:\" 的 remote，请确认是否已用 rclone config 配置。${NC}"
fi

#--------------------------------------------------
# [5/7] 保留天数 / Retention
#--------------------------------------------------
echo
echo "[5/7] 备份保留天数 / Retention policy"
echo "默认策略 / Defaults："
echo "  - 本机保留 7 天"
echo "  - 远端保留 30 天"
read -rp "本机保留天数 [7] : " LOCAL_KEEP_DAYS
read -rp "远端保留天数 [30] : " REMOTE_KEEP_DAYS

LOCAL_KEEP_DAYS="${LOCAL_KEEP_DAYS:-7}"
REMOTE_KEEP_DAYS="${REMOTE_KEEP_DAYS:-30}"

if ! [[ "$LOCAL_KEEP_DAYS" =~ ^[0-9]+$ ]]; then
  echo -e "${YELLOW}[!] 本机保留天数格式不正确，使用默认 7 天。${NC}"
  LOCAL_KEEP_DAYS="7"
fi
if ! [[ "$REMOTE_KEEP_DAYS" =~ ^[0-9]+$ ]]; then
  echo -e "${YELLOW}[!] 远端保留天数格式不正确，使用默认 30 天。${NC}"
  REMOTE_KEEP_DAYS="30"
fi

#--------------------------------------------------
# [6/7] 每日备份时间（服务器时间 / 通常 UTC）
#--------------------------------------------------
echo
echo "[6/7] 每日备份时间 / Daily backup time"
echo "注意：这是\"服务器时间\"，大多数 VPS 上为 UTC。"
echo "例如："
echo "  填 03:30 → 每天 03:30 (UTC) 运行。"
read -rp "每日备份时间 (HH:MM，24 小时制) [03:30] : " BACKUP_TIME
BACKUP_TIME="${BACKUP_TIME:-03:30}"

if ! [[ "$BACKUP_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo -e "${YELLOW}[!] 时间格式不合法，将使用默认 03:30。${NC}"
  BACKUP_TIME="03:30"
fi

#--------------------------------------------------
# [7/7] 邮件报警 / Email alert (msmtp)
#--------------------------------------------------
echo
echo "[7/7] 邮件报警 / Email alert (msmtp)"

MSMTP_AVAILABLE="false"
if command -v msmtp >/dev/null 2>&1 && [[ -f /etc/msmtprc ]]; then
  MSMTP_AVAILABLE="true"
fi

if [[ "$MSMTP_AVAILABLE" == "true" ]]; then
  echo "检测到系统已安装 msmtp，并存在 /etc/msmtprc 配置。"
  echo "你可以为本站启用\"备份失败时发送邮件报警\"。"
  read -rp "是否启用邮件报警？[y/N] : " enable_alert
  if [[ "$enable_alert" =~ ^[Yy]$ ]]; then
    read -rp "报警接收邮箱 (alert email, 例如 you@example.com) : " ALERT_EMAIL_INPUT
  else
    ALERT_EMAIL_INPUT=""
  fi
else
  echo -e "${YELLOW}[!] 未检测到 msmtp 或 /etc/msmtprc。${NC}"
  echo "建议先在 HorizonTech 一键入口主菜单中执行："
  echo "  7) 邮件报警（msmtp + Brevo）"
  echo "完成邮件发送配置后，再重新运行本备份向导。"
  read -rp "仍然继续创建\"无邮件报警\"的备份脚本？[Y/n] : " cont
  if [[ "$cont" =~ ^[Nn]$ ]]; then
    echo "已取消安装 WordPress 备份模块。"
    exit 0
  fi
  ALERT_EMAIL_INPUT=""
fi

#--------------------------------------------------
# 生成备份脚本 + systemd 单元
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

ALERT_EMAIL="${ALERT_EMAIL_INPUT}"    # 安装时写入的报警邮箱（可为空）
SEND_SUCCESS_MAIL="false"             # 默认：只在失败时发邮件，若要成功也发可改成 true

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

echo "\${LOG_TAG} 创建本机目录: \${WORK_DIR}" | tee -a "\${LOG_FILE}"
mkdir -p "\${WORK_DIR}"

# 备份数据库
run mysqldump -h "\${DB_HOST_ONLY}" -P "\${DB_PORT_ONLY}" -u "\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" | gzip -c > "\${DB_FILE}"

# 备份 WordPress 文件
run tar -C "\${WP_ROOT}" -czf "\${FILES_FILE}" .

REMOTE_TARGET="\${RCLONE_REMOTE}/\${TIMESTAMP}"
# 同步到远端
run rclone copy "\${WORK_DIR}" "\${REMOTE_TARGET}" --create-empty-src-dirs

# 清理远端旧备份
run rclone delete "\${RCLONE_REMOTE}" --min-age "\${REMOTE_KEEP_DAYS}d"
run rclone rmdirs "\${RCLONE_REMOTE}" --leave-root

# 清理本机旧备份
run find "\${BACKUP_BASE}" -maxdepth 1 -type d -name "20*" -mtime +\${LOCAL_KEEP_DAYS} -print -exec rm -rf {} \;

if [ "\${STATUS}" -eq 0 ]; then
  echo "\${LOG_TAG} 备份完成 OK。" | tee -a "\${LOG_FILE}"

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
  echo "\${LOG_TAG} 备份存在错误，状态码=\${STATUS}。" | tee -a "\${LOG_FILE}"

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
# 写入 systemd service / timer
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
echo "备份脚本已生成：$BACKUP_SCRIPT"
echo "systemd service：$SERVICE_FILE"
echo "systemd timer：  $TIMER_FILE"
echo
echo "已启用定时任务：每天 ${BACKUP_TIME}（服务器时间，通常为 UTC）执行一次备份。"
echo
echo "手动立即测试一次备份："
echo "  sudo $BACKUP_SCRIPT"
echo
echo "查看定时器状态："
echo "  systemctl status wp-backup-${SITE}.timer"
echo "查看备份日志："
echo "  tail -n 50 /var/log/wp-backup-${SITE}.log"
echo "=================================================="
