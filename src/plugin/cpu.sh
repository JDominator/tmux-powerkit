#!/usr/bin/env bash
# Plugin: cpu - Display CPU usage percentage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT_DIR/../plugin_bootstrap.sh"

plugin_init "cpu"

# Linux: /proc/stat with sampling
get_cpu_linux() {
    local line vals idle1 total1 idle2 total2 v

    line=$(grep '^cpu ' /proc/stat)
    read -ra vals <<< "${line#cpu }"
    idle1=${vals[3]}; total1=0
    for v in "${vals[@]}"; do total1=$((total1 + v)); done

    sleep "$POWERKIT_TIMING_CPU_SAMPLE"

    line=$(grep '^cpu ' /proc/stat)
    read -ra vals <<< "${line#cpu }"
    idle2=${vals[3]}; total2=0
    for v in "${vals[@]}"; do total2=$((total2 + v)); done

    local di=$((idle2 - idle1)) dt=$((total2 - total1))
    [[ $dt -gt 0 ]] && printf '%d' "$(( (1000 * (dt - di) / dt + 5) / 10 ))" || printf '0'
}

# macOS: iostat or ps fallback
get_cpu_macos() {
  local cpu=$(top -l 1 -n 0 | awk '
    /CPU usage/ {
      idle = 0
      # find the last field that looks like "number%"
      for (i = 1; i <= NF; i++) {
        if ($i ~ /%$/) idle = $i
      }
      gsub("%","",idle)
      printf "%.2f%%\n", 100 - idle
    }
  ')
    printf '%s' "${cpu:-0}"
}

plugin_get_type() { printf 'static'; }

load_plugin() {
    local cached
    if cached=$(cache_get "$CACHE_KEY" "$CACHE_TTL"); then
        printf '%s' "$cached"
        return
    fi

    local r
    is_linux && r=$(get_cpu_linux) || { is_macos && r=$(get_cpu_macos) || r="N/A"; }
    [[ "$r" != "N/A" ]] && r=$(printf '%3d%%' "$r")

    cache_set "$CACHE_KEY" "$r"
    printf '%s' "$r"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && load_plugin || true
