#!/usr/bin/env bash

# Baseline diagnostics for WordPress/App runtime.
# Only defines functions; no logic is executed on source.

baseline_wp__is_wp_root() {
  local path markers found
  path="$1"
  markers=()
  found=0

  if [ -d "$path" ]; then
    if [ -f "$path/wp-config.php" ]; then
      markers+=("wp-config.php")
      found=$((found + 1))
    fi
    if [ -d "$path/wp-includes" ]; then
      markers+=("wp-includes")
      found=$((found + 1))
    fi
    if [ -d "$path/wp-admin" ]; then
      markers+=("wp-admin")
      found=$((found + 1))
    fi
  fi

  echo "$found:${markers[*]}"
}

baseline_wp__auto_detect_path() {
  local candidates=('/var/www' '/usr/local/lsws' '/usr/local/lsws/Example/html')
  local best_path="" best_score=0 candidate path score marker_info

  for base in "${candidates[@]}"; do
    if [ -d "$base" ]; then
      if [ "$base" = "/usr/local/lsws" ]; then
        while IFS= read -r -d '' path; do
          candidate="${path%/}/html"
          if [ -d "$candidate" ]; then
            marker_info="$(baseline_wp__is_wp_root "$candidate")"
            score="${marker_info%%:*}"
            if [ "$score" -gt "$best_score" ]; then
              best_score="$score"
              best_path="$candidate"
            fi
          fi
        done < <(find "$base" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
      elif [ "$base" = "/var/www" ]; then
        while IFS= read -r -d '' path; do
          marker_info="$(baseline_wp__is_wp_root "$path")"
          score="${marker_info%%:*}"
          if [ "$score" -gt "$best_score" ]; then
            best_score="$score"
            best_path="$path"
          fi
        done < <(find "$base" -maxdepth 2 -mindepth 1 -type d -print0 2>/dev/null)
      else
        marker_info="$(baseline_wp__is_wp_root "$base")"
        score="${marker_info%%:*}"
        if [ "$score" -gt "$best_score" ]; then
          best_score="$score"
          best_path="$base"
        fi
      fi
    fi
  done

  if [ -n "$best_path" ]; then
    printf "%s" "$best_path"
  fi
}

baseline_wp__prompt_path() {
  local lang input
  lang="$1"

  if [ ! -t 0 ]; then
    echo ""
    return
  fi

  if [ "$lang" = "en" ]; then
    read -rp "Enter WordPress path (optional, e.g., /var/www/html): " input
  else
    read -rp "请输入 WordPress 路径（可选，例如 /var/www/html）: " input
  fi
  input="${input//[[:space:]]/}"
  echo "$input"
}

baseline_wp__check_permissions() {
  local file mode owner others readable writable status keyword suggestion lang
  file="$1"
  lang="$2"
  status="PASS"
  keyword="WP_CONFIG_PERM"
  suggestion=""

  mode="$(stat -c '%a %U:%G' "$file" 2>/dev/null || echo '')"
  owner="${mode#* }"
  mode="${mode%% *}"
  others="${mode: -1}"

  readable=0
  writable=0
  if echo "$others" | grep -Eq '^[0-9]+$'; then
    if [ "$others" -ge 4 ]; then
      readable=1
    fi
    if [ "$others" -ge 2 ]; then
      writable=1
    fi
  fi

  if [ "$writable" -eq 1 ]; then
    status="FAIL"
    keyword="permission_risk"
    if [ "$lang" = "en" ]; then
      suggestion="Restrict wp-config.php to 640/600 and ensure ownership (e.g., chown www-data:www-data)."
    else
      suggestion="将 wp-config.php 权限收紧至 640/600，并确认属主（例如 chown www-data:www-data）。"
    fi
  elif [ "$readable" -eq 1 ]; then
    status="WARN"
    keyword="permission_risk"
    if [ "$lang" = "en" ]; then
      suggestion="Reduce world-readable bits of wp-config.php (e.g., chmod 640) to avoid exposure."
    else
      suggestion="避免 wp-config.php 对全局可读，可使用 chmod 640 等方式收紧权限。"
    fi
  fi

  printf '%s;%s;%s;%s' "$status" "$keyword" "mode=${mode:-N/A} owner=${owner:-N/A}" "$suggestion"
}

baseline_wp__summarize_headers() {
  local header_file headers
  header_file="$1"
  headers="$(grep -iE '^(server|content-type|location|cache-control|expires|x-cache|cf-cache-status):' "$header_file" | head -n 5 | tr -d '\r')"
  if [ -z "$headers" ]; then
    echo "(no headers)"
  else
    echo "$headers"
  fi
}

baseline_wp__curl_probe() {
  local url label lang header_file result http_code exit_code final_url headers status keyword evidence suggestion redirect_hint
  url="$1"
  label="$2"
  lang="$3"
  header_file="$(mktemp 2>/dev/null || printf '/tmp/wp_headers_%s' "$label")"
  redirect_hint=""

  result="$(curl -L -s -D "$header_file" -o /dev/null -w '%{http_code} %{url_effective}' --max-time 12 --connect-timeout 8 "$url" 2>/dev/null)"
  exit_code=$?
  http_code="${result%% *}"
  final_url="${result#* }"

  if [ "$exit_code" -eq 28 ]; then
    status="FAIL"
    keyword="${label}_timeout"
    suggestion=$([ "$lang" = "en" ] && echo "Endpoint timeout; check upstream availability and security devices." || echo "请求超时，请检查上游服务状态及反代/CDN/WAF 等安全策略。")
  elif [ "$exit_code" -eq 47 ]; then
    status="WARN"
    keyword="redirect_loop"
    suggestion=$([ "$lang" = "en" ] && echo "Possible redirect loop; review siteurl/home and reverse proxy rules." || echo "疑似重定向循环，请检查 siteurl/home 配置及反代规则。")
  elif [ "$exit_code" -ne 0 ]; then
    status="WARN"
    keyword="${label}_error"
    suggestion=$([ "$lang" = "en" ] && echo "Curl error; verify DNS/SSL reachability." || echo "Curl 请求异常，请检查 DNS/SSL 连通性。")
  else
    if echo "$http_code" | grep -Eq '^[0-9]{3}$'; then
      if [ "${http_code}" -ge 500 ]; then
        status="FAIL"
        keyword="${label}_5xx"
      elif [ "${http_code}" -ge 400 ]; then
        status="WARN"
        if [ "$http_code" = "429" ] || [ "$http_code" = "403" ]; then
          suggestion=$([ "$lang" = "en" ] && echo "Blocked or rate-limited by reverse proxy/CDN/WAF; review security rules." || echo "可能被反向代理/CDN/WAF/安全策略拦截或限流，请检查对应规则。")
        fi
        keyword="${label}_4xx"
      elif [ "${http_code}" -ge 300 ]; then
        status="PASS"
        keyword="${label}_redirect"
      else
        status="PASS"
        keyword="${label}_ok"
      fi
    else
      status="WARN"
      keyword="${label}_error"
      suggestion=$([ "$lang" = "en" ] && echo "Unexpected response; verify endpoint availability." || echo "返回异常，请检查站点可用性。")
    fi
  fi

  if echo "$url" | grep -q '^http://' && echo "$final_url" | grep -q '^https://'; then
    redirect_hint="http->https"
  fi

  headers="$(baseline_wp__summarize_headers "$header_file")"
  rm -f "$header_file"

  evidence="code=${http_code:-NA} exit=${exit_code} final=${final_url:-NA}"
  if [ -n "$redirect_hint" ]; then
    evidence="$evidence (${redirect_hint})"
  fi
  evidence="$evidence\n${headers}"

  printf '%s;%s;%s;%s' "$status" "$keyword" "$evidence" "$suggestion"
}

baseline_wp_run() {
  # Usage: baseline_wp_run "<domain>" "<wp_path_optional>" "<lang>"
  local domain wp_path lang group structure_info structure_score markers evidence suggestions status keyword config_file config_status config_keyword
  local perm_info perm_status perm_keyword perm_evidence perm_suggestion backup_found wpcli_cmd cli_status cli_keyword cli_evidence cli_suggestion
  local siteurl homeurl info status_line suggestion_line
  local curl_status curl_keyword curl_evidence curl_suggestion

  domain="$1"
  wp_path="$2"
  lang="${3:-zh}"
  group="WP/APP"

  if [ -z "$domain" ]; then
    return
  fi

  if [[ "${lang,,}" == en* ]]; then
    lang="en"
  else
    lang="zh"
  fi

  if [ -z "$wp_path" ]; then
    wp_path="$(baseline_wp__auto_detect_path)"
  fi

  if [ -z "$wp_path" ] && [ -z "${BASELINE_WP_NO_PROMPT:-}" ]; then
    wp_path="$(baseline_wp__prompt_path "$lang")"
  fi

  if [ -z "$wp_path" ]; then
    baseline_add_result "$group" "WP_PATH" "WARN" "wp_path_missing" \
      "$([ "$lang" = "en" ] && echo "WordPress path not provided; local checks skipped." || echo "未提供 WordPress 路径，本地检查跳过。")" \
      "$([ "$lang" = "en" ] && echo "Provide --path for wp-cli or rerun with WordPress root to enable local diagnostics." || echo "重新提供 WordPress 根目录路径，可开启本地检查。")"
  elif [ ! -d "$wp_path" ]; then
    baseline_add_result "$group" "WP_PATH" "FAIL" "wp_path_not_found" \
      "path=${wp_path}" \
      "$([ "$lang" = "en" ] && echo "Confirm the WordPress root exists and rerun." || echo "确认 WordPress 根目录存在后重试。")"
  else
    structure_info="$(baseline_wp__is_wp_root "$wp_path")"
    structure_score="${structure_info%%:*}"
    markers="${structure_info#*:}"

    if [ "$structure_score" -ge 2 ]; then
      status="PASS"
      keyword="wp_root_ok"
    else
      status="WARN"
      keyword="wp_root_suspect"
    fi

    evidence="path=${wp_path}\nmarkers=${markers:-none}"
    suggestions=""
    if [ "$status" = "WARN" ]; then
      suggestions=$([ "$lang" = "en" ] && echo "Path missing WordPress signatures; verify correct root." || echo "路径缺少典型 WordPress 文件/目录，请确认是否为站点根目录。")
    fi

    baseline_add_result "$group" "WP_PATH" "$status" "$keyword" "$evidence" "$suggestions"

    config_file="${wp_path%/}/wp-config.php"
    if [ -f "$config_file" ]; then
      config_status="PASS"
      config_keyword="wp_config_ok"
      evidence="wp-config.php present"
      suggestions=""

      for key in DB_NAME DB_USER DB_PASSWORD DB_HOST; do
        if ! grep -Eq "define\s*\(\s*['\"]${key}['\"]" "$config_file" 2>/dev/null; then
          config_status="WARN"
          config_keyword="wp_config_incomplete"
        fi
      done

      if [ "$config_status" != "PASS" ]; then
        evidence="wp-config.php missing DB defines"
        suggestions=$([ "$lang" = "en" ] && echo "Fill DB_NAME/DB_USER/DB_PASSWORD/DB_HOST in wp-config.php." || echo "请在 wp-config.php 中补齐 DB_NAME/DB_USER/DB_PASSWORD/DB_HOST。")
      fi

      baseline_add_result "$group" "WP_CONFIG" "$config_status" "$config_keyword" "$evidence" "$suggestions"

      perm_info="$(baseline_wp__check_permissions "$config_file" "$lang")"
      perm_status="${perm_info%%;*}"
      perm_info="${perm_info#*;}"; perm_keyword="${perm_info%%;*}"; perm_info="${perm_info#*;}"
      perm_evidence="${perm_info%%;*}"; perm_info="${perm_info#*;}"; perm_suggestion="$perm_info"

      baseline_add_result "$group" "WP_CONFIG_PERM" "$perm_status" "$perm_keyword" "$perm_evidence" "$perm_suggestion"

      backup_found=""
      for suffix in .bak .old .backup .save ~; do
        if [ -f "${config_file}${suffix}" ]; then
          backup_found+="${config_file}${suffix} "
        fi
      done
      if [ -n "$backup_found" ]; then
        baseline_add_result "$group" "WP_CONFIG_BACKUP" "WARN" "wp_config_backup" \
          "backup files: $(echo "$backup_found" | xargs)" \
          "$([ "$lang" = "en" ] && echo "Remove/secure wp-config backup copies to avoid leakage." || echo "清理或妥善保护 wp-config 备份文件，避免泄露。")"
      else
        baseline_add_result "$group" "WP_CONFIG_BACKUP" "PASS" "wp_config_backup" \
          "no backup copies detected" ""
      fi
    else
      baseline_add_result "$group" "WP_CONFIG" "FAIL" "wp_config_missing" \
        "wp-config.php not found" \
        "$([ "$lang" = "en" ] && echo "Create wp-config.php or verify path is correct." || echo "未找到 wp-config.php，请创建或确认路径是否正确。")"
    fi
  fi

  if command -v wp >/dev/null 2>&1 && [ -n "$wp_path" ] && [ -d "$wp_path" ]; then
    wpcli_cmd=(wp --path="$wp_path" --allow-root)

    if "${wpcli_cmd[@]}" core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
      cli_status="PASS"
      cli_keyword="wp_installed"
      cli_evidence="wp core is-installed: yes"
      cli_suggestion=""
    else
      cli_status="FAIL"
      cli_keyword="wp_not_installed"
      cli_evidence="wp core is-installed: no"
      cli_suggestion=$([ "$lang" = "en" ] && echo "Run wp core install/configure database before diagnostics." || echo "请先完成 wp core install/db 配置后再检查。")
    fi
    baseline_add_result "$group" "WPCLI_CORE" "$cli_status" "$cli_keyword" "$cli_evidence" "$cli_suggestion"

    siteurl="$("${wpcli_cmd[@]}" option get siteurl 2>/dev/null | head -n1)"
    if [ -z "$siteurl" ]; then
      status_line="FAIL"; keyword="siteurl_empty"; suggestion_line=$([ "$lang" = "en" ] && echo "Configure siteurl via wp option update siteurl <url>." || echo "使用 wp option update siteurl <url> 设置站点地址。")
      evidence="siteurl: EMPTY"
    elif echo "$siteurl" | grep -Eq '^https?://[^[:space:]]+$'; then
      status_line="PASS"; keyword="siteurl_set"; suggestion_line=""; evidence="siteurl: SET"
    else
      status_line="WARN"; keyword="siteurl_invalid"; suggestion_line=$([ "$lang" = "en" ] && echo "Siteurl format looks invalid; verify protocol/domain." || echo "siteurl 格式异常，请检查协议/域名是否正确。")
      evidence="siteurl: INVALID"
    fi
    baseline_add_result "$group" "WPCLI_SITEURL" "$status_line" "$keyword" "$evidence" "$suggestion_line"

    homeurl="$("${wpcli_cmd[@]}" option get home 2>/dev/null | head -n1)"
    if [ -z "$homeurl" ]; then
      status_line="FAIL"; keyword="home_empty"; suggestion_line=$([ "$lang" = "en" ] && echo "Configure home via wp option update home <url>." || echo "使用 wp option update home <url> 设置首页地址。")
      evidence="home: EMPTY"
    elif echo "$homeurl" | grep -Eq '^https?://[^[:space:]]+$'; then
      status_line="PASS"; keyword="home_set"; suggestion_line=""; evidence="home: SET"
    else
      status_line="WARN"; keyword="home_invalid"; suggestion_line=$([ "$lang" = "en" ] && echo "Home option looks malformed; align with siteurl." || echo "home 配置格式异常，请与 siteurl 对齐。")
      evidence="home: INVALID"
    fi
    baseline_add_result "$group" "WPCLI_HOME" "$status_line" "$keyword" "$evidence" "$suggestion_line"
  else
    baseline_add_result "$group" "WPCLI" "WARN" "wpcli_missing" \
      "$([ command -v wp >/dev/null 2>&1 ] && echo "wp-cli skipped (path missing)" || echo "wp-cli not found")" \
      "$([ "$lang" = "en" ] && echo "Install wp-cli and rerun with --path to enable WordPress runtime checks." || echo "安装 wp-cli 并提供 --path，可启用 WordPress 运行态检查。")"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    baseline_add_result "$group" "HTTP_CLIENT" "WARN" "curl_missing" \
      "curl not available" \
      "$([ "$lang" = "en" ] && echo "Install curl to run HTTP diagnostics." || echo "安装 curl 以执行 HTTP 诊断。")"
    baseline_add_result "$group" "HTTP_ROOT" "WARN" "home_unchecked" "curl missing" ""
    baseline_add_result "$group" "HTTP_LOGIN" "WARN" "login_unchecked" "curl missing" ""
    baseline_add_result "$group" "HTTP_WPJSON" "WARN" "wpjson_unchecked" "curl missing" ""
    return
  fi

  local IFS=';'
  read -r curl_status curl_keyword curl_evidence curl_suggestion <<<"$(baseline_wp__curl_probe "https://${domain}/" "home" "$lang")"
  baseline_add_result "$group" "HTTP_ROOT" "$curl_status" "$curl_keyword" "$curl_evidence" "$curl_suggestion"

  read -r curl_status curl_keyword curl_evidence curl_suggestion <<<"$(baseline_wp__curl_probe "https://${domain}/wp-login.php" "login" "$lang")"
  baseline_add_result "$group" "HTTP_LOGIN" "$curl_status" "$curl_keyword" "$curl_evidence" "$curl_suggestion"

  read -r curl_status curl_keyword curl_evidence curl_suggestion <<<"$(baseline_wp__curl_probe "https://${domain}/wp-json/" "wpjson" "$lang")"
  baseline_add_result "$group" "HTTP_WPJSON" "$curl_status" "$curl_keyword" "$curl_evidence" "$curl_suggestion"
}
