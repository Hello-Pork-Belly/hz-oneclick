#!/usr/bin/env bash
set -e

# 颜色函数
cyan()   { printf '\033[36m%s\033[0m\n' "$@"; }
green()  { printf '\033[32m%s\033[0m\n' "$@"; }
yellow() { printf '\033[33m%s\033[0m\n' "$@"; }

# 默认语言：英文
HZ_LANG="en"

choose_lang() {
  clear
  cyan "hz-oneclick - HorizonTech Installer"

  echo
  echo "Please select language / 请选择语言："
  echo "  1) English"
  echo "  2) 简体中文"
  echo
  read -rp "Enter a number and press Enter: " lang_choice

  case "$lang_choice" in
    2) HZ_LANG="zh" ;;   # 选 2 就切到中文
    *) HZ_LANG="en" ;;   # 其它情况都用英文（包括直接回车）
  esac
}

main_menu() {
  clear

  if [ "$HZ_LANG" = "en" ]; then
    # ===== English menu =====
    cyan  "hz-oneclick - HorizonTech Installer (Preview)"
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
    yellow "  0) Exit"
    echo
    read -rp "Please enter a number and press Enter: " choice

  else
    # ===== 中文菜单 =====
    cyan  "hz-oneclick - HorizonTech 一键安装入口（预览版）"
    green "hz-oneclick - HorizonTech 一键安装入口（预览版）"
    echo
    cyan  "菜单选项"
    cyan  "  1) Immich 上云（VPS / OCI）"
    green "  2) rclone 基础安装（OneDrive 等）"
    cyan  "  3) Plex 媒体服务器"
    green "  4) Transmission BT 下载"
    cyan  "  5) Tailscale “接入”"
    green "  6) Cloudflare Tunnel"
    cyan  "  7) 邮件报警（msmtp + Brevo）"
    green "  8) WordPress 备份（数据库 + 文件）"
    yellow "  0) 退出"
    echo
    read -rp "请输入编号并按回车: " choice
  fi

  case "$choice" in
    1)
      echo "准备安装 Immich on Cloud..."
      # 原来的 1 号逻辑放这里
      ;;
    2)
      echo "准备安装 rclone 基础模块..."
      # ...
      ;;
    7)
      echo "准备安装 msmtp + Brevo 邮件报警模块..."
      bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/mail/setup-msmtp-brevo.sh)
      ;;
    8)
      echo "准备安装 WordPress 备份模块..."
      bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/wp/setup-wp-backup-basic.sh)
      ;;
    0)
      echo "Bye~"
      exit 0
      ;;
    *)
      echo "Invalid choice / 无效输入."
      read -rp "Press Enter to continue... / 按回车继续..." _
      ;;
  esac

  # 执行完一个选项后，回到主菜单
  choose_lang
  main_menu
}
