#!/usr/bin/env bash
# WordPress 备份安装脚本 + systemd 定时任务（依赖 msmtp 报警）

set -euo pipefail

# 避免 set -u 报未定义
SITE=""
WP_ROOT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
BACKUP_DIR=""
USE_REMOTE="n"
CHOSEN_MOUNT=""

if [[ "$(id -u)" -ne 0 ]]; then
  echo "本脚本需要以 root 身份运行（需要写 /usr/local/bin 和 /etc/systemd/system）" >&2
  exit 1
fi

echo "============================================================"
echo " WordPress backup setup (DB + files)"
echo " WordPress 备份配置向导（数据库 + 文件）"
echo "============================================================"
echo

########################################
# 1) 先检查 rclone 挂载
########################################
echo "正在检测 rclone 挂载 / Checking rclone mounts..."

# 找出 fuse.rclone 类型的挂载点
mapfile -t RCLONE_MOUNTS < <(findmnt -nt fuse.rclone -o TARGET 2>/dev/null || true)

if (( ${#RCLONE_MOUNTS[@]} == 0 )); then
  echo
  echo "未检测到任何 rclone 挂载。"
  echo "No rclone mounts detected."
  echo
  echo "建议先在 hz-oneclick 主菜单中选择："
  echo "  2) rclone basics / rclone 基础安装（OneDrive 等）"
  echo "配置好 OneDrive / Google Drive / 其它网盘挂载后，再次运行本模块。"
  echo
  echo "脚本将退出，返回一键安装入口。"
  exit 1
fi

echo
echo "检测到以下 rclone 挂载 / Detected rclone mounts:"
for i in "${!RCLONE_MOUNTS[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${RCLONE_MOUNTS[$i]}"
done
echo

read -rp "是否将备份直接保存到其中一个挂载？[y/N]: " use_remote
use_remote=${use_remote:-n}

if [[ "$use_remote" =~ ^[Yy]$ ]]; then
  USE_REMOTE="y"
  while :; do
    read -rp "请输入要使用的挂载编号 (1-${#RCLONE_MOUNTS[@]}): " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#RCLONE_MOUNTS[@]} )); then
      CHOSEN_MOUNT="${RCLONE_MOUNTS[$((idx-1))]}"
      echo "已选择挂载点: ${CHOSEN_MOUNT}"
      break
    else
      echo "编号无效，请重新输入。"
    fi
  done
else
  USE_REMOTE="n"
  CHOSEN_MOUNT=""
  echo "将使用本机路径作为默认备份目录（也可以稍后手动改成挂载路径）。"
fi

echo

########################################
# 2) 站点信息收集
########################################

# 站点代号 / Site identifier
read -rp "Site ID (e.g. example.com) / 站点代号: " SITE
SITE="${SITE:-example}"

# 默认 WP 路径
DEFAULT_WP_ROOT="/var/www/${SITE}/html"
read -rp "WP 根目录 [${DEFAULT_WP_ROOT}]: " WP_ROOT
WP_ROOT="${WP_ROOT:-$DEFAULT_WP_ROOT}"

echo
echo "Database settings / 数据库设置："
read -rp "数据库名（DB_NAME）: " DB_NAME
read -rp "数据库用户（DB_USER）: " DB_USER
read -rsp "数据库密码（DB_PASSWORD）: " DB_PASS
echo
read -rp "数据库主机（127.0.0.1:3306）: " DB_HOST
DB_HOST="${DB_HOST:-127.0.0.1:3306}"

echo

# 根据是否选择网盘挂载决定默认备份目录
if [[ "$USE_REMOTE" == "y" && -n "$CHOSEN_MOUNT" ]]; then
  DEFAULT_BACKUP_DIR="${CHOSEN_MOUNT%/}/wp-backups/${SITE}"
else
  DEFAULT_BACKUP_DIR="/root/backups/${SITE}"
fi

read -rp "备份目录 [${DEFAULT_BACKUP_DIR}]: " BACKUP_DIR
BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"

mkdir -p "$BACKUP_DIR"

########################################
# 3) 生成备份脚本
########################################

BACKUP_SCRIPT="/usr/local/bin/wp-backup-${SITE}.sh"

DB_HOST_ONLY="${DB_HOST%%:*}"
DB_PORT_ONLY="${DB_HOST##*:}"

cat > "${BACKUP_SCRIPT}" <<EOF
#!/usr/bin/env bash
# AUTO-GENERATED: WordPress backup for ${SITE}

set -euo pipefail

SITE="${SITE}"
WP_ROOT="${WP_ROOT}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_HOST="${DB_HOST}"
DB_HOST_ONLY="${DB_HOST_ONLY}"
DB_PORT_ONLY="${DB_PORT_ONLY}"
BACKUP_DIR="${BACKUP_DIR}"
LOG_FILE="/var/log/wp-backup-${SITE}.log"

DATE=\$(date '+%Y%m%d-%H%M%S')

mkdir -p "\${BACKUP_DIR}"

DB_FILE="\${BACKUP_DIR}/\${SITE}-db-\${DATE}.sql.gz"
FILES_FILE="\${BACKUP_DIR}/\${SITE}-files-\${DATE}.tar.gz"

{
  echo "==== Backup run at \${DATE} ===="
  echo "DB  -> \${DB_FILE}"
  echo "Files -> \${FILES_FILE}"

  echo "[1/2] Dumping database..."
  mysqldump -h "\${DB_HOST_ONLY}" -P "\${DB_PORT_ONLY}" -u"\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" | gzip -c > "\${DB_FILE}"

  echo "[2/2] Archiving WordPress files..."
  tar -czf "\${FILES_FILE}" -C "\${WP_ROOT}" .

  echo "Backup finished OK."
} >>"\${LOG_FILE}" 2>&1 || {
  # 仅失败时发送告警邮件（使用系统已配置好的 msmtp）
  echo "WordPress backup FAILED on ${SITE} at \$(date -u '+%Y-%m-%d %H:%M:%S UTC')" | msmtp "freemankkw@gmail.com"
  exit 1
}
EOF

chmod +x "${BACKUP_SCRIPT}"

########################################
# 4) 创建 systemd service + timer
########################################

SERVICE_FILE="/etc/systemd/system/wp-backup-${SITE}.service"
TIMER_FILE="/etc/systemd/system/wp-backup-${SITE}.timer"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=WordPress backup for ${SITE}

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
EOF

# 每天 03:05 备份一次，可按需调整时间
cat > "${TIMER_FILE}" <<EOF
[Unit]
Description=Daily WordPress backup for ${SITE}

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "wp-backup-${SITE}.timer"

########################################
# 5) 总结信息
########################################

echo
echo "============================================================"
echo " WordPress 备份模块已配置完成！"
echo "============================================================"
echo "站点代号 / Site ID:      ${SITE}"
echo "WP 根目录 / WP root:     ${WP_ROOT}"
echo "备份目录 / Backup dir:   ${BACKUP_DIR}"
if [[ -n "\$CHOSEN_MOUNT" ]]; then
  echo "使用挂载 / Using mount:  ${CHOSEN_MOUNT}"
fi
echo
echo "备份脚本 / Backup script:"
echo "  ${BACKUP_SCRIPT}"
echo
echo "systemd timer:"
echo "  wp-backup-${SITE}.service"
echo "  wp-backup-${SITE}.timer  (已启用并启动)"
echo
echo "查看定时任务状态:"
echo "  systemctl status wp-backup-${SITE}.timer"
echo
echo "查看最近日志:"
echo "  tail -n 50 /var/log/wp-backup-${SITE}.log"
echo
echo "提示：仅当备份失败时才会通过 msmtp 发送告警邮件。"
