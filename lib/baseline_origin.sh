#!/usr/bin/env bash

# Baseline diagnostics for ORIGIN/FW group (ports/service/UFW).
# This file only defines functions and does not execute logic on load.

baseline_origin__check_service() {
  local status_lsws status_lshttpd active evidence fallback_active=1

  status_lsws=""
  status_lshttpd=""
  evidence=""

  if command -v systemctl >/dev/null 2>&1; then
    status_lsws="$(systemctl is-active lsws.service 2>/dev/null || true)"
    status_lshttpd="$(systemctl is-active lshttpd.service 2>/dev/null || true)"
    evidence+="lsws.service: ${status_lsws:-N/A}\n"
    evidence+="lshttpd.service: ${status_lshttpd:-N/A}"
  else
    fallback_active=0
  fi

  if [ -z "$status_lsws" ] && [ -z "$status_lshttpd" ]; then
    fallback_active=0
  fi

  if [ "$fallback_active" -eq 0 ]; then
    if pgrep -f lshttpd >/dev/null 2>&1; then
      active=1
      evidence="pgrep -f lshttpd: running"
    else
      active=0
      evidence="pgrep -f lshttpd: not found"
    fi
  else
    active=0
    if [ "${status_lsws,,}" = "active" ] || [ "${status_lshttpd,,}" = "active" ]; then
      active=1
    fi
  fi

  printf "%s\n%s" "$active" "$evidence"
}

baseline_origin__collect_listen() {
  local port output lines
  port="$1"

  if command -v ss >/dev/null 2>&1; then
    output="$(ss -lntp 2>/dev/null || true)"
  elif command -v netstat >/dev/null 2>&1; then
    output="$(netstat -lntp 2>/dev/null || true)"
  else
    output=""
  fi

  lines="$(echo "$output" | awk -v p=":${port}$" '$0 ~ p')"
  printf "%s" "$lines"
}

baseline_origin__analyze_listen() {
  local port lines has_listener=0 only_local=1 public=0 addr evidence
  port="$1"
  lines="$2"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    has_listener=1
    addr="$(echo "$line" | awk '{print $4}')"
    addr="${addr//[[]/}"
    addr="${addr//]/}"

    case "$addr" in
      127.0.0.1:*|::1:*)
        :
        ;;
      0.0.0.0:*|::*)
        only_local=0
        public=1
        ;;
      *)
        only_local=0
        ;;
    esac
  done <<< "$lines"

  evidence="$lines"

  if [ "$has_listener" -eq 0 ]; then
    printf "FAIL\nport-closed\n%s" "$evidence"
    return
  fi

  if [ "$public" -eq 1 ]; then
    printf "PASS\nlisten-public\n%s" "$evidence"
  elif [ "$only_local" -eq 1 ]; then
    printf "FAIL\nlisten-localhost\n%s" "$evidence"
  else
    printf "WARN\nlisten-unknown\n%s" "$evidence"
  fi
}

baseline_origin__format_curl() {
  local url domain http_code exit_code header_args
  url="$1"
  domain="$2"
  header_args=()

  if [ -n "$domain" ]; then
    header_args+=("-H" "Host: ${domain}")
  fi

  http_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 6 "${header_args[@]}" "$url" -k 2>/dev/null)"
  exit_code=$?

  printf "%s %s" "$http_code" "$exit_code"
}

baseline_origin_run() {
  # Usage: baseline_origin_run "<domain>" "<lang>"
  local domain lang group service_state service_evidence listen80 listen443
  local status80 keyword80 evidence80 status443 keyword443 evidence443
  local ufw_evidence ufw_allow80 ufw_allow443 ufw_state ufw_keyword
  local http_code http_exit https_code https_exit
  local evidence_curl_http evidence_curl_https suggestions keyword_http keyword_https

  domain="$1"
  lang="${2:-zh}"
  group="ORIGIN/FW"

  IFS=$'\n' read -r service_state service_evidence <<< "$(baseline_origin__check_service)"
  if [ "$service_state" -eq 1 ]; then
    baseline_add_result "$group" "SERVICE_OLS" "PASS" "lshttpd" "$service_evidence" ""
  else
    if [ "$lang" = "en" ]; then
      suggestions="Ensure lshttpd/lsws service is running (systemctl start lsws.service) and enabled to listen on 80/443."
    else
      suggestions="确认 lshttpd/lsws 服务已在运行（如 systemctl start lsws.service），并监听 80/443。"
    fi
    baseline_add_result "$group" "SERVICE_OLS" "FAIL" "service-down" "$service_evidence" "$suggestions"
  fi

  listen80="$(baseline_origin__collect_listen 80)"
  IFS=$'\n' read -r status80 keyword80 evidence80 <<< "$(baseline_origin__analyze_listen 80 "$listen80")"
  listen443="$(baseline_origin__collect_listen 443)"
  IFS=$'\n' read -r status443 keyword443 evidence443 <<< "$(baseline_origin__analyze_listen 443 "$listen443")"

  if [ "$lang" = "en" ]; then
    suggestions="Confirm the web service listens on public addresses (*:80/*:443) and firewall/security rules allow access."
  else
    suggestions="确认 Web 服务已在公网地址监听（*:80/*:443），并且防火墙/安全规则已放行。"
  fi

  baseline_add_result "$group" "LISTEN_80" "$status80" "$keyword80" "${evidence80:-no-listener}" "$([ "$status80" = "FAIL" ] && echo "$suggestions" || echo "")"
  baseline_add_result "$group" "LISTEN_443" "$status443" "$keyword443" "${evidence443:-no-listener}" "$([ "$status443" = "FAIL" ] && echo "$suggestions" || echo "")"

  ufw_evidence="ufw: not installed"
  ufw_allow80=0
  ufw_allow443=0
  ufw_state="PASS"
  ufw_keyword="ufw-inactive"

  if command -v ufw >/dev/null 2>&1; then
    ufw_evidence="$(ufw status 2>/dev/null || true)"
    if echo "$ufw_evidence" | grep -iq "Status: active"; then
      ufw_keyword="ufw-active"
      if echo "$ufw_evidence" | grep -Eq '\b80(/tcp)?\b.*ALLOW'; then
        ufw_allow80=1
      fi
      if echo "$ufw_evidence" | grep -Eq '\b443(/tcp)?\b.*ALLOW'; then
        ufw_allow443=1
      fi
      if [ $ufw_allow80 -eq 0 ] || [ $ufw_allow443 -eq 0 ]; then
        ufw_state="WARN"
        ufw_keyword="ufw-block"
      fi
    fi
  fi

  if [ "$lang" = "en" ]; then
    suggestions="If UFW is active, allow 80/443 and ensure upstream security policies also permit them."
  else
    suggestions="如启用 UFW，请放行 80/443，并确保上游安全策略也允许访问。"
  fi

  baseline_add_result "$group" "UFW_RULES" "$ufw_state" "$ufw_keyword" "$ufw_evidence" "$([ "$ufw_state" != "PASS" ] && echo "$suggestions" || echo "")"

  read -r http_code http_exit <<< "$(baseline_origin__format_curl "http://127.0.0.1" "$domain")"
  read -r https_code https_exit <<< "$(baseline_origin__format_curl "https://127.0.0.1" "$domain")"

  evidence_curl_http="http_code=${http_code} exit=${http_exit}"
  evidence_curl_https="http_code=${https_code} exit=${https_exit}"

  if [ "$lang" = "en" ]; then
    suggestions="Verify local HTTP/HTTPS respond successfully (200/301). Check service logs if curl returns 000 or times out."
  else
    suggestions="确认本机 HTTP/HTTPS 可正常返回 (200/301)。如 curl 显示 000 或超时，请查看服务日志。"
  fi

  keyword_http="localhost-http"
  keyword_https="localhost-https"

  if [ "$http_exit" -ne 0 ] || [ "$http_code" = "000" ]; then
    keyword_http+=" curl-000"
  fi

  if [ "$https_exit" -ne 0 ] || [ "$https_code" = "000" ]; then
    keyword_https+=" curl-000"
  fi

  baseline_add_result "$group" "LOCAL_HTTP" "$( [ "$http_exit" -eq 0 ] && [ "$http_code" != "000" ] && echo "PASS" || echo "WARN" )" \
    "$keyword_http" "$evidence_curl_http" "$([ "$http_exit" -eq 0 ] && [ "$http_code" != "000" ] && echo "" || echo "$suggestions")"

  baseline_add_result "$group" "LOCAL_HTTPS" "$( [ "$https_exit" -eq 0 ] && [ "$https_code" != "000" ] && echo "PASS" || echo "WARN" )" \
    "$keyword_https" "$evidence_curl_https" "$([ "$https_exit" -eq 0 ] && [ "$https_code" != "000" ] && echo "" || echo "$suggestions")"
}

