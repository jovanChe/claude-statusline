# Claude Code Compact Statusline

A 2-line status bar for [Claude Code](https://code.claude.com/docs/en/status-line) showing context usage, rate limits, git branch, and session cost.

```
── Predrag · Opus · my-project · main ── ◉ ⛁⛁⛁⛁⛁⛁⛁░░░░░░░░░░░░░ 37%
── ▰ 5H:11% ↻21:00 │ WK:2% ↻Mon 17:00 │ $4.12 ── ◈ CC 2.1.89
```

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

- `jq`
- `git` (optional, for branch display)

## What it shows

**Line 1:** Your name, active model, project directory, git branch, and a gradient context bar (green -> red)

**Line 2:** 5-hour and 7-day rate limit usage with reset times, session cost, and Claude Code version
