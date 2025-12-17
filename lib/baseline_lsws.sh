#!/usr/bin/env bash

# Baseline diagnostics for LSWS/OLS service/ports/config/logs.

baseline_lsws__sanitize_log() {
  # Redact sensitive tokens from log snippets.
  sed -E 's/(token|authorization|password|secret|apikey|key=)[^[:space:]]*/\1=***REDACTED***/Ig'
}

baseline_lsws__tail_file() {
  # Usage: baseline_lsws__tail_file <path> <lines>
  local file lines
  file="$1"
  lines="$2"

  if [ ! -r "$file" ]; then
    return 1
  fi

  tail -n "$lines" "$file" 2>/dev/null | baseline_lsws__sanitize_log
}

baseline_lsws__check_listen() {
  # Usage: baseline_lsws__check_listen <port>
  local port output status
  port="$1"

  if command -v ss >/dev/null 2>&1; then
    output="$(ss -lnt 2>/dev/null || true)"
  elif command -v netstat >/dev/null 2>&1; then
    output="$(netstat -lnt 2>/dev/null || true)"
  else
    echo "WARN|no ss/netstat"
    return 0
  fi

  if echo "$output" | awk '{print $4}' | grep -Eq "(^|[:])${port}$"; then
    status="PASS"
  else
    status="FAIL"
  fi

  echo "${status}|listener check via ss/netstat"
}

baseline_lsws__probe_http() {
  # Usage: baseline_lsws__probe_http <url> <insecure:0/1>
  local url insecure code exit_code status_hint evidence
  url="$1"
  insecure="$2"

  if command -v curl >/dev/null 2>&1; then
    code="$(curl ${insecure:+-k} -I -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 6 "$url" 2>/dev/null)"
    exit_code=$?
  elif command -v wget >/dev/null 2>&1; then
    evidence="$(wget ${insecure:+--no-check-certificate} --timeout=10 --tries=1 --server-response "$url" -O /dev/null 2>&1 | awk '/HTTP\//{print $2; exit}')"
    exit_code=$?
    code="$evidence"
  else
    echo "WARN|no curl/wget"
    return 0
  fi

  if [ "$exit_code" -eq 28 ]; then
    status_hint="TIMEOUT"
  elif [ "$exit_code" -ne 0 ]; then
    status_hint="ERROR"
  elif echo "$code" | grep -Eq '^[0-9]{3}$'; then
    status_hint="$code"
  else
    status_hint="ERROR"
  fi

  echo "${status_hint}|http code=${code:-N/A}"
}

baseline_lsws__detect_conflicts() {
  local services service evidence status found state
  services=(nginx apache2 httpd caddy haproxy)
  evidence=""
  status="PASS"
  found=0

  for service in "${services[@]}"; do
    state=""
    if command -v systemctl >/dev/null 2>&1; then
      state="$(systemctl is-active "$service" 2>/dev/null || true)"
      if [ "$state" = "active" ]; then
        evidence+="${service}(active) "
        found=1
      elif [ -n "$state" ] && [ "$state" != "unknown" ]; then
        evidence+="${service}(${state}) "
      fi
    elif command -v pgrep >/dev/null 2>&1; then
      if pgrep -x "$service" >/dev/null 2>&1; then
        evidence+="${service}(process) "
        found=1
      fi
    fi
  done

  if [ $found -eq 1 ]; then
    status="WARN"
  fi

  if [ -z "$evidence" ]; then
    evidence="no known conflicts detected"
  fi

  echo "${status}|${evidence}" 
}

baseline_lsws_run() {
  # Usage: baseline_lsws_run "<domain_optional>" "<lang_optional>"
  local domain lang group lsws_state lsws_evidence lsws_keyword lsws_suggestion
  local listen80 listen443 listen7080 listen_status listen_evidence
  local http_status http_ev https_status https_ev admin_status admin_ev
  local conflict_status conflict_ev config_status config_ev log_status log_ev
  local version output keywords log_keywords log_tail evidence_lines suggestions_lines

  domain="$1"
  lang="${2:-zh}"
  group="LSWS/OLS"

  if [[ "${lang,,}" == en* ]]; then
    lang="en"
  else
    lang="zh"
  fi

  # Service status
  lsws_state="WARN"
  lsws_evidence=""
  lsws_keyword="SERVICE_UNKNOWN"
  lsws_suggestion=""
  if command -v systemctl >/dev/null 2>&1; then
    output="$(systemctl is-active lsws 2>/dev/null || true)"
    if [ "$output" = "active" ]; then
      lsws_state="PASS"
      lsws_keyword="SERVICE_RUNNING"
      lsws_evidence="systemctl is-active lsws: active"
    elif [ -n "$output" ]; then
      lsws_state="FAIL"
      lsws_keyword="SERVICE_STOPPED"
      lsws_evidence="systemctl is-active lsws: ${output}"
    else
      lsws_state="WARN"
      lsws_evidence="systemctl not reporting lsws"
    fi
  elif command -v pgrep >/dev/null 2>&1; then
    if pgrep -x lshttpd >/dev/null 2>&1; then
      lsws_state="PASS"
      lsws_keyword="SERVICE_RUNNING"
      lsws_evidence="pgrep lshttpd: found"
    else
      lsws_state="FAIL"
      lsws_keyword="SERVICE_STOPPED"
      lsws_evidence="pgrep lshttpd: not found"
    fi
  else
    lsws_state="WARN"
    lsws_evidence="systemctl/pgrep unavailable"
  fi

  if [ "$lsws_state" != "PASS" ]; then
    if [ "$lang" = "en" ]; then
      lsws_suggestion="Check if lsws service is installed and start it manually."
    else
      lsws_suggestion="请确认已安装 lsws 服务并尝试手动启动。"
    fi
  fi

  baseline_add_result "$group" "lsws_active" "$lsws_state" "$lsws_keyword" "$lsws_evidence" "$lsws_suggestion"

  # Port listening
  local listen_keyword listen_suggestion

  IFS='|' read -r listen_status listen_evidence <<< "$(baseline_lsws__check_listen 80)"
  listen_keyword="LISTEN_80"
  listen_suggestion=""
  if [ "$listen_status" = "FAIL" ]; then
    listen_keyword="PORT_80_BLOCK"
    if [ "$lang" = "en" ]; then
      listen_suggestion="Port 80 not listening; check service bindings and firewall."
    else
      listen_suggestion="80 端口未监听，请检查服务绑定与防火墙。"
    fi
  fi
  baseline_add_result "$group" "listen_80" "$listen_status" "$listen_keyword" "${listen_evidence}" "$listen_suggestion"

  IFS='|' read -r listen_status listen_evidence <<< "$(baseline_lsws__check_listen 443)"
  listen_keyword="LISTEN_443"
  listen_suggestion=""
  if [ "$listen_status" = "FAIL" ]; then
    listen_keyword="PORT_443_BLOCK"
    if [ "$lang" = "en" ]; then
      listen_suggestion="Port 443 not listening; check TLS listener and firewall."
    else
      listen_suggestion="443 端口未监听，请检查 TLS 监听与防火墙。"
    fi
  fi
  baseline_add_result "$group" "listen_443" "$listen_status" "$listen_keyword" "${listen_evidence}" "$listen_suggestion"

  IFS='|' read -r listen_status listen_evidence <<< "$(baseline_lsws__check_listen 7080)"
  listen_keyword="LISTEN_7080"
  listen_suggestion=""
  if [ "$listen_status" = "FAIL" ]; then
    listen_keyword="PORT_7080_BLOCK"
    if [ "$lang" = "en" ]; then
      listen_suggestion="Port 7080 not listening; ensure admin console is enabled and not blocked by firewall."
    else
      listen_suggestion="7080 未监听，检查后台是否启用以及防火墙放行。"
    fi
  fi
  baseline_add_result "$group" "listen_7080" "$listen_status" "$listen_keyword" "${listen_evidence}" "$listen_suggestion"

  # HTTP probes
  local http_state http_suggestion https_state admin_state domain_state domain_suggestion

  IFS='|' read -r http_status http_ev <<< "$(baseline_lsws__probe_http "http://127.0.0.1/" 0)"
  if echo "$http_status" | grep -Eq '^(200|301|302|307|308)$'; then
    http_state="PASS"
  elif [ "$http_status" = "WARN" ]; then
    http_state="WARN"
  else
    http_state="FAIL"
  fi
  http_suggestion=""
  if [ "$http_state" != "PASS" ]; then
    if [ "$lang" = "en" ]; then
      http_suggestion="Local HTTP unreachable; verify lsws vhost and firewall."
    else
      http_suggestion="本地 HTTP 不可达，请检查站点配置与防火墙。"
    fi
  fi
  baseline_add_result "$group" "localhost_http" "$http_state" "HTTP_LOCAL" "$http_ev" "$http_suggestion"

  IFS='|' read -r https_status https_ev <<< "$(baseline_lsws__probe_http "https://127.0.0.1/" 1)"
  if echo "$https_status" | grep -Eq '^(200|301|302|307|308)$'; then
    https_state="PASS"
  else
    https_state="WARN"
  fi
  baseline_add_result "$group" "localhost_https" "$https_state" "HTTPS_LOCAL" "$https_ev" "$([ "$lang" = "en" ] && echo "HTTPS probe may fail due to certificate; confirm listener and cert." || echo "HTTPS 探测可能因证书失败，请确认监听与证书配置。")"

  IFS='|' read -r admin_status admin_ev <<< "$(baseline_lsws__probe_http "http://127.0.0.1:7080/" 0)"
  if echo "$admin_status" | grep -Eq '^[0-9]{3}$'; then
    admin_state="PASS"
  elif [ "$admin_status" = "WARN" ]; then
    admin_state="WARN"
  else
    admin_state="FAIL"
  fi
  admin_suggestion=""
  if [ "$admin_state" != "PASS" ]; then
    if [ "$lang" = "en" ]; then
      admin_suggestion="Admin port 7080 unreachable; check listener bind address, service status, and firewall/security rules."
    else
      admin_suggestion="后台 7080 端口不可达，请检查监听地址、服务状态与防火墙安全策略。"
    fi
  fi
  baseline_add_result "$group" "admin_7080" "$admin_state" "ADMIN_CONSOLE" "$admin_ev" "$admin_suggestion"

  # Optional domain probe
  if [ -n "$domain" ]; then
    IFS='|' read -r http_status http_ev <<< "$(baseline_lsws__probe_http "http://${domain}" 0)"
    if echo "$http_status" | grep -Eq '^(200|301|302|307|308)$'; then
      domain_state="PASS"
    elif [ "$http_status" = "WARN" ]; then
      domain_state="WARN"
    else
      domain_state="FAIL"
    fi
    domain_suggestion=""
    if [ "$domain_state" != "PASS" ]; then
      if [ "$lang" = "en" ]; then
        domain_suggestion="Domain HTTP probe failed; check DNS resolution and security rules."
      else
        domain_suggestion="域名 HTTP 探测失败，请检查 DNS 解析与安全放行。"
      fi
    fi
    baseline_add_result "$group" "domain_http" "$domain_state" "DOMAIN_HTTP" "${http_ev}" "$domain_suggestion"
  fi

  # Conflict detection
  IFS='|' read -r conflict_status conflict_ev <<< "$(baseline_lsws__detect_conflicts)"
  suggestions_lines=""
  if [ "$conflict_status" = "WARN" ]; then
    if [ "$lang" = "en" ]; then
      suggestions_lines="Other web services detected; stop or remove conflicts if ports 80/443 are occupied."
    else
      suggestions_lines="发现其他 Web 服务，占用 80/443 时请停止或卸载冲突服务。"
    fi
  fi
  baseline_add_result "$group" "conflicts" "$conflict_status" "SERVICE_CONFLICT" "$conflict_ev" "$suggestions_lines"

  # Config and version
  config_ev=""
  config_status="PASS"
  version=""
  if [ -x "/usr/local/lsws/bin/lswsctrl" ]; then
    version="$(/usr/local/lsws/bin/lswsctrl -v 2>/dev/null | tr -d '\r' | head -n1)"
    output="$(/usr/local/lsws/bin/lswsctrl status 2>/dev/null || true)"
    if [ -n "$output" ]; then
      config_ev+="lswsctrl status: ${output//$'\n'/; }\n"
    fi
  elif command -v lsws >/dev/null 2>&1; then
    version="$(lsws -v 2>/dev/null | tr -d '\r' | head -n1)"
  fi
  if [ -n "$version" ]; then
    config_ev+="version: ${version}\n"
  fi
  if [ -d "/usr/local/lsws" ]; then
    config_ev+="/usr/local/lsws: present\n"
  else
    config_ev+="/usr/local/lsws: missing\n"
    config_status="WARN"
  fi
  if [ -f "/usr/local/lsws/conf/httpd_config.conf" ]; then
    config_ev+="conf/httpd_config.conf: present\n"
  else
    config_ev+="conf/httpd_config.conf: missing\n"
    config_status="WARN"
  fi
  if [ -d "/usr/local/lsws/logs" ]; then
    config_ev+="logs directory: present"
  else
    config_ev+="logs directory: missing"
    config_status="WARN"
  fi

  suggestions_lines=""
  if [ "$config_status" = "WARN" ]; then
    if [ "$lang" = "en" ]; then
      suggestions_lines="Verify LSWS installation path and configs."
    else
      suggestions_lines="检查 LSWS 安装路径和配置文件是否完整。"
    fi
  fi
  baseline_add_result "$group" "config_paths" "$config_status" "LSWS_CONFIG" "${config_ev%\\n}" "$suggestions_lines"

  # Logs tail
  log_tail=""
  log_keywords=()
  if baseline_lsws__tail_file "/usr/local/lsws/logs/error.log" 80 >/tmp/lsws_error_tail 2>/dev/null; then
    log_tail+="[error.log]\n$(cat /tmp/lsws_error_tail)\n"
  fi
  if baseline_lsws__tail_file "/usr/local/lsws/logs/stderr.log" 80 >/tmp/lsws_stderr_tail 2>/dev/null; then
    log_tail+="[stderr.log]\n$(cat /tmp/lsws_stderr_tail)\n"
  fi
  rm -f /tmp/lsws_error_tail /tmp/lsws_stderr_tail

  if [ -n "$log_tail" ]; then
    while IFS= read -r line; do
      case "$line" in
        *"address already in use"*) log_keywords+=("PORT_IN_USE") ;;
        *"Permission denied"*|*"permission denied"*) log_keywords+=("PERMISSION_DENIED") ;;
        *"segfault"*|*"Segmentation fault"*) log_keywords+=("SEGFAULT") ;;
        *"killed"*|*"Killed process"*) log_keywords+=("OOM_KILLED") ;;
        *"SSL"*|*"handshake"*) log_keywords+=("SSL_HANDSHAKE") ;;
        *"cannot load"*|*"failed to load"*) log_keywords+=("LOAD_FAIL") ;;
        *"config"*"error"*|*"configuration"*"error"*) log_keywords+=("CONFIG_ERROR") ;;
      esac
    done <<< "$(printf "%s" "$log_tail")"
    log_status="PASS"
    log_ev="${log_tail%\\n}"
  else
    log_status="WARN"
    log_ev="logs not found or unreadable"
  fi

  keywords="${log_keywords[*]}"
  if [ -z "$keywords" ]; then
    keywords="LOGS_RECENT"
  fi

  suggestions_lines=""
  if [ "$lang" = "en" ]; then
    suggestions_lines="If logs show port conflict, stop conflicting service; if permission issues, check vhost ownership; if OOM, consider swap or smaller workload."
  else
    suggestions_lines="若日志提示端口占用，请停止冲突服务；如有权限问题，检查站点目录 owner/group；如出现 OOM，建议增加 swap 或降低负载。"
  fi
  baseline_add_result "$group" "logs_tail" "$log_status" "$keywords" "$log_ev" "$suggestions_lines"
}
