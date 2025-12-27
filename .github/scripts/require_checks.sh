#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: require_checks.sh --pr <number> --repo <owner/repo> [--self-test]

Ensures required checks are successful for a PR head SHA.
USAGE
}

REQUIRED_WORKFLOWS=("CI" "Regression Checks" "Full Regression")
REQUIRED_CHECK_RUNS=("shell-ci")
SCHEDULE_ONLY_WORKFLOWS=("Full Regression")

contains_name() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

summarize_entries() {
  local entries="$1"
  local status_summary="missing"
  local conclusion_summary="missing"
  local ok="missing"

  if [[ -n "$entries" ]]; then
    status_summary="completed"
    conclusion_summary="success"
    ok="true"
    while IFS=$'\t' read -r status conclusion; do
      conclusion=${conclusion:-none}
      if [[ "$status" != "completed" ]]; then
        status_summary="$status"
        ok="false"
      fi
      if [[ "$conclusion" != "success" ]]; then
        conclusion_summary="$conclusion"
        ok="false"
      fi
    done <<<"$entries"
  fi

  printf '%s|%s|%s\n' "$status_summary" "$conclusion_summary" "$ok"
}

run_self_test() {
  local workflow_json check_run_json
  workflow_json=$(cat <<'JSON'
{
  "workflow_runs": [
    {"name": "CI", "status": "completed", "conclusion": "success"},
    {"name": "Regression Checks", "status": "completed", "conclusion": "failure"}
  ]
}
JSON
)

  check_run_json=$(cat <<'JSON'
{
  "check_runs": [
    {"name": "shell-ci", "status": "completed", "conclusion": "success"}
  ]
}
JSON
)

  local ci_entries shell_entries
  ci_entries=$(jq -r --arg name "CI" '.workflow_runs[] | select(.name==$name) | [.status, (.conclusion // "none")] | @tsv' <<<"$workflow_json")
  shell_entries=$(jq -r --arg name "shell-ci" '.check_runs[] | select(.name==$name) | [.status, (.conclusion // "none")] | @tsv' <<<"$check_run_json")

  local ci_summary shell_summary
  ci_summary=$(summarize_entries "$ci_entries")
  shell_summary=$(summarize_entries "$shell_entries")

  if [[ "$ci_summary" != "completed|success|true" ]]; then
    echo "Self-test failed: expected CI to be successful but got $ci_summary" >&2
    exit 1
  fi

  if [[ "$shell_summary" != "completed|success|true" ]]; then
    echo "Self-test failed: expected shell-ci to be successful but got $shell_summary" >&2
    exit 1
  fi

  echo "Self-test passed: parsing and summary logic." >&2
}

PR_NUMBER=""
REPO=""
SELF_TEST="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      PR_NUMBER="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --self-test)
      SELF_TEST="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$SELF_TEST" == "true" ]]; then
  run_self_test
  exit 0
fi

if [[ -z "$PR_NUMBER" || -z "$REPO" ]]; then
  usage
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required but not installed." >&2
  exit 1
fi

HEAD_SHA=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq '.head.sha')

workflow_runs_json=$(gh api "repos/$REPO/actions/runs" -f head_sha="$HEAD_SHA" -f per_page=100)
check_runs_json=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-runs" -f per_page=100)
check_suites_json=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-suites" -f per_page=100)

printf 'PR #%s head SHA: %s\n' "$PR_NUMBER" "$HEAD_SHA"

printf '%-32s %-14s %-12s %-12s\n' "Check" "Type" "Status" "Conclusion"
printf '%-32s %-14s %-12s %-12s\n' "----" "----" "------" "----------"

blocked_reasons=()

for name in "${REQUIRED_WORKFLOWS[@]}"; do
  entries=$(jq -r --arg name "$name" '.workflow_runs[] | select(.name==$name) | [.status, (.conclusion // "none")] | @tsv' <<<"$workflow_runs_json")
  summary=$(summarize_entries "$entries")
  status=${summary%%|*}
  rest=${summary#*|}
  conclusion=${rest%%|*}
  ok=${summary##*|}

  printf '%-32s %-14s %-12s %-12s\n' "$name" "workflow" "$status" "$conclusion"

  if [[ -z "$entries" ]]; then
    if contains_name "$name" "${SCHEDULE_ONLY_WORKFLOWS[@]}"; then
      echo "WARN: required workflow '$name' is missing but is schedule-only." >&2
    else
      blocked_reasons+=("Required workflow '$name' is missing")
    fi
  elif [[ "$ok" != "true" ]]; then
    blocked_reasons+=("Required workflow '$name' status=$status conclusion=$conclusion")
  fi
done

for name in "${REQUIRED_CHECK_RUNS[@]}"; do
  entries=$(jq -r --arg name "$name" '.check_runs[] | select(.name==$name) | [.status, (.conclusion // "none")] | @tsv' <<<"$check_runs_json")
  summary=$(summarize_entries "$entries")
  status=${summary%%|*}
  rest=${summary#*|}
  conclusion=${rest%%|*}
  ok=${summary##*|}

  printf '%-32s %-14s %-12s %-12s\n' "$name" "check-run" "$status" "$conclusion"

  if [[ -z "$entries" ]]; then
    blocked_reasons+=("Required check-run '$name' is missing")
  elif [[ "$ok" != "true" ]]; then
    blocked_reasons+=("Required check-run '$name' status=$status conclusion=$conclusion")
  fi
done

suite_failures=$(jq -r '.check_suites[] | select(.conclusion == "failure" or .conclusion == "cancelled") | "\(.app.slug // .app.name // "unknown"): \(.conclusion)"' <<<"$check_suites_json")
if [[ -n "$suite_failures" ]]; then
  while IFS= read -r failure; do
    [[ -n "$failure" ]] || continue
    blocked_reasons+=("Check suite failure: $failure")
  done <<<"$suite_failures"
fi

if (( ${#blocked_reasons[@]} > 0 )); then
  echo "Auto-merge blocked for the following reasons:" >&2
  for reason in "${blocked_reasons[@]}"; do
    echo "- $reason" >&2
  done
  exit 1
fi

echo "All required checks are successful. Auto-merge may proceed." >&2
