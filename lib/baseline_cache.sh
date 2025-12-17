#!/usr/bin/env bash

# Baseline diagnostics for cache layer (Redis + PHP OPcache + WP hints).
# Defines functions only; no logic executed on source.

baseline_cache__detect_php_bin() {
  # Detect preferred PHP binary (lsphp first, then php).
  if command -v lsphp >/dev/null 2>&1; then
    echo "lsphp"
  elif command -v php >/dev/null 2>&1; then
    echo "php"
  else
    echo ""
  fi
}

baseline_cache__check_redis_service() {
  # Inspect redis service status via systemctl when available.
  local service_name status output suggestion lang
  lang="$1"
  status="WARN"
  suggestion=""

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "WARN|systemctl not available"
    return
  fi

  for service_name in redis-server redis; do
    if systemctl list-unit-files | awk '{print $1}' | grep -q "^${service_name}\.service$"; then
      output="$(systemctl is-active "${service_name}" 2>/dev/null || true)"
      if [ "$output" = "active" ]; then
        status="PASS"
        suggestion=""
        echo "${status}|${service_name} active"
        return
      else
        status="WARN"
        suggestion=$([ "$lang" = "en" ] && echo "Check redis service state: systemctl status ${service_name} --no-pager" || \
          echo "检查 Redis 服务状态：systemctl status ${service_name} --no-pager")
        echo "${status}|${service_name} ${output:-unknown}"
        return
      fi
    fi
  done

  suggestion=$([ "$lang" = "en" ] && echo "redis service unit not found; ensure package installed." || \
    echo "未找到 redis 服务单元，请确认是否已安装 redis。")
  echo "WARN|service unit missing|${suggestion}"
}

baseline_cache__check_redis_listen() {
  # Inspect Redis listening sockets.
  local output status evidence listeners suggestion lang
  lang="$1"
  listeners=""
  suggestion=""

  if command -v ss >/dev/null 2>&1; then
    output="$(ss -lnt 2>/dev/null || true)"
  elif command -v netstat >/dev/null 2>&1; then
    output="$(netstat -lnt 2>/dev/null || true)"
  else
    echo "WARN|no ss/netstat"
    return
  fi

  while IFS= read -r line; do
    if echo "$line" | awk '{print $4}' | grep -Eq '(:|^)(6379)$'; then
      listeners+="${line% *}\n"
    fi
  done <<< "$output"

  listeners="${listeners%$'\n'}"

  if [ -z "$listeners" ]; then
    status="WARN"
    evidence="no :6379 listener"
    suggestion=$([ "$lang" = "en" ] && echo "Verify Redis is bound: ss -lntp | grep ':6379'" || \
      echo "确认 Redis 是否监听端口：ss -lntp | grep ':6379'")
    echo "${status}|${evidence}|${suggestion}"
    return
  fi

  evidence="$(printf '%s' "$listeners" | awk '{print $4}' | paste -sd"," -)"
  if echo "$evidence" | grep -Eq '(0\.0\.0\.0|::):6379'; then
    status="WARN"
    suggestion=$([ "$lang" = "en" ] && echo "Redis should not listen publicly; bind to 127.0.0.1/::1 or unix socket." || \
      echo "建议 Redis 仅监听本地回环或 unix socket，避免公网暴露。")
  else
    status="PASS"
    suggestion=""
  fi

  echo "${status}|listen ${evidence}|${suggestion}"
}

baseline_cache__redis_ping() {
  # Attempt redis-cli PING using provided host/port/socket/password.
  local host port socket password lang output exit_code suggestion status
  local -a target=()
  host="$1"
  port="$2"
  socket="$3"
  password="$4"
  lang="$5"

  if ! command -v redis-cli >/dev/null 2>&1; then
    suggestion=$([ "$lang" = "en" ] && echo "redis-cli not found; install client to verify connectivity." || \
      echo "未找到 redis-cli，可安装客户端以验证连通性。")
    echo "WARN|redis-cli missing|${suggestion}"
    return
  fi

  if [ -n "$socket" ]; then
    target=("-s" "$socket")
  else
    target=("-h" "${host:-127.0.0.1}" "-p" "${port:-6379}")
  fi

  if [ -n "$password" ]; then
    output="$(redis-cli "${target[@]}" -a "$password" PING 2>&1 || true)"
  else
    output="$(redis-cli "${target[@]}" PING 2>&1 || true)"
  fi
  exit_code=$?

  if [ $exit_code -eq 0 ] && echo "$output" | grep -qi 'PONG'; then
    status="PASS"
    suggestion=""
    echo "${status}|PING ok"
    return
  fi

  suggestion=$([ "$lang" = "en" ] && echo "Check Redis auth/binding and try: redis-cli ${socket:+-s "$socket"}${host:+ -h $host -p ${port:-6379}} PING" || \
    echo "检查 Redis 认证/绑定，可手动执行：redis-cli ${socket:+-s "$socket"}${host:+ -h $host -p ${port:-6379}} PING")
  echo "FAIL|${output:-ping failed}|${suggestion}"
}

baseline_cache__detect_wp_path() {
  local provided detected
  provided="$1"

  if [ -n "$provided" ] && [ -d "$provided" ]; then
    echo "$provided"
    return
  fi

  if declare -F baseline_wp__auto_detect_path >/dev/null 2>&1; then
    detected="$(baseline_wp__auto_detect_path)"
    if [ -n "$detected" ]; then
      echo "$detected"
      return
    fi
  fi

  for candidate in /var/www/html /usr/local/lsws/Example/html; do
    if [ -f "$candidate/wp-config.php" ]; then
      echo "$candidate"
      return
    fi
  done
}

baseline_cache__parse_wp_config() {
  local wp_root wp_config defines object_cache dropin hint
  wp_root="$1"
  defines=""
  dropin=""
  hint=""

  if [ -z "$wp_root" ] || [ ! -f "$wp_root/wp-config.php" ]; then
    echo ""
    return
  fi

  wp_config="$wp_root/wp-config.php"
  defines="$(grep -E "define\s*\(" "$wp_config" 2>/dev/null | grep -Ei 'WP_CACHE|WP_REDIS_' || true)"
  dropin="${wp_root}/wp-content/object-cache.php"

  if [ -f "$dropin" ]; then
    hint="object-cache.php present"
  fi

  echo "${defines//$'\n'/; }${hint:+; ${hint}}"
}

baseline_cache__extract_wp_redis_config() {
  local wp_root wp_config host port socket
  wp_root="$1"
  wp_config="$wp_root/wp-config.php"

  if [ ! -f "$wp_config" ]; then
    echo ""; return
  fi

  host="$(grep -E "WP_REDIS_HOST" "$wp_config" 2>/dev/null | sed -E "s/.*'WP_REDIS_HOST'[^']*'([^']*)'.*/\\1/" | head -n1)"
  port="$(grep -E "WP_REDIS_PORT" "$wp_config" 2>/dev/null | sed -E "s/.*'WP_REDIS_PORT'[^0-9]*([0-9]+).*/\\1/" | head -n1)"
  socket="$(grep -E "WP_REDIS_PATH|WP_REDIS_SOCKET" "$wp_config" 2>/dev/null | sed -E "s/.*'(WP_REDIS_PATH|WP_REDIS_SOCKET)'[^']*'([^']*)'.*/\\2/" | head -n1)"

  echo "${host}|${port}|${socket}"
}

baseline_cache_run() {
  # Usage: baseline_cache_run "<wp_root_optional>" "<lang_optional>" "<redis_password_optional>"
  local wp_root lang redis_pass service_check listen_check ping_check php_bin opcache_info wp_defines redis_config
  local redis_host redis_port redis_socket redis_active redis_listener_status ping_status
  local service_evidence service_suggestion listen_evidence listen_suggestion ping_evidence ping_suggestion

  wp_root="$1"
  lang="${2:-zh}"
  redis_pass="${3:-}"

  if [[ "${lang,,}" == en* ]]; then
    lang="en"
  else
    lang="zh"
  fi

  wp_root="$(baseline_cache__detect_wp_path "$wp_root")"

  # Redis service status
  service_check="$(baseline_cache__check_redis_service "$lang")"
  redis_active="${service_check%%|*}"
  service_evidence="${service_check#*|}"
  service_suggestion="${service_evidence#*|}"
  if [ "$service_evidence" = "$service_suggestion" ]; then
    service_suggestion=""
  else
    service_evidence="${service_evidence%%|*}"
  fi
  if [ -z "$service_suggestion" ]; then
    service_suggestion=$([ "$lang" = "en" ] && echo "systemctl status redis-server --no-pager" || echo "systemctl status redis-server --no-pager")
  fi
  if [ "${redis_active:-WARN}" = "PASS" ]; then
    service_suggestion=""
  fi
  baseline_add_result "CACHE/REDIS" "REDIS_SERVICE" "${redis_active:-WARN}" "redis_service" "$service_evidence" \
    "$service_suggestion"

  # Listener check
  listen_check="$(baseline_cache__check_redis_listen "$lang")"
  redis_listener_status="${listen_check%%|*}"
  listen_evidence="${listen_check#*|}"
  listen_suggestion="${listen_evidence#*|}"
  if [ "$listen_evidence" = "$listen_suggestion" ]; then
    listen_suggestion=""
  else
    listen_evidence="${listen_evidence%%|*}"
  fi
  if [ -z "$listen_suggestion" ]; then
    listen_suggestion=$([ "$lang" = "en" ] && echo "ss -lntp | grep ':6379'" || echo "ss -lntp | grep ':6379'")
  fi
  if [ "${redis_listener_status:-WARN}" = "PASS" ]; then
    listen_suggestion=""
  fi
  baseline_add_result "CACHE/REDIS" "REDIS_LISTEN" "${redis_listener_status:-WARN}" "redis_listen" "$listen_evidence" \
    "$listen_suggestion"

  # WP Redis config
  redis_config=""
  redis_host=""; redis_port=""; redis_socket=""
  if [ -n "$wp_root" ]; then
    redis_config="$(baseline_cache__extract_wp_redis_config "$wp_root")"
    IFS='|' read -r redis_host redis_port redis_socket <<< "$redis_config"
  fi

  # Redis ping
  ping_check="$(baseline_cache__redis_ping "$redis_host" "$redis_port" "$redis_socket" "$redis_pass" "$lang")"
  ping_status="${ping_check%%|*}"
  ping_evidence="${ping_check#*|}"
  ping_suggestion="${ping_evidence#*|}"
  if [ "$ping_evidence" = "$ping_suggestion" ]; then
    ping_suggestion=""
  else
    ping_evidence="${ping_evidence%%|*}"
  fi
  baseline_add_result "CACHE/REDIS" "REDIS_PING" "${ping_status:-WARN}" "redis_ping" "$ping_evidence" "${ping_suggestion}"

  # PHP OPcache status
  php_bin="$(baseline_cache__detect_php_bin)"
  if [ -z "$php_bin" ]; then
    baseline_add_result "CACHE/REDIS" "OPCACHE_STATUS" "WARN" "opcache_enabled" \
      "php/lsphp not found" \
      "$([ "$lang" = "en" ] && echo "Install php/lsphp and ensure opcache is enabled (php -i | grep -i opcache)." || \
        echo "未找到 php/lsphp，请安装后通过 php -i | grep -i opcache 确认 OPCache 配置。")"
  else
    opcache_info="$("$php_bin" -i 2>/dev/null | grep -iE 'opcache.enable|opcache.enable_cli|opcache.memory_consumption|opcache.jit' || true)"
    if echo "$opcache_info" | grep -iq '^opcache.enable => On'; then
      baseline_add_result "CACHE/REDIS" "OPCACHE_STATUS" "PASS" "opcache_enabled" "$(echo "$opcache_info" | tr '\n' '; ')" ""
    else
      baseline_add_result "CACHE/REDIS" "OPCACHE_STATUS" "WARN" "opcache_enabled" \
        "$(echo "$opcache_info" | tr '\n' '; ' | sed 's/; $//')" \
        "$([ "$lang" = "en" ] && echo "Enable opcache for php/lsphp and allocate enough memory (php -i | grep -i opcache)." || \
          echo "建议启用 OPCache 并合理分配内存，可通过 php -i | grep -i opcache 查看配置。")"
    fi
  fi

  # WP cache hints
  wp_defines=""
  if [ -n "$wp_root" ] && [ -f "$wp_root/wp-config.php" ]; then
    wp_defines="$(baseline_cache__parse_wp_config "$wp_root")"
    baseline_add_result "CACHE/REDIS" "WP_CACHE_HINT" "PASS" "wp_cache_define object_cache_dropin" \
      "${wp_defines:-wp-config detected}" \
      "$([ "$lang" = "en" ] && echo "Review wp-config.php cache settings; ensure drop-in matches redis availability." || \
        echo "检查 wp-config.php 缓存相关设置，确认 object-cache drop-in 与 Redis 可用性一致。")"
  else
    baseline_add_result "CACHE/REDIS" "WP_CACHE_HINT" "WARN" "wp_cache_define" \
      "wp-config.php not found" \
      "$([ "$lang" = "en" ] && echo "Provide WordPress root for cache hints or ensure wp-config.php accessible." || \
        echo "未找到 wp-config.php，可提供 WordPress 路径以获取缓存配置线索。")"
  fi

  # Contradiction detection
  if { [ -n "$redis_host" ] || [ -n "$redis_socket" ]; } && [ "${ping_status}" = "FAIL" ]; then
    baseline_add_result "CACHE/REDIS" "WP_REDIS_UNREACHABLE" "FAIL" "redis_config_mismatch" \
      "redis configured (host=${redis_host:-N/A} socket=${redis_socket:-N/A}) but ping failed" \
      "$([ "$lang" = "en" ] && echo "Validate Redis credentials/binding; ensure service reachable from PHP." || \
        echo "检查 Redis 认证/绑定，确保 PHP 可访问对应实例。")"
  fi
}

