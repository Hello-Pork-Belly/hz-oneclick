#!/usr/bin/env bash

ops_require_repo_root() {
  if [ -z "${REPO_ROOT:-}" ]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  fi

  if [ -z "${REPO_ROOT:-}" ] || [ ! -d "${REPO_ROOT}/modules" ]; then
    echo "[ERROR] 无法定位仓库根目录或 modules 目录不存在。"
    return 1
  fi

  return 0
}

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
  local fail2ban_path postfix_path rclone_path healthcheck_path rkhunter_path
  local module_path

  if ! ops_require_repo_root; then
    ops_pause
    return 1
  fi

  fail2ban_path="${REPO_ROOT}/modules/security/install-fail2ban.sh"
  postfix_path="${REPO_ROOT}/modules/mail/setup-postfix-relay.sh"
  rclone_path="${REPO_ROOT}/modules/backup/setup-backup-rclone.sh"
  healthcheck_path="${REPO_ROOT}/modules/monitor/setup-healthcheck.sh"
  rkhunter_path="${REPO_ROOT}/modules/security/install-rkhunter.sh"

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
        module_path="$fail2ban_path"
        ;;
      2)
        module_path="$postfix_path"
        ;;
      3)
        module_path="$rclone_path"
        ;;
      4)
        module_path="$healthcheck_path"
        ;;
      5)
        module_path="$rkhunter_path"
        ;;
      0)
        return 0
        ;;
      *)
        echo "无效选项，请重试。"
        continue
        ;;
    esac

    if [ ! -f "$module_path" ]; then
      echo "[WARN] 模块脚本不存在：${module_path}"
      ops_pause
      continue
    fi

    if ! bash "$module_path"; then
      echo "[WARN] 模块执行失败，请检查日志后重试。"
    fi
    ops_pause
  done
}
