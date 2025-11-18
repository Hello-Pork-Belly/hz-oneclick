#!/usr/bin/env bash
set -e

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

main_menu() {
  clear
  cyan  "hz-oneclick - HorizonTech Installer (Preview)"
  cyan  "hz-oneclick - HorizonTech 一键安装入口（预览版）"
  echo

  # 菜单选项 / Menu options
  cyan  " 1) Immich on Cloud (VPS / OCI) / Immich 上云"
  green " 2) rclone basics / rclone 基础安装"
  cyan  " 3) Plex Media Server / Plex 媒体服务器"
  green " 4) Transmission (BT download) / Transmission BT 下载"
  cyan  " 5) Tailscale / Tailscale 节点"
  green " 6) Cloudflare Tunnel / Cloudflare Tunnel"

  echo
  yellow " 0) Exit / 退出"
  echo
  read -rp "Please enter a number and press Enter / 请输入编号并按回车: " choice

  case "$choice" in
    1) echo "〖预览〗Immich on Cloud 相关功能稍后补齐～";;
    2) echo "〖预览〗rclone 基础安装脚本稍后补齐～";;
    3) echo "〖预览〗Plex 安装脚本稍后补齐～";;
    4) echo "〖预览〗Transmission 安装脚本稍后补齐～";;
    5) echo "〖预览〗Tailscale 安装脚本稍后补齐～";;
    6) echo "〖预览〗Cloudflare Tunnel 安装脚本稍后补齐～";;
    0) echo "Bye~ 退出。"; exit 0;;
    *) echo "无效选项 / Invalid choice，请重新输入。";;
  esac

  echo
  read -rp "按回车返回主菜单… / Press Enter to go back to main menu… " _
  main_menu
}

main_menu
