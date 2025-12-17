#!/usr/bin/env bash

# Unified tier identifiers for stack selection
: "${TIER_LITE:=lite}"
: "${TIER_STANDARD:=standard}"
: "${TIER_HUB:=hub}"

normalize_tier() {
  # Normalize and validate tier input. Returns normalized tier or non-zero status on failure.
  local tier
  tier="${1:-}"
  tier="${tier,,}"

  case "$tier" in
    "$TIER_LITE"|"$TIER_STANDARD"|"$TIER_HUB")
      printf "%s" "$tier"
      ;;
    *)
      return 1
      ;;
  esac
}

is_valid_tier() {
  # Check if provided tier is supported.
  normalize_tier "$1" >/dev/null 2>&1
}
