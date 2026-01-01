#!/usr/bin/env bash
# 验收要点:
# - 运行本脚本会安装 rclone、引导配置 remote、生成 /usr/local/bin/hz-backup.sh
# - 创建每日 03:00 的 cron（不会重复）
# - 手动运行 hz-backup.sh 会生成数据库与文件备份并同步至远端
# - 失败时通过本地 mail 命令发送告警
set -Eeuo pipefail

log_info() { echo "[INFO] $*"; }
log_ok() { echo "[OK] $*"; }
log_warn() { echo "[WARN] $*"; }
log_err() { echo "[ERR] $*"; }

die() {
  log_err "$*"
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  die "请使用 root 用户运行此脚本。"
fi

tz_name="$(timedatectl show -p Timezone --value 2>/dev/null || echo "未知")"

backup_root="/root/backups"
backup_db_dir="${backup_root}/db"
backup_files_dir="${backup_root}/files"
log_file="/var/log/hz-backup.log"

mkdir -p "${backup_db_dir}" "${backup_files_dir}"
chmod 700 "${backup_root}" "${backup_db_dir}" "${backup_files_dir}"

touch "${log_file}"
if getent group adm >/dev/null 2>&1; then
  chown root:adm "${log_file}"
else
  chown root:root "${log_file}"
fi
chmod 640 "${log_file}"

log_info "检测时区: ${tz_name}"

if ! command -v rclone >/dev/null 2>&1; then
  log_info "未检测到 rclone，开始安装。"
  if ! command -v curl >/dev/null 2>&1; then
    log_info "安装 curl。"
    apt-get update -y
    apt-get install -y curl
  fi
  if ! dpkg -s ca-certificates >/dev/null 2>&1; then
    log_info "安装 ca-certificates。"
    apt-get update -y
    apt-get install -y ca-certificates
  fi
  curl -fsSL https://rclone.org/install.sh | bash
else
  log_ok "已检测到 rclone: $(rclone version | head -n1)"
fi

if ! rclone version >/dev/null 2>&1; then
  die "rclone 安装失败或不可用。"
fi

rclone_config_file="$(rclone config file 2>/dev/null | awk -F': ' '/Configuration file is/ {print $2}')"
if [[ -z "${rclone_config_file}" ]]; then
  rclone_config_file="/root/.config/rclone/rclone.conf"
fi
log_info "rclone 配置文件路径: ${rclone_config_file}"

mapfile -t remotes < <(rclone listremotes 2>/dev/null || true)
if [[ ${#remotes[@]} -eq 0 ]]; then
  log_warn "未检测到任何 Rclone remote。"
  read -r -p "未检测到任何 Rclone remote。是否现在进入交互配置 (rclone config)？[Y/n] " answer
  answer="${answer:-Y}"
  if [[ "${answer}" =~ ^[Yy]$ ]]; then
    rclone config
  fi
  mapfile -t remotes < <(rclone listremotes 2>/dev/null || true)
  if [[ ${#remotes[@]} -eq 0 ]]; then
    log_warn "仍未配置任何 remote。后续备份将无法同步到远端。"
    read -r -p "是否继续安装？继续将导致备份同步失败。[y/N] " continue_answer
    continue_answer="${continue_answer:-N}"
    if [[ ! "${continue_answer}" =~ ^[Yy]$ ]]; then
      die "用户取消。请先配置 rclone remote。"
    fi
  fi
fi

remote_name=""
if [[ ${#remotes[@]} -gt 0 ]]; then
  log_info "可用 remotes: ${remotes[*]}"
  while [[ -z "${remote_name}" ]]; do
    read -r -p "请输入 Remote Name（例如 mydrive 或 mydrive:）：" input_name
    input_name="${input_name// /}"
    input_name="${input_name%:}"
    if [[ -z "${input_name}" ]]; then
      log_warn "Remote Name 不能为空。"
      continue
    fi
    for remote in "${remotes[@]}"; do
      if [[ "${remote%:}" == "${input_name}" ]]; then
        remote_name="${input_name}"
        break
      fi
    done
    if [[ -z "${remote_name}" ]]; then
      log_warn "Remote Name 不匹配现有配置。"
    fi
  done
else
  remote_name="未配置"
fi

remote_path=""
while [[ -z "${remote_path}" ]]; do
  read -r -p "请输入 Remote Path（例如 backups/my-vps）：" input_path
  input_path="${input_path#/}"
  input_path="${input_path%/}"
  if [[ -z "${input_path}" ]]; then
    log_warn "Remote Path 不能为空。"
    continue
  fi
  remote_path="${input_path}"
done

admin_email=""
while [[ -z "${admin_email}" ]]; do
  read -r -p "请输入告警接收邮箱（用于失败通知）：" input_email
  if [[ "${input_email}" =~ .+@.+\..+ ]]; then
    admin_email="${input_email}"
  else
    log_warn "邮箱格式不正确。"
  fi
done

if ! command -v mail >/dev/null 2>&1; then
  log_info "安装 mailutils。"
  apt-get update -y
  apt-get install -y mailutils
fi

if systemctl is-active --quiet postfix; then
  log_ok "postfix 服务正在运行。"
else
  log_warn "postfix 服务未运行，失败告警可能无法发送。"
fi

web_root=""
if [[ -d /var/www ]] && [[ -n "$(ls -A /var/www 2>/dev/null)" ]]; then
  web_root="/var/www"
  log_ok "检测到默认站点目录: ${web_root}"
else
  while [[ -z "${web_root}" ]]; do
    read -r -p "未检测到 /var/www 或为空。请输入网站根目录路径：" input_root
    if [[ -d "${input_root}" ]]; then
      web_root="${input_root}"
    else
      log_warn "路径不存在，请重新输入。"
    fi
  done
fi

log_info "数据库备份方式：1) 使用 /root/.my.cnf (推荐) 2) 临时输入 DB 用户/密码 3) 跳过 DB 备份"
read -r -p "请选择 [1-3]：" db_option
case "${db_option}" in
  1)
    db_mode="mycnf"
    ;;
  2)
    db_mode="temp"
    read -r -p "请输入 DB 用户名：" db_user
    read -r -s -p "请输入 DB 密码（不会回显）：" db_password
    echo
    if [[ -z "${db_user}" || -z "${db_password}" ]]; then
      die "DB 用户名或密码为空。"
    fi
    log_info "将写入 /root/.my.cnf 以供备份使用。"
    cat <<MYCNF > /root/.my.cnf
[client]
user=${db_user}
password=${db_password}
MYCNF
    chmod 600 /root/.my.cnf
    db_mode="mycnf"
    ;;
  3)
    db_mode="skip"
    ;;
  *)
    die "无效选项。"
    ;;
esac

runner_path="/usr/local/bin/hz-backup.sh"
cat <<RUNNER > "${runner_path}"
#!/usr/bin/env bash
set -Eeuo pipefail

ADMIN_EMAIL="${admin_email}"
REMOTE_NAME="${remote_name}"
REMOTE_PATH="${remote_path}"
WEB_ROOT="${web_root}"
DB_MODE="${db_mode}"

backup_root="/root/backups"
backup_db_dir="${backup_root}/db"
backup_files_dir="${backup_root}/files"
log_file="/var/log/hz-backup.log"
lock_file="/var/lock/hz-backup.lock"

log_with_ts() {
  local line
  while IFS= read -r line; do
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${line}"
  done
}

exec > >(log_with_ts >> "${log_file}") 2>&1

log_info() { echo "[INFO] $*"; }
log_ok() { echo "[OK] $*"; }
log_warn() { echo "[WARN] $*"; }
log_err() { echo "[ERR] $*"; }

send_failure_email() {
  local step="$1"
  local host
  host="$(hostname)"
  {
    echo "主机名: ${host}"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "失败步骤: ${step}"
    echo
    echo "日志尾部:"
    tail -n 80 "${log_file}"
  } | mail -s "Backup Failed" "${ADMIN_EMAIL}"
}

with_lock() {
  exec 200>"${lock_file}"
  if ! flock -n 200; then
    log_warn "检测到任务正在运行，跳过本次备份。"
    exit 0
  fi
}

keep_latest_n_files() {
  local dir="$1"
  local pattern="$2"
  local keep="$3"
  mapfile -t files < <(ls -1t "${dir}/${pattern}" 2>/dev/null || true)
  if (( ${#files[@]} > keep )); then
    for ((i=keep; i<${#files[@]}; i++)); do
      rm -f -- "${files[$i]}"
    done
  fi
}

with_lock

log_info "开始备份。"

mkdir -p "${backup_db_dir}" "${backup_files_dir}"
chmod 700 "${backup_root}" "${backup_db_dir}" "${backup_files_dir}"

db_backup_file=""
if [[ "${DB_MODE}" == "skip" ]]; then
  log_warn "已选择跳过数据库备份。"
else
  log_info "执行数据库备份。"
  if [[ -f /root/.my.cnf ]]; then
    db_backup_file="${backup_db_dir}/db-all-$(date '+%Y%m%d-%H%M%S').sql.gz"
    if mysqldump --all-databases --single-transaction --quick --routines --triggers | gzip -c > "${db_backup_file}"; then
      log_ok "数据库备份完成: ${db_backup_file}"
      find "${backup_db_dir}" -type f -name '*.gz' -mtime +14 -delete
    else
      log_err "数据库备份失败。"
      send_failure_email "数据库备份"
      exit 1
    fi
  else
    log_err "未找到 /root/.my.cnf，无法进行数据库备份。"
    send_failure_email "数据库备份"
    exit 1
  fi
fi

log_info "执行文件备份。"
files_backup_file="${backup_files_dir}/files-$(date '+%Y%m%d-%H%M%S').tar.gz"
exclude_args=(
  --exclude='*/cache/*'
  --exclude='*/wp-content/cache/*'
  --exclude='*/wp-content/litespeed/*'
  --exclude='*/wp-content/uploads/litespeed/*'
)
if [[ "${WEB_ROOT}" == "${backup_root}"* ]]; then
  exclude_args+=("--exclude=${backup_root}/*")
fi

if tar -czf "${files_backup_file}" "${exclude_args[@]}" -C "${WEB_ROOT}" .; then
  log_ok "文件备份完成: ${files_backup_file}"
  keep_latest_n_files "${backup_files_dir}" "files-*.tar.gz" 14
else
  log_err "文件备份失败。"
  send_failure_email "文件备份"
  exit 1
fi

if [[ -n "${REMOTE_NAME}" && -n "${REMOTE_PATH}" && "${REMOTE_NAME}" != "未配置" ]]; then
  log_info "开始 rclone 同步。"
  if rclone sync "${backup_root}" "${REMOTE_NAME}:${REMOTE_PATH}" \
    --transfers 4 \
    --checkers 4 \
    --retries 3 \
    --low-level-retries 10 \
    --retries-sleep 10s \
    --timeout 1m \
    --contimeout 15s \
    --stats 30s \
    --log-level INFO; then
    log_ok "rclone 同步完成。"
  else
    log_err "rclone 同步失败。"
    send_failure_email "rclone 同步"
    exit 1
  fi
else
  log_warn "未配置 remote，跳过 rclone 同步。"
fi

log_ok "备份流程完成。"
log_info "最近数据库备份: ${db_backup_file:-无}"
log_info "最近文件备份: ${files_backup_file}"
log_info "远端目标: ${REMOTE_NAME}:${REMOTE_PATH}"
log_info "日志文件: ${log_file}"
RUNNER

chmod 755 "${runner_path}"

cron_line="0 3 * * * ${runner_path}"
if crontab -l 2>/dev/null | grep -F "${runner_path}" >/dev/null 2>&1; then
  log_ok "已存在定时任务，未重复添加。"
else
  (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
  log_ok "已添加定时任务: ${cron_line}"
fi

log_ok "安装完成。"
log_info "测试说明："
log_info "- 安装脚本会安装 rclone 并生成备份脚本"
log_info "- 执行 ${runner_path} 可手动触发备份"
log_info "- 备份失败会发送邮件通知"
log_info "- 定时任务已设置为每日 03:00"
