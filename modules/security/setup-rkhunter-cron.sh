#!/usr/bin/env bash
#
# hz-oneclick - modules/security/setup-rkhunter-cron.sh
# Version: 0.1.0 (ZH)
#
# 功能：
#   - 为 rkhunter 创建统一检查脚本（默认：/usr/local/bin/rkhunter-check.sh）
#   - 创建 systemd service + timer（rkhunter-check.service / .timer）
#   - 支持"仅日志"或"调用 send-alert-mail.sh 发邮件"两种模式
#   - 在每次检查后对 /var/log/rkhunter.log 做简单截断，防止无限增大
#
# 前置假设：
#   - rkhunter 已安装并完成初次 propupd（建议通过 install-rkhunter.sh 完成）
#   - 如需邮件告警，系统已配置：
#       /usr/local/bin/send-alert-mail.sh
#     且内部调用 msmtp + Brevo（或其他 SMTP）发送邮件
#

SCRIPT_VERSION="0.1.0"

# 默认路径，可在交互中允许用户修改
DEFAULT_CHECK_SCRIPT="/usr/local/bin/rkhunter-check.sh"
DEFAULT_ALERT_SCRIPT="/usr/local/bin/send-alert-mail.sh"
RK_LOG_FILE="/var/log/rkhunter.log"

# 日志截断策略
LOG_MAX_LINES=5000       # 超过多少行开始截断
LOG_KEEP_LINES=3000      # 截断后保留多少行

# 运行模式：mail / silent
ALERT_MODE="mail"

# --- 简单输出函数 ---

info()  { echo -e "[\e[32mINFO\e[0m]  $*"; }
warn()  { echo -e "[\e[33mWARN\e[0m]  $*"; }
error() { echo -e "[\e[31mERROR\e[0m] $*" >&2; }
step()  { echo -e "\n==== $* ====\n"; }

press_enter() {
  read -r -p "按回车键继续..." _
}

prompt_exit_hint() {
  echo "提示：在大部分步骤中输入 0 可以直接退出向导。"
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error "请使用 root 用户运行本脚本（sudo -i 后再执行）。"
    exit 1
  fi
}

require_rkhunter() {
  if ! command -v rkhunter >/dev/null 2>&1; then
    error "未检测到 rkhunter 命令，请先通过 install-rkhunter.sh 安装并初始化。"
    exit 1
  fi
}

require_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    error "未检测到 systemctl，本脚本目前只支持 systemd 系统。"
    exit 1
  fi
}

# ---------------------------
# Step 1/5 - 简介 & 前置检查
# ---------------------------
step1_intro_and_checks() {
  step "Step 1/5 - rkhunter 定时任务 + 邮件告警简介"

  cat <<EOF
本向导将为 rkhunter 配置：

  1) 一个统一的检查脚本（默认：${DEFAULT_CHECK_SCRIPT}）
     - 每次运行时执行：
         a) rkhunter --update
         b) rkhunter --check --sk
         c) 分析日志中 WARNING / ERROR
         d) 按模式决定是否发送告警邮件
         e) 对 /var/log/rkhunter.log 做简单截断，防止日志无限增大

  2) systemd Service + Timer：
     - Service：rkhunter-check.service
     - Timer： rkhunter-check.timer
     - 可以按每天固定时间、每 12 小时、每 6 小时等频率执行

不会修改：
  - rkhunter 的安装方式（假设你已通过 install-rkhunter.sh 安装并初始化）
  - 你的 WordPress 或数据库

EOF

  prompt_exit_hint
  echo

  require_rkhunter
  require_systemd

  read -r -p "是否继续配置 rkhunter 定时任务 + 邮件告警？(Y/n, 0 = 退出): " ans
  case "$ans" in
    0)
      info "用户选择退出，向导结束。"
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

# ------------------------------------
# Step 2/5 - 告警模式：邮件 or 静默模式
# ------------------------------------
step2_choose_alert_mode() {
  step "Step 2/5 - 告警邮件脚本 / 模式选择"

  local alert_script_path="${DEFAULT_ALERT_SCRIPT}"

  if [[ -x "$alert_script_path" ]]; then
    info "检测到告警邮件脚本：${alert_script_path}"
    cat <<EOF

说明：
  - 本向导会在发现 WARNING / ERROR 时调用该脚本。
  - 默认假设脚本调用方式为：
      ${alert_script_path} "邮件标题" "邮件正文"
  - 邮件内容仅作简要摘要，详细内容请查看 /var/log/rkhunter.log。

EOF
    echo "请选择告警模式："
    echo "  1) 使用上述告警邮件脚本（推荐）"
    echo "  2) 不使用邮件告警，仅记录本机日志"
    echo "  0) 退出"
    while true; do
      read -r -p "请选择 [1-2, 0]: " choice
      case "$choice" in
        1) ALERT_MODE="mail";   return ;;
        2) ALERT_MODE="silent"; return ;;
        0)
          info "用户选择退出，向导结束。"
          exit 0
          ;;
        *)
          warn "输入无效，请重新输入。"
          ;;
      esac
    done
  else
    warn "未检测到 ${alert_script_path}，将默认采用\"仅日志\"模式。"
    cat <<EOF

你可以：
  1) 继续配置，仅在本机日志中查看 rkhunter 结果（不发邮件）
  2) 先退出，在 hz-oneclick 菜单 7 安装"邮件报警（msmtp + Brevo）"并配置好 send-alert-mail.sh 后再回来
  0) 退出

EOF
    while true; do
      read -r -p "请选择 [1-2, 0]: " choice
      case "$choice" in
        1) ALERT_MODE="silent"; return ;;
        2)
          info "建议先完成邮件报警脚本配置，向导结束。"
          exit 0
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
  fi
}

# -------------------------------------------------
# Step 3/5 - 生成 rkhunter-check.sh（含日志截断）
# -------------------------------------------------
CHECK_SCRIPT_PATH=""

step3_gen_check_script() {
  step "Step 3/5 - 生成 rkhunter 检查脚本 (${DEFAULT_CHECK_SCRIPT})"

  echo "默认检查脚本路径为：${DEFAULT_CHECK_SCRIPT}"
  read -r -p "如需修改，请输入新路径（直接回车使用默认）: " custom_path
  if [[ -n "$custom_path" ]]; then
    CHECK_SCRIPT_PATH="$custom_path"
  else
    CHECK_SCRIPT_PATH="$DEFAULT_CHECK_SCRIPT"
  fi

  echo
  warn "即将生成/覆盖：${CHECK_SCRIPT_PATH}"
  read -r -p "确认生成/覆盖该脚本？(Y/n, 0 = 退出): " ans
  case "$ans" in
    0)
      info "用户选择退出，向导结束。"
      exit 0
      ;;
    ""|Y|y)
      ;;
    *)
      info "用户取消生成脚本，向导结束。"
      exit 0
      ;;
  esac

  # 根据 ALERT_MODE 注入不同逻辑
  local alert_mode_in_script="$ALERT_MODE"
  local alert_script_in_script="$DEFAULT_ALERT_SCRIPT"

  cat > "${CHECK_SCRIPT_PATH}" <<EOF
#!/usr/bin/env bash
#
# rkhunter-check.sh - 由 hz-oneclick 生成的 rkhunter 定时检查脚本
#
# 功能：
#   - rkhunter --update
#   - rkhunter --check --sk
#   - 从 /var/log/rkhunter.log 中抽取 WARNING / ERROR
#   - 如启用邮件模式，则调用 send-alert-mail.sh 发送摘要
#   - 控制 /var/log/rkhunter.log 行数，避免无限增长
#

set -euo pipefail

ALERT_MODE="${alert_mode_in_script}"      # mail / silent
ALERT_SCRIPT="${alert_script_in_script}"  # 调用邮件脚本路径（如存在）
RK_LOG_FILE="${RK_LOG_FILE}"
LOG_MAX_LINES=${LOG_MAX_LINES}
LOG_KEEP_LINES=${LOG_KEEP_LINES}

HOSTNAME_STR=\$(hostname)
NOW_STR=\$(date -u +"%Y-%m-%d %H:%M:%S UTC")

log()  { echo "[rkhunter-check][\$(date +'%Y-%m-%d %H:%M:%S')] \$*"; }
warn() { echo "[rkhunter-check][WARN][\$(date +'%Y-%m-%d %H:%M:%S')] \$*" >&2; }

run_rkhunter() {
  log "开始 rkhunter --update ..."
  if ! rkhunter --update --quiet; then
    warn "rkhunter --update 出现错误，请稍后检查。"
  fi

  log "开始 rkhunter --check --sk ..."
  # --nocolors 避免日志中出现控制符
  if ! rkhunter --check --sk --nocolors --quiet; then
    warn "rkhunter --check 返回非零退出码，可能存在 WARNING / ERROR。"
  fi
}

extract_warnings() {
  if [[ ! -f "\$RK_LOG_FILE" ]]; then
    warn "日志文件 \$RK_LOG_FILE 不存在，无法分析 WARNING / ERROR。"
    return 1
  fi

  # 抽取最后 200 行中的 WARNING / ERROR 关键字
  local tmp_snippet
  tmp_snippet=\$(tail -n 200 "\$RK_LOG_FILE" | grep -Ei 'warning|error' || true)

  if [[ -z "\$tmp_snippet" ]]; then
    # 没有 WARNING / ERROR
    echo ""
    return 0
  fi

  echo "\$tmp_snippet"
  return 0
}

maybe_send_mail() {
  local snippet="\$1"

  if [[ "\$ALERT_MODE" != "mail" ]]; then
    log "当前为 silent 模式，不发送邮件。"
    return 0
  fi

  if [[ -z "\$snippet" ]]; then
    log "未检测到新的 WARNING / ERROR，不发送邮件。"
    return 0
  fi

  if [[ ! -x "\$ALERT_SCRIPT" ]]; then
    warn "告警模式为 mail，但未找到可执行的 ALERT_SCRIPT=\$ALERT_SCRIPT。"
    return 1
  fi

  local subject="[ALERT] rkhunter warnings on \$HOSTNAME_STR"
  local body=""
  body+="rkhunter 在主机 \$HOSTNAME_STR 上检测到 WARNING / ERROR。\n"
  body+="时间: \$NOW_STR\n"
  body+="\n"
  body+="以下为最近日志中的关键信息（截取自 \$RK_LOG_FILE 最后 200 行）：\n"
  body+="----------------------------------------\n"
  body+="\$snippet\n"
  body+="----------------------------------------\n"
  body+="\n"
  body+="请登录服务器进一步查看 /var/log/rkhunter.log 以获取完整详情。\n"

  log "发送告警邮件..."
  if ! "\$ALERT_SCRIPT" "\$subject" "\$body"; then
    warn "调用 \$ALERT_SCRIPT 发送邮件失败。"
    return 1
  fi

  log "告警邮件已发送。"
}

rotate_log_if_needed() {
  if [[ ! -f "\$RK_LOG_FILE" ]]; then
    return 0
  fi

  local lines
  lines=\$(wc -l < "\$RK_LOG_FILE" 2>/dev/null || echo 0)

  if [[ "\$lines" -gt "\$LOG_MAX_LINES" ]]; then
    log "rkhunter 日志行数为 \$lines，超过限制 \$LOG_MAX_LINES，开始截断..."
    # 保留最后 LOG_KEEP_LINES 行
    local tmp_file="\${RK_LOG_FILE}.tmp.\$\$"
    tail -n "\$LOG_KEEP_LINES" "\$RK_LOG_FILE" > "\$tmp_file" 2>/dev/null || true
    mv "\$tmp_file" "\$RK_LOG_FILE"
    log "日志截断完成，保留最后 \$LOG_KEEP_LINES 行。"
  fi
}

main() {
  log "===== rkhunter-check 开始 (\$NOW_STR) ====="

  run_rkhunter

  local snippet
  snippet=\$(extract_warnings || true)

  maybe_send_mail "\$snippet"

  rotate_log_if_needed

  log "===== rkhunter-check 结束 (\$NOW_STR) ====="
}

main "\$@"
EOF

  chmod +x "${CHECK_SCRIPT_PATH}"
  info "已生成并赋予可执行权限：${CHECK_SCRIPT_PATH}"
  echo "你可以随时手动运行：${CHECK_SCRIPT_PATH}"
  press_enter
}

# ------------------------------------------------------------
# Step 4/5 - systemd service & timer + 执行频率 / 时间配置
# ------------------------------------------------------------
SERVICE_PATH="/etc/systemd/system/rkhunter-check.service"
TIMER_PATH="/etc/systemd/system/rkhunter-check.timer"

SCHEDULE_MODE=""   # daily / 12h / 6h
DAILY_TIME="03:30" # 默认每天执行时间

step4_setup_systemd() {
  step "Step 4/5 - 创建 systemd Service & Timer"

  if [[ -z "$CHECK_SCRIPT_PATH" ]]; then
    CHECK_SCRIPT_PATH="$DEFAULT_CHECK_SCRIPT"
  fi

  if [[ ! -x "$CHECK_SCRIPT_PATH" ]]; then
    error "检查脚本 ${CHECK_SCRIPT_PATH} 不存在或不可执行，请先完成上一步。"
    exit 1
  fi

  echo "当前系统时间（本地）：$(date)"
  echo "当前 UTC 时间：       $(date -u)"
  echo
  cat <<EOF
说明：
  - 定时任务使用的是系统"本地时间"（上面第一行）。
  - 你可以选择每天固定时间执行，或按 12 小时 / 6 小时周期执行。

请选择执行频率：
  1) 每天固定时间执行（默认 03:30）
  2) 每 12 小时执行一次
  3) 每 6 小时执行一次
  0) 退出
EOF

  while true; do
    read -r -p "请选择 [1-3, 0]: " choice
    case "$choice" in
      1)
        SCHEDULE_MODE="daily"
        read -r -p "请输入每天执行的时间 (HH:MM，24 小时制，回车使用默认 ${DAILY_TIME}): " t
        if [[ -n "$t" ]]; then
          if [[ "$t" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            DAILY_TIME="$t"
          else
            warn "时间格式不正确，使用默认 ${DAILY_TIME}。"
          fi
        fi
        break
        ;;
      2)
        SCHEDULE_MODE="12h"
        break
        ;;
      3)
        SCHEDULE_MODE="6h"
        break
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

  info "开始写入 systemd service：${SERVICE_PATH}"

  cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=rkhunter 定时安全检查
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${CHECK_SCRIPT_PATH}
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

  info "开始写入 systemd timer：${TIMER_PATH}"

  if [[ "$SCHEDULE_MODE" == "daily" ]]; then
    cat > "${TIMER_PATH}" <<EOF
[Unit]
Description=rkhunter 每日安全检查定时任务

[Timer]
OnCalendar=*-*-* ${DAILY_TIME}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  elif [[ "$SCHEDULE_MODE" == "12h" ]]; then
    cat > "${TIMER_PATH}" <<EOF
[Unit]
Description=rkhunter 每 12 小时安全检查定时任务

[Timer]
OnBootSec=5min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF
  else
    cat > "${TIMER_PATH}" <<EOF
[Unit]
Description=rkhunter 每 6 小时安全检查定时任务

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF
  fi

  info "重新加载 systemd 配置并启用 timer..."

  systemctl daemon-reload
  systemctl enable --now rkhunter-check.timer

  echo
  info "当前 rkhunter-check.timer 状态："
  systemctl status rkhunter-check.timer --no-pager || true
  echo
  info "当前 rkhunter-check.service 状态（最近）："
  systemctl status rkhunter-check.service --no-pager | head -n 10 || true

  press_enter
}

# -------------------------
# Step 5/5 - 测试 & 总结
# -------------------------
step5_test_and_summary() {
  step "Step 5/5 - 测试运行 & 总结"

  cat <<EOF
已完成配置：

  - 检查脚本：
      ${CHECK_SCRIPT_PATH}
  - systemd service：
      ${SERVICE_PATH}
  - systemd timer：
      ${TIMER_PATH}
  - 告警模式：
      $( [[ "$ALERT_MODE" == "mail" ]] && echo "邮件告警 + 日志" || echo "仅日志，不发邮件" )

定时策略：
EOF

  case "$SCHEDULE_MODE" in
    daily)
      echo "  - 每天本地时间 ${DAILY_TIME} 执行一次 rkhunter-check"
      ;;
    12h)
      echo "  - 每 12 小时执行一次（开机约 5 分钟后首次运行）"
      ;;
    6h)
      echo "  - 每 6 小时执行一次（开机约 5 分钟后首次运行）"
      ;;
    *)
      echo "  - 模式未知（内部状态异常），请手动检查 timer 配置。"
      ;;
  esac

  cat <<EOF

你可以使用以下命令查看定时任务情况：
  systemctl list-timers | grep rkhunter
  journalctl -u rkhunter-check.service --no-pager | tail

如需临时停用定时任务：
  systemctl disable --now rkhunter-check.timer

EOF

  echo "是否立即测试一次 rkhunter 检查脚本？"
  echo "  1) 立即执行一次 ${CHECK_SCRIPT_PATH}"
  echo "  2) 不测试，等待下一个定时执行"
  echo "  0) 退出"

  while true; do
    read -r -p "请选择 [1-2, 0]: " choice
    case "$choice" in
      1)
        info "开始手动执行：${CHECK_SCRIPT_PATH} （过程可能需要几分钟）"
        if "${CHECK_SCRIPT_PATH}"; then
          info "手动执行完成。"
        else
          warn "手动执行过程中出现非零退出码，请查看日志进一步确认。"
        fi
        break
        ;;
      2)
        info "不执行手动测试，将在下一个定时周期自动运行。"
        break
        ;;
      0)
        info "直接退出，定时任务配置已生效。"
        exit 0
        ;;
      *)
        warn "输入无效，请重新输入。"
        ;;
    esac
  done

  info "向导已完成配置。按回车键返回主菜单或关闭窗口。"
  press_enter
}

main() {
  require_root
  step1_intro_and_checks
  step2_choose_alert_mode
  step3_gen_check_script
  step4_setup_systemd
  step5_test_and_summary
}

main "$@"
