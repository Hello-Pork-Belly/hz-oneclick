#!/usr/bin/env bash
# Postfix Null Client（仅发送）中继配置脚本
# - 设计目标：替换 msmtp，用 Postfix 作为仅发送的 SMTP 中继客户端
# - 可重复运行：每次运行会备份配置到 /root/hz-oneclick-backups/
# - 备份位置：/root/hz-oneclick-backups/mail-YYYYmmdd-HHMMSS/ 或 postfix-YYYYmmdd-HHMMSS/

set -euo pipefail

log_info() { echo -e "[INFO] $*"; }
log_ok() { echo -e "[ OK ] $*"; }
log_warn() { echo -e "[WARN] $*"; }
log_err() { echo -e "[ERR ] $*"; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_err "请用 root 运行本脚本。"
    exit 1
  fi
}

require_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log_err "当前系统非 Debian/Ubuntu（缺少 apt-get），退出。"
    exit 1
  fi
}

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

backup_paths() {
  local backup_dir="$1"
  shift
  mkdir -p "${backup_dir}"
  local path
  for path in "$@"; do
    if [ -e "${path}" ]; then
      cp -a "${path}" "${backup_dir}/"
    fi
  done
}

is_pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

detect_conflicts() {
  local conflicts=()
  local pkgs=(msmtp msmtp-mta sendmail sendmail-bin exim4 ssmtp)
  local pkg
  for pkg in "${pkgs[@]}"; do
    if is_pkg_installed "${pkg}"; then
      conflicts+=("${pkg}")
    fi
  done

  if [ "${#conflicts[@]}" -eq 0 ]; then
    return 0
  fi

  log_warn "检测到潜在冲突的邮件组件：${conflicts[*]}"
  log_warn "可能相关配置文件："
  local cfgs=(/etc/msmtprc /etc/msmtp /etc/msmtp.conf /etc/mailname /etc/exim4 /etc/ssmtp /etc/mail.rc)
  local cfg
  for cfg in "${cfgs[@]}"; do
    if [ -e "${cfg}" ]; then
      echo " - ${cfg}"
    fi
  done

  read -r -p "检测到潜在冲突的邮件组件，是否备份并移除？[y/N] " answer
  if [[ "${answer}" =~ ^[Yy]$ ]]; then
    local backup_dir="/root/hz-oneclick-backups/mail-$(timestamp)"
    log_info "备份配置到 ${backup_dir}"
    backup_paths "${backup_dir}" "${cfgs[@]}"
    log_info "移除冲突组件（仅已安装者）"
    apt-get remove --purge -y "${conflicts[@]}"
    log_ok "已完成备份与移除。"
  else
    log_warn "选择保留冲突组件，可能导致行为不可预期。"
  fi
}

install_postfix_packages() {
  log_info "准备安装 Postfix 相关包（非交互）"
  export DEBIAN_FRONTEND=noninteractive
  local mailname
  mailname="$(hostname -f 2>/dev/null || hostname)"
  echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
  echo "postfix postfix/mailname string ${mailname}" | debconf-set-selections
  apt-get update -y
  apt-get install -y postfix libsasl2-modules mailutils ca-certificates

  if ! is_pkg_installed postfix; then
    log_err "Postfix 安装失败。"
    exit 1
  fi
}

prompt_required() {
  local prompt="$1"
  local var
  while true; do
    read -r -p "${prompt}" var
    if [ -n "${var}" ]; then
      echo "${var}"
      return 0
    fi
    log_warn "输入不能为空，请重试。"
  done
}

prompt_port() {
  local default_port="$1"
  local port
  while true; do
    read -r -p "中继端口 [${default_port}]: " port
    port="${port:-${default_port}}"
    if [[ "${port}" =~ ^[0-9]+$ ]]; then
      echo "${port}"
      return 0
    fi
    log_warn "端口必须是数字，请重试。"
  done
}

set_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  if [ ! -f "${file}" ]; then
    touch "${file}"
  fi

  awk -v key="${key}" -v value="${value}" '
    BEGIN {found=0}
    {
      pattern="^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*="
      if ($0 ~ pattern) {
        if (found == 0) {
          print key " = " value
          found=1
        } else {
          print "# " $0
        }
        next
      }
      print
    }
    END {
      if (found == 0) {
        print key " = " value
      }
    }
  ' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
}

write_file() {
  local file="$1"
  local content="$2"
  printf "%s\n" "${content}" >"${file}"
}

ensure_postfix_config() {
  local relay_host="$1"
  local relay_port="$2"
  local smtp_user="$3"
  local smtp_pass="$4"
  local sender_email="$5"

  local postfix_backup="/root/hz-oneclick-backups/postfix-$(timestamp)"
  if [ -f /etc/postfix/main.cf ]; then
    mkdir -p "${postfix_backup}"
    cp -a /etc/postfix/main.cf "${postfix_backup}/main.cf.bak"
    log_info "已备份 /etc/postfix/main.cf 到 ${postfix_backup}/main.cf.bak"
  fi

  set_kv /etc/postfix/main.cf "inet_interfaces" "loopback-only"
  set_kv /etc/postfix/main.cf "mydestination" ""
  set_kv /etc/postfix/main.cf "relayhost" "[${relay_host}]:${relay_port}"
  set_kv /etc/postfix/main.cf "smtp_sasl_auth_enable" "yes"
  set_kv /etc/postfix/main.cf "smtp_sasl_password_maps" "hash:/etc/postfix/sasl_passwd"
  set_kv /etc/postfix/main.cf "smtp_sasl_security_options" "noanonymous"
  set_kv /etc/postfix/main.cf "smtp_tls_security_level" "encrypt"
  set_kv /etc/postfix/main.cf "smtp_tls_CAfile" "/etc/ssl/certs/ca-certificates.crt"
  set_kv /etc/postfix/main.cf "smtp_tls_note_starttls_offer" "yes"
  set_kv /etc/postfix/main.cf "disable_vrfy_command" "yes"
  set_kv /etc/postfix/main.cf "smtp_header_checks" "regexp:/etc/postfix/header_checks"
  set_kv /etc/postfix/main.cf "sender_canonical_maps" "hash:/etc/postfix/sender_canonical"

  umask 077
  write_file /etc/postfix/sasl_passwd "[${relay_host}]:${relay_port} ${smtp_user}:${smtp_pass}"
  chown root:root /etc/postfix/sasl_passwd
  chmod 600 /etc/postfix/sasl_passwd
  postmap /etc/postfix/sasl_passwd
  chmod 600 /etc/postfix/sasl_passwd.db

  read -r -p "为降低明文风险，是否删除 /etc/postfix/sasl_passwd 仅保留 .db？[y/N] " del_plain
  if [[ "${del_plain}" =~ ^[Yy]$ ]]; then
    rm -f /etc/postfix/sasl_passwd
    log_ok "已删除明文 /etc/postfix/sasl_passwd"
  else
    log_warn "保留明文 /etc/postfix/sasl_passwd（权限 600）。"
  fi

  write_file /etc/postfix/sender_canonical "/^.*/  ${sender_email}"
  chmod 644 /etc/postfix/sender_canonical
  postmap /etc/postfix/sender_canonical

  write_file /etc/postfix/header_checks "/^From:.*root@.*/ REPLACE From: ${sender_email}"
  chmod 644 /etc/postfix/header_checks
}

restart_postfix() {
  systemctl restart postfix
  if systemctl is-active --quiet postfix; then
    log_ok "Postfix 已重启并处于运行状态。"
  else
    log_err "Postfix 未能正常启动。"
    exit 1
  fi
}

show_status() {
  log_info "Postfix 版本："
  postconf -d mail_version || postfix -v || true
  log_info "Postfix 关键配置："
  postconf -n | grep -E '^(inet_interfaces|relayhost|smtp_sasl_auth_enable|smtp_sasl_password_maps|smtp_sasl_security_options|smtp_tls_security_level|smtp_tls_CAfile|smtp_tls_note_starttls_offer|disable_vrfy_command|smtp_header_checks|sender_canonical_maps|mydestination)\s*=' || true
}

send_test_mail() {
  local sender_email="$1"
  local default_recipient="$2"
  read -r -p "现在发送测试邮件？[Y/n] " do_test
  if [[ "${do_test}" =~ ^[Nn]$ ]]; then
    log_info "跳过测试邮件。"
    return 0
  fi

  local recipient
  if [ -n "${default_recipient}" ]; then
    read -r -p "收件人邮箱 [${default_recipient}]: " recipient
    recipient="${recipient:-${default_recipient}}"
  else
    recipient="$(prompt_required "请输入收件人邮箱: ")"
  fi

  echo "This is a test from hz-oneclick Postfix relay." \
    | mail -s "hz-oneclick Postfix relay test" -r "${sender_email}" "${recipient}"
  if [ $? -eq 0 ]; then
    log_ok "测试邮件发送成功。"
  else
    log_err "测试邮件发送失败。"
    log_info "建议检查：/var/log/mail.log（最近 50 行）"
    tail -n 50 /var/log/mail.log || true
    log_info "常见问题：账号或密码错误、587 端口被阻断、TLS 协商失败、服务商要求特定用户名（如 Brevo apikey）。"
    return 1
  fi
}

main() {
  log_info "== preflight =="
  require_root
  require_apt
  detect_conflicts

  log_info "== install =="
  if is_pkg_installed postfix; then
    log_ok "Postfix 已安装，跳过安装步骤。"
  else
    install_postfix_packages
  fi

  log_info "== configure =="
  local relay_host relay_port smtp_user smtp_pass sender_email default_recipient
  relay_host="$(prompt_required "中继主机（如 smtp-relay.brevo.com）: ")"
  relay_port="$(prompt_port 587)"
  smtp_user="$(prompt_required "SMTP 用户名: ")"
  read -r -s -p "SMTP 密码（不回显）: " smtp_pass
  echo
  while [ -z "${smtp_pass}" ]; do
    log_warn "密码不能为空，请重新输入。"
    read -r -s -p "SMTP 密码（不回显）: " smtp_pass
    echo
  done
  sender_email="$(prompt_required "发信邮箱（From）: ")"
  read -r -p "默认测试收件人（可留空）: " default_recipient

  log_info "配置摘要："
  echo " - 中继主机: ${relay_host}"
  echo " - 中继端口: ${relay_port}"
  echo " - 用户名: ${smtp_user}"
  echo " - 密码: ********"
  echo " - 发信邮箱: ${sender_email}"
  if [ -n "${default_recipient}" ]; then
    echo " - 默认测试收件人: ${default_recipient}"
  fi

  read -r -p "确认写入配置并重启 Postfix？[Y/n] " confirm
  if [[ "${confirm}" =~ ^[Nn]$ ]]; then
    log_warn "用户取消，退出。"
    exit 1
  fi

  ensure_postfix_config "${relay_host}" "${relay_port}" "${smtp_user}" "${smtp_pass}" "${sender_email}"

  log_info "== restart =="
  restart_postfix
  show_status

  log_info "== test =="
  send_test_mail "${sender_email}" "${default_recipient}" || true

  log_ok "全部完成。"
}

main "$@"
