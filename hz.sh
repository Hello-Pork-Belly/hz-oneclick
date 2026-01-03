#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE=${BASH_SOURCE[0]}
while [ -h "$SCRIPT_SOURCE" ]; do
  SCRIPT_DIR=$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)
  SCRIPT_SOURCE=$(readlink "$SCRIPT_SOURCE")
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR=$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)

if [[ ! -d "${SCRIPT_DIR}/.git" && ! -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git
  else
    echo "Unsupported package manager. Please install git manually." >&2
    exit 1
  fi

  if [[ -d /opt/hz-oneclick/.git ]]; then
    git -C /opt/hz-oneclick pull --ff-only
  else
    git clone https://github.com/Hello-Pork-Belly/hz-oneclick.git /opt/hz-oneclick
  fi

  exec /opt/hz-oneclick/hz.sh "$@"
fi

REPO_ROOT=$SCRIPT_DIR
export REPO_ROOT

COMMON_SH="${REPO_ROOT}/lib/common.sh"
OPS_MENU_SH="${REPO_ROOT}/lib/ops_menu_lib.sh"

if [[ ! -f "$COMMON_SH" ]]; then
  echo "Missing required file: $COMMON_SH" >&2
  echo "REPO_ROOT: $REPO_ROOT" >&2
  exit 1
fi

# shellcheck source=lib/common.sh
auth_lang(){
  :
}
source "$COMMON_SH"

if [[ ! -f "$OPS_MENU_SH" ]]; then
  echo "Missing required file: $OPS_MENU_SH" >&2
  echo "REPO_ROOT: $REPO_ROOT" >&2
  exit 1
fi

# shellcheck source=lib/ops_menu_lib.sh
source "$OPS_MENU_SH"

while true; do
  echo ""
  echo "==== hz-oneclick ===="
  echo "1) WP 安装"
  echo "2) 运维中心"
  echo "3) 诊断"
  echo "4) Exit"
  read -r -p "请选择: " choice

  case "$choice" in
    1)
      bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
      ;;
    2)
      show_ops_menu
      ;;
    3)
      bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh"
      ;;
    4)
      exit 0
      ;;
    *)
      echo "无效选项，请重试。"
      ;;
  esac

done
