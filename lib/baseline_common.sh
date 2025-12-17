#!/usr/bin/env bash

# Common helpers for baseline diagnostics.

baseline_sanitize_text() {
  # Redact common sensitive keys before writing to report/output.
  # Preserves line structure while masking values.
  sed -E \
    -e 's/((authorization|token|password|secret|apikey|api_key)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/Ig' \
    -e 's/((^|[[:space:]])key=)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/((bearer)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig'
}

baseline_json_escape() {
  # Minimal JSON string escaper (no external dependencies).
  # Usage: baseline_json_escape "raw text"
  # Handles quotes, backslashes, and newlines to produce safe JSON strings.
  local input escaped
  input="$1"
  escaped=$(printf '%s' "$input" | \
    sed \
      -e 's/\\/\\\\/g' \
      -e 's/"/\\\"/g' \
      -e 's/\r/\\r/g' \
      -e 's/\t/\\t/g' | \
    tr '\n' '\n')
  # Replace literal newlines with \n via printf to keep sed portable
  escaped=$(printf '%s' "$escaped" | sed ':a;N;$!ba;s/\n/\\n/g')
  printf '%s' "$escaped"
}
