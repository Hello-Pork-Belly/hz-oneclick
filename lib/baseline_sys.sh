#!/usr/bin/env bash

# Baseline diagnostics for System/Resource (CPU/RAM/Disk/Swap/Logs).
# Defines functions only; no logic is executed on load.

baseline_sys__parse_size_bytes() {
  # Usage: baseline_sys__parse_size_bytes "<size string>"
  # Supports strings like "123M", "1.5G", "2048 K", "1024B"; returns bytes.
  local size unit value
  size="${1:-}"
  value="${size%%[kKmMgGtTbB ]*}"
  unit="${size#${value}}"
  unit="${unit//[[:space:]]/}"
  if ! echo "$value" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
    echo "0"
    return
  fi
  case "${unit^^}" in
    B|BYTE|BYTES|"" )
      awk -v v="$value" 'BEGIN {printf "%.0f", v}'
      ;;
    K|KB|KIB)
      awk -v v="$value" 'BEGIN {printf "%.0f", v*1024}'
      ;;
    M|MB|MIB)
      awk -v v="$value" 'BEGIN {printf "%.0f", v*1024*1024}'
      ;;
    G|GB|GIB)
      awk -v v="$value" 'BEGIN {printf "%.0f", v*1024*1024*1024}'
      ;;
    T|TB|TIB)
      awk -v v="$value" 'BEGIN {printf "%.0f", v*1024*1024*1024*1024}'
      ;;
    *)
      echo "0"
      ;;
  esac
}

baseline_sys__read_load() {
  local uptime_out
  uptime_out="$(uptime 2>/dev/null || true)"
  if echo "$uptime_out" | grep -Eq 'load average'; then
    echo "$uptime_out" | awk -F'load average: ' '{print $2}' | awk -F',' '{printf "%s %s %s", $1, $2, $3}'
  else
    echo "0 0 0"
  fi
}

baseline_sys__read_meminfo() {
  # Outputs key=value pairs for MemTotal, MemAvailable, SwapTotal, SwapFree
  awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ {gsub(/kB/, "", $2); print $1"="$2}' /proc/meminfo 2>/dev/null || true
}

baseline_sys_run() {
  # Usage: baseline_sys_run <lang> OR baseline_sys_run <domain> <lang>
  local domain lang group cores load_values load1 load5 load15 load_per_core load_state
  local mem_kv memtotal_kb memavail_kb swaptotal_kb swapfree_kb swap_used_kb swap_used_pct swap_state swap_present
  local disk_info_root disk_used_pct_root disk_state_root inode_info_root inode_used_pct_root inode_state_root
  local os_release uname_out arch_out journal_usage journal_bytes journal_state journal_size_str
  local suggestions_load suggestions_swap suggestions_disk suggestions_inode suggestions_journal suggestions_docker suggestions_log
  local evidence_disk evidence_inode evidence_mem evidence_load evidence_os evidence_journal evidence_docker evidence_logs
  local logs_listing

  if [ "$#" -ge 2 ]; then
    domain="$1"
    lang="${2:-zh}"
  else
    domain=""
    lang="${1:-zh}"
  fi

  if [[ "${lang,,}" == en* ]]; then
    lang="en"
  else
    lang="zh"
  fi

  group="SYSTEM/RESOURCE"
  cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  if ! echo "$cores" | grep -Eq '^[0-9]+$'; then
    cores="1"
  fi

  os_release="$(
    if [ -r /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      echo "${PRETTY_NAME:-${NAME:-Unknown}}"
    fi
  )"
  uname_out="$(uname -a 2>/dev/null || true)"
  arch_out="$(arch 2>/dev/null || uname -m 2>/dev/null || true)"
  evidence_os=$(printf "OS: %s\nKernel: %s\nArch: %s" "${os_release:-N/A}" "${uname_out:-N/A}" "${arch_out:-N/A}")
  baseline_add_result "$group" "OS_KERNEL" "PASS" "" "$evidence_os" ""

  load_values="$(baseline_sys__read_load)"
  read -r load1 load5 load15 <<< "$load_values"
  load_per_core="$(awk -v l="${load1:-0}" -v c="$cores" 'BEGIN {if (c<=0) c=1; printf "%.2f", l/c}')"

  load_state="PASS"
  suggestions_load=""
  if awk -v v="$load_per_core" 'BEGIN{exit (v>=2.0)?0:1}'; then
    load_state="FAIL"
    if [ "$lang" = "en" ]; then
      suggestions_load="Investigate sustained load with: top/htop; check cron jobs or heavy processes causing timeouts/521."
    else
      suggestions_load="使用 top/htop 查看持续高负载进程；检查计划任务或异常进程，避免长时间高负载导致 521/超时。"
    fi
  elif awk -v v="$load_per_core" 'BEGIN{exit (v>=1.0)?0:1}'; then
    load_state="WARN"
    if [ "$lang" = "en" ]; then
      suggestions_load="Load per core >=1. Consider scaling CPU, optimizing apps, or reducing background tasks."
    else
      suggestions_load="每核负载 >=1，建议优化应用/减少后台任务，必要时扩容 CPU。"
    fi
  fi
  evidence_load=$(printf "Load1/5/15: %s %s %s\nCPU cores: %s\nLoad1 per core: %s\nKEY:CPU_CORES=%s\nKEY:LOAD_1=%s\nKEY:LOAD1_PER_CORE=%s" \
    "${load1:-N/A}" "${load5:-N/A}" "${load15:-N/A}" "$cores" "$load_per_core" "$cores" "${load1:-N/A}" "$load_per_core")
  baseline_add_result "$group" "LOAD" "$load_state" "KEY:LOAD1_PER_CORE=${load_per_core}" "$evidence_load" "$suggestions_load"

  while read -r mem_kv; do
    case "$mem_kv" in
      MemTotal=*) memtotal_kb="${mem_kv#MemTotal=}" ;;
      MemAvailable=*) memavail_kb="${mem_kv#MemAvailable=}" ;;
      SwapTotal=*) swaptotal_kb="${mem_kv#SwapTotal=}" ;;
      SwapFree=*) swapfree_kb="${mem_kv#SwapFree=}" ;;
    esac
  done < <(baseline_sys__read_meminfo)

  swap_present=0
  swap_used_pct=0
  if echo "${swaptotal_kb:-0}" | grep -Eq '^[0-9]+$' && [ "${swaptotal_kb:-0}" -gt 0 ]; then
    swap_present=1
    swap_used_kb=$(( swaptotal_kb - ${swapfree_kb:-0} ))
    swap_used_pct="$(awk -v u="$swap_used_kb" -v t="$swaptotal_kb" 'BEGIN {if (t<=0) {print 0} else {printf "%.1f", (u/t)*100}}')"
  fi

  swap_state="PASS"
  suggestions_swap=""
  if [ "$swap_present" -eq 0 ]; then
    if [ "${memtotal_kb:-0}" -le 2097152 ]; then
      swap_state="WARN"
    else
      swap_state="PASS"
    fi
    if [ "$lang" = "en" ]; then
      suggestions_swap="No swap detected. Consider provisioning swap (e.g., fallocate && mkswap && swapon) if memory pressure occurs."
    else
      suggestions_swap="未检测到 swap。若内存紧张，建议使用 fallocate/mkswap/swapon 手动创建并启用 swap。"
    fi
  elif awk -v p="$swap_used_pct" 'BEGIN{exit (p>=80)?0:1}'; then
    swap_state="WARN"
    if [ "$lang" = "en" ]; then
      suggestions_swap="High swap usage. Review memory-heavy processes and consider tuning application memory limits."
    else
      suggestions_swap="swap 使用率较高，建议排查内存占用大的进程，必要时调整应用内存限制。"
    fi
  fi

  evidence_mem=$(printf "MemTotal: %s kB\nMemAvailable: %s kB\nSwapTotal: %s kB\nSwapFree: %s kB\nSwapUsed%%: %s\nKEY:SWAP_PRESENT=%s\nKEY:SWAP_USED_PCT=%s" \
    "${memtotal_kb:-N/A}" "${memavail_kb:-N/A}" "${swaptotal_kb:-N/A}" "${swapfree_kb:-N/A}" "${swap_used_pct:-0}" "$swap_present" "$swap_used_pct")
  baseline_add_result "$group" "MEM_SWAP" "$swap_state" "KEY:SWAP_PRESENT=${swap_present} KEY:SWAP_USED_PCT=${swap_used_pct}" "$evidence_mem" "$suggestions_swap"

  disk_info_root="$(df -PTh / 2>/dev/null | awk 'NR==2 {print $1" "$2" "$3" "$4" "$5" "$7}')"
  disk_used_pct_root="$(echo "$disk_info_root" | awk '{print $(NF-1)}')"
  disk_used_pct_root="${disk_used_pct_root%%%}"
  if ! echo "$disk_used_pct_root" | grep -Eq '^[0-9]+$'; then
    disk_used_pct_root="0"
  fi
  disk_state_root="PASS"
  suggestions_disk=""
  if [ "$disk_used_pct_root" -ge 90 ]; then
    disk_state_root="FAIL"
    if [ "$lang" = "en" ]; then
      suggestions_disk="Disk usage >=90% on /. Free space by cleaning logs/cache or extending storage. Example: du -sh /var/log/* | sort -h; apt clean; remove old backups."
    else
      suggestions_disk="根分区使用率 >=90%，请清理日志/缓存或扩容磁盘。例如：du -sh /var/log/* | sort -h；apt clean；删除过期备份。"
    fi
  elif [ "$disk_used_pct_root" -ge 80 ]; then
    disk_state_root="WARN"
    if [ "$lang" = "en" ]; then
      suggestions_disk="Disk usage >=80% on /. Plan cleanup (logs/cache) or increase disk size before it fills up."
    else
      suggestions_disk="根分区使用率 >=80%，建议提前清理日志/缓存或扩容，避免写入失败。"
    fi
  fi
  evidence_disk=$(printf "df -hT / => %s\nKEY:DISK_USAGE_ROOT=%s%%" "${disk_info_root:-N/A}" "$disk_used_pct_root")
  baseline_add_result "$group" "DISK_ROOT" "$disk_state_root" "KEY:DISK_USAGE_ROOT=${disk_used_pct_root}%" "$evidence_disk" "$suggestions_disk"

  if command -v df >/dev/null 2>&1; then
    inode_info_root="$(df -Pih / 2>/dev/null | awk 'NR==2 {print $1" "$2" "$3" "$4" "$5" "$7}')"
    inode_used_pct_root="$(echo "$inode_info_root" | awk '{print $(NF-1)}')"
    inode_used_pct_root="${inode_used_pct_root%%%}"
    if echo "$inode_used_pct_root" | grep -Eq '^[0-9]+$'; then
      inode_state_root="PASS"
      if [ "$inode_used_pct_root" -ge 90 ]; then
        inode_state_root="FAIL"
      elif [ "$inode_used_pct_root" -ge 80 ]; then
        inode_state_root="WARN"
      fi
      if [ "$inode_state_root" != "PASS" ]; then
        if [ "$lang" = "en" ]; then
          suggestions_inode="High inode usage; remove excessive small files (e.g., cache, rotated logs)."
        else
          suggestions_inode="inode 使用率偏高，建议清理大量小文件（缓存、过期日志等）。"
        fi
      fi
      evidence_inode=$(printf "df -ih / => %s\nKEY:INODE_USAGE_ROOT=%s%%" "${inode_info_root:-N/A}" "$inode_used_pct_root")
      baseline_add_result "$group" "INODE_ROOT" "$inode_state_root" "KEY:INODE_USAGE_ROOT=${inode_used_pct_root}%" "$evidence_inode" "$suggestions_inode"
    fi
  fi

  if command -v journalctl >/dev/null 2>&1; then
    journal_usage="$(journalctl --disk-usage 2>/dev/null | head -n1 || true)"
    journal_size_str="$(echo "$journal_usage" | grep -Eo '[0-9.]+[KMGTP]?B?' | head -n1)"
    journal_bytes="$(baseline_sys__parse_size_bytes "${journal_size_str}")"
    journal_state="PASS"
    suggestions_journal=""
    if echo "$journal_bytes" | grep -Eq '^[0-9]+$'; then
      if [ "$journal_bytes" -ge $((3*1024*1024*1024)) ]; then
        journal_state="FAIL"
      elif [ "$journal_bytes" -ge $((1024*1024*1024)) ]; then
        journal_state="WARN"
      fi
    fi
    if [ "$journal_state" != "PASS" ]; then
      if [ "$lang" = "en" ]; then
        suggestions_journal="Consider rotating/vacuuming logs manually, e.g., journalctl --vacuum-size=512M (run after review)."
      else
        suggestions_journal="建议手动清理/收缩日志，例如：journalctl --vacuum-size=512M（审阅后再执行）。"
      fi
    fi
    evidence_journal=$(printf "%s\nKEY:JOURNAL_DISK=%s" "${journal_usage:-journalctl --disk-usage not available}" "${journal_usage:-N/A}")
    baseline_add_result "$group" "JOURNAL_DISK" "$journal_state" "KEY:JOURNAL_DISK=${journal_usage:-N/A}" "$evidence_journal" "$suggestions_journal"
  fi

  if command -v docker >/dev/null 2>&1; then
    docker_out="$(docker system df 2>/dev/null | head -n 10 || true)"
    evidence_docker=$(printf "docker system df (preview):\n%s\nKEY:DOCKER_DISK=%s" "${docker_out:-unavailable}" "${docker_out%%$'\n'*}")
    suggestions_docker=""
    baseline_add_result "$group" "DOCKER_DISK" "PASS" "KEY:DOCKER_DISK" "$evidence_docker" "$suggestions_docker"
  fi

  if [ -d /var/log ]; then
    logs_listing="$(ls -lhS /var/log 2>/dev/null | head -n 20 || true)"
    if [ -z "$logs_listing" ]; then
      logs_listing="(empty)"
    fi
    evidence_logs=$(printf "/var/log top entries:\n%s" "$logs_listing")
    if command -v find >/dev/null 2>&1; then
      large_logs="$(find /var/log -maxdepth 2 -type f -size +100M -printf '%p (%s bytes)\n' 2>/dev/null | head -n 10 || true)"
      if [ -n "$large_logs" ]; then
        evidence_logs=$(printf "%s\nLarge log files (>100M):\n%s" "$evidence_logs" "$large_logs")
      fi
    fi
    if [ "$lang" = "en" ]; then
      suggestions_log="Inspect large log files above; truncate cautiously if needed (e.g., :> /var/log/xxx.log after backup)."
    else
      suggestions_log="查看上述较大的日志文件；如需释放空间，请先备份再用 :> /var/log/xxx.log 谨慎截断。"
    fi
    baseline_add_result "$group" "LOG_DIR" "PASS" "" "$evidence_logs" "$suggestions_log"
  fi

  if command -v lsblk >/dev/null 2>&1; then
    lsblk_out="$(lsblk -f 2>/dev/null | head -n 30 || true)"
    baseline_add_result "$group" "BLOCK_DEV" "PASS" "" "lsblk -f:\n${lsblk_out}" ""
  fi
}

