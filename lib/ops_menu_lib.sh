#!/usr/bin/env bash

if [ -z "${REPO_ROOT:-}" ]; then
  echo "❌ Error: REPO_ROOT is not set. Run via hz.sh or installer."
  return 1
fi

ops_pause() {
  read -r -p "按回车继续..." _
}

ops_root_crontab_has() {
  local pattern="$1"

  if command -v crontab >/dev/null 2>&1; then
    if crontab -l -u root 2>/dev/null | grep -q -- "$pattern"; then
      return 0
    fi
  fi

  return 1
}

get_fail2ban_status_tag() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet fail2ban 2>/dev/null && [ -f /etc/fail2ban/jail.local ]; then
      echo "[已启用]"
      return 0
    fi
  fi

  echo "[未配置]"
  return 0
}

get_postfix_status_tag() {
  if [ -f /etc/postfix/sasl_passwd ]; then
    echo "[已配置]"
  else
    echo "[未配置]"
  fi
}

get_rclone_backup_status_tag() {
  if [ -f /etc/cron.d/hz-backup ] || ops_root_crontab_has "hz-backup.sh"; then
    echo "[已计划]"
  else
    echo "[未配置]"
  fi
}

get_healthcheck_status_tag() {
  if ops_root_crontab_has "hz-healthcheck.sh"; then
    echo "[已计划]"
  else
    echo "[未配置]"
  fi
}

get_rkhunter_status_tag() {
  if [ -f /etc/cron.d/rkhunter ] || [ -f /etc/default/rkhunter ]; then
    echo "[已计划]"
  else
    echo "[未配置]"
  fi
}

show_ops_menu() {
  local choice

  if ! command -v log_info >/dev/null 2>&1; then
    if [ -f "${REPO_ROOT}/lib/common.sh" ]; then
      # shellcheck source=/dev/null
      source "${REPO_ROOT}/lib/common.sh"
    fi
  fi
  if ! command -v log_warn >/dev/null 2>&1; then
    log_warn() { echo "[WARN] $*" >&2; }
  fi

  while true; do
    echo
    echo "=== 运维与安全中心 ==="
    echo "  1) Fail2Ban 防御部署 $(get_fail2ban_status_tag)"
    echo "  2) Postfix 邮件告警配置 $(get_postfix_status_tag)"
    echo "  3) Rclone 备份策略 $(get_rclone_backup_status_tag)"
    echo "  4) HealthCheck 健康检查 $(get_healthcheck_status_tag)"
    echo "  5) Rkhunter 入侵检测 $(get_rkhunter_status_tag)"
    echo "  0) 返回上一级"
    read -r -p "请输入选项 [0-5]: " choice

    case "$choice" in
      1)
        if [ -f "${REPO_ROOT}/modules/security/install-fail2ban.sh" ]; then
          bash "${REPO_ROOT}/modules/security/install-fail2ban.sh"
        else
          log_warn "模块不存在：modules/security/install-fail2ban.sh"
        fi
        ops_pause
        continue
        ;;
      2)
        if [ -f "${REPO_ROOT}/modules/mail/setup-postfix-relay.sh" ]; then
          bash "${REPO_ROOT}/modules/mail/setup-postfix-relay.sh"
        else
          log_warn "模块不存在：modules/mail/setup-postfix-relay.sh"
        fi
        ops_pause
        continue
        ;;
      3)
        if [ -f "${REPO_ROOT}/modules/backup/setup-backup-rclone.sh" ]; then
          bash "${REPO_ROOT}/modules/backup/setup-backup-rclone.sh"
        else
          log_warn "模块不存在：modules/backup/setup-backup-rclone.sh"
        fi
        ops_pause
        continue
        ;;
      4)
        if [ -f "${REPO_ROOT}/modules/monitor/setup-healthcheck.sh" ]; then
          bash "${REPO_ROOT}/modules/monitor/setup-healthcheck.sh"
        else
          log_warn "模块不存在：modules/monitor/setup-healthcheck.sh"
        fi
        ops_pause
        continue
        ;;
      5)
        if [ -f "${REPO_ROOT}/modules/security/install-rkhunter.sh" ]; then
          bash "${REPO_ROOT}/modules/security/install-rkhunter.sh"
        else
          log_warn "模块不存在：modules/security/install-rkhunter.sh"
        fi
        ops_pause
        continue
        ;;
      0)
        return 0
        ;;
      *)
        echo "无效选项，请重试。"
        continue
        ;;
    esac
  done
}
