# Claude Code Compact Statusline

A compact 3-line status bar for [Claude Code](https://code.claude.com/docs/en/statusline) with gradient context visualization, rate limit tracking, and full session awareness. Line 3 is width-aligned to line 2 to form a clean rectangle.

![Claude Code Statusline](screenshot.png)

## Layout

### Line 1 — Project & Context

```
── claude-statusline · master ── ◉ ⛁⛁⛁⛁⛁⛁⛁⛁░░░░░░░░░░░░ 7%
```

| Element | Description |
|---------|-------------|
| `claude-statusline` | Current project directory name |
| `master` | Git branch (shows `detached` for detached HEAD, hidden outside git repos) |
| `wt:feature` | Active worktree name (only during `--worktree` sessions) |
| `@security-reviewer` | Agent name (only when running with `--agent`) |
| `NORMAL` | Vim mode (only when vim mode is enabled) |
| `◉ ⛁⛁⛁...` | Gradient context bar — 20 buckets transitioning green to amber to red as usage grows |
| `7%` | Context window usage percentage, color-coded: green (<40%), amber (40–59%), orange (60–79%), red (80%+) |
| Warning icon | Shown when token count exceeds 200k threshold |

### Line 2 — Limits, Cost & Duration

```
── ▰ 5H:4% ↻03:00 │ WK:5% ↻Mon 19:00 │ $1.81 │ 36m3s
```

| Element | Description |
|---------|-------------|
| `5H:4%` | 5-hour rolling rate limit usage (Pro/Max subscribers only, hidden otherwise) |
| `↻03:00` | 5-hour rate limit reset time |
| `WK:5%` | 7-day rate limit usage (Pro/Max subscribers only, hidden otherwise) |
| `↻Mon 19:00` | 7-day rate limit reset time (includes day of week) |
| `$1.81(est)` / `$1.81` | Session cost in USD. Shows `(est)` suffix for Pro/Max subscribers (estimated equivalent), exact cost for API users. Hidden when $0.00 |
| `36m3s` | Session duration (hidden at 0) |

Rate limit percentages are color-coded with the same thresholds as context usage.

### Line 3 — Model, Session & Version

```
── Opus/1M · Fix status line formatting and d… ◈ CC 2.1.128
```

| Element | Description |
|---------|-------------|
| `Opus/1M` | Active model short name. Appends `/1M` when context window is 1M tokens |
| `Fix status line…` | Custom session name (from `--name` or `/rename`). Truncated with `…` so line 3 width matches line 2 |
| `◈ CC 2.1.128` | Claude Code version, anchored at the end of the line |

The session name is auto-truncated based on the visible width of line 2 (rate limits + cost + duration), so the bottom two lines form a roughly rectangular block regardless of session name length.

## Install

1. Copy the script and make it executable:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

3. Restart Claude Code.

## Requirements

- `jq` — JSON parsing (`brew install jq` / `apt install jq`)
- `git` — optional, for branch display
- A terminal with truecolor support and UTF-8 locale (Kitty, iTerm2, WezTerm, Ghostty)

## Color Thresholds

Usage percentages (context, 5H, 7D) change color based on severity:

| Range | Color |
|-------|-------|
| 0–39% | Green |
| 40–59% | Amber |
| 60–79% | Orange |
| 80–100% | Red |

The context bar uses a smooth gradient across all 20 buckets, transitioning from green through amber to red.

## Features

- **Single `jq` call** — all JSON fields extracted in one pass, no `eval`
- **Git caching** — branch lookup cached for 5 seconds per session (keyed by `session_id`)
- **Width-aligned layout** — session name truncated to match line 2 width for a rectangular look
- **Graceful degradation** — rate limits hidden for non-subscribers, optional fields appear only when present
- **Portable** — works on macOS and Linux (`date`, `stat`, `wc -m`, `cut` cross-platform fallbacks)
- **Safe input handling** — JSON parsed via here-string, no pipes into `jq`, no `eval`
- **Future-proof** — unknown model names display their full `display_name`

## Testing

Test with mock JSON input:

```bash
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/home/user/project"},"context_window":{"used_percentage":42,"context_window_size":1000000},"session_id":"test","session_name":"Fix status line formatting","version":"2.1.128","cost":{"total_cost_usd":1.23,"total_duration_ms":120000},"exceeds_200k_tokens":false,"rate_limits":{"five_hour":{"used_percentage":15,"resets_at":1738425600},"seven_day":{"used_percentage":8,"resets_at":1738857600}}}' | ./statusline-command.sh
```
