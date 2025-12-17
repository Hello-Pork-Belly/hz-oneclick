#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./baseline-wrapper-common.sh
. "$SCRIPT_DIR/baseline-wrapper-common.sh"

REPO_ROOT="$(baseline_wrapper_repo_root)"
baseline_wrapper_load_libs "$REPO_ROOT" baseline_common.sh baseline.sh baseline_tls.sh baseline_https.sh

domain=""
lang=""
format=""
baseline_wrapper_parse_inputs domain lang format -- "$@"

group="TLS/HTTPS"
baseline_init
baseline_wrapper_missing_tools_warn "$group" "$lang" curl wget openssl

if [ -z "$domain" ]; then
  baseline_wrapper_mark_domain_skipped "$group" "$lang"
else
  baseline_tls_run "$domain" "$lang"
  baseline_https_run "$domain" "$lang"
fi

baseline_wrapper_finalize "$group" "$domain" "$lang" "$format"
