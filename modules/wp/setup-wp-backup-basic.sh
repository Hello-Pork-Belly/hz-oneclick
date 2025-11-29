#!/usr/bin/env bash
#
# 一键配置 WordPress 备份 + systemd 定时（数据库 + 文件）
# 注意：本脚本不直接发送邮件，只负责生成备份脚本和定时任务

set -euo pipefail

# 提前声明变量，避免 set -u 报错
SITE=""
WP_ROOT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
BACKUP_BASE=""
BACKUP_DIR=""

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请以 root 身份运行本脚本。"
  echo "Please run this script as root."
  exit 1
fi

echo "============================================================"
echo " WordPress backup setup (DB + files)"
echo " WordPress 备份配置向导（数据库 + 文件）"
echo "============================================================"
echo

# ---------- 站点代号 / Site identifier ----------
read -rp "Site ID (e.g. google) / 站点代号: " SITE
SITE="${SITE:-wp}"

# ---------- WP 路径 / WordPress path ----------
DEFAULT_WP_ROOT="/var/www/${SITE}/html"
read -rp "WordPress path [${DEFAULT_WP_ROOT}]: " WP_ROOT
WP_ROOT="${WP_ROOT:-$DEFAULT_WP_ROOT}"

if [[ ! -d "${WP_ROOT}" ]]; then
  echo "❌ 找不到目录：${WP_ROOT}"
  echo "Directory not found: ${WP_ROOT}"
  exit 1
fi

# ---------- DB 信息 ----------
echo
echo "Database settings / 数据库设置："

read -rp "DB name (DB_NAME): " DB_NAME
read -rp "DB user (DB_USER): " DB_USER
read -rp "DB password (DB_PASSWORD): " DB_PASS

read -rp "DB host [127.0.0.1:3306] (DB_HOST): " DB_HOST
DB_HOST="${DB_HOST:-127.0.0.1:3306}"

# 拆分 host:port
DB_HOST_ONLY="${DB_HOST%:*}"
DB_PORT_ONLY="${DB_HOST##*:}"

# ============================================================
#  检查 rclone 挂载 / Check rclone mounts
# ============================================================

echo
echo "Checking for rclone mounts..."
echo "正在检查是否存在 rclone 挂载的网盘..."

mapfile -t RCLONE_MOUNTS < <(findmnt -rn -t fuse.rclone -o TARGET 2>/dev/null || true)

if ((${#RCLONE_MOUNTS[@]} == 0)); then
  echo
  echo "⚠ No rclone mounts detected."
  echo "⚠ 未检测到 rclone 挂载的网盘。"
  echo "  建议先通过主菜单选项 2 安装 rclone 并挂载 OneDrive / Google Drive 等网盘。"
  echo

  read -rp "Return to main menu now? [y/N] / 是否先返回主菜单？[y/N]: " back_choice
  case "${back_choice}" in
    y|Y)
      echo "返回主菜单 / Returning to main menu..."
      exit 0
      ;;
    *)
      echo "继续使用本机目录进行备份。"
      echo "Continue with local directory for backup."
      BACKUP_BASE="/root/backups/${SITE}"
      ;;
  esac
else
  echo
  echo "Detected rclone mounts / 检测到以下 rclone 挂载点："
  idx=1
  for m in "${RCLONE_MOUNTS[@]}"; do
    echo "  ${idx}) ${m}"
    ((idx++))
  done
  echo "  0) Use local directory / 使用本机目录 (/root/backups/${SITE})"
  echo

  read -rp "Select backup base (number) / 请选择备份根目录编号: " sel
  if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#RCLONE_MOUNTS[@]} )); then
    BACKUP_BASE="${RCLONE_MOUNTS[sel-1]}"
    echo "Using mounted path as backup base: ${BACKUP_BASE}"
    echo "将使用挂载路径作为备份根目录：${BACKUP_BASE}"
  else
    BACKUP_BASE="/root/backups/${SITE}"
    echo "Using local directory as backup base: ${BACKUP_BASE}"
    echo "将使用本机目录作为备份根目录：${BACKUP_BASE}"
  fi
fi

# ---------- 最终备份目录 ----------
DEFAULT_BACKUP_DIR="${BACKUP_BASE%/}/wp-backups/${SITE}"
echo
read -rp "Backup dir [${DEFAULT_BACKUP_DIR}]: " BACKUP_DIR
BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"

mkdir -p "${BACKUP_DIR}/db" "${BACKUP_DIR}/files"

echo
echo "Backup directory will be: ${BACKUP_DIR}"
echo "备份将保存到：${BACKUP_DIR}"
echo

# ============================================================
#  生成备份脚本 / Generate backup script
# ============================================================

BACKUP_SCRIPT="/usr/local/bin/wp-backup-${SITE}.sh"

cat >"${BACKUP_SCRIPT}" <<EOF
#!/usr/bin/env bash
# Auto generated WordPress backup script for site: ${SITE}
# 自动生成的 WordPress 备份脚本（站点：${SITE}）

set -euo pipefail

SITE="${SITE}"
WP_ROOT="${WP_ROOT}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_HOST_ONLY="${DB_HOST_ONLY}"
DB_PORT_ONLY="${DB_PORT_ONLY}"
BACKUP_DIR="${BACKUP_DIR}"

DATE=\$(date +"%Y%m%d-%H%M%S")

LOG_DIR="\${BACKUP_DIR}/logs"
mkdir -p "\${LOG_DIR}"
LOG_FILE="\${LOG_DIR}/backup-\${DATE}.log"

{
  echo "=== WordPress backup started (\${DATE}) ==="
  echo "Site: \${SITE}"
  echo "WP_ROOT: \${WP_ROOT}"
  echo "DB: \${DB_USER}@\${DB_HOST_ONLY}:\${DB_PORT_ONLY}/\${DB_NAME}"
  echo "Backup dir: \${BACKUP_DIR}"
  echo

  mkdir -p "\${BACKUP_DIR}/db" "\${BACKUP_DIR}/files"

  # DB backup
  DB_FILE="\${BACKUP_DIR}/db/\${SITE}-db-\${DATE}.sql.gz"
  echo "[DB] Dumping MySQL/MariaDB to \${DB_FILE} ..."
  mysqldump -h "\${DB_HOST_ONLY}" -P "\${DB_PORT_ONLY}" -u "\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" | gzip -c > "\${DB_FILE}"
  echo "[DB] Done."

  # Files backup
  FILES_FILE="\${BACKUP_DIR}/files/\${SITE}-files-\${DATE}.tar.gz"
  echo "[Files] Archiving WordPress files to \${FILES_FILE} ..."
  tar -czf "\${FILES_FILE}" -C "\${WP_ROOT}" .
  echo "[Files] Done."

  echo
  echo "All done."
  echo "=== WordPress backup finished (\$(date +"%Y%m%d-%H%M%S")) ==="

} | tee "\${LOG_FILE}"

EOF

chmod +x "${BACKUP_SCRIPT}"

# ============================================================
#  systemd service + timer
# ============================================================

SERVICE_FILE="/etc/systemd/system/wp-backup-${SITE}.service"
TIMER_FILE="/etc/systemd/system/wp-backup-${SITE}.timer"

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=WordPress backup for site ${SITE}

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
EOF

cat >"${TIMER_FILE}" <<EOF
[Unit]
Description=Daily WordPress backup for site ${SITE}

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "wp-backup-${SITE}.timer"

echo
echo "============================================================"
echo "Setup finished."
echo "配置完成。"
echo
echo "Backup script  : ${BACKUP_SCRIPT}"
echo "Service unit   : ${SERVICE_FILE}"
echo "Timer unit     : ${TIMER_FILE}"
echo
echo "Timer status   :"
systemctl status "wp-backup-${SITE}.timer" --no-pager || true

echo
echo "下一步建议 / Next suggestions:"
echo "  1) 使用菜单 2 确保 rclone 已正确挂载网盘（如有需要）。"
echo "  2) 使用菜单 7 安装 msmtp + 邮件报警（可选，仅在出错时发邮件，留待后续步骤实现）。"
echo
