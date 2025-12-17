#!/usr/bin/env bash

# Baseline diagnostics framework for Chapter 20.
# This file only defines functions and does not execute any logic on load.

baseline_init() {
  # Initialize in-memory structures for a baseline diagnostics session.
  declare -ga BASELINE_RESULTS_GROUP=()
  declare -ga BASELINE_RESULTS_ID=()
  declare -ga BASELINE_RESULTS_STATUS=()
  declare -ga BASELINE_RESULTS_KEYWORD=()
  declare -ga BASELINE_RESULTS_EVIDENCE=()
  declare -ga BASELINE_RESULTS_SUGGESTIONS=()
}

baseline_add_result() {
  # Usage: baseline_add_result <group> <id> <status> <keyword> <evidence> <suggestions>
  local group id status keyword evidence suggestions normalized_status

  if [ "$#" -lt 6 ]; then
    return 1
  fi

  group="$1"
  id="$2"
  status="$3"
  keyword="$4"
  evidence="$5"
  suggestions="$6"

  normalized_status="${status^^}"
  case "$normalized_status" in
    PASS|FAIL|WARN)
      :
      ;;
    *)
      return 1
      ;;
  esac

  if ! declare -p BASELINE_RESULTS_GROUP >/dev/null 2>&1; then
    baseline_init
  fi

  BASELINE_RESULTS_GROUP+=("$group")
  BASELINE_RESULTS_ID+=("$id")
  BASELINE_RESULTS_STATUS+=("$normalized_status")
  BASELINE_RESULTS_KEYWORD+=("$keyword")
  BASELINE_RESULTS_EVIDENCE+=("$evidence")
  BASELINE_RESULTS_SUGGESTIONS+=("$suggestions")
}

baseline__overall_state() {
  local status overall
  overall="PASS"

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  for status in "${BASELINE_RESULTS_STATUS[@]}"; do
    case "$status" in
      FAIL)
        overall="FAIL"
        break
        ;;
      WARN)
        if [ "$overall" = "PASS" ]; then
          overall="WARN"
        fi
        ;;
      *)
        :
        ;;
    esac
  done

  printf "%s" "$overall"
}

baseline__print_group_counts() {
  local idx total group status
  declare -A group_pass=()
  declare -A group_fail=()
  declare -A group_warn=()
  declare -A group_seen=()
  local -a group_order=()

  total=${#BASELINE_RESULTS_STATUS[@]}

  for ((idx=0; idx<total; idx++)); do
    group="${BASELINE_RESULTS_GROUP[idx]}"
    status="${BASELINE_RESULTS_STATUS[idx]}"

    if [ -z "${group_seen[$group]+x}" ]; then
      group_seen["$group"]=1
      group_order+=("$group")
    fi

    case "$status" in
      PASS)
        group_pass["$group"]=$(( ${group_pass["$group"]:-0} + 1 ))
        ;;
      FAIL)
        group_fail["$group"]=$(( ${group_fail["$group"]:-0} + 1 ))
        ;;
      WARN)
        group_warn["$group"]=$(( ${group_warn["$group"]:-0} + 1 ))
        ;;
      *)
        :
        ;;
    esac
  done

  for group in "${group_order[@]}"; do
    printf "- Group: %s (PASS: %s WARN: %s FAIL: %s)\n" \
      "$group" \
      "${group_pass["$group"]:-0}" \
      "${group_warn["$group"]:-0}" \
      "${group_fail["$group"]:-0}"
  done
}

baseline_print_summary() {
  local overall

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  echo "=== Baseline Diagnostics Summary ==="
  baseline__print_group_counts

  overall="$(baseline__overall_state)"
  case "$overall" in
    PASS)
      echo "Overall: PASS"
      ;;
    WARN)
      echo "Overall: ⚠️ WARN"
      ;;
    FAIL)
      echo "Overall: FAIL"
      ;;
  esac
}

baseline_print_details() {
  local total idx group status id keyword evidence suggestions evidence_fmt suggestions_fmt
  local current_group

  if ! declare -p BASELINE_RESULTS_STATUS >/dev/null 2>&1; then
    baseline_init
  fi

  echo "=== Baseline Diagnostics Details ==="
  total=${#BASELINE_RESULTS_STATUS[@]}
  current_group=""

  for ((idx=0; idx<total; idx++)); do
    group="${BASELINE_RESULTS_GROUP[idx]}"
    status="${BASELINE_RESULTS_STATUS[idx]}"
    id="${BASELINE_RESULTS_ID[idx]}"
    keyword="${BASELINE_RESULTS_KEYWORD[idx]}"
    evidence="${BASELINE_RESULTS_EVIDENCE[idx]}"
    suggestions="${BASELINE_RESULTS_SUGGESTIONS[idx]}"

    if [ "$group" != "$current_group" ]; then
      current_group="$group"
      echo ""
      echo "Group: $group"
    fi

    evidence_fmt=${evidence//\\n/$'\n'}
    suggestions_fmt=${suggestions//\\n/$'\n'}

    echo "- [$status] $id (${keyword})"
    if [ -n "$evidence_fmt" ]; then
      echo "  Evidence:"
      while IFS= read -r line; do
        echo "    $line"
      done <<< "${evidence_fmt}"
    else
      echo "  Evidence: (none)"
    fi

    if [ -n "$suggestions_fmt" ]; then
      echo "  Suggestions:"
      while IFS= read -r line; do
        echo "    - $line"
      done <<< "${suggestions_fmt}"
    else
      echo "  Suggestions: (none)"
    fi
  done
}

baseline_overall_status() {
  local overall

  overall="$(baseline__overall_state)"
  case "$overall" in
    PASS)
      return 0
      ;;
    WARN)
      return 10
      ;;
    FAIL)
      return 20
      ;;
    *)
      return 0
      ;;
  esac
}
