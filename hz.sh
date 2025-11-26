main_menu() {
  clear
  cyan "hz-oneclick - HorizonTech Installer (Preview)"
  cyan "hz-oneclick - HorizonTech 一键安装入口（预览版）"
  echo

  # 菜单选项 / Menu options
  cyan  " 1) Immich on Cloud (VPS / OCI) / Immich 上云"
  cyan  " 2) rclone basics / rclone 基础安装"
  cyan  " 3) Plex Media Server / Plex 媒体服务器"
  cyan  " 4) Transmission (BT download) / Transmission BT 下载"
  cyan  " 5) Tailscale / Tailscale 节点"
  cyan  " 6) Cloudflare Tunnel / Cloudflare Tunnel"
  cyan  " 7) msmtp + Brevo (SMTP) / 邮件报警（msmtp + Brevo）"
  echo
  yellow " 0) Exit / 退出"
  echo

  read -rp "Please enter a number and press Enter / 请输入编号并按回车: " choice

  case "$choice" in
    1)
      echo "暂时保留 Immich on Cloud 模块，将在后续补齐～"
      ;;
    2)
      echo "将执行 rclone 基础安装脚本..."
      curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/rclone/install.sh | bash
      ;;
    3) echo "暂时保留 Plex 安装模块占位～" ;;
    4) echo "暂时保留 Transmission 安装模块占位～" ;;
    5) echo "暂时保留 Tailscale 安装模块占位～" ;;
    6) echo "暂时保留 Cloudflare Tunnel 安装模块占位～" ;;
    7)
      echo "将执行 msmtp + Brevo 邮件发送安装脚本..."
      curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/mail/setup-msmtp-brevo.sh | bash
      ;;
    0)
      echo "再见～"
      exit 0
      ;;
    *)
      echo "无效选项 / Invalid choice：请重新输入。"
      ;;
  esac

  echo
  read -rp "按回车返回主菜单... / Press Enter to go back to main menu... " _
  main_menu
}

main_menu
