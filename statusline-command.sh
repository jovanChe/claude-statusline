#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Claude Code Status Line — Compact 2-line display
# ═══════════════════════════════════════════════════════════════════════════════
#
# Line 1: User · Model · Project · Branch ── Context bar
# Line 2: Rate limits · Session cost ── CC version
#
# Uses native JSON fields from Claude Code (rate_limits, cost, etc.)
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# ─── Parse input ──────────────────────────────────────────────────────────────

input=$(cat)

eval "$(echo "$input" | jq -r '
  "current_dir=" + (.workspace.current_dir // .cwd // "." | @sh) + "\n" +
  "model_name=" + (.model.display_name // "unknown" | @sh) + "\n" +
  "cc_version=" + (.version // "unknown" | @sh) + "\n" +
  "context_pct=" + (.context_window.used_percentage // 0 | tostring) + "\n" +
  "session_cost=" + (.cost.total_cost_usd // 0 | tostring) + "\n" +
  "usage_5h=" + (.rate_limits.five_hour.used_percentage // 0 | tostring) + "\n" +
  "usage_5h_reset=" + (.rate_limits.five_hour.resets_at // 0 | tostring) + "\n" +
  "usage_7d=" + (.rate_limits.seven_day.used_percentage // 0 | tostring) + "\n" +
  "usage_7d_reset=" + (.rate_limits.seven_day.resets_at // 0 | tostring)
' 2>/dev/null)"

context_pct=${context_pct:-0}
usage_5h=${usage_5h:-0}
usage_7d=${usage_7d:-0}

dir_name=$(basename "$current_dir" 2>/dev/null || echo ".")

# ─── Git branch ──────────────────────────────────────────────────────────────

is_git_repo=false
branch=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    is_git_repo=true
    branch=$(git branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch="detached"
fi

# ─── Session cost ────────────────────────────────────────────────────────────

session_cost_str=""
if [ "${session_cost:-0}" != "0" ]; then
    session_cost_str=$(printf '$%.2f' "$session_cost")
fi

# ─── Reset times ─────────────────────────────────────────────────────────────

format_reset_time() {
    local epoch=$1 fmt=$2
    [ "$epoch" = "0" ] || [ -z "$epoch" ] && { echo "—"; return; }
    if [ "$fmt" = "weekly" ]; then
        date -r "$epoch" '+%a %H:%M' 2>/dev/null || date -d "@$epoch" '+%a %H:%M' 2>/dev/null || echo "—"
    else
        date -r "$epoch" '+%H:%M' 2>/dev/null || date -d "@$epoch" '+%H:%M' 2>/dev/null || echo "—"
    fi
}

reset_5h_time=$(format_reset_time "${usage_5h_reset:-0}" "hourly")
reset_7d_time=$(format_reset_time "${usage_7d_reset:-0}" "weekly")

# ─── Colors ──────────────────────────────────────────────────────────────────

RESET='\033[0m'
SLATE_400='\033[38;2;148;163;184m'
SLATE_500='\033[38;2;100;116;139m'
SLATE_600='\033[38;2;71;85;105m'
EMERALD='\033[38;2;74;222;128m'
ROSE='\033[38;2;251;113;133m'
ORANGE='\033[38;2;251;146;60m'
AMBER='\033[38;2;251;191;36m'
CTX_PRIMARY='\033[38;2;129;140;248m'
CTX_ACCENT='\033[38;2;139;92;246m'
CTX_EMPTY='\033[38;2;75;82;95m'
GIT_VALUE='\033[38;2;186;230;253m'
GIT_DIR='\033[38;2;147;197;253m'
GIT_ICON='\033[38;2;56;189;248m'
BLUE='\033[38;2;59;130;246m'
LIGHT_BLUE='\033[38;2;147;197;253m'

# ─── Helpers ─────────────────────────────────────────────────────────────────

get_level_color() {
    local pct_int=${1%%.*}; [ -z "$pct_int" ] && pct_int=0
    if   [ "$pct_int" -ge 80 ]; then echo "$ROSE"
    elif [ "$pct_int" -ge 60 ]; then echo "$ORANGE"
    elif [ "$pct_int" -ge 40 ]; then echo "$AMBER"
    else echo "$EMERALD"; fi
}

get_bucket_color() {
    local pos=$1 max=$2
    local pct=$(($1 * 100 / $2))
    local r g b
    if [ "$pct" -le 33 ]; then
        r=$((74 + (250 - 74) * pct / 33)); g=$((222 + (204 - 222) * pct / 33)); b=$((128 + (21 - 128) * pct / 33))
    elif [ "$pct" -le 66 ]; then
        local t=$((pct - 33)); r=$((250 + (251 - 250) * t / 33)); g=$((204 + (146 - 204) * t / 33)); b=$((21 + (60 - 21) * t / 33))
    else
        local t=$((pct - 66)); r=$((251 + (239 - 251) * t / 34)); g=$((146 + (68 - 146) * t / 34)); b=$((60 + (68 - 60) * t / 34))
    fi
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

render_context_bar() {
    local width=$1 pct=$2 output="" filled=$(($2 * $1 / 100))
    [ "$filled" -lt 0 ] && filled=0
    for i in $(seq 1 $width 2>/dev/null); do
        if [ "$i" -le "$filled" ]; then
            output="${output}$(get_bucket_color $i $width)⛁${RESET}"
        else
            output="${output}${CTX_EMPTY}⛁${RESET}"
        fi
    done
    echo "$output"
}

# ─── Derived values ─────────────────────────────────────────────────────────

# Model short name
case "$model_name" in
    *"Opus"*)   model_short="Opus" ;;
    *"Sonnet"*) model_short="Sonnet" ;;
    *"Haiku"*)  model_short="Haiku" ;;
    *)          model_short="$model_name" ;;
esac

# User first name
USER_FIRST=$(id -F 2>/dev/null | awk '{print $1}')
USER_FIRST="${USER_FIRST:-$(whoami)}"

# Context percentage
raw_pct="${context_pct%%.*}"; [ -z "$raw_pct" ] && raw_pct=0
pct_color=$(get_level_color "$raw_pct")

# Context bar
bar_compact=$(render_context_bar 20 $raw_pct)

# Usage colors
usage_5h_int=${usage_5h%%.*}; usage_5h_int=${usage_5h_int:-0}
usage_7d_int=${usage_7d%%.*}; usage_7d_int=${usage_7d_int:-0}
usage_5h_color=$(get_level_color "$usage_5h_int")
usage_7d_color=$(get_level_color "$usage_7d_int")

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT — 2 lines
# ═══════════════════════════════════════════════════════════════════════════════

# Line 1: User · Model · Project · Branch ── Context bar
printf "${SLATE_600}──${RESET} ${LIGHT_BLUE}${USER_FIRST}${RESET} ${SLATE_600}·${RESET} ${CTX_ACCENT}${model_short}${RESET} ${SLATE_600}·${RESET} ${GIT_DIR}${dir_name}${RESET}"
[ "$is_git_repo" = "true" ] && printf " ${SLATE_600}·${RESET} ${GIT_VALUE}${branch}${RESET}"
printf " ${SLATE_600}──${RESET} ${CTX_PRIMARY}◉${RESET} ${bar_compact} ${pct_color}${raw_pct}%%${RESET}\n"

# Line 2: Rate limits · Cost ── CC version
printf "${SLATE_600}──${RESET} ${AMBER}▰${RESET} ${SLATE_400}5H:${RESET}${usage_5h_color}${usage_5h_int}%%${RESET} ${SLATE_500}↻${reset_5h_time}${RESET} ${SLATE_600}│${RESET} ${SLATE_400}WK:${RESET}${usage_7d_color}${usage_7d_int}%%${RESET} ${SLATE_500}↻${reset_7d_time}${RESET}"
[ -n "$session_cost_str" ] && printf " ${SLATE_600}│${RESET} ${SLATE_500}${session_cost_str}${RESET}"
printf " ${SLATE_600}──${RESET} ${GIT_ICON}◈${RESET} ${SLATE_400}CC ${BLUE}${cc_version}${RESET}\n"
