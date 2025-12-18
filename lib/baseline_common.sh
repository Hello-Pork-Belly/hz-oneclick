#!/usr/bin/env bash

# Common helpers for baseline diagnostics.

baseline_redact_enabled() {
  [ "${BASELINE_REDACT:-0}" = "1" ]
}

baseline_redact_text() {
  # Optional redaction pass for domains, IPs, emails, absolute paths.
  if ! baseline_redact_enabled; then
    cat
    return
  fi

  sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted-email>/g' \
    -e 's#([0-9]{1,3}\.){3}[0-9]{1,3}#<redacted-ip>#g' \
    -e 's#([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}#<redacted-ip>#g' \
    -e 's#([A-Za-z0-9-]+\.)+[A-Za-z]{2,}#<redacted-domain>#g' \
    -e 's#(/[^[:space:]]+)#<redacted-path>#g' \
    -e 's#([A-Za-z]:\\\\[^[:space:]]+)#<redacted-path>#g'
}

baseline_sanitize_text() {
  # Redact common sensitive keys before writing to report/output.
  # Preserves line structure while masking values.
  sed -E \
    -e 's/((authorization|token|password|secret|apikey|api_key)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/Ig' \
    -e 's/((^|[[:space:]])key=)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/((bearer)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig' | \
    baseline_redact_text
}

baseline_vendor_scrub_text() {
  # Replace vendor-specific cloud names with neutral wording for JSON outputs.
  local vendor_terms_b64=(
    "b3JhY2xl"
    "YXdz"
    "YW1hem9u"
    "YWxpeXVu"
    "dGVuY2VudA=="
    "YXp1cmU="
    "Z2Nw"
    "Z29vZ2xlIGNsb3Vk"
  )
  local vendor_terms=()
  local vendor_pattern=""
  local term

  for term_b64 in "${vendor_terms_b64[@]}"; do
    if term=$(printf '%s' "$term_b64" | base64 -d 2>/dev/null); then
      vendor_terms+=("$term")
    fi
  done

  if [ ${#vendor_terms[@]} -eq 0 ]; then
    cat
    return
  fi

  vendor_pattern=$(IFS='|'; echo "${vendor_terms[*]}")
    sed -E \
      -e "s/(${vendor_pattern})/cloud provider/Ig"
}

baseline_json_sanitize_field() {
  # Apply secret redaction and vendor-neutral wording to any JSON string field.
  local input sanitized
  input="$1"

  if declare -f baseline_sanitize_text >/dev/null 2>&1; then
    sanitized="$(printf "%s" "$input" | baseline_sanitize_text)"
  else
    sanitized="$input"
  fi

  if declare -f baseline_vendor_scrub_text >/dev/null 2>&1; then
    sanitized="$(printf "%s" "$sanitized" | baseline_vendor_scrub_text)"
  fi

  printf "%s" "$sanitized"
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
