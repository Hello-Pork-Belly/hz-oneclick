#!/usr/bin/env bash
# WordPress 备份安装脚本 + systemd 定时任务（使用 rclone 远程）
# 用于一键生成单站点的 DB + 文件备份脚本（公共版）

set -euo pipefail

# 预定义变量，避免 set -u 报错
SITE=""
WP_ROOT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
BACKUP_BASE=""
RCLONE_REMOTE=""
LOCAL_KEEP_DAYS=""
REMOTE_KEEP_DAYS=""
BACKUP_TIME=""

CYAN="\e[36m"
YELLOW="\e[33m"
NC="\e[0m"

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

# 短说明：特点 / Features
echo -e "${CYAN}特性 / Features${NC}"
echo "  - 本机 + 网盘 双重备份（默认：本机保留 7 天，远端保留 30 天）"
echo "  - 使用 rclone 直接推送到远端（OneDrive / Google Drive 等）"
echo "  - 生成 systemd service + timer，每天自动定时备份"
echo "  - 可与“邮件报警模块”配合，只在失败时发送告警"
echo

#--------------------------------------------------
# 1) 站点信息 / Site info
#--------------------------------------------------
echo "[1/6] 站点基本信息 / Site info"
echo "Site ID 会用于："
echo "  - 备份脚本名：/usr/local/bin/wp-backup-<SiteID>.sh"
echo "  - 本机备份目录：/root/backups/<SiteID>/..."
echo "请使用小写字母/数字/连字符，不要包含空格。"
read -rp "Site ID（例如 blog1 / nzf）: " SITE
SITE="${SITE// /}"   # 去掉空格
if [[ -z "$SITE" ]]; then
  echo "Site ID 不能为空，退出。" >&2
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
# 2) 数据库信息 / Database settings
#--------------------------------------------------
echo
echo "[2/6] 数据库设置 / Database settings"

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
echo "DB 主机请“原样输入” wp-config.php 中 DB_HOST，例如："
echo "  127.0.0.1"
echo "  127.0.0.1:3306"
echo "脚本会自动把主机和端口拆开处理，无需手动修改。"
echo "DB host (exactly as in wp-config.php, e.g. 127.0.0.1 or 127.0.0.1:3306)"
read -rp "DB 主机（wp-config.php 中 DB_HOST）: " DB_HOST

if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_HOST" ]]; then
  echo "[!] 数据库信息不完整，退出。" >&2
  exit 1
fi

# 拆分 DB_HOST 为 host + port
DB_HOST_ONLY="$DB_HOST"
DB_PORT_ONLY="3306"
if [[ "$DB_HOST" == *:* ]]; then
  DB_HOST_ONLY="${DB_HOST%%:*}"
  DB_PORT_ONLY="${DB_HOST##*:}"
fi

#--------------------------------------------------
# 3) 本机备份目录 / Local backup base
#--------------------------------------------------
echo
echo "[3/6] 本机备份目录 / Local backup base"
DEFAULT_BACKUP_BASE="/root/backups/${SITE}"
echo "本机备份会按日期创建子目录，例如："
echo "  ${DEFAULT_BACKUP_BASE}/2025-11-30_031500/"
echo "直接回车使用默认路径：${DEFAULT_BACKUP_BASE}"
read -rp "本机备份根目录 [${DEFAULT_BACKUP_BASE}] : " BACKUP_BASE
BACKUP_BASE="${BACKUP_BASE:-$DEFAULT_BACKUP_BASE}"
mkdir -p "$BACKUP_BASE"

#--------------------------------------------------
# 4) rclone 远程路径 / rclone remote path
#--------------------------------------------------
echo
echo "[4/6] rclone 远程路径 / rclone remote path"

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
echo "  any-remote:some-folder"
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
# 5) 保留天数 / Retention
#--------------------------------------------------
echo
echo "[5/6] 备份保留天数 / Retention policy"
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
# 6) 备份时间 / Backup time
#--------------------------------------------------
echo
echo "[6/6] 每日备份时间 / Daily backup time"
echo "请输入每天的备份时间（24 小时制，格式 HH:MM）。例如："
echo "  03:30  表示每天凌晨 3:30"
echo "  23:45  表示每天 23:45"
read -rp "每日备份时间 [03:30] : " BACKUP_TIME
BACKUP_TIME="${BACKUP_TIME:-03:30}"

if ! [[ "$BACKUP_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo -e "${YELLOW}[!] 时间格式不合法，将使用默认 03:30。${NC}"
  BACKUP_TIME="03:30"
fi

#--------------------------------------------------
# 7) 生成备份脚本 / Generate backup script
#--------------------------------------------------
BACKUP_SCRIPT="/usr/local/bin/wp-backup-${SITE}.sh"
SERVICE_FILE="/etc/systemd/system/wp-backup-${SITE}.service"
TIMER_FILE="/etc/systemd/system/wp-backup-${SITE}.timer"

cat >"$BACKUP_SCRIPT" <<EOF
#!/usr/bin/env bash
# Auto-generated WordPress backup script for site: ${SITE}

set -euo pipefail

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

TIMESTAMP=\$(date +'%Y-%m-%d_%H%M%S')
WORK_DIR="\${BACKUP_BASE}/\${TIMESTAMP}"
LOG_TAG="[wp-backup:\${SITE}]"

echo "\${LOG_TAG} 创建本机目录: \${WORK_DIR}"
mkdir -p "\${WORK_DIR}"

DB_FILE="\${WORK_DIR}/db_\${TIMESTAMP}.sql.gz"
FILES_FILE="\${WORK_DIR}/html_\${TIMESTAMP}.tgz"

echo "\${LOG_TAG} 备份数据库..."
mysqldump -h "\${DB_HOST_ONLY}" -P "\${DB_PORT_ONLY}" -u "\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" | gzip -c > "\${DB_FILE}"

echo "\${LOG_TAG} 备份 WordPress 文件..."
tar -C "\${WP_ROOT}" -czf "\${FILES_FILE}" .

echo "\${LOG_TAG} 同步到远程: \${RCLONE_REMOTE}/\${TIMESTAMP}"
rclone copy "\${WORK_DIR}" "\${RCLONE_REMOTE}/\${TIMESTAMP}" --create-empty-src-dirs

echo "\${LOG_TAG} 清理远程超过 \${REMOTE_KEEP_DAYS} 天的旧备份..."
rclone delete "\${RCLONE_REMOTE}" --min-age "\${REMOTE_KEEP_DAYS}d" || true
rclone rmdirs "\${RCLONE_REMOTE}" --leave-root || true

echo "\${LOG_TAG} 清理本机超过 \${LOCAL_KEEP_DAYS} 天的旧备份..."
find "\${BACKUP_BASE}" -maxdepth 1 -type d -name "20*" -mtime +\${LOCAL_KEEP_DAYS} -print -exec rm -rf {} \; || true

echo "\${LOG_TAG} 备份完成。"
EOF

chmod +x "$BACKUP_SCRIPT"

#--------------------------------------------------
# 8) 写入 systemd service & timer
#--------------------------------------------------
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=WordPress backup for site ${SITE}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$BACKUP_SCRIPT
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
echo "已启用定时任务：每天 ${BACKUP_TIME} 执行一次备份。"
echo
echo "手动立即测试一次备份："
echo "  sudo $BACKUP_SCRIPT"
echo
echo "查看定时器状态："
echo "  systemctl status wp-backup-${SITE}.timer"
echo "  journalctl -u wp-backup-${SITE}.service"
echo "=================================================="
