#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./baseline-wrapper-common.sh
. "$SCRIPT_DIR/baseline-wrapper-common.sh"

REPO_ROOT="$(baseline_wrapper_repo_root)"
baseline_wrapper_load_libs "$REPO_ROOT" baseline_common.sh baseline.sh baseline_cache.sh

domain=""
lang=""
format=""
baseline_wrapper_parse_inputs domain lang format -- "$@"

group="CACHE/REDIS"
baseline_init
baseline_wrapper_missing_tools_warn "$group" "$lang" systemctl

baseline_cache_run "" "$lang"

baseline_wrapper_finalize "$group" "$domain" "$lang" "$format"
