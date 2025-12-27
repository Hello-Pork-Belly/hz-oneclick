#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

strict=0
for arg in "$@"; do
  case "$arg" in
    --strict)
      strict=1
      ;;
    *)
      echo "ERROR: Unknown argument: $arg"
      echo "Usage: $0 [--strict]"
      exit 2
      ;;
  esac
done

if [[ ! -d "$repo_root/.github" ]]; then
  echo "ERROR: scripts/lint.sh must be run from the repository root"
  exit 1
fi

deprecated_helpers=(
  ".github/scripts/lint_bash.sh"
  ".github/scripts/run_ci_locally.sh"
  "docs/MAINTAINERS_CI.md"
)

# Keep discovery consistent with CI linting.
mapfile -d '' -t files < <(find ./modules ./tests ./.github/scripts -type f -name '*.sh' -print0)

script_count=${#files[@]}
echo "Found ${script_count} shell scripts"

if [[ $script_count -eq 0 ]]; then
  echo "No shell scripts found for lint checks"
  exit 0
fi

echo ""
echo "==> bash -n"
bash_status=0
for f in "${files[@]}"; do
  if ! bash -n "$f"; then
    bash_status=1
  fi
done
if [[ $bash_status -ne 0 ]]; then
  echo "ERROR: bash -n reported syntax issues"
  exit 1
fi

echo ""
echo "==> ShellCheck"
shellcheck_status=0
if command -v shellcheck >/dev/null 2>&1; then
  set +e
  shellcheck -x "${files[@]}"
  shellcheck_status=$?
  set -e
  if [[ $shellcheck_status -ne 0 ]]; then
    if [[ $strict -eq 1 ]]; then
      echo "ERROR: ShellCheck reported findings"
    else
      echo "WARN: ShellCheck reported findings"
    fi
  fi
else
  shellcheck_status=127
  if [[ $strict -eq 1 ]]; then
    echo "ERROR: ShellCheck is required in strict mode"
  else
    echo "WARN: ShellCheck not installed; skipping"
  fi
fi

echo ""
echo "==> shfmt (check only)"
shfmt_status=0
if command -v shfmt >/dev/null 2>&1; then
  set +e
  shfmt -d -i 2 -ci -sr "${files[@]}"
  shfmt_status=$?
  set -e
  if [[ $shfmt_status -ne 0 ]]; then
    if [[ $strict -eq 1 ]]; then
      echo "ERROR: shfmt reported formatting differences"
    else
      echo "WARN: shfmt reported formatting differences"
    fi
  fi
else
  shfmt_status=127
  if [[ $strict -eq 1 ]]; then
    echo "ERROR: shfmt is required in strict mode"
  else
    echo "WARN: shfmt not installed; skipping"
  fi
fi

echo ""
echo "==> deprecated helper references"
deprecated_status=0
deprecated_matches=""
if command -v rg >/dev/null 2>&1; then
  for deprecated in "${deprecated_helpers[@]}"; do
    set +e
    match_output="$(git ls-files -z -- ':!scripts/lint.sh' | xargs -0 rg -n -H --fixed-strings -e "$deprecated")"
    status=$?
    set -e
    if [[ $status -eq 0 ]]; then
      deprecated_status=1
      deprecated_matches+=$'Deprecated reference found:\n'"${match_output}"$'\n'
    fi
  done
else
  for deprecated in "${deprecated_helpers[@]}"; do
    set +e
    match_output="$(git ls-files -z -- ':!scripts/lint.sh' | xargs -0 grep -n -H -F -- "$deprecated")"
    status=$?
    set -e
    if [[ $status -eq 0 ]]; then
      deprecated_status=1
      deprecated_matches+=$'Deprecated reference found:\n'"${match_output}"$'\n'
    fi
  done
fi

if [[ $deprecated_status -ne 0 ]]; then
  if [[ $strict -eq 1 ]]; then
    echo "ERROR: Deprecated helper references detected."
  else
    echo "WARN: Deprecated helper references detected."
  fi
  echo "Use Makefile targets or scripts/lint.sh and scripts/ci_local.sh instead."
  echo ""
  printf "%s" "$deprecated_matches"
fi

echo ""
echo "Summary: bash -n=${bash_status} shellcheck=${shellcheck_status} shfmt=${shfmt_status} deprecated_refs=${deprecated_status}"

if [[ $strict -eq 1 ]]; then
  if [[ $shellcheck_status -ne 0 ]]; then
    exit 1
  fi
  if [[ $shfmt_status -ne 0 ]]; then
    exit 1
  fi
  if [[ $deprecated_status -ne 0 ]]; then
    exit 1
  fi
fi

exit 0
