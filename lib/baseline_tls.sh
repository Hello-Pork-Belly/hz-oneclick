#!/usr/bin/env bash

# Baseline diagnostics for TLS/Certificate group.
# This file only defines functions and does not execute any logic on load.

baseline_tls__has_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    echo "1"
  else
    echo "0"
  fi
}

baseline_tls__run_sclient() {
  # Usage: baseline_tls__run_sclient <domain>
  local domain output status cmd_has_timeout
  domain="$1"
  status=0
  cmd_has_timeout="$(baseline_tls__has_timeout)"

  if [ "$cmd_has_timeout" = "1" ]; then
    output="$(timeout 10s openssl s_client -servername "$domain" -connect "${domain}:443" -verify 5 -brief </dev/null 2>&1)" || status=$?
  else
    output="$(openssl s_client -servername "$domain" -connect "${domain}:443" -verify 5 -brief </dev/null 2>&1)" || status=$?
  fi

  printf '%s\n%s' "$status" "$output"
}

baseline_tls__parse_cert_field() {
  # Usage: baseline_tls__parse_cert_field <pem> <field>
  local pem field
  pem="$1"
  field="$2"

  if [ -z "$pem" ]; then
    return 0
  fi

  case "$field" in
    subject)
      echo "$pem" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//'
      ;;
    issuer)
      echo "$pem" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer= *//'
      ;;
    notBefore)
      echo "$pem" | openssl x509 -noout -startdate 2>/dev/null | sed 's/^notBefore=//'
      ;;
    notAfter)
      echo "$pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//'
      ;;
    san)
      echo "$pem" | openssl x509 -noout -ext subjectAltName 2>/dev/null | sed 's/^X509v3 Subject Alternative Name://'
      ;;
  esac
}

baseline_tls__days_until() {
  # Usage: baseline_tls__days_until "<date string>"
  local date_str target_epoch now_epoch
  date_str="$1"

  if [ -z "$date_str" ]; then
    return 1
  fi

  if ! target_epoch=$(date -d "$date_str" +%s 2>/dev/null); then
    return 1
  fi

  now_epoch=$(date +%s)
  echo $(( (target_epoch - now_epoch) / 86400 ))
}

baseline_tls__san_match() {
  # Usage: baseline_tls__san_match "<san_string>" "<domain>"
  local san domain suffix
  san="$1"
  domain="$2"

  if [ -z "$san" ]; then
    echo "UNKNOWN"
    return 0
  fi

  if echo "$san" | grep -Eq "DNS:${domain}(,|$| )"; then
    echo "EXACT"
    return 0
  fi

  suffix="${domain#*.}"
  if [ "$suffix" != "$domain" ] && echo "$san" | grep -Eq "DNS:\*\\.${suffix}(,|$| )"; then
    echo "WILDCARD"
    return 0
  fi

  echo "NONE"
}

baseline_tls_run() {
  # Usage: baseline_tls_run "<domain>" "<lang>"
  local domain lang group sclient_output sclient_status cert_pem subject issuer not_before not_after san
  local handshake_status name_status expiry_status chain_status
  local handshake_keyword name_keyword expiry_keyword chain_keyword
  local verify_code verify_desc san_match days_left evidence_handshake evidence_name evidence_expiry evidence_chain
  local suggestions_handshake suggestions_name suggestions_expiry suggestions_chain

  domain="$1"
  lang="${2:-zh}"
  group="TLS/CERT"

  if ! command -v openssl >/dev/null 2>&1; then
    baseline_add_result "$group" "TLS_HANDSHAKE" "WARN" "TLS_TOOL_MISSING" \
      "OPENSSL: not available" \
      "$([ "$lang" = "en" ] && echo "Install openssl to perform TLS diagnostics." || echo "系统未安装 openssl，无法执行 TLS 诊断，请先安装。")"
    baseline_add_result "$group" "CERT_NAME" "WARN" "TLS_TOOL_MISSING" "CERT: unavailable" ""
    baseline_add_result "$group" "CERT_EXPIRY" "WARN" "TLS_TOOL_MISSING" "EXPIRY: unavailable" ""
    baseline_add_result "$group" "CERT_CHAIN" "WARN" "TLS_TOOL_MISSING" "CHAIN: unavailable" ""
    return 0
  fi

  sclient_status=0
  sclient_output="$(baseline_tls__run_sclient "$domain")"
  sclient_status="${sclient_output%%$'\n'*}"
  sclient_output="${sclient_output#*$'\n'}"

  cert_pem="$(echo "$sclient_output" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' | sed -n '1,/-----END CERTIFICATE-----/p')"
  subject="$(baseline_tls__parse_cert_field "$cert_pem" subject)"
  issuer="$(baseline_tls__parse_cert_field "$cert_pem" issuer)"
  not_before="$(baseline_tls__parse_cert_field "$cert_pem" notBefore)"
  not_after="$(baseline_tls__parse_cert_field "$cert_pem" notAfter)"
  san="$(baseline_tls__parse_cert_field "$cert_pem" san | tr -d '\n')"

  verify_code="$(echo "$sclient_output" | awk -F: '/Verify return code/ {gsub(/^ +| +$/,"",$0); sub(/Verify return code: */,"",$0); print $1; exit}')"
  verify_desc="$(echo "$sclient_output" | awk -F': ' '/Verify return code/ {print $2; exit}')"

  san_match="$(baseline_tls__san_match "$san" "$domain")"
  days_left=""
  if [ -n "$not_after" ]; then
    days_left="$(baseline_tls__days_until "$not_after" || echo "")"
  fi

  # Handshake result
  if [ "$sclient_status" = "0" ]; then
    handshake_status="PASS"
    handshake_keyword="TLS_HANDSHAKE"
  else
    handshake_status="FAIL"
    handshake_keyword="TLS_SNI_FAIL"
  fi

  if [ "$lang" = "en" ]; then
    suggestions_handshake="Check 443 reachability, DNS/proxy routing, and ensure the proxy passes the correct SNI/Host to origin."
    suggestions_name="Ensure the served certificate covers the domain (SAN/wildcard) and the correct vhost certificate is selected."
    suggestions_expiry="Renew the certificate and deploy it on the origin/proxy; refresh chains and reload services."
    suggestions_chain="Include intermediate certificates and align proxy/origin trust; verify full chain after changes."
  else
    suggestions_handshake="检查 443 端口连通、DNS/代理路由，以及代理是否传递正确的 SNI/Host 至源站。"
    suggestions_name="确保证书覆盖域名（SAN/通配符），并在虚拟主机/代理中选中正确证书。"
    suggestions_expiry="续签证书并部署到源站/代理，更新链文件后重载服务。"
    suggestions_chain="补全中间证书链，确保代理/源站信任一致，变更后重新验证链。"
  fi

  evidence_handshake="EXIT: ${sclient_status}\nSCLIENT_HINT: $(echo "$sclient_output" | head -n 2 | tr -d '\r')"

  baseline_add_result "$group" "TLS_HANDSHAKE" "$handshake_status" "$handshake_keyword" \
    "$evidence_handshake" \
    "$([ "$handshake_status" = "FAIL" ] && echo "$suggestions_handshake" || echo "")"

  # Certificate name matching
  if [ -z "$cert_pem" ]; then
    name_status="WARN"
    name_keyword="CERT_MISSING"
    evidence_name="SUBJECT: N/A\nSAN: N/A"
  else
    evidence_name="SUBJECT: ${subject:-N/A}\nSAN_MATCH: ${san_match}\nSAN_SNIPPET: $(echo "$san" | cut -c1-120)"
    case "$san_match" in
      EXACT|WILDCARD)
        name_status="PASS"
        name_keyword="CERT_SAN_MATCH"
        ;;
      NONE)
        name_status="FAIL"
        name_keyword="CERT_SAN_MISMATCH"
        ;;
      *)
        name_status="WARN"
        name_keyword="CERT_SAN_UNKNOWN"
        ;;
    esac
  fi

  baseline_add_result "$group" "CERT_NAME" "$name_status" "$name_keyword" \
    "$evidence_name" \
    "$([ "$name_status" = "FAIL" ] && echo "$suggestions_name" || echo "")"

  # Certificate expiry
  if [ -z "$not_after" ]; then
    expiry_status="WARN"
    expiry_keyword="CERT_EXPIRY_UNKNOWN"
    evidence_expiry="NOT_BEFORE: ${not_before:-N/A}\nNOT_AFTER: N/A"
  else
    if [ -n "$days_left" ]; then
      evidence_expiry="NOT_BEFORE: ${not_before:-N/A}\nNOT_AFTER: ${not_after}\nDAYS_LEFT: ${days_left}"
      if [ "$days_left" -le 0 ]; then
        expiry_status="FAIL"
        expiry_keyword="CERT_EXPIRED"
      elif [ "$days_left" -lt 7 ]; then
        expiry_status="WARN"
        expiry_keyword="CERT_EXPIRING"
      else
        expiry_status="PASS"
        expiry_keyword="CERT_VALID"
      fi
    else
      expiry_status="WARN"
      expiry_keyword="CERT_EXPIRY_UNKNOWN"
      evidence_expiry="NOT_BEFORE: ${not_before:-N/A}\nNOT_AFTER: ${not_after}"
    fi
  fi

  baseline_add_result "$group" "CERT_EXPIRY" "$expiry_status" "$expiry_keyword" \
    "$evidence_expiry" \
    "$({
      if [ "$expiry_status" = "FAIL" ] || [ "$expiry_status" = "WARN" ]; then
        echo "$suggestions_expiry"
      fi
    })"

  # Certificate chain / verify
  if [ -z "$verify_code" ]; then
    chain_status="WARN"
    chain_keyword="CERT_VERIFY_FAIL"
  elif [ "$verify_code" = "0" ]; then
    chain_status="PASS"
    chain_keyword="CERT_VERIFY_OK"
  elif echo "$verify_code" | grep -Eq '^(20|21|27|45)$'; then
    chain_status="FAIL"
    chain_keyword="CERT_CHAIN_INCOMPLETE"
  else
    chain_status="FAIL"
    chain_keyword="CERT_VERIFY_FAIL"
  fi

  evidence_chain="VERIFY_CODE: ${verify_code:-N/A}\nVERIFY_DESC: ${verify_desc:-N/A}"

  baseline_add_result "$group" "CERT_CHAIN" "$chain_status" "$chain_keyword" \
    "$evidence_chain" \
    "$([ "$chain_status" = "FAIL" ] && echo "$suggestions_chain" || echo "")"
}

