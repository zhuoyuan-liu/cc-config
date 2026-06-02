# context-bar.sh

A two-line status line for [Claude Code](https://docs.claude.com/claude-code) that shows:

- **Line 1** — model · context-usage bar · cost · cwd · git branch + dirty count · session name
- **Line 2** — your last user message (truncated to terminal width)

Segments drop gracefully on narrow terminals (lowest-priority first: session → git detail → branch → cost → dir).

## Preview

```
claude-opus-4-7 | ████▄░░░░░ 45% (89.4k/1M) | 💰 $1.23 | 🗂️ cc-config | 🌿 main (2 files) | ◈ status-line-readme
💬 Can you copy my current status file for Claude Code to this folder?
```

## Requirements

`bash`, `jq`, `awk`, `git`, `stat` — standard on macOS and most Linux distros.

## Install

1. Copy the script into your Claude config dir and make it executable:

   ```bash
   mkdir -p ~/.claude/scripts
   curl -fsSL https://raw.githubusercontent.com/zhuoyuan-liu/cc-config/main/scripts/context-bar.sh \
     -o ~/.claude/scripts/context-bar.sh
   chmod +x ~/.claude/scripts/context-bar.sh
   ```

   Or, from a local clone: `cp scripts/context-bar.sh ~/.claude/scripts/ && chmod +x ~/.claude/scripts/context-bar.sh`.

2. Merge this block into `~/.claude/settings.json` (create the file as `{}` if it doesn't exist). **Don't overwrite** the file — preserve any existing keys like `permissions`, `env`, `hooks`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/scripts/context-bar.sh"
     }
   }
   ```

3. Restart Claude Code — the new status line shows up at the bottom.

> **Agents installing this for a user:** follow the same steps. Do *not* copy `settings.json` from any other source; it likely contains secrets. Only merge the `statusLine` key.

## Uninstall

Remove the `statusLine` block from `~/.claude/settings.json` and delete `~/.claude/scripts/context-bar.sh`.
