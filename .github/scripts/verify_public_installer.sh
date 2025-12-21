#!/usr/bin/env bash
set -euo pipefail

installer_url="https://sh.horizontech.eu.org"
deprecated_tld="page"
deprecated_host="sh.horizontech.${deprecated_tld}"

script_path="$(mktemp)"
trap 'rm -f "$script_path"' EXIT

if ! curl -fsSL --retry 3 --retry-delay 1 --retry-all-errors "$installer_url" -o "$script_path"; then
  echo "FAIL: Unable to download installer from ${installer_url}."
  exit 1
fi

if [ ! -s "$script_path" ]; then
  echo "FAIL: Installer download is empty."
  exit 1
fi

if grep -q "$deprecated_host" "$script_path"; then
  echo "FAIL: Installer contains deprecated host ${deprecated_host}."
  exit 1
fi

if ! bash -n "$script_path"; then
  echo "FAIL: Installer did not pass bash -n validation."
  exit 1
fi

echo "PASS: Public installer endpoint is reachable and valid."
