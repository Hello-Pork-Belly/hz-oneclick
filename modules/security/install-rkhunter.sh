#!/usr/bin/env bash
#
# hz-oneclick - modules/security/install-rkhunter.sh
# Version: 0.1.0 (ZH)
#
# 功能：
#   - 检测当前系统是否适合安装 rkhunter（仅支持 Ubuntu + apt）
#   - 安装 / 重新安装 rkhunter
#   - 执行一次 rkhunter --update + rkhunter --propupd 建立基线
#   - 不自动添加定时任务，也不直接发邮件
#
# 后续配套：
#   - modules/security/setup-rkhunter-cron.sh
#     负责：
#       * 定期执行 rkhunter --update && rkhunter --check --sk
#       * 只在 WARNING / ERROR 时通过 msmtp + Brevo 发邮件
#       * 对 /var/log/rkhunter.log 做简单截断/轮转（例如保留最近 N 天）

SCRIPT_VERSION="0.1.0"
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL:-https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main}"
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL%/}"

# --- 简单输出函数（不依赖 common.sh） ---

info()  { echo -e "[\e[32mINFO\e[0m]  $*"; }
warn()  { echo -e "[\e[33mWARN\e[0m]  $*"; }
error() { echo -e "[\e[31mERROR\e[0m] $*" >&2; }
step()  { echo -e "\n==== $* ====\n"; }

press_enter() {
  read -r -p "按回车键继续..." _
}

prompt_exit_hint() {
  echo "提示：在大部分步骤中输入 0 可以直接退出向导并返回主菜单。"
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error "请使用 root 用户运行本脚本（sudo -i 后再执行）。"
    exit 1
  fi
}

require_ubuntu_apt() {
  if [[ ! -f /etc/os-release ]]; then
    error "无法检测系统类型，/etc/os-release 不存在。暂不支持此系统。"
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID}" != "ubuntu" ]]; then
    error "当前系统不是 Ubuntu（检测到 ID=${ID}）。本脚本目前只支持 Ubuntu。"
    exit 1
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    error "未找到 apt-get，本脚本目前只支持使用 apt 的环境。"
    exit 1
  fi
}

# --- rkhunter 状态检测 ---

is_rkhunter_installed() {
  if command -v rkhunter >/dev/null 2>&1; then
    return 0
  fi
  dpkg -l | grep -qE '^ii\s+rkhunter\b'
}

show_rkhunter_version() {
  if ! command -v rkhunter >/dev/null 2>&1; then
    return
  fi
  # rkhunter --version 的第一行一般包含版本号
  local ver
  ver="$(rkhunter --version 2>/dev/null | head -n1)"
  [[ -n "$ver" ]] && info "当前 rkhunter 版本：$ver"
}

# --- Step 1/4: 简介与风险提示 ---

step1_intro() {
  step "Step 1/4 - rkhunter 简介（后门 / 木马 / Rootkit 检测）"

  cat <<EOF
rkhunter（Rootkit Hunter）用于扫描系统中常见的 rootkit / 木马 / 异常改动。

本向导将会执行：
  1) 通过 apt 安装或重新安装 rkhunter
  2) 执行一次 rkhunter --update 更新数据库
  3) 执行一次 rkhunter --propupd 建立"基线"（记录当前系统文件状态）

不会执行：
  - 不修改数据库、不修改 WordPress 网站文件
  - 不自动添加定时任务
  - 不发送任何告警邮件

说明：
  - 首次执行 rkhunter --propupd 以及后续第一次扫描，耗时可能会稍长（几分钟内），属于正常情况。

EOF

  prompt_exit_hint
  echo
  read -r -p "是否继续安装 / 初始化 rkhunter？(Y/n, 0 = 返回主菜单): " ans
  case "$ans" in
    0)
      info "用户选择退出，返回主菜单。"
      exit 0
      ;;
    ""|Y|y)
      ;;
    *)
      info "用户取消操作，向导结束。"
      exit 0
      ;;
  esac
}

# --- Step 2/4: 检查系统环境 & 安装模式选择 ---

INSTALL_MODE=""

step2_check_env_and_mode() {
  step "Step 2/4 - 检查系统环境"

  require_ubuntu_apt

  info "已检测到当前系统为 Ubuntu + apt，可正常安装 rkhunter。"
  echo

  if is_rkhunter_installed; then
    info "检测到系统已安装 rkhunter。"
    show_rkhunter_version
    echo
    cat <<EOF
你可以选择：
  1) 保持当前安装，仅执行初始化（rkhunter --update + --propupd）（推荐）
  2) 使用 apt 重新安装 rkhunter，然后再执行初始化
  0) 退出并返回主菜单
EOF
    while true; do
      read -r -p "请选择 [1-2, 0]: " choice
      case "$choice" in
        1) INSTALL_MODE="keep";       return ;;
        2) INSTALL_MODE="reinstall";  return ;;
        0)
          info "用户选择退出，返回主菜单。"
          exit 0
          ;;
        *)
          warn "输入无效，请重新输入。"
          ;;
      esac
    done
  else
    warn "未检测到 rkhunter，将通过 apt 安装。"
    echo
    while true; do
      read -r -p "确认安装 rkhunter？(Y/n, 0 = 返回主菜单): " ans
      case "$ans" in
        0)
          info "用户选择退出，返回主菜单。"
          exit 0
          ;;
        ""|Y|y)
          INSTALL_MODE="install"
          return
          ;;
        N|n)
          info "用户取消安装，向导结束。"
          exit 0
          ;;
        *)
          warn "请输入 Y / n / 0。"
          ;;
      esac
    done
  fi
}

# --- Step 3/4: 安装/重装 + 更新 + 初始化基线 ---

step3_install_and_init() {
  step "Step 3/4 - 安装 / 初始化 rkhunter"

  case "$INSTALL_MODE" in
    install)
      info "正在执行：apt-get update ..."
      if ! apt-get update -y >/dev/null 2>&1; then
        error "apt-get update 失败，请稍后重试或手动检查。"
        exit 1
      fi

      info "正在执行：apt-get install -y rkhunter ..."
      if ! apt-get install -y rkhunter; then
        error "安装 rkhunter 失败，请检查网络或 apt 源配置。"
        exit 1
      fi
      ;;
    reinstall)
      info "正在执行：apt-get install --reinstall -y rkhunter ..."
      if ! apt-get install --reinstall -y rkhunter; then
        error "重新安装 rkhunter 失败，请检查网络或 apt 源配置。"
        exit 1
      fi
      ;;
    keep)
      info "保留现有 rkhunter 安装，仅执行更新与初始化。"
      ;;
    *)
      error "内部状态错误：未知的 INSTALL_MODE='${INSTALL_MODE}'。"
      exit 1
      ;;
  esac

  if ! command -v rkhunter >/dev/null 2>&1; then
    error "安装完成后仍未检测到 rkhunter 命令，请手动检查。"
    exit 1
  fi

  show_rkhunter_version
  echo

  info "正在执行：rkhunter --update（更新签名数据库，可能需要几分钟）..."
  if ! rkhunter --update --quiet; then
    warn "rkhunter --update 遇到错误，请稍后手动检查，但向导会继续执行 --propupd。"
  fi

  echo
  info "正在执行：rkhunter --propupd（建立当前系统文件基线）..."
  echo "提示：此步骤会记录当前系统文件状态，首次执行耗时可能略久。"
  if ! rkhunter --propupd --quiet; then
    warn "rkhunter --propupd 遇到错误，请稍后查看 /var/log/rkhunter.log。"
  else
    info "rkhunter 基线初始化完成。"
  fi

  press_enter
}

# --- Step 4/4: 总结 & 下一步建议 ---

step4_summary_and_next() {
  step "Step 4/4 - 安装结果 & 下一步建议"

  cat <<EOF
rkhunter 已完成安装 / 初始化。

关键信息：
  - 配置文件：/etc/rkhunter.conf
  - 日志文件：/var/log/rkhunter.log
  - 已执行过：
      * rkhunter --update
      * rkhunter --propupd

说明：
  - 目前仅完成"安装 + 建立基线"，尚未开启自动定时扫描。
  - 后续建议通过"rkhunter 定时任务 + 邮件报警向导"来：
      * 定期执行 rkhunter --update && rkhunter --check --sk
      * 仅在发现 WARNING / ERROR 时发送告警邮件（依赖 msmtp + Brevo）
      * 定期对 /var/log/rkhunter.log 做简单截断，避免日志无限增长

你也可以手动测试一次扫描：
  rkhunter --check --sk
  tail -n 50 /var/log/rkhunter.log

EOF

  echo "接下来你想要做什么？"
  echo "  1) 返回主菜单（不做后续配置）"
  echo "  2) 立刻进入\"rkhunter 定时任务 + 邮件报警向导\"（需要脚本已在 hz-oneclick 中）"
  echo "  0) 退出本向导"

  while true; do
    read -r -p "请选择 [1-2, 0]: " choice
    case "$choice" in
      1)
        info "返回主菜单。"
        return 0
        ;;
      2)
        info "尝试加载：rkhunter 定时任务 + 邮件报警向导 ..."
        # 未来你会在这个位置放置实际脚本
        # modules/security/setup-rkhunter-cron.sh
        if bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/setup-rkhunter-cron.sh"); then
          info "已从 hz-oneclick 运行 rkhunter 定时任务向导。"
        else
          error "加载 rkhunter 定时任务向导失败，请检查网络或脚本路径。"
        fi
        return 0
        ;;
      0)
        info "用户选择退出，向导结束。"
        exit 0
        ;;
      *)
        warn "输入无效，请重新输入。"
        ;;
    esac
  done
}

# --- 主流程 ---

main() {
  require_root
  step1_intro
  step2_check_env_and_mode
  step3_install_and_init
  step4_summary_and_next
}

main "$@"
