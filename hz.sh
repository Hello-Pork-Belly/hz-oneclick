#!/usr/bin/env bash
set -euo pipefail

# 颜色输出
cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

# 全局语言变量：en / zh
HZ_LANG=""
HZ_BASELINE_FORMAT="${HZ_BASELINE_FORMAT:-text}"
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL:-https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main}"
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL%/}"

baseline_menu_normalize_format() {
  local format
  format="${1:-text}"
  case "${format,,}" in
    json)
      echo "json"
      ;;
    *)
      echo "text"
      ;;
  esac
}

baseline_menu_normalize_lang() {
  local lang
  lang="${1:-zh}"
  if [[ "${lang,,}" == en* ]]; then
    echo "en"
  else
    echo "zh"
  fi
}

parse_global_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --format)
        HZ_BASELINE_FORMAT="$(baseline_menu_normalize_format "${2:-$HZ_BASELINE_FORMAT}")"
        shift 2
        ;;
      --format=*)
        HZ_BASELINE_FORMAT="$(baseline_menu_normalize_format "${1#--format=}")"
        shift
        ;;
      --help|-h)
        echo "Usage: $0 [--format text|json]"
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done
}

baseline_diagnostics_menu() {
  local diag_domain diag_lang choice lang_input diag_format format_input

  diag_lang="$(baseline_menu_normalize_lang "$HZ_LANG")"
  diag_format="$(baseline_menu_normalize_format "$HZ_BASELINE_FORMAT")"
  while true; do
    clear

    if [ "$diag_lang" = "en" ]; then
      echo "== Baseline Diagnostics =="
      echo "Enter a domain to diagnose (optional, press Enter to skip):"
    else
      echo "== 基础诊断（Baseline Diagnostics）=="
      echo "请输入要诊断的域名（可留空跳过域名相关检查）："
    fi
    read -r diag_domain

    if [ "$diag_lang" = "en" ]; then
      echo "Select language for diagnostics [en/zh] (default: $diag_lang):"
    else
      echo "选择诊断语言 [en/zh]（默认：$diag_lang）："
    fi
    read -r lang_input
    diag_lang="$(baseline_menu_normalize_lang "${lang_input:-$diag_lang}")"

    if [ "$diag_lang" = "en" ]; then
      echo "Select output format [text/json] (default: $diag_format):"
    else
      echo "选择输出格式 [text/json]（默认：$diag_format）："
    fi
    read -r format_input
    diag_format="$(baseline_menu_normalize_format "${format_input:-$diag_format}")"

    while true; do
      clear
      if [ "$diag_lang" = "en" ]; then
        cyan "Baseline Diagnostics"
        echo "Domain: ${diag_domain:-<none>}"
        echo "Language: ${diag_lang}"
        echo "Format: ${diag_format}"
        echo "  1) Run Quick Triage (521/HTTPS/TLS first)"
        echo "  2) Run DNS/IP baseline group"
        echo "  3) Run Origin/Firewall baseline group"
        echo "  4) Run Proxy/CDN baseline group"
        echo "  5) Run TLS/HTTPS baseline group"
        echo "  6) Run LSWS/OLS baseline group"
        echo "  7) Run WP/App baseline group"
        echo "  8) Run Cache/Redis/OPcache baseline group"
        echo "  9) Run System/Resource baseline group"
        echo "  d) Update domain/language"
        echo "  0) Back"
        read -rp "Please enter a choice: " choice
      else
        cyan "基础诊断（Baseline Diagnostics）"
        echo "域名：${diag_domain:-<无>}"
        echo "语言：${diag_lang}"
        echo "输出格式：${diag_format}"
        echo "  1) Quick Triage（优先排查 521/HTTPS/TLS）"
        echo "  2) DNS/IP 基线检查"
        echo "  3) 源站/防火墙 基线检查"
        echo "  4) 代理/CDN 基线检查"
        echo "  5) TLS/HTTPS 基线检查"
        echo "  6) LSWS/OLS 基线检查"
        echo "  7) WP/App 基线检查"
        echo "  8) 缓存/Redis/OPcache 基线检查"
        echo "  9) 系统/资源 基线检查"
        echo "  d) 更新域名/语言"
        echo "  0) 返回"
        read -rp "请输入选项: " choice
      fi

      case "$choice" in
        1)
          echo "Running Baseline Quick Triage (read-only checks)..."
          HZ_TRIAGE_USE_LOCAL=1 HZ_TRIAGE_LOCAL_ROOT="$(pwd)" HZ_TRIAGE_LANG="$diag_lang" HZ_TRIAGE_DOMAIN="$diag_domain" HZ_TRIAGE_FORMAT="$diag_format" bash ./modules/diagnostics/quick-triage.sh --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        2)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-dns-ip.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        3)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-origin-firewall.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        4)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-proxy-cdn.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        5)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-tls-https.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        6)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-lsws-ols.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        7)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-wp-app.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        8)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-cache.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        9)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-system.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        d|D)
          break
          ;;
        0)
          return
          ;;
        *)
          echo "Invalid choice, please try again."
          read -rp "Press Enter to continue..." _
          ;;
      esac
    done
  done
}

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
      cyan  "  1) Immich on Cloud (VPS)"
      green "  2) rclone basics (OneDrive etc.)"
      cyan  "  3) Plex Media Server"
      green "  4) Transmission (BT download)"
      cyan  "  5) Tailscale access"
      green "  6) Edge Tunnel / Reverse Proxy"
      cyan  "  7) msmtp + Brevo (SMTP alert)"
      green "  8) WP backup (DB + files)"
      cyan  "  9) wp-cron helper (system cron for WordPress)"
      green  " 10) rkhunter (rootkit / trojan scanner)"
      cyan  "  11) rkhunter (daily check / optional mail alert)"
      green " 12) Baseline Diagnostics"
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
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/rclone/install.sh")
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
          echo "Edge tunnel / reverse proxy helper scripts are not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        7)
          echo "Running msmtp + Brevo alert setup..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/mail/setup-msmtp-brevo.sh")
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        8)
          echo "Running WordPress backup (DB + files) setup..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/setup-wp-backup-basic-en.sh")
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        9)
          echo "Running wp-cron helper (system cron for WordPress)..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/gen-wp-cron-en.sh")
          ;;
        10)
          echo "Installing rkhunter (rootkit / trojan scanner) ..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/install-rkhunter-en.sh")
          ;;
        11)
          echo "rkhunter (setting / optional mail alert)) ..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/setup-rkhunter-cron-en.sh")
          ;;
        12)
          baseline_diagnostics_menu
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
      cyan  "  1) Immich 上云（VPS）"
      green "  2) rclone 基础安装（OneDrive 等）"
      cyan  "  3) Plex 媒体服务器"
      green "  4) Transmission BT 下载"
      cyan  "  5) Tailscale 接入"
      green "  6) 反向代理/隧道穿透"
      cyan  "  7) 邮件报警（msmtp + Brevo）"
      green "  8) WordPress 备份（数据库 + 文件）"
      cyan  "  9) wp-cron 定时任务向导"
      green "  10) rkhunter（系统后门 / 木马检测）"
      cyan  "  11) rkhunter 定时扫描(报错邮件通知 /日志维护）"
      green "  12) 基础诊断（Baseline Diagnostics）"
      cyan  "  13) LOMP/LNMP（DB / Redis 配置）"
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
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/rclone/install.sh")
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
          echo "反向代理/隧道辅助脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        7)
          echo "即将安装 msmtp + Brevo 邮件报警模块..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/mail/setup-msmtp-brevo.sh")
          read -rp "完成。按回车返回菜单..." _
          ;;
        8)
          echo "即将安装 WordPress 备份模块（数据库 + 文件）..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/setup-wp-backup-basic.sh")
          read -rp "完成。按回车返回菜单..." _
          ;;
        9)
          echo "将运行 wp-cron 定时任务向导..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/gen-wp-cron.sh")
          ;;
        10)
          echo "将安装 / 初始化 rkhunter（系统后门 / 木马检测）..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/install-rkhunter.sh")
          ;;
        11)
          echo "将设置 rkhunter 定时扫描（报错邮件通知 /日志维护）..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/setup-rkhunter-cron.sh")
          ;;
        12)
          baseline_diagnostics_menu
          ;;
        13)
          echo "将安装OLS+WP （ DB/Redis ）..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/install-ols-wp-standard.sh")
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
parse_global_args "$@"
choose_lang
main_menu
