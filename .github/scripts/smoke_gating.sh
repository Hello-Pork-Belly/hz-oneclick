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

enforce() {
  local verdict_raw exit_code_raw strict_raw verdict strict exit_code
  verdict_raw="${1:-}"
  exit_code_raw="${2:-}"
  strict_raw="${3:-}"

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
  smoke_gating.sh enforce --verdict <value> --exit-code <code> --strict <value>
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
      enforce "$verdict_raw" "$exit_code_raw" "$strict_raw"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
