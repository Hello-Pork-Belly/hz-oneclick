#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

echo "==> bash -n (installer)"
bash -n hz.sh

echo ""
echo "==> bash -n (.github/scripts)"
bash -n .github/scripts/*.sh

echo ""
echo "==> Guard deprecated installer host"
deprecated_label="sh.horizontech"
deprecated_tld="page"
deprecated_host="${deprecated_label}.${deprecated_tld}"
if git grep -n -F "$deprecated_host" -- .; then
  echo "Deprecated installer host detected. Use https://sh.horizontech.eu.org instead."
  exit 1
fi

echo ""
echo "==> Validate workflow YAML"
if command -v ruby >/dev/null 2>&1; then
  shopt -s nullglob
  workflow_files=(.github/workflows/*.yml .github/workflows/*.yaml)
  shopt -u nullglob
  if [ ${#workflow_files[@]} -eq 0 ]; then
    echo "WARN: No workflow YAML files found"
  else
    for file in "${workflow_files[@]}"; do
      ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$file"
    done
  fi
else
  echo "WARN: ruby not installed; skipping YAML validation"
fi

echo "PASS: Repository integrity checks succeeded."
