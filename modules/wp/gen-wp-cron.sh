#!/usr/bin/env bash
#
# hz-oneclick - gen-wp-cron.sh
# 版本: 0.1.0
# 功能: 检测并配置 WordPress 的定时任务执行方式（伪 cron / systemd 定时）
# 说明:
#   - 仅负责 wp-cron.php 相关逻辑，不改动数据库和备份脚本
#   - 可处理三种状态：
#       A) 默认伪 cron (未定义 DISABLE_WP_CRON, 无 systemd timer)
#       B) 不推荐状态 (DISABLE_WP_CRON = true, 但无 systemd timer)
#       C) 已接管 (DISABLE_WP_CRON = true, 且有对应 wp-cron timer)
#

SCRIPT_VERSION="0.1.0"

# 如果存在 hz-oneclick 的通用函数库，就加载（颜色输出等）
COMMON_SH="$(dirname "$0")/../lib/common.sh"
if [[ -f "$COMMON_SH" ]]; then
  # shellcheck disable=SC1090
  . "$COMMON_SH"
else
  # 兼容: 定义最简版输出函数
  info()  { echo -e "[INFO]  $*"; }
  warn()  { echo -e "[WARN]  $*"; }
  error() { echo -e "[ERROR] $*" >&2; }
  step()  { echo -e "\n==== $* ====\n"; }
fi

# 全局变量
WP_ROOT=""          # 站点根目录 /var/www/xxx/html
WP_CONFIG=""        # wp-config.php 路径
SITE_SLUG=""        # 站点代号 (目录名，如 horizontech / nzfreeman)
STATE=""            # A / B / C
PHP_CMD=""          # 执行 wp-cron.php 的完整命令
INTERVAL_MIN=5      # 执行间隔（分钟）
TARGET_MODE=""      # keep_default / enable_systemd / restore_wp_cron / keep_systemd / adjust_systemd

# 输出统一提示：0 代表返回主菜单 / 退出向导
prompt_exit_hint() {
  echo "提示：输入 0 随时可以退出向导并返回一键安装主菜单。"
}

require_systemctl() {
  if ! command -v systemctl >/dev/null 2>&1; then
    error "未检测到 systemctl，此脚本需要在支持 systemd 的系统上运行。"
    exit 1
  fi
}

press_enter_to_continue() {
  read -r -p "按 Enter 继续..." _
}

# ------------- Step 2 帮助函数：选择 WP 路径 -------------

auto_discover_wp_sites() {
  # 尝试在 /var/www 下找到包含 wp-config.php 的 html 目录
  find /var/www -maxdepth 3 -type f -name "wp-config.php" 2>/dev/null \
    | grep "/html/wp-config.php$" \
    | sort
}

select_wp_root_step() {
  step "Step 2/7 - 选择要配置的 WordPress 站点"
  prompt_exit_hint
  echo

  local candidates=()
  local idx=1

  while IFS= read -r line; do
    candidates+=("$line")
  done < <(auto_discover_wp_sites)

  if ((${#candidates[@]} > 0)); then
    echo "检测到以下可能的 WordPress 站点："
    for f in "${candidates[@]}"; do
      local dir
      dir="$(dirname "$f")"
      echo "  [$idx] $dir"
      ((idx++))
    done
    echo "  [$idx] 手动输入路径"
  else
    warn "未在 /var/www 内自动发现 wp-config.php，可能使用了自定义路径。"
    echo "  [1] 手动输入路径"
  fi

  echo
  echo "示例路径：/var/www/example/html"
  while true; do
    read -r -p "请输入序号，或直接输入完整路径（0 = 返回主菜单）: " input
    if [[ "$input" == "0" ]]; then
      info "已退出向导，返回主菜单。"
      exit 0
    fi

    # 若是纯数字且在范围内，则选列表
    if [[ "$input" =~ ^[0-9]+$ ]] && ((${#candidates[@]} > 0)); then
      local num="$input"
      if ((num >= 1 && num <= ${#candidates[@]})); then
        WP_ROOT="$(dirname "${candidates[num-1]}")"
        break
      elif ((num == ${#candidates[@]} + 1)); then
        # 手动输入
        read -r -p "请输入 WordPress 根目录（例如 /var/www/example/html）: " WP_ROOT
        [[ -z "$WP_ROOT" ]] && continue
        break
      else
        warn "无效的序号，请重试。"
        continue
      fi
    else
      # 当作路径
      if [[ -z "$input" ]]; then
        warn "输入为空，请重试。"
        continue
      fi
      WP_ROOT="$input"
      break
    fi
  done

  WP_CONFIG="$WP_ROOT/wp-config.php"
  if [[ ! -f "$WP_CONFIG" ]]; then
    error "在 $WP_ROOT 未找到 wp-config.php，请确认路径是否正确。"
    press_enter_to_continue
    select_wp_root_step
    return
  fi

  # 根据目录推断站点代号，例如 /var/www/nzfreeman/html => nzfreeman
  SITE_SLUG="$(basename "$(dirname "$WP_ROOT")")"

  info "已选择站点："
  echo "  根目录: $WP_ROOT"
  echo "  配置:   $WP_CONFIG"
  echo "  站点代号(SITE_SLUG): $SITE_SLUG"
}

# ------------- Step 3：检测当前状态 -------------

detect_state_step() {
  step "Step 3/7 - 检测当前 wp-cron 状态"

  local has_disable="no"
  local disable_true="no"

  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    has_disable="yes"
    # 粗略判断是否 true
    if grep -E "DISABLE_WP_CRON'.*true" "$WP_CONFIG" >/dev/null 2>&1; then
      disable_true="yes"
    else
      disable_true="no"
    fi
  fi

  local timer_name="wp-cron-${SITE_SLUG}.timer"
  local timer_exists="no"
  local timer_active="no"

  if systemctl list-timers --all 2>/dev/null | grep -q "$timer_name"; then
    timer_exists="yes"
    if systemctl is-active "$timer_name" >/dev/null 2>&1; then
      timer_active="yes"
    fi
  fi

  # 决定状态 A / B / C
  # A: 未定义 DISABLE_WP_CRON，且无 timer
  # B: DISABLE_WP_CRON = true，但无 timer
  # C: DISABLE_WP_CRON = true，且有 timer (active 或 inactive 都视为 C，后面可以微调)
  if [[ "$has_disable" == "no" ]]; then
    if [[ "$timer_exists" == "no" ]]; then
      STATE="A"
    else
      # 比较罕见：未禁用伪 cron，但有 timer；先归为 A 的变种
      STATE="A"
    fi
  else
    if [[ "$disable_true" == "yes" && "$timer_exists" == "no" ]]; then
      STATE="B"
    elif [[ "$disable_true" == "yes" && "$timer_exists" == "yes" ]]; then
      STATE="C"
    else
      # 有 DISABLE_WP_CRON 但不是 true，归为 A 处理
      STATE="A"
    fi
  fi

  case "$STATE" in
    A)
      info "检测结果：状态 A - 使用 WordPress 默认\"伪 cron\"。"
      echo "  - wp-config.php 中未定义 DISABLE_WP_CRON"
      echo "  - systemd 中未发现 $timer_name 定时器"
      echo "说明：访问量较少时，某些定时任务可能长时间延迟执行。"
      ;;
    B)
      warn "检测结果：状态 B - 不推荐状态！"
      echo "  - wp-config.php 中已设置 DISABLE_WP_CRON = true"
      echo "  - systemd 中未发现 $timer_name 定时器"
      echo "说明：当前已关闭 WP 内置 cron，但没有系统级定时任务接管，定时任务可能不执行。"
      ;;
    C)
      info "检测结果：状态 C - 已启用系统级 wp-cron。"
      echo "  - wp-config.php 中已设置 DISABLE_WP_CRON = true"
      echo "  - systemd 中检测到定时器: $timer_name (active: $timer_active)"
      ;;
    *)
      warn "未知状态，按状态 A 处理。"
      STATE="A"
      ;;
  esac

  press_enter_to_continue
}

# ------------- Step 4：选择目标模式 -------------

choose_target_mode_step() {
  step "Step 4/7 - 选择目标定时任务模式"
  prompt_exit_hint
  echo

  case "$STATE" in
    A)
      echo "当前为默认伪 cron 模式。可以继续使用，或切换为系统级 wp-cron。"
      echo
      echo "1) 保持当前状态（继续使用伪 cron，不做更改）"
      echo "2) 启用系统级 wp-cron（推荐生产环境使用）"
      echo "0) 返回主菜单（退出向导）"
      while true; do
        read -r -p "请选择 [1-2, 0]: " ans
        case "$ans" in
          1)
            TARGET_MODE="keep_default"
            return
            ;;
          2)
            TARGET_MODE="enable_systemd"
            return
            ;;
          0)
            info "已退出向导，返回主菜单。"
            exit 0
            ;;
          *)
            warn "无效选择，请重试。"
            ;;
        esac
      done
      ;;
    B)
      echo "当前为不推荐状态：已禁用伪 cron，但没有系统级定时任务。"
      echo
      echo "1) 创建系统级 wp-cron 定时任务（推荐）"
      echo "2) 取消 DISABLE_WP_CRON，恢复默认伪 cron"
      echo "0) 返回主菜单（退出向导）"
      while true; do
        read -r -p "请选择 [1-2, 0]: " ans
        case "$ans" in
          1)
            TARGET_MODE="enable_systemd"
            return
            ;;
          2)
            TARGET_MODE="restore_wp_cron"
            return
            ;;
          0)
            info "已退出向导，返回主菜单。"
            exit 0
            ;;
          *)
            warn "无效选择，请重试。"
            ;;
        esac
      done
      ;;
    C)
      echo "当前已由 systemd 接管 wp-cron：DISABLE_WP_CRON = true 且存在 wp-cron timer。"
      echo
      echo "1) 保持现有配置，仅查看状态后退出"
      echo "2) 调整系统级 wp-cron 的执行频率"
      echo "0) 返回主菜单（退出向导）"
      while true; do
        read -r -p "请选择 [1-2, 0]: " ans
        case "$ans" in
          1)
            TARGET_MODE="keep_systemd"
            return
            ;;
          2)
            TARGET_MODE="adjust_systemd"
            return
            ;;
          0)
            info "已退出向导，返回主菜单。"
            exit 0
            ;;
          *)
            warn "无效选择，请重试。"
            ;;
        esac
      done
      ;;
  esac
}

# ------------- Step 5：确认 PHP 命令 -------------

auto_detect_php_cmd() {
  local php_bin=""
  # 优先 lsphp83
  if [[ -x /usr/local/lsws/lsphp83/bin/php ]]; then
    php_bin="/usr/local/lsws/lsphp83/bin/php"
  elif command -v php >/dev/null 2>&1; then
    php_bin="$(command -v php)"
  fi

  if [[ -n "$php_bin" ]]; then
    PHP_CMD="$php_bin -q \"$WP_ROOT/wp-cron.php\""
  else
    PHP_CMD=""
  fi
}

confirm_php_cmd_step() {
  step "Step 5/7 - 确认 PHP 与 wp-cron 执行命令"
  prompt_exit_hint
  echo

  auto_detect_php_cmd

  if [[ -n "$PHP_CMD" ]]; then
    echo "已自动检测到可能的执行命令："
    echo "  $PHP_CMD"
  else
    warn "未能自动检测到 PHP 命令，需要手动输入。"
  fi

  echo
  echo "示例：/usr/local/lsws/lsphp83/bin/php -q /var/www/example/html/wp-cron.php"

  while true; do
    if [[ -n "$PHP_CMD" ]]; then
      read -r -p "是否使用检测到的命令？(Y/n, 0 = 返回主菜单): " ans
      case "$ans" in
        0)
          info "已退出向导，返回主菜单。"
          exit 0
          ;;
        ""|Y|y)
          # 保持 PHP_CMD 不变
          break
          ;;
        N|n)
          PHP_CMD=""
          ;;
        *)
          warn "无效输入，请输入 Y / n / 0。"
          continue
          ;;
      esac
    fi

    if [[ -z "$PHP_CMD" ]]; then
      read -r -p "请输入完整执行命令（0 = 返回主菜单）: " cmd
      if [[ "$cmd" == "0" ]]; then
        info "已退出向导，返回主菜单。"
        exit 0
      fi
      if [[ -z "$cmd" ]]; then
        warn "命令不能为空，请重试。"
        continue
      fi
      PHP_CMD="$cmd"
    fi

    # 粗略验证 php 是否存在
    local php_bin
    php_bin="$(echo "$PHP_CMD" | awk '{print $1}')"
    if ! command -v "$php_bin" >/dev/null 2>&1 && [[ ! -x "$php_bin" ]]; then
      warn "命令中的 PHP 可执行文件不存在或不可执行: $php_bin"
      PHP_CMD=""
      continue
    fi

    break
  done

  info "最终将使用命令：$PHP_CMD"
  press_enter_to_continue
}

# ------------- Step 6：配置执行频率并写入 systemd -------------

config_interval_and_apply_step() {
  step "Step 6/7 - 配置执行频率并生成 systemd 定时任务"
  prompt_exit_hint
  echo

  echo "推荐每 5 分钟执行一次 wp-cron.php。"
  echo
  echo "1) 每 5 分钟执行一次（推荐）"
  echo "2) 每 10 分钟执行一次"
  echo "3) 每 15 分钟执行一次"
  echo "4) 自定义分钟数"
  echo "0) 返回主菜单（退出向导）"

  while true; do
    read -r -p "请选择 [1-4, 0]: " ans
    case "$ans" in
      0)
        info "已退出向导，返回主菜单。"
        exit 0
        ;;
      1)
        INTERVAL_MIN=5
        break
        ;;
      2)
        INTERVAL_MIN=10
        break
        ;;
      3)
        INTERVAL_MIN=15
        break
        ;;
      4)
        read -r -p "请输入间隔分钟数（整数，如 3 或 30，0 = 返回主菜单）: " num
        if [[ "$num" == "0" ]]; then
          info "已退出向导，返回主菜单。"
          exit 0
        fi
        if ! [[ "$num" =~ ^[0-9]+$ ]] || ((num <= 0)); then
          warn "请输入大于 0 的整数。"
          continue
        fi
        INTERVAL_MIN="$num"
        break
        ;;
      *)
        warn "无效选择，请重试。"
        ;;
    esac
  done

  echo
  echo "即将执行以下操作："
  echo "  - 在 wp-config.php 中设置或保留 DISABLE_WP_CRON = true"
  echo "  - 创建/更新 systemd 服务: wp-cron-${SITE_SLUG}.service"
  echo "  - 创建/更新 systemd 定时器: wp-cron-${SITE_SLUG}.timer，每 ${INTERVAL_MIN} 分钟执行一次"
  echo
  read -r -p "确认执行上述更改吗？(Y/n): " confirm
  case "$confirm" in
    ""|Y|y) ;;
    *)
      warn "用户取消更改，向导结束。"
      exit 0
      ;;
  esac

  # 1) 设置或更新 DISABLE_WP_CRON = true
  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    # 用统一格式覆盖
    sed -i -E "s/define\(\s*'DISABLE_WP_CRON'.*/define( 'DISABLE_WP_CRON', true );/" "$WP_CONFIG"
  else
    # 追加到文件末尾前一行（尽量简单安全）
    {
      echo ""
      echo "/** Enable system cron for wp-cron (hz-oneclick) */"
      echo "define( 'DISABLE_WP_CRON', true );"
    } >>"$WP_CONFIG"
  fi

  # 2) 写入 systemd unit
  local svc="/etc/systemd/system/wp-cron-${SITE_SLUG}.service"
  local tmr="/etc/systemd/system/wp-cron-${SITE_SLUG}.timer"

  cat >"$svc" <<EOF
[Unit]
Description=Run WordPress cron for ${SITE_SLUG}

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${PHP_CMD}'
EOF

  cat >"$tmr" <<EOF
[Unit]
Description=Timer to run WordPress cron for ${SITE_SLUG} every ${INTERVAL_MIN} minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=${INTERVAL_MIN}min
Unit=wp-cron-${SITE_SLUG}.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "wp-cron-${SITE_SLUG}.timer"

  info "systemd 定时任务已创建/更新并启用。"
  press_enter_to_continue
}

# ------------- 恢复伪 cron：移除或注释 DISABLE_WP_CRON -------------

restore_wp_cron_step() {
  step "Step 6/7 - 恢复 WordPress 默认伪 cron 模式"
  prompt_exit_hint
  echo

  echo "即将执行以下操作："
  echo "  - 在 wp-config.php 中移除或注释 DISABLE_WP_CRON 行"
  echo "  - 保留或停用系统中已有的 wp-cron 定时器（请手动确认）"
  echo
  read -r -p "确认恢复到默认伪 cron 模式吗？(Y/n): " confirm
  case "$confirm" in
    ""|Y|y) ;;
    *)
      warn "用户取消更改，向导结束。"
      exit 0
      ;;
  esac

  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    # 简单处理：在行首加上 //
    sed -i -E "s/^(.*DISABLE_WP_CRON.*)$/\/\/ \1/" "$WP_CONFIG"
    info "已在 wp-config.php 中注释 DISABLE_WP_CRON 行。"
  else
    info "wp-config.php 中本就未定义 DISABLE_WP_CRON，无需修改。"
  fi

  press_enter_to_continue
}

# ------------- Step 7：总结 -------------

summary_step() {
  step "Step 7/7 - 配置结果与后续建议"

  local timer_name="wp-cron-${SITE_SLUG}.timer"
  local timer_status="not-found"
  local disable_status="unknown"

  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    if grep -E "DISABLE_WP_CRON'.*true" "$WP_CONFIG" >/dev/null 2>&1; then
      disable_status="true"
    else
      disable_status="defined-but-not-true"
    fi
  else
    disable_status="not-defined"
  fi

  if systemctl list-timers --all 2>/dev/null | grep -q "$timer_name"; then
    if systemctl is-active "$timer_name" >/dev/null 2>&1; then
      timer_status="active"
    else
      timer_status="exists-not-active"
    fi
  fi

  echo "当前站点：$WP_ROOT"
  echo "DISABLE_WP_CRON 状态：$disable_status"
  echo "systemd timer：$timer_name ($timer_status)"
  echo

  echo "建议："
  echo "  - 如需查看定时器详情，可执行："
  echo "      systemctl status $timer_name"
  echo "      systemctl list-timers | grep wp-cron"
  echo "  - 如需完全恢复默认伪 cron 模式："
  echo "      1) 编辑 wp-config.php，删除或注释 DISABLE_WP_CRON 行"
  echo "      2) 手动停用并删除对应的 wp-cron-*.timer / wp-cron-*.service"

  echo
  echo "向导已结束，如需再次调整执行频率或站点，可重新运行本脚本。"
}

# ------------- Step 1：说明与风险提示 -------------

intro_step() {
  step "Step 1/7 - 说明与风险提示 (版本: $SCRIPT_VERSION)"
  echo "本向导用于配置 WordPress 定时任务 (wp-cron.php) 的执行方式。"
  echo
  echo "主要功能："
  echo "  - 检测当前站点是否启用 DISABLE_WP_CRON"
  echo "  - 检测是否已有 systemd 定时任务接管 wp-cron"
  echo "  - 按需切换到系统级 wp-cron，或恢复默认伪 cron"
  echo
  echo "注意："
  echo "  - 不会改动数据库和站点文件，只修改 wp-config.php 与 systemd 配置"
  echo "  - 如当前已禁用伪 cron 且没有定时任务，这是不推荐状态，"
  echo "    有可能导致 Rank Math 等插件的定时任务长期不执行。"
  echo
  prompt_exit_hint
  echo
  read -r -p "继续执行向导吗？(Y/n, 0 = 返回主菜单): " ans
  case "$ans" in
    0)
      info "已退出向导，返回主菜单。"
      exit 0
      ;;
    ""|Y|y)
      ;;
    *)
      info "用户取消，退出向导。"
      exit 0
      ;;
  esac
}

# ------------- 主流程 -------------

main() {
  require_systemctl
  intro_step
  select_wp_root_step
  detect_state_step
  choose_target_mode_step

  case "$TARGET_MODE" in
    keep_default)
      info "保持默认伪 cron 模式，不做更改。"
      ;;
    keep_systemd)
      info "保持现有 systemd wp-cron 配置，不做更改。"
      ;;
    restore_wp_cron)
      restore_wp_cron_step
      ;;
    enable_systemd|adjust_systemd)
      confirm_php_cmd_step
      config_interval_and_apply_step
      ;;
    *)
      warn "未知目标模式，向导终止。"
      ;;
  esac

  summary_step
}

main "$@"
