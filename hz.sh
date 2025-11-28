#!/usr/bin/env bash
set -e

# 颜色函数
cyan()   { printf '\033[36m%s\033[0m\n' "$@"; }
green()  { printf '\033[32m%s\033[0m\n' "$@"; }
yellow() { printf '\033[33m%s\033[0m\n' "$@"; }

main_menu() {
  clear
  cyan "hz-oneclick - HorizonTech Installer (Preview)"
  green "hz-oneclick - HorizonTech 一键安装入口（预览版）"
  echo

  cyan "菜单选项 / Menu options"
  cyan "  1) Immich on Cloud (VPS / OCI) / Immich 上云"
  green "  2) rclone basics / rclone 基础安装"
  cyan "  3) Plex Media Server / Plex 媒体服务器"
  green "  4) Transmission (BT download) / Transmission BT 下载"
  cyan "  5) Tailscale / Tailscale “接入”"
  green "  6) Cloudflare Tunnel / Cloudflare Tunnel"
  cyan "  7) msmtp + Brevo (SMTP) / 邮件报警（msmtp + Brevo）"
  green "  8) WP backup (DB + files) / WordPress 备份（数据库 + 文件）"
  yellow "  0) Exit / 退出"
  yellow "  0) Exit / 退出"
  echo

  read -rp "Please enter a number and press Enter / 请输入编号并按回车: " choice

  case "$choice" in
    1)
      echo "暂时保留 Immich on Cloud 选项，安装脚本稍后补齐…"
      ;;
    2)
      echo "将调用 rclone 基础安装脚本…"
      curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/rclone/install.sh | bash
      ;;
    3)
      echo "预留 Plex 安装模块（暂未实现）…"
      ;;
    4)
      echo "预留 Transmission 安装模块（暂未实现）…"
      ;;
    5)
      echo "预留 Tailscale 安装模块（暂未实现）…"
      ;;
    6)
      echo "预留 Cloudflare Tunnel 安装模块（暂未实现）…"
      ;;
    7)
      echo "将调用 msmtp + Brevo 邮件系统安装脚本…"
      curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/mail/setup-msmtp-brevo.sh | bash
      ;;
    8) echo "正在安装 WordPress 备份脚本..."; \
     curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/wp/setup-wp-backup-basic.sh | bash
     ;;
    0)
      echo "再见～"
      exit 0
      ;;
    *)
      echo "无效选项 / Invalid choice：请重新输入编号。"
      ;;
  esac

  echo
  read -rp "按回车返回主菜单… / Press Enter to go back to main menu... " _
  main_menu
}

main_menu
