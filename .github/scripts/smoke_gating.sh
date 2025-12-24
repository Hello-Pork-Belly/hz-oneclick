#!/usr/bin/env bash
set -euo pipefail

normalize_verdict() {
  local value token
  value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value^^}"
  token="$(printf '%s' "$value" | grep -Eo '(PASS|OK|WARN|FAIL)' | head -n1 || true)"
  if [ -n "$token" ]; then
    printf '%s' "$token"
  else
    printf 'FAIL'
  fi
}

normalize_strict() {
  local value
  value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  case "${value,,}" in
    1|true|yes|on)
      printf 'true'
      ;;
    *)
      printf 'false'
      ;;
  esac
}

print_report_findings() {
  local report_path="$1"
  local desired_status="$2"
  local status_label="$3"
  local in_details=0
  local current_group=""
  local current_status=""
  local current_entry=""

  if [ -z "$report_path" ] || [ ! -f "$report_path" ]; then
    echo "[smoke-enforce] ${status_label} report not found: ${report_path:-<unset>}"
    return
  fi

  while IFS= read -r line; do
    if [ "$line" = "=== Baseline Diagnostics Details ===" ]; then
      in_details=1
      continue
    fi
    if [ "$in_details" -ne 1 ]; then
      continue
    fi
    if [[ "$line" == "KEY:"* ]]; then
      break
    fi
    if [[ "$line" == "Group: "* ]]; then
      current_group="${line#Group: }"
      continue
    fi
    if [[ "$line" =~ ^-\\ \\[(PASS|WARN|FAIL)\\]\\ (.*)$ ]]; then
      current_status="${BASH_REMATCH[1]}"
      current_entry="${BASH_REMATCH[2]}"
      if [ "$current_status" = "$desired_status" ]; then
        echo "[smoke-enforce] ${status_label}: group=${current_group} check=${current_entry}"
      fi
      continue
    fi
    if [ "$current_status" = "$desired_status" ]; then
      if [[ "$line" == "  Evidence:"* ]]; then
        echo "[smoke-enforce]   Evidence:"
        continue
      fi
      if [[ "$line" == "  Suggestions:"* ]]; then
        echo "[smoke-enforce]   Suggestions:"
        continue
      fi
      if [[ "$line" == "    "* ]]; then
        echo "[smoke-enforce]     ${line#    }"
      fi
    fi
  done < "$report_path"
}

enforce() {
  local verdict_raw exit_code_raw strict_raw report_path report_json_path verdict strict exit_code
  verdict_raw="${1:-}"
  exit_code_raw="${2:-}"
  strict_raw="${3:-}"
  report_path="${4:-}"
  report_json_path="${5:-}"

  verdict="$(normalize_verdict "$verdict_raw")"
  strict="$(normalize_strict "$strict_raw")"

  case "$exit_code_raw" in
    ''|*[!0-9]*)
      exit_code=1
      ;;
    *)
      exit_code="$exit_code_raw"
      ;;
  esac

  if { [ "$verdict" = "PASS" ] || [ "$verdict" = "OK" ]; } && [ "$exit_code" -ne 0 ]; then
    verdict="FAIL"
  fi

  echo "[smoke-enforce] verdict=${verdict} exit_code=${exit_code} strict=${strict}"
  if [ -n "$report_path" ]; then
    echo "[smoke-enforce] report_path=${report_path}"
  fi
  if [ -n "$report_json_path" ]; then
    echo "[smoke-enforce] report_json_path=${report_json_path}"
  fi

  if [ "$verdict" = "WARN" ]; then
    print_report_findings "$report_path" "WARN" "WARN reason"
  fi

  if [ "$verdict" = "FAIL" ]; then
    print_report_findings "$report_path" "FAIL" "FAIL reason"
  fi

  case "$verdict" in
    PASS|OK)
      return 0
      ;;
    WARN)
      if [ "$strict" = "true" ]; then
        return 1
      fi
      return 0
      ;;
    FAIL|*)
      return 1
      ;;
  esac
}

require_result() {
  local label verdict exit_code strict expected actual
  label="$1"
  verdict="$2"
  exit_code="$3"
  strict="$4"
  expected="$5"

  if enforce "$verdict" "$exit_code" "$strict"; then
    actual=0
  else
    actual=1
  fi

  if [ "$actual" -ne "$expected" ]; then
    echo "[smoke-gating] ${label} verdict=${verdict} exit_code=${exit_code} strict=${strict} expected=${expected} got=${actual}" >&2
    exit 1
  fi
}

self_test() {
  require_result "case-pass-nonstrict" "PASS" 0 0 0
  require_result "case-pass-strict" "PASS" 0 1 0
  require_result "case-ok-lower" "ok" 0 0 0
  require_result "case-pass-exit-fail" "PASS" 2 0 1
  require_result "case-warn-nonstrict" "WARN" 1 0 0
  require_result "case-warn-strict" "WARN" 1 1 1
  require_result "case-fail" "FAIL" 1 0 1
  require_result "case-unknown" "maybe" 0 0 1
}

usage() {
  cat <<'USAGE'
Usage:
  smoke_gating.sh self-test
  smoke_gating.sh enforce --verdict <value> --exit-code <code> --strict <value> [--report-path <path>] [--report-json <path>]
USAGE
}

main() {
  local command verdict_raw exit_code_raw strict_raw
  if [ "$#" -lt 1 ]; then
    usage
    exit 2
  fi

  command="$1"
  shift

  case "$command" in
    self-test)
      self_test
      ;;
    enforce)
      verdict_raw=""
      exit_code_raw=""
      strict_raw=""
      report_path=""
      report_json_path=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --verdict)
            verdict_raw="${2:-}"
            shift 2
            ;;
          --exit-code)
            exit_code_raw="${2:-}"
            shift 2
            ;;
          --strict)
            strict_raw="${2:-}"
            shift 2
            ;;
          --report-path)
            report_path="${2:-}"
            shift 2
            ;;
          --report-json)
            report_json_path="${2:-}"
            shift 2
            ;;
          -h|--help)
            usage
            exit 0
            ;;
          *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
        esac
      done
      enforce "$verdict_raw" "$exit_code_raw" "$strict_raw" "$report_path" "$report_json_path"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
