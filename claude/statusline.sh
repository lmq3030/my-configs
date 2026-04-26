#!/bin/bash
# Claude Code statusline: Context % | 5h: % (reset) | 7d: % (reset)
exec 2>/dev/null

CACHE_DIR="$HOME/.cache/waza-statusline"
CACHE_FILE="$CACHE_DIR/last.json"
CACHE_MAX_AGE=21600  # 6 hours: one full rate_limit window

input=$(cat)

tab=$(printf '\t')

jq_full='[
  (.model.display_name // "" | tostring),
  ((.context_window.current_usage.input_tokens // 0)
   + (.context_window.current_usage.cache_creation_input_tokens // 0)
   + (.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
  (.context_window.context_window_size // 0 | tostring),
  (.rate_limits.five_hour.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.five_hour.resets_at // "" | tostring),
  (.rate_limits.seven_day.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.seven_day.resets_at // "" | tostring),
  (.workspace.current_dir // .cwd // "" | tostring),
  (.session_id // "" | tostring)
] | @tsv'

jq_rl='[
  (.rate_limits.five_hour.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.five_hour.resets_at // "" | tostring),
  (.rate_limits.seven_day.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.seven_day.resets_at // "" | tostring)
] | @tsv'

cache_file_mtime() {
  local path="$1"
  local ts=""
  ts=$(stat -c %Y "$path" 2>/dev/null || true)
  if [ -z "$ts" ]; then
    ts=$(stat -f %m "$path" 2>/dev/null || true)
  fi
  printf '%s\n' "${ts:-0}"
}

# Single jq pass for live input
parsed=""
[ -n "$input" ] && parsed=$(printf '%s' "$input" | jq -r "$jq_full" 2>/dev/null)

IFS="$tab" read -r model_name used_tokens window_size live_five_pct live_five_reset live_seven_pct live_seven_reset cwd session_id <<EOF
$parsed
EOF

five_pct="${live_five_pct:-}"
five_reset="${live_five_reset:-}"
seven_pct="${live_seven_pct:-}"
seven_reset="${live_seven_reset:-}"

# If rate_limits missing from live input, read from cache
if [ "$five_pct" = "null" ] || [ -z "$five_pct" ]; then
  if [ -f "$CACHE_FILE" ]; then
    cache_mtime=$(cache_file_mtime "$CACHE_FILE")
    cache_age=$(( $(date +%s) - cache_mtime ))
    if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
      cached=$(jq -r "$jq_rl" "$CACHE_FILE" 2>/dev/null)
      IFS="$tab" read -r five_pct five_reset seven_pct seven_reset <<EOF
$cached
EOF
    fi
  fi
fi

# Persist live rate_limits only when present (atomic write)
if [ "${live_five_pct:-}" != "null" ] && [ -n "${live_five_pct:-}" ] && [ -n "$input" ]; then
  mkdir -p "$CACHE_DIR"
  printf '%s' "$input" | jq '{rate_limits: .rate_limits}' \
    > "${CACHE_FILE}.tmp" 2>/dev/null \
    && mv "${CACHE_FILE}.tmp" "$CACHE_FILE" 2>/dev/null \
    || true
fi

# --- Colors ---
RESET="\033[0m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[94m"
MAGENTA="\033[95m"

# Format seconds remaining as "4h23m" or "1d21h"
format_reset() {
  local ts="$1"
  [ -z "$ts" ] && return
  local epoch now diff
  epoch=$(printf '%s' "$ts" | tr -dc '0-9')
  [ -z "$epoch" ] && return
  now=$(date +%s)
  diff=$((epoch - now))
  [ "$diff" -le 0 ] && return
  local mins=$(( diff / 60 ))
  local hours=$(( mins / 60 ))
  local days=$(( hours / 24 ))
  if [ "$days" -ge 1 ]; then
    printf "%dd%dh" "$days" $(( hours % 24 ))
  elif [ "$hours" -ge 1 ]; then
    printf "%dh%dm" "$hours" $(( mins % 60 ))
  else
    printf "%dm" "$mins"
  fi
}

# Thinking level (read from user settings; /think persists here)
SETTINGS_FILE="$HOME/.claude/settings.json"
think_label=""
if [ -f "$SETTINGS_FILE" ]; then
  thinking_enabled=$(jq -r '.alwaysThinkingEnabled // true' "$SETTINGS_FILE" 2>/dev/null)
  effort=$(jq -r '.effortLevel // ""' "$SETTINGS_FILE" 2>/dev/null)
  if [ "$thinking_enabled" = "false" ]; then
    think_label="off"
  elif [ -n "$effort" ]; then
    think_label="$effort"
  else
    think_label="on"
  fi
fi

# Model name
if [ -n "$model_name" ]; then
  if [ -n "$think_label" ]; then
    model_part="${BLUE}${model_name}${RESET} ${DIM}(${think_label})${RESET}"
  else
    model_part="${BLUE}${model_name}${RESET}"
  fi
else
  model_part=""
fi

# Context %
ctx_pct=0
if [ "$window_size" -gt 0 ] 2>/dev/null; then
  ctx_pct=$(awk -v u="${used_tokens:-0}" -v t="$window_size" 'BEGIN { printf "%d", (u/t)*100 }')
fi
if [ "$ctx_pct" -ge 85 ] 2>/dev/null; then
  ctx_color="$RED"
elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then
  ctx_color="$YELLOW"
else
  ctx_color="$GREEN"
fi
context_part="${DIM}ctx${RESET} ${ctx_color}${ctx_pct}%${RESET}"

# Usage color
usage_color() {
  local pct="$1"
  if [ "$pct" -ge 90 ] 2>/dev/null; then printf "%s" "$RED"
  elif [ "$pct" -ge 70 ] 2>/dev/null; then printf "%s" "$MAGENTA"
  else printf "%s" "$BLUE"
  fi
}

# Combined rate-limit part: "88%(3h25m):35%(3d22h)" — first=5h, second=7d.
fmt_rl_segment() {
  local pct="$1" reset_ts="$2"
  if [ "$pct" = "null" ] || [ -z "$pct" ]; then
    printf "%b--%b" "$DIM" "$RESET"
    return
  fi
  local color reset_str
  color=$(usage_color "$pct")
  reset_str=$(format_reset "$reset_ts")
  if [ -n "$reset_str" ]; then
    printf "%b%s%%%b%b(%s)%b" "$color" "$pct" "$RESET" "$DIM" "$reset_str" "$RESET"
  else
    printf "%b%s%%%b" "$color" "$pct" "$RESET"
  fi
}
five_seg=$(fmt_rl_segment "$five_pct" "$five_reset")
seven_seg=$(fmt_rl_segment "$seven_pct" "$seven_reset")
five_part="${five_seg}${DIM}:${RESET}${seven_seg}"

# Subagents part (count marker files maintained by SubagentStart/Stop hooks)
agents_count=0
if [ -n "$session_id" ]; then
  sanitized_session=$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9._-' '_')
  agents_dir="$HOME/.cache/waza-statusline/subagents/$sanitized_session"
  if [ -d "$agents_dir" ]; then
    agents_count=$(find "$agents_dir" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  fi
fi
if [ "$agents_count" -gt 0 ] 2>/dev/null; then
  agents_part="${DIM}agents${RESET} ${MAGENTA}${agents_count}${RESET}"
else
  agents_part="${DIM}agents${RESET} ${DIM}0${RESET}"
fi

# Current directory (abbreviate $HOME as ~)
dir_part=""
if [ -n "$cwd" ]; then
  dir_display="${cwd##*/}"
  dir_part="${DIM}Dir${RESET} ${MAGENTA}${dir_display}${RESET}"
fi

if [ -n "$model_part" ] && [ -n "$dir_part" ]; then
  printf "%b | %b | %b | %b | %b\n" "$model_part" "$dir_part" "$context_part" "$five_part" "$agents_part"
elif [ -n "$model_part" ]; then
  printf "%b | %b | %b | %b\n" "$model_part" "$context_part" "$five_part" "$agents_part"
elif [ -n "$dir_part" ]; then
  printf "%b | %b | %b | %b\n" "$dir_part" "$context_part" "$five_part" "$agents_part"
else
  printf "%b | %b | %b\n" "$context_part" "$five_part" "$agents_part"
fi
