#!/usr/bin/env bash
#
# install-fail2ban.sh - 安装并配置基础 fail2ban（SSH 防爆破）
# 适用：Debian/Ubuntu（APT 系）
#

set -euo pipefail

echo "==== Fail2ban 安装向导 (hz-oneclick) ===="

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 用户运行本脚本。" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "当前系统不是基于 APT 的 Debian/Ubuntu，暂不支持一键安装。" >&2
  exit 1
fi

# Step 1: 安装 fail2ban
if command -v fail2ban-client >/dev/null 2>&1; then
  echo "[Step 1/3] 检测到系统已安装 fail2ban，跳过安装。"
else
  echo "[Step 1/3] 安装 fail2ban..."
  apt-get update -y
  apt-get install -y fail2ban
fi

# Step 2: 写入基础 jail 配置
CONF_DIR="/etc/fail2ban/jail.d"
CONF_FILE="${CONF_DIR}/hz-basic.conf"

echo "[Step 2/3] 写入基础配置到 ${CONF_FILE} ..."
mkdir -p "$CONF_DIR"

if [[ -f "$CONF_FILE" ]]; then
  cp "$CONF_FILE" "${CONF_FILE}.$(date +%Y%m%d%H%M%S).bak"
  echo "已备份原有配置到 ${CONF_FILE}.$(date +%Y%m%d%H%M%S).bak"
fi

cat > "$CONF_FILE" <<'EOF'
# hz-oneclick: 基础 fail2ban 配置（可按需修改）

[DEFAULT]
# 可自行按需调整这些参数
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

# 基本 SSH 防爆破：如果 22 端口对公网关闭，则影响不大
[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 5
EOF

# Step 3: 启动并设置开机自启
echo "[Step 3/3] 启动并设为开机自启..."
systemctl enable --now fail2ban

echo
echo "==== 完成：fail2ban 已安装并启用基础 SSH 防护 ===="
echo "常用检查命令："
echo "  fail2ban-client status"
echo "  fail2ban-client status sshd"
echo
echo "如需为 OLS / Nginx / 其它服务添加 jail，可编辑："
echo "  /etc/fail2ban/jail.d/hz-basic.conf"
echo
echo "提示：如果你本身关闭了公网 22 端口，fail2ban 主要是作为额外保险，"
echo "      是否继续使用取决于实际场景。"
