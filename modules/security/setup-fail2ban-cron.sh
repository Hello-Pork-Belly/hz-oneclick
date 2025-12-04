#!/usr/bin/env bash
#
# setup-fail2ban-cron.sh - 配置 fail2ban 日志维护的 systemd 定时任务
# 作用：限制 /var/log/fail2ban.log 行数，避免日志无限膨胀
#

set -euo pipefail

echo "==== Fail2ban 日志维护定时任务配置 (hz-oneclick) ===="

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 用户运行本脚本。" >&2
  exit 1
fi

if ! command -v fail2ban-client >/dev/null 2>&1; then
  echo "未检测到 fail2ban，建议先执行 install-fail2ban 模块。" >&2
  exit 1
fi

MAINT_SCRIPT="/usr/local/bin/fail2ban-log-maintain.sh"
SERVICE_FILE="/etc/systemd/system/fail2ban-log-maintain.service"
TIMER_FILE="/etc/systemd/system/fail2ban-log-maintain.timer"

echo "[Step 1/3] 写入日志维护脚本到 ${MAINT_SCRIPT} ..."
cat > "$MAINT_SCRIPT" <<'EOF'
#!/usr/bin/env bash
# fail2ban-log-maintain.sh - 控制 fail2ban.log 大小（按行数截断）

set -euo pipefail

LOG_FILE="/var/log/fail2ban.log"
MAX_LINES=5000
KEEP_LINES=3000

ts() { date +"%Y-%m-%d %H:%M:%S"; }

echo "[fail2ban-log-maintain][$(ts)] 开始检查日志大小..."

if [[ ! -f "$LOG_FILE" ]]; then
  echo "[fail2ban-log-maintain][$(ts)] 日志文件不存在：$LOG_FILE"
  exit 0
fi

lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

if (( lines > MAX_LINES )); then
  echo "[fail2ban-log-maintain][$(ts)] 当前行数 $lines > 最大限制 $MAX_LINES，开始截断..."
  tmp="${LOG_FILE}.tmp.$$"
  tail -n "$KEEP_LINES" "$LOG_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$LOG_FILE"
  echo "[fail2ban-log-maintain][$(ts)] 已保留最后 $KEEP_LINES 行。"
else
  echo "[fail2ban-log-maintain][$(ts)] 当前行数 $lines，不需要截断。"
fi
EOF

chmod +x "$MAINT_SCRIPT"

echo "[Step 2/3] 写入 systemd service / timer ..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Maintain fail2ban.log size (hz-oneclick)

[Service]
Type=oneshot
ExecStart=${MAINT_SCRIPT}
EOF

cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Daily fail2ban.log maintenance timer (hz-oneclick)

[Timer]
# 每天 03:40 UTC 运行一次
OnCalendar=*-*-* 03:40:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "[Step 3/3] 重新加载 systemd 并启用定时任务..."
systemctl daemon-reload
systemctl enable --now fail2ban-log-maintain.timer

echo
echo "==== 完成：fail2ban 日志维护定时任务已启用 ===="
echo "查看状态："
echo "  systemctl status fail2ban-log-maintain.service"
echo "  systemctl status fail2ban-log-maintain.timer"
echo
echo "如需修改执行时间，请编辑："
echo "  ${TIMER_FILE}"
