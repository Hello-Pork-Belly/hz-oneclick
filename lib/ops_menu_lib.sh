#!/usr/bin/env bash

if [[ -z "${REPO_ROOT:-}" ]]; then
  return 1
fi

pause_for_key() {
  read -r -p "按回车键继续..." _
}

run_module() {
  local script_path="$1"
  if [[ ! -f "$script_path" ]]; then
    echo "File missing: $script_path"
    pause_for_key
    return 0
  fi
  bash "$script_path"
}

show_ops_menu() {
  while true; do
    echo ""
    echo "==== 运维中心 ===="
    echo "1) 安装 Fail2ban"
    echo "2) 配置 Postfix Relay"
    echo "3) 配置 Rclone 备份"
    echo "4) 设置健康检查"
    echo "5) 安装 RKHunter"
    echo "0) Back"
    read -r -p "请选择: " choice

    case "$choice" in
      1)
        run_module "${REPO_ROOT}/modules/security/install-fail2ban.sh"
        ;;
      2)
        run_module "${REPO_ROOT}/modules/mail/setup-postfix-relay.sh"
        ;;
      3)
        run_module "${REPO_ROOT}/modules/backup/setup-backup-rclone.sh"
        ;;
      4)
        run_module "${REPO_ROOT}/modules/monitor/setup-healthcheck.sh"
        ;;
      5)
        run_module "${REPO_ROOT}/modules/security/install-rkhunter.sh"
        ;;
      0)
        return 0
        ;;
      *)
        echo "无效选项，请重试。"
        ;;
    esac
  done
}
