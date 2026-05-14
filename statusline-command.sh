#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Claude Code Status Line — Compact 2-line display
# ═══════════════════════════════════════════════════════════════════════════════
#
# Line 1: User · Model · Project · Branch ── Context bar
# Line 2: Rate limits · Session cost · Duration ── CC version
#
# Uses native JSON fields from Claude Code (rate_limits, cost, etc.)
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# ─── Dependency check ───────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo "[statusline] jq not found — install with: brew install jq"
    exit 1
fi

# ─── Parse input ──────────────────────────────────────────────────────────────

input=$(cat)

# Single jq call — extract all fields as newline-delimited values
parsed=$(jq -r '
  [
    (.workspace.current_dir // .cwd // "."),
    (.model.display_name // "unknown"),
    (.version // "unknown"),
    (.context_window.used_percentage // 0 | tostring),
    (.context_window.context_window_size // 200000 | tostring),
    (.cost.total_cost_usd // 0 | tostring),
    (.session_id // ""),
    (.session_name // ""),
    (.cost.total_duration_ms // 0 | tostring),
    (.exceeds_200k_tokens // false | tostring),
    (.vim.mode // ""),
    (.agent.name // ""),
    (.worktree.name // ""),
    (if .rate_limits then "true" else "false" end),
    (.rate_limits.five_hour.used_percentage // "" | tostring),
    (.rate_limits.five_hour.resets_at // "" | tostring),
    (.rate_limits.seven_day.used_percentage // "" | tostring),
    (.rate_limits.seven_day.resets_at // "" | tostring)
  ] | join("\n")
' <<< "$input" 2>&1)

if [ $? -ne 0 ]; then
    echo "[statusline] jq parse error: ${parsed}"
    exit 1
fi

# Read all fields from the single jq output
{
    IFS= read -r current_dir
    IFS= read -r model_name
    IFS= read -r cc_version
    IFS= read -r context_pct
    IFS= read -r context_size
    IFS= read -r session_cost
    IFS= read -r session_id
    IFS= read -r session_name
    IFS= read -r duration_ms
    IFS= read -r exceeds_200k
    IFS= read -r vim_mode
    IFS= read -r agent_name
    IFS= read -r worktree_name
    IFS= read -r has_rate_limits
    IFS= read -r usage_5h
    IFS= read -r usage_5h_reset
    IFS= read -r usage_7d
    IFS= read -r usage_7d_reset
} <<< "$parsed"

context_pct=${context_pct:-0}

dir_name=$(basename "$current_dir" 2>/dev/null || echo ".")

# ─── Git branch (cached) ───────────────────────────────────────────────────

CACHE_FILE=""
CACHE_MAX_AGE=5

if [ -n "$session_id" ]; then
    CACHE_FILE="/tmp/statusline-git-cache-${session_id}"
fi

cache_is_stale() {
    [ -z "$CACHE_FILE" ] && return 0
    [ ! -f "$CACHE_FILE" ] && return 0
    local file_age
    file_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    [ "$file_age" -gt "$CACHE_MAX_AGE" ]
}

is_git_repo=false
branch=""

if cache_is_stale; then
    if git rev-parse --git-dir > /dev/null 2>&1; then
        is_git_repo=true
        branch=$(git branch --show-current 2>/dev/null)
        [ -z "$branch" ] && branch="detached"
        [ -n "$CACHE_FILE" ] && echo "${is_git_repo}|${branch}" > "$CACHE_FILE"
    else
        [ -n "$CACHE_FILE" ] && echo "false|" > "$CACHE_FILE"
    fi
elif [ -n "$CACHE_FILE" ] && [ -f "$CACHE_FILE" ]; then
    IFS='|' read -r is_git_repo branch < "$CACHE_FILE"
fi

# ─── Session cost ────────────────────────────────────────────────────────────

session_cost_str=""
if [ "${session_cost:-0}" != "0" ]; then
    # Pro/Max subscribers have rate_limits — cost is an estimate, not a bill
    if [ "$has_rate_limits" = "true" ]; then
        session_cost_str=$(printf '$%.2f(est)' "$session_cost")
    else
        session_cost_str=$(printf '$%.2f' "$session_cost")
    fi
fi

# ─── Session duration ───────────────────────────────────────────────────────

duration_str=""
if [ "${duration_ms:-0}" != "0" ]; then
    duration_sec=$((duration_ms / 1000))
    mins=$((duration_sec / 60))
    secs=$((duration_sec % 60))
    duration_str="${mins}m${secs}s"
fi

# ─── Reset times ─────────────────────────────────────────────────────────────

format_reset_time() {
    local epoch=$1 fmt=$2
    [ -z "$epoch" ] && { echo ""; return; }
    if [ "$fmt" = "weekly" ]; then
        date -r "$epoch" '+%a %H:%M' 2>/dev/null || date -d "@$epoch" '+%a %H:%M' 2>/dev/null || echo ""
    else
        date -r "$epoch" '+%H:%M' 2>/dev/null || date -d "@$epoch" '+%H:%M' 2>/dev/null || echo ""
    fi
}

# ─── Colors ──────────────────────────────────────────────────────────────────

RESET=$'\033[0m'
SLATE_400=$'\033[38;2;148;163;184m'
SLATE_500=$'\033[38;2;100;116;139m'
SLATE_600=$'\033[38;2;71;85;105m'
EMERALD=$'\033[38;2;74;222;128m'
ROSE=$'\033[38;2;251;113;133m'
ORANGE=$'\033[38;2;251;146;60m'
AMBER=$'\033[38;2;251;191;36m'
CTX_PRIMARY=$'\033[38;2;129;140;248m'
CTX_ACCENT=$'\033[38;2;139;92;246m'
CTX_EMPTY=$'\033[38;2;75;82;95m'
GIT_VALUE=$'\033[38;2;186;230;253m'
GIT_DIR=$'\033[38;2;147;197;253m'
GIT_ICON=$'\033[38;2;56;189;248m'
BLUE=$'\033[38;2;59;130;246m'

# ─── Helpers ─────────────────────────────────────────────────────────────────

get_level_color() {
    local pct_int=${1%%.*}; [ -z "$pct_int" ] && pct_int=0
    if   [ "$pct_int" -ge 80 ]; then echo "$ROSE"
    elif [ "$pct_int" -ge 60 ]; then echo "$ORANGE"
    elif [ "$pct_int" -ge 40 ]; then echo "$AMBER"
    else echo "$EMERALD"; fi
}

get_bucket_color() {
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
    local i=1
    while [ "$i" -le "$width" ]; do
        if [ "$i" -le "$filled" ]; then
            output="${output}$(get_bucket_color $i $width)⛁${RESET}"
        else
            output="${output}${CTX_EMPTY}⛁${RESET}"
        fi
        i=$((i + 1))
    done
    printf '%s' "$output"
}

# ─── Derived values ─────────────────────────────────────────────────────────

# Model short name + context size indicator
case "$model_name" in
    *"Opus"*)   model_short="Opus" ;;
    *"Sonnet"*) model_short="Sonnet" ;;
    *"Haiku"*)  model_short="Haiku" ;;
    *)          model_short="$model_name" ;;
esac

# Append context window size hint
if [ "$context_size" -ge 1000000 ] 2>/dev/null; then
    model_short="${model_short}/1M"
fi

# Context percentage
raw_pct="${context_pct%%.*}"; [ -z "$raw_pct" ] && raw_pct=0
pct_color=$(get_level_color "$raw_pct")

# Context bar
bar_compact=$(render_context_bar 20 "$raw_pct")

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT — 3 lines
# ═══════════════════════════════════════════════════════════════════════════════

# Line 1: Project · Branch [· Worktree/Agent/Vim] ── Context bar
printf "${SLATE_600}──${RESET} ${GIT_DIR}%s${RESET}" "$dir_name"

if [ "$is_git_repo" = "true" ]; then
    printf " ${SLATE_600}·${RESET} ${GIT_VALUE}%s${RESET}" "$branch"
fi

if [ -n "$worktree_name" ]; then
    printf " ${SLATE_600}·${RESET} ${AMBER}wt:%s${RESET}" "$worktree_name"
fi

if [ -n "$agent_name" ]; then
    printf " ${SLATE_600}·${RESET} ${CTX_ACCENT}@%s${RESET}" "$agent_name"
fi

if [ -n "$vim_mode" ]; then
    printf " ${SLATE_600}·${RESET} ${SLATE_400}%s${RESET}" "$vim_mode"
fi

# Context bar + percentage + 200k warning
printf " ${SLATE_600}──${RESET} ${CTX_PRIMARY}◉${RESET} %s ${pct_color}%s%%${RESET}" "$bar_compact" "$raw_pct"

if [ "$exceeds_200k" = "true" ]; then
    printf " ${ROSE}⚠${RESET}"
fi

printf "\n"

# ─── Build line 2 into a buffer (no CC version — moved to line 3) ──────────

line2=""
line2+="${SLATE_600}──${RESET}"
has_prev=false

if [ "$has_rate_limits" = "true" ]; then
    if [ -n "$usage_5h" ]; then
        usage_5h_int=${usage_5h%%.*}; usage_5h_int=${usage_5h_int:-0}
        usage_5h_color=$(get_level_color "$usage_5h_int")
        reset_5h_time=$(format_reset_time "$usage_5h_reset" "hourly")
        line2+=" ${AMBER}▰${RESET} ${SLATE_400}5H:${RESET}${usage_5h_color}${usage_5h_int}%${RESET}"
        [ -n "$reset_5h_time" ] && line2+=" ${SLATE_500}↻${reset_5h_time}${RESET}"
        has_prev=true
    fi
    if [ -n "$usage_7d" ]; then
        usage_7d_int=${usage_7d%%.*}; usage_7d_int=${usage_7d_int:-0}
        usage_7d_color=$(get_level_color "$usage_7d_int")
        reset_7d_time=$(format_reset_time "$usage_7d_reset" "weekly")
        line2+=" ${SLATE_600}│${RESET} ${SLATE_400}WK:${RESET}${usage_7d_color}${usage_7d_int}%${RESET}"
        [ -n "$reset_7d_time" ] && line2+=" ${SLATE_500}↻${reset_7d_time}${RESET}"
        has_prev=true
    fi
else
    line2+=" ${AMBER}▰${RESET} ${SLATE_500}5H:-- │ WK:--${RESET}"
    has_prev=true
fi

if [ -n "$session_cost_str" ]; then
    [ "$has_prev" = "true" ] && line2+=" ${SLATE_600}│${RESET}"
    line2+=" ${SLATE_500}${session_cost_str}${RESET}"
    has_prev=true
fi

if [ -n "$duration_str" ]; then
    [ "$has_prev" = "true" ] && line2+=" ${SLATE_600}│${RESET}"
    line2+=" ${SLATE_500}${duration_str}${RESET}"
fi

printf '%s\n' "$line2"

# ─── Measure line 2 visible width (for line 3 rectangle alignment) ─────────

visual_width() {
    local stripped
    stripped=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')
    printf '%s' "$stripped" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

target_width=$(visual_width "$line2")

# ─── Line 3: Model · session_name (truncated) ◈ CC version ─────────────────

line3_prefix_plain="── ${model_short}"
[ -n "$session_name" ] && line3_prefix_plain="${line3_prefix_plain} · "
line3_suffix_plain=" ◈ CC ${cc_version}"

prefix_w=$(visual_width "$line3_prefix_plain")
suffix_w=$(visual_width "$line3_suffix_plain")

avail=$((target_width - prefix_w - suffix_w))
[ "$avail" -lt 5 ] && avail=5

truncated="$session_name"
if [ -n "$session_name" ]; then
    sname_len=$(printf '%s' "$session_name" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    if [ "$sname_len" -gt "$avail" ]; then
        truncated=$(printf '%s' "$session_name" | LC_ALL=en_US.UTF-8 cut -c1-$((avail - 1)))…
    fi
fi

printf "${SLATE_600}──${RESET} ${CTX_ACCENT}%s${RESET}" "$model_short"
if [ -n "$session_name" ]; then
    printf " ${SLATE_600}·${RESET} ${SLATE_400}%s${RESET}" "$truncated"
fi
printf " ${GIT_ICON}◈${RESET} ${SLATE_400}CC ${BLUE}%s${RESET}\n" "$cc_version"
