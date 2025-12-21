#!/usr/bin/env bash
set -euo pipefail

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
    echo "WARN: ShellCheck reported findings"
  fi
else
  echo "WARN: ShellCheck not installed; skipping"
  shellcheck_status=127
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
    echo "WARN: shfmt reported formatting differences"
  fi
else
  echo "WARN: shfmt not installed; skipping"
  shfmt_status=127
fi

echo ""
echo "Summary: bash -n=${bash_status} shellcheck=${shellcheck_status} shfmt=${shfmt_status}"
