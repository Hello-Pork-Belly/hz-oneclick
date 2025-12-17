#!/usr/bin/env bash

# Baseline diagnostics for Proxy/CDN (Cloudflare-aware) group.
# This file only defines functions and does not execute any logic on load.

baseline_proxy__extract_headers() {
  # Usage: baseline_proxy__extract_headers "<headers>"
  # Returns filtered header lines for evidence.
  local headers
  headers="$1"

  echo "$headers" | sed -n \
    -e '/^HTTP/Ip' \
    -e '/^server:/Ip' \
    -e '/^via:/Ip' \
    -e '/^x-cache/Ip' \
    -e '/^x-served-by/Ip' \
    -e '/^cf-ray/Ip' \
    -e '/^cf-cache-status/Ip' \
    -e '/^cf-connection/Ip' \
    -e '/^cf-visitor/Ip'
}

baseline_proxy__curl_headers() {
  # Usage: baseline_proxy__curl_headers "<url>"
  # Prints "<exit_code>\n<headers>" to stdout.
  local url output exit_code
  url="$1"
  if ! command -v curl >/dev/null 2>&1; then
    printf "127\n" && return 0
  fi
  output="$(curl -I -s --max-time 12 --connect-timeout 8 "$url" 2>&1)"
  exit_code=$?
  printf "%s\n%s" "$exit_code" "$output"
}

baseline_proxy__https_status() {
  # Usage: baseline_proxy__https_status "<domain>"
  # Prints "<status_hint> <exit_code>" where status_hint is HTTP code or ERROR/TIMEOUT.
  local domain status exit_code status_hint
  domain="$1"

  if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR 127"
    return 0
  fi

  status="$(curl -I -s -o /dev/null -w "%{http_code}" --max-time 12 --connect-timeout 8 "https://${domain}/" 2>/dev/null)"
  exit_code=$?

  if [ "$exit_code" -eq 28 ]; then
    status_hint="TIMEOUT"
  elif [ "$exit_code" -eq 6 ]; then
    status_hint="DNS_FAIL"
  elif [ "$exit_code" -ne 0 ]; then
    status_hint="ERROR"
  elif echo "$status" | grep -Eq '^[0-9]{3}$'; then
    status_hint="$status"
  else
    status_hint="ERROR"
  fi

  printf "%s %s" "$status_hint" "$exit_code"
}

baseline_proxy__openssl_probe() {
  # Usage: baseline_proxy__openssl_probe "<domain>"
  # Prints "<exit_code>\n<selected lines>" to stdout.
  local domain output exit_code
  domain="$1"

  if ! command -v openssl >/dev/null 2>&1; then
    printf "127\n" && return 0
  fi

  if command -v timeout >/dev/null 2>&1; then
    output="$(
      timeout 8 openssl s_client -servername "$domain" -connect "${domain}:443" </dev/null 2>/dev/null |
        sed -n -e '/^subject=/p' -e '/^issuer=/p' -e '/^Verify return code:/p'
    )"
    exit_code=$?
  else
    output="$(
      openssl s_client -servername "$domain" -connect "${domain}:443" </dev/null 2>/dev/null |
        sed -n -e '/^subject=/p' -e '/^issuer=/p' -e '/^Verify return code:/p'
    )"
    exit_code=$?
  fi
  printf "%s\n%s" "$exit_code" "$output"
}

baseline_proxy_run() {
  # Usage: baseline_proxy_run "<domain>" "<lang>"
  local domain lang group
  local headers_http headers_https http_exit https_exit http_raw https_raw
  local detect_keyword detect_status detect_evidence detect_suggestions
  local https_hint https_exit_code http_status http_hint http_exit_code baseline_status
  local tls_exit tls_info tls_keyword tls_status tls_suggestions tls_raw
  local keywords_https=() evidence_https suggestions_https
  local cf_detected generic_detected sni_mismatch handshake_fail

  domain="$1"
  lang="${2:-zh}"
  group="Proxy/CDN"

  # Header detection for HTTP and HTTPS
  http_raw="$(baseline_proxy__curl_headers "http://${domain}/")"
  https_raw="$(baseline_proxy__curl_headers "https://${domain}/")"
  http_exit="${http_raw%%$'\n'*}"
  headers_http="${http_raw#*$'\n'}"
  https_exit="${https_raw%%$'\n'*}"
  headers_https="${https_raw#*$'\n'}"

  detect_keyword="proxy_detected:none"
  detect_status="PASS"
  detect_suggestions=""
  tls_suggestions=""
  cf_detected=0
  generic_detected=0

  if [ "$http_exit" = "127" ] || [ "$https_exit" = "127" ]; then
    detect_status="WARN"
    detect_keyword="proxy_check:curl_missing"
    if [ "$lang" = "en" ]; then
      detect_suggestions="curl not available; install curl to run proxy diagnostics."
    else
      detect_suggestions="未检测到 curl，安装后可完成代理/CDN 诊断。"
    fi
  else
    if [ "$http_exit" -eq 28 ] || [ "$https_exit" -eq 28 ]; then
      detect_status="WARN"
      detect_keyword="proxy_check:timeout"
      if [ "$lang" = "en" ]; then
        detect_suggestions="Timeout reaching domain over HTTP/HTTPS; verify DNS and firewall for proxy edge."
      else
        detect_suggestions="HTTP/HTTPS 连接超时，请检查 DNS 解析与到代理边缘的防火墙放行。"
      fi
    elif [ "$http_exit" -eq 6 ] || [ "$https_exit" -eq 6 ]; then
      detect_status="FAIL"
      detect_keyword="proxy_check:dns_fail"
      if [ "$lang" = "en" ]; then
        detect_suggestions="DNS lookup failed; confirm domain resolves before proxy/CDN checks."
      else
        detect_suggestions="DNS 解析失败，请确认域名已正确解析后再进行代理/CDN 检查。"
      fi
    else
      if echo "$headers_http" "$headers_https" | grep -Eqi 'server: *cloudflare|cf-ray|cf-cache-status'; then
        detect_keyword="proxy_detected:cloudflare"
        cf_detected=1
      elif echo "$headers_http" "$headers_https" | grep -Eqi '^via:|x-cache|x-served-by'; then
        detect_keyword="proxy_detected:generic"
        generic_detected=1
      fi
    fi
  fi

  detect_evidence="$(baseline_proxy__extract_headers "$headers_http")"
  detect_evidence+=$'\n'
  detect_evidence+="$(baseline_proxy__extract_headers "$headers_https")"
  detect_evidence="$(printf "%s" "$detect_evidence" | sed '/^$/d')"

  baseline_add_result "$group" "PROXY_HEADERS" "$detect_status" "$detect_keyword" \
    "$detect_evidence" "$detect_suggestions"

  # HTTPS status classification
  read -r https_hint https_exit_code <<< "$(baseline_proxy__https_status "$domain")"
  if command -v curl >/dev/null 2>&1; then
    http_status="$(curl -I -s -o /dev/null -w "%{http_code}" --max-time 8 --connect-timeout 6 "http://${domain}/" 2>/dev/null || echo "ERROR")"
    http_exit_code=$?
  else
    http_status="ERROR"
    http_exit_code=127
  fi
  http_hint="$http_status"
  if [ "$http_exit_code" -eq 28 ]; then
    http_hint="TIMEOUT"
  elif [ "$http_exit_code" -eq 6 ]; then
    http_hint="DNS_FAIL"
  elif ! echo "$http_status" | grep -Eq '^[0-9]{3}$'; then
    http_hint="ERROR"
  fi

  if [ "$https_hint" = "TIMEOUT" ] || [ "$https_hint" = "DNS_FAIL" ] || [ "$https_hint" = "ERROR" ]; then
    baseline_status="FAIL"
  elif echo "$https_hint" | grep -Eq '^[0-9]{3}$' && [ "$https_hint" -ge 400 ]; then
    baseline_status="FAIL"
  else
    baseline_status="PASS"
  fi

  if [ "$https_hint" = "TIMEOUT" ]; then
    keywords_https+=("proxy_check:timeout")
  elif [ "$https_hint" = "DNS_FAIL" ]; then
    keywords_https+=("proxy_check:dns_fail")
  fi

  if echo "$https_hint" | grep -Eq '^521$'; then
    keywords_https+=("status:https_521" "origin:unreachable_suspect")
  elif echo "$https_hint" | grep -Eq '^(525|526)$'; then
    keywords_https+=("status:https_525_526")
  elif echo "$https_hint" | grep -Eq '^522$'; then
    keywords_https+=("origin:unreachable_suspect")
  fi

  if echo "$http_hint" | grep -Eq '^[0-9]{3}$' && [ "$http_hint" -lt 400 ] && { [ "$baseline_status" = "FAIL" ] || [ "$baseline_status" = "WARN" ]; }; then
    keywords_https+=("proxy_only_http")
  fi

  evidence_https="HTTP_STATUS: ${http_hint} (curl_exit=${http_exit_code})\nHTTPS_STATUS: ${https_hint} (curl_exit=${https_exit_code})"

  if [ "$lang" = "en" ]; then
    suggestions_https="Check proxy/CDN HTTPS reachability; ensure TLS mode matches origin and port 443 is allowed."
  else
    suggestions_https="检查代理/CDN 的 HTTPS 连通性，确认 TLS 模式与回源一致且 443 端口已放行。"
  fi

  baseline_add_result "$group" "HTTPS_STATUS" "$baseline_status" "${keywords_https[*]:-HTTPS_STATUS}" \
    "$evidence_https" "$suggestions_https"

  # TLS handshake probe
  tls_raw="$(baseline_proxy__openssl_probe "$domain")"
  tls_exit="${tls_raw%%$'\n'*}"
  tls_info="${tls_raw#*$'\n'}"
  tls_keyword="tls:ok"
  tls_status="PASS"
  handshake_fail=0
  sni_mismatch=0

  if [ "$tls_exit" = "127" ]; then
    tls_status="WARN"
    tls_keyword="tls:openssl_missing"
    if [ "$lang" = "en" ]; then
      tls_suggestions="openssl not available; install to perform TLS handshake diagnostics."
    else
      tls_suggestions="未检测到 openssl，安装后可进行 TLS 握手诊断。"
    fi
  else
    if [ "$tls_exit" -ne 0 ]; then
      handshake_fail=1
      tls_status="FAIL"
      tls_keyword="tls:handshake_fail"
    fi

    if echo "$tls_info" | grep -Eqi 'verify error|handshake failure'; then
      handshake_fail=1
      tls_status="FAIL"
      tls_keyword="tls:handshake_fail"
    fi

    if echo "$tls_info" | awk -F'=' '/^subject=/{print $0}' | grep -Fqi "$domain"; then
      :
    else
      if echo "$tls_info" | awk -F'=' '/^subject=/{print $0}' | grep -Fqi "*.${domain#*.}"; then
        :
      elif [ -n "$tls_info" ]; then
        sni_mismatch=1
      fi
    fi

    if [ $sni_mismatch -eq 1 ]; then
      if [ "$tls_keyword" = "tls:ok" ]; then
        tls_keyword="tls:sni_mismatch_suspect"
      else
        tls_keyword+=" tls:sni_mismatch_suspect"
      fi
    fi

    if [ $handshake_fail -eq 1 ] && echo "${keywords_https[*]}" | grep -q "origin:unreachable_suspect"; then
      tls_keyword+=" origin:unreachable_suspect"
    fi

    if [ "$lang" = "en" ]; then
      tls_suggestions=$(cat <<'SUG'
Check if proxy/CDN SSL mode matches the origin certificate and that port 443 is reachable from the edge.
If using a reverse proxy, ensure the presented certificate includes the requested domain/SAN.
SUG
)
    else
      tls_suggestions=$(cat <<'SUG'
检查代理/CDN 的 SSL 模式与回源证书是否匹配，确认边缘到服务器的 443 端口可访问。
如使用反向代理，确保证书包含请求的域名或 SAN。
SUG
)
    fi

    if [ $handshake_fail -eq 1 ] && [ "$lang" = "en" ]; then
      tls_suggestions+=$'\nTLS handshake failed; verify origin service accepts TLS and the proxy mode is correct.'
    elif [ $handshake_fail -eq 1 ]; then
      tls_suggestions+=$'\nTLS 握手失败，请确认回源服务开启 TLS 并检查代理模式设置是否正确。'
    fi

    if [ $sni_mismatch -eq 1 ] && [ "$lang" = "en" ]; then
      tls_suggestions+=$'\nCertificate subject appears mismatched; reissue certificate for the exact domain or adjust SNI.'
    elif [ $sni_mismatch -eq 1 ]; then
      tls_suggestions+=$'\n证书主题可能不匹配，请为目标域名重新签发证书或校正 SNI。'
    fi

    if [ $cf_detected -eq 1 ]; then
      if [ "$lang" = "en" ]; then
        tls_suggestions+=$'\nCloudflare detected; align SSL/TLS mode (Flexible/Full/Strict) with origin certificate and firewall rules.'
      else
        tls_suggestions+=$'\n检测到 Cloudflare，请在其控制台确认 SSL/TLS 模式（灵活/完全/严格）与回源证书、防火墙配置一致。'
      fi
    elif [ $generic_detected -eq 1 ]; then
      if [ "$lang" = "en" ]; then
        tls_suggestions+=$'\nReview reverse proxy/CDN console TLS settings to match origin certificate and open ports.'
      else
        tls_suggestions+=$'\n请检查反向代理/CDN 控制台的 TLS 设置，确保与回源证书和放行端口一致。'
      fi
    fi
  fi

  baseline_add_result "$group" "TLS_HANDSHAKE" "$tls_status" "$tls_keyword" \
    "${tls_info}" "${tls_suggestions//$'\n'/$'\\n'}"
}
