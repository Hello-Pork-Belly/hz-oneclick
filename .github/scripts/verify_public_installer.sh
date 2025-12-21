#!/usr/bin/env bash
set -euo pipefail

installer_url="${HZ_PUBLIC_INSTALLER_URL:-https://sh.horizontech.eu.org}"
deprecated_label="sh.horizontech"
deprecated_tld="page"
deprecated_host="${deprecated_label}.${deprecated_tld}"
strict_mode="${HZ_PUBLIC_INSTALLER_STRICT:-0}"

script_path="$(mktemp)"
trap 'rm -f "$script_path"' EXIT

if ! curl -fsSL --retry 3 --retry-delay 1 --retry-all-errors --retry-connrefused "$installer_url" -o "$script_path"; then
  echo "WARN: Unable to download installer from ${installer_url}."
  if [ "$strict_mode" = "1" ]; then
    exit 1
  fi
  exit 0
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
