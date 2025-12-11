#!/usr/bin/env bash
# Plugin: memory - Display memory usage percentage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT_DIR/../plugin_bootstrap.sh"

plugin_init "memory"

plugin_get_type() { printf 'static'; }

bytes_to_human() {
    local bytes=$1
    local gb=$((bytes / 1073741824))
    
    if [[ $gb -gt 0 ]]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1fG", b / 1073741824}'
    else
        printf '%dM' "$((bytes / POWERKIT_BYTE_MB))"
    fi
}

get_memory_linux() {
    local format
    format=$(get_cached_option "@powerkit_plugin_memory_format" "$POWERKIT_PLUGIN_MEMORY_FORMAT")
    
    local mem_info mem_total mem_available mem_used percent
    mem_info=$(awk '
        /^MemTotal:/ {total=$2}
        /^MemAvailable:/ {available=$2}
        /^MemFree:/ {free=$2}
        /^Buffers:/ {buffers=$2}
        /^Cached:/ {cached=$2}
        END {
            if (available > 0) { print total, available }
            else { print total, (free + buffers + cached) }
        }
    ' /proc/meminfo)
    
    read -r mem_total mem_available <<< "$mem_info"
    mem_used=$((mem_total - mem_available))
    percent=$(( (mem_used * 100) / mem_total ))
    
    if [[ "$format" == "usage" ]]; then
        printf '%s/%s' "$(bytes_to_human $((mem_used * POWERKIT_BYTE_KB)))" "$(bytes_to_human $((mem_total * POWERKIT_BYTE_KB)))"
    else
        printf '%3d%%' "$percent"
    fi
}

get_memory_macos() {
  # Grab vm_stat output once
  local vmstat
  vmstat=$(vm_stat)

  # Page size (usually 4096)
  local pagesize
  pagesize=$(printf "%s\n" "$vmstat" | awk '/page size of/ {gsub(/\./,"",$8); print $8}')
  [ -z "$pagesize" ] && pagesize=4096

  # Extract page counts, strip trailing dots
  local free speculative filebacked
  free=$(printf "%s\n" "$vmstat" | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
  speculative=$(printf "%s\n" "$vmstat" | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')
  filebacked=$(printf "%s\n" "$vmstat" | awk '/File-backed/ {gsub(/\./,"",$3); print $3}')

  [ -z "$free" ] && free=0
  [ -z "$speculative" ] && speculative=0
  [ -z "$filebacked" ] && filebacked=0

  # Treat file-backed + speculative as "cache"
  local cached_pages
  cached_pages=$((speculative + filebacked))

  # Total physical memory in bytes
  local total_bytes
  total_bytes=$(sysctl -n hw.memsize)

  # Convert pages to bytes
  local free_bytes cached_bytes used_bytes
  free_bytes=$((free * pagesize))
  cached_bytes=$((cached_pages * pagesize))
  used_bytes=$((total_bytes - free_bytes - cached_bytes))
  if [ "$used_bytes" -lt 0 ]; then
    used_bytes=0
  fi

  # Convert to MB
  local total_mb used_mb cached_mb
  total_mb=$((total_bytes / 1024 / 1024))
  used_mb=$((used_bytes / 1024 / 1024))
  cached_mb=$((cached_bytes / 1024 / 1024))

  # Percentage (use awk for float math)
  local used_pct
  used_pct=$(awk -v u="$used_mb" -v t="$total_mb" 'BEGIN { if (t>0) printf "%.2f", 100*u/t; else print "0.00"; }')

  # printf "Mem used (excluding cache): %s%% (%d / %d MB, cache: %d MB)\n" "$used_pct" "$used_mb" "$total_mb" "$cached_mb"
  printf "%3d%%" "$used_pct"
}

load_plugin() {
    local cached_value
    if cached_value=$(cache_get "$CACHE_KEY" "$CACHE_TTL"); then
        printf '%s' "$cached_value"
        return
    fi

    local result
    if is_linux; then
        result=$(get_memory_linux)
    elif is_macos; then
        result=$(get_memory_macos)
    else
        result="N/A"
    fi

    cache_set "$CACHE_KEY" "$result"
    printf '%s' "$result"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && load_plugin || true
