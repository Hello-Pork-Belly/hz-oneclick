#!/usr/bin/env bash

# Baseline diagnostics for database connectivity and privileges.

baseline_db_check_tcp() {
  # Usage: baseline_db_check_tcp <host> <port>
  local host port output exit_code
  host="$1"
  port="$2"

  output="$(timeout 6 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>&1)"
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "OK"
    return 0
  fi

  if [ "$exit_code" -eq 124 ]; then
    echo "TIMEOUT"
    return 0
  fi

  if echo "$output" | grep -qi "refused"; then
    echo "REFUSED"
  else
    echo "FAIL"
  fi
}

baseline_db_run() {
  # Usage: baseline_db_run <host> <port> <db_name> <user> <password> <lang>
  local host port db_name user password lang group tcp_check tcp_state
  local evidence_tcp suggestions_tcp keyword_tcp
  local auth_state auth_keyword evidence_auth suggestions_auth
  local select_state select_keyword evidence_select suggestions_select
  local mysql_exists auth_output auth_exit select_output select_exit
  local select_cmd select_hint

  host="$1"
  port="$2"
  db_name="$3"
  user="$4"
  password="$5"
  lang="${6:-zh}"
  group="DB"

  tcp_check="$(baseline_db_check_tcp "$host" "$port")"
  case "$tcp_check" in
    OK)
      tcp_state="PASS"
      keyword_tcp="DB_TCP_CONNECT"
      suggestions_tcp=""
      ;;
    TIMEOUT|REFUSED|FAIL)
      tcp_state="FAIL"
      keyword_tcp="DB_PORT_UNREACHABLE"
      if [ "$lang" = "en" ]; then
        suggestions_tcp="Verify firewall/proxy rules and ensure the database listens on ${port}."
      else
        suggestions_tcp="检查防火墙/代理策略是否放行 ${port}，确认数据库正在监听该端口。"
      fi
      ;;
    *)
      tcp_state="WARN"
      keyword_tcp="DB_TCP_CONNECT"
      ;;
  esac

  evidence_tcp="DB_HOST: ${host}\nDB_PORT: ${port}\nDB_TCP_CONNECT: ${tcp_check}"
  baseline_add_result "$group" "DB_TCP_CONNECT" "$tcp_state" "$keyword_tcp" "$evidence_tcp" "$suggestions_tcp"

  if [ "$tcp_state" != "PASS" ]; then
    if [ "$lang" = "en" ]; then
      evidence_auth="DB_AUTH: SKIPPED (TCP failed)"
      suggestions_auth="$suggestions_tcp"
      evidence_select="DB_CAN_SELECT_1: SKIPPED (TCP failed)"
      suggestions_select="$suggestions_tcp"
    else
      evidence_auth="DB_AUTH: 已跳过（TCP 不通）"
      suggestions_auth="$suggestions_tcp"
      evidence_select="DB_CAN_SELECT_1: 已跳过（TCP 不通）"
      suggestions_select="$suggestions_tcp"
    fi

    baseline_add_result "$group" "DB_AUTH" "FAIL" "DB_PORT_UNREACHABLE" "$evidence_auth" "$suggestions_auth"
    baseline_add_result "$group" "DB_CAN_SELECT_1" "FAIL" "DB_PORT_UNREACHABLE" "${evidence_select}" "$suggestions_select"
    return
  fi

  if ! command -v mysql >/dev/null 2>&1; then
    mysql_exists=0
  else
    mysql_exists=1
  fi

  if [ "$mysql_exists" -ne 1 ]; then
    if [ "$lang" = "en" ]; then
      evidence_auth="mysql client not found; cannot verify credentials."
      evidence_select="mysql client not found; cannot run SELECT 1."
      suggestions_auth="Install mariadb-client or mysql-client, then rerun diagnostics."
    else
      evidence_auth="未检测到 mysql 客户端，无法验证账号。"
      evidence_select="未检测到 mysql 客户端，无法执行 SELECT 1。"
      suggestions_auth="请安装 mariadb-client 或 mysql-client 后重试诊断。"
    fi
    suggestions_select="$suggestions_auth"

    baseline_add_result "$group" "DB_AUTH" "WARN" "DB_CLIENT_MISSING" "$evidence_auth" "$suggestions_auth"
    baseline_add_result "$group" "DB_CAN_SELECT_1" "WARN" "DB_CLIENT_MISSING" "$evidence_select" "$suggestions_select"
    return
  fi

  auth_output="$(MYSQL_PWD="$password" mysql -h "$host" -P "$port" -u "$user" -N -s -e "SELECT 1;" 2>&1)"
  auth_exit=$?

  if [ "$auth_exit" -eq 0 ]; then
    auth_state="PASS"
    auth_keyword="DB_AUTH"
    evidence_auth="DB_AUTH: OK"
    suggestions_auth=""
  else
    auth_state="FAIL"
    auth_keyword="DB_AUTH_FAILED"
    if echo "$auth_output" | grep -qi "access denied"; then
      if [ "$lang" = "en" ]; then
        evidence_auth="DB_AUTH: ACCESS_DENIED"
        suggestions_auth="Check DB user/password and allowed source IP/host."
      else
        evidence_auth="DB_AUTH: 认证被拒绝"
        suggestions_auth="请检查数据库用户名/密码与允许连接的来源主机。"
      fi
    else
      if [ "$lang" = "en" ]; then
        evidence_auth="DB_AUTH: FAIL"
        suggestions_auth="Connection succeeded but authentication failed; review credentials and database settings."
      else
        evidence_auth="DB_AUTH: 失败"
        suggestions_auth="已连通但认证失败，请检查账号密码与数据库配置。"
      fi
    fi
  fi

  baseline_add_result "$group" "DB_AUTH" "$auth_state" "$auth_keyword" "$evidence_auth" "$suggestions_auth"

  if [ "$auth_state" != "PASS" ]; then
    if [ "$lang" = "en" ]; then
      evidence_select="DB_CAN_SELECT_1: SKIPPED (auth failed)"
      suggestions_select="$suggestions_auth"
    else
      evidence_select="DB_CAN_SELECT_1: 已跳过（认证失败）"
      suggestions_select="$suggestions_auth"
    fi
    baseline_add_result "$group" "DB_CAN_SELECT_1" "FAIL" "$auth_keyword" "$evidence_select" "$suggestions_select"
    return
  fi

  if [ -n "$db_name" ]; then
    select_cmd="USE \`$db_name\`; SELECT 1;"
  else
    select_cmd="SELECT 1;"
  fi

  select_output="$(MYSQL_PWD="$password" mysql -h "$host" -P "$port" -u "$user" -N -s -e "$select_cmd" 2>&1)"
  select_exit=$?

  if [ "$select_exit" -eq 0 ]; then
    select_state="PASS"
    select_keyword="DB_CAN_SELECT_1"
    select_hint="OK"
    suggestions_select=""
  else
    select_state="FAIL"
    select_hint="FAIL"
    if echo "$select_output" | grep -qiE "denied|privilege|permission"; then
      select_keyword="DB_PRIVILEGE_INSUFFICIENT"
      select_state="WARN"
      if [ "$lang" = "en" ]; then
        suggestions_select="Grant SELECT/USAGE on the target database and ensure it exists."
      else
        suggestions_select="请为目标数据库授予 SELECT/USAGE 权限并确认数据库已创建。"
      fi
      if [ "$lang" = "en" ]; then
        select_hint="INSUFFICIENT_PRIVILEGE"
      else
        select_hint="权限不足"
      fi
    elif echo "$select_output" | grep -qi "unknown database"; then
      select_keyword="DB_PRIVILEGE_INSUFFICIENT"
      if [ "$lang" = "en" ]; then
        suggestions_select="Database not found; create it or update DB_NAME before installing WordPress."
        select_hint="UNKNOWN_DATABASE"
      else
        suggestions_select="未找到指定数据库，请创建数据库或更新 DB_NAME 后再安装 WordPress。"
        select_hint="数据库不存在"
      fi
    else
      select_keyword="DB_CAN_SELECT_1"
      if [ "$lang" = "en" ]; then
        suggestions_select="Query failed; confirm database status and network stability."
      else
        suggestions_select="查询失败，请检查数据库状态与网络稳定性。"
      fi
    fi
  fi

  evidence_select="DB_NAME: ${db_name:-N/A}\nDB_CAN_SELECT_1: ${select_hint}"
  baseline_add_result "$group" "DB_CAN_SELECT_1" "$select_state" "$select_keyword" "$evidence_select" "$suggestions_select"
}
