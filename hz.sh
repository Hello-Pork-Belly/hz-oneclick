#!/usr/bin/env bash

set -e

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

main_menu() {
  clear
  cyan "hz-oneclick - HorizonTech 一键安装入口（预览版）"
  echo

  # 菜单项：青色 / 绿色 交错
  cyan  " 1) Immich 上云 (VPS / OCI)"
  green " 2) rclone 基础安装"
  cyan  " 3) Plex 媒体服务器"
  green " 4) Transmission / BT 下载"
  cyan  " 5) Tailscale"
  green " 6) Cloudflare Tunnel"
  echo
  yellow " 0) 退出"
  echo

  read -rp "请选择编号并按回车: " choice

  case "$choice" in
    1) echo " [预览] 将调用：immich-cloud 仓库中的脚本（尚未接好）…" ;;
    2) echo " [预览] 将调用：rclone 安装与基础配置脚本…" ;;
    3) echo " [预览] 将调用：Plex 安装脚本…" ;;
    4) echo " [预览] 将调用：Transmission 安装脚本…" ;;
    5) echo " [预览] 将调用：Tailscale 安装脚本…" ;;
    6) echo " [预览] 将调用：Cloudflare Tunnel 安装脚本…" ;;
    0) echo "Bye~"; exit 0 ;;
    *) echo "无效选项，请重新输入。" ;;
  esac

  echo
  read -rp "按回车返回主菜单..." _
  main_menu
}

main_menu
