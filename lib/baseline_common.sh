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
