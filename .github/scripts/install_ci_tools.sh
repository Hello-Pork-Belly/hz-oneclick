#!/usr/bin/env bash
set -euo pipefail

shfmt_version="v3.8.0"
shfmt_url="https://github.com/mvdan/sh/releases/download/${shfmt_version}/shfmt_${shfmt_version}_linux_amd64"

sudo apt-get update
sudo apt-get install -y shellcheck curl

if command -v shfmt >/dev/null 2>&1; then
  echo "shfmt already available"
  exit 0
fi

if sudo apt-get install -y shfmt; then
  echo "Installed shfmt from apt"
else
  echo "WARN: apt-get install shfmt failed, attempting to download release"
  if curl -fSL "$shfmt_url" -o /usr/local/bin/shfmt; then
    sudo chmod +x /usr/local/bin/shfmt
    echo "Installed shfmt ${shfmt_version} from release"
  else
    echo "WARN: failed to download shfmt from mvdan/sh release"
  fi
fi
