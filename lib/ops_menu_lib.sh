#!/usr/bin/env bash

if [ -z "${REPO_ROOT:-}" ]; then
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
        bash "${REPO_ROOT}/modules/security/install-fail2ban.sh"
        ;;
      2)
        bash "${REPO_ROOT}/modules/mail/setup-postfix-relay.sh"
        ;;
      3)
        bash "${REPO_ROOT}/modules/backup/setup-backup-rclone.sh"
        ;;
      4)
        bash "${REPO_ROOT}/modules/monitor/setup-healthcheck.sh"
        ;;
      5)
        bash "${REPO_ROOT}/modules/security/install-rkhunter.sh"
        ;;
      0)
        return 0
        ;;
      *)
        echo "无效选项，请重试。"
        ;;
    esac

    ops_pause
  done
}
