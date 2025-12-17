#!/usr/bin/env bash
set -euo pipefail

# 颜色输出
cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

# 全局语言变量：en / zh
HZ_LANG=""

choose_lang() {
  while true; do
    clear
    cyan "hz-oneclick - HorizonTech Installer"
    echo
    echo "Please select language / 请选择语言："
    echo "  1) English"
    echo "  2) 简体中文"
    echo "  e) Exit / 退出"
    echo

    read -rp "Enter a choice and press Enter / 请输入选项并按回车: " lang_choice

    case "$lang_choice" in
      1)
        HZ_LANG="en"
        break
        ;;
      2)
        HZ_LANG="zh"
        break
        ;;
      e|E|0)
        echo "Bye~ / 再见～"
        exit 0
        ;;
      *)
        echo "Invalid choice / 无效选项，请重新输入..."
        read -rp "Press Enter to continue / 按回车继续..." _
        ;;
    esac
  done
}

main_menu() {
  while true; do
    clear

    if [ "$HZ_LANG" = "en" ]; then
      # ===== English menu =====
      cyan  "hz-oneclick - HorizonTech Installer (preview)"
      green "hz-oneclick - HorizonTech one-click installer (preview)"
      echo
      cyan  "Menu options"
      cyan  "  1) Immich on Cloud (VPS / OCI)"
      green "  2) rclone basics (OneDrive etc.)"
      cyan  "  3) Plex Media Server"
      green "  4) Transmission (BT download)"
      cyan  "  5) Tailscale access"
      green "  6) Cloudflare Tunnel"
      cyan  "  7) msmtp + Brevo (SMTP alert)"
      green "  8) WP backup (DB + files)"
      cyan  "  9) wp-cron helper (system cron for WordPress)"
      green  " 10) rkhunter (rootkit / trojan scanner)"
      cyan  "  11) rkhunter (daily check / optional mail alert)"
      green " 12) Quick Triage (521/HTTPS/TLS) - export report"
      yellow "  0) Exit"
      green "  r) Return to language selection / 返回语言选择 "
      echo
      read -rp "Please enter a choice and press Enter: " choice

      case "$choice" in
        1)
          echo "Immich installer is not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        2)
          echo "Running rclone basics installer..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/rclone/install.sh)
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        3)
          echo "Plex installer is not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        4)
          echo "Transmission installer is not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        5)
          echo "Tailscale helper scripts are not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        6)
          echo "Cloudflare Tunnel helper scripts are not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        7)
          echo "Running msmtp + Brevo alert setup..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/mail/setup-msmtp-brevo.sh)
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        8)
          echo "Running WordPress backup (DB + files) setup..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/wp/setup-wp-backup-basic-en.sh)
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        9)
          echo "Running wp-cron helper (system cron for WordPress)..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/wp/gen-wp-cron-en.sh)
          ;;
        10)
          echo "Installing rkhunter (rootkit / trojan scanner) ..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/security/install-rkhunter-en.sh)
          ;;
        11)
          echo "rkhunter (setting / optional mail alert)) ..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/security/setup-rkhunter-cron-en.sh)
          ;;
        12)
          echo "Running Baseline Quick Triage (read-only checks)..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh)
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        0)
          echo "Bye~"
          exit 0
          ;;
        r|R)
          # 回到语言选择
          choose_lang
          ;;
        *)
          echo "Invalid choice, please try again."
          read -rp "Press Enter to continue..." _
          ;;
      esac

    else
      # ===== 中文菜单 =====
      cyan  "hz-oneclick - HorizonTech 一键安装入口（预览版）"
      green "hz-oneclick - HorizonTech 一键安装入口（预览版）"
      echo
      cyan  "菜单选项 / Menu options"
      cyan  "  1) Immich 上云（VPS / OCI）"
      green "  2) rclone 基础安装（OneDrive 等）"
      cyan  "  3) Plex 媒体服务器"
      green "  4) Transmission BT 下载"
      cyan  "  5) Tailscale 接入"
      green "  6) Cloudflare Tunnel 穿透"
      cyan  "  7) 邮件报警（msmtp + Brevo）"
      green "  8) WordPress 备份（数据库 + 文件）"
      cyan  "  9) wp-cron 定时任务向导"
      green "  10) rkhunter（系统后门 / 木马检测）"
      cyan  "  11) rkhunter 定时扫描(报错邮件通知 /日志维护）"
      green "  12) Quick Triage（优先排查 521/HTTPS/TLS）- 导出报告"
      cyan  "  13) ols-wp（ DB / redis 配置）"
      yellow "  0) 退出"
      yellow "  r) 返回语言选择 / Return to language selection"
      echo
      read -rp "请输入选项并按回车: " choice

      case "$choice" in
        1)
          echo "Immich 安装脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        2)
          echo "即将安装 rclone 基础模块..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/rclone/install.sh)
          read -rp "完成。按回车返回菜单..." _
          ;;
        3)
          echo "Plex 安装脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        4)
          echo "Transmission 安装脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        5)
          echo "Tailscale 辅助脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        6)
          echo "Cloudflare Tunnel 辅助脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        7)
          echo "即将安装 msmtp + Brevo 邮件报警模块..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/mail/setup-msmtp-brevo.sh)
          read -rp "完成。按回车返回菜单..." _
          ;;
        8)
          echo "即将安装 WordPress 备份模块（数据库 + 文件）..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/wp/setup-wp-backup-basic.sh)
          read -rp "完成。按回车返回菜单..." _
          ;;
        9)
          echo "将运行 wp-cron 定时任务向导..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/wp/gen-wp-cron.sh)
          ;;
        10)
          echo "将安装 / 初始化 rkhunter（系统后门 / 木马检测）..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/security/install-rkhunter.sh)
          ;;
        11)
          echo "将设置 rkhunter 定时扫描（报错邮件通知 /日志维护）..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/security/setup-rkhunter-cron.sh)
          ;;
        12)
          echo "将运行 Baseline Quick Triage（只读排查，自动生成报告）..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh)
          read -rp "完成。按回车返回菜单..." _
          ;;
        13)
          echo "将安装OLS+WP （ DB/Redis ）..."
          bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/wp/install-ols-wp-standard.sh)
          ;;
        0)
          echo "再见～"
          exit 0
          ;;
        r|R)
          # 回到语言选择
          choose_lang
          ;;
        *)
          echo "无效选项，请重新输入。"
          read -rp "按回车继续..." _
          ;;
      esac
    fi
  done
}

# 程序入口
choose_lang
main_menu
