#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
installer_path="${HZ_INSTALLER_PATH:-${repo_root}/hz.sh}"
expected_shebang='#!/usr/bin/env bash'
deprecated_snippet='curl -fsSL https://sh.horizontech.eu.org | bash -s -- --help'

if [ ! -f "$installer_path" ]; then
  echo "FAIL: Installer script not found at ${installer_path}."
  exit 1
fi

first_line="$(head -n 1 "$installer_path")"
if [ "$first_line" != "$expected_shebang" ]; then
  echo "FAIL: Installer shebang must be '${expected_shebang}'."
  echo "Found: ${first_line}"
  exit 1
fi

if grep -n -F "$deprecated_snippet" "$installer_path"; then
  echo "FAIL: Deprecated installer snippet detected in ${installer_path}."
  exit 1
fi

echo "PASS: Installer header checks succeeded."
