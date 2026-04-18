# SideQuest Plugin for Claude Code

Earn money by engaging with contextual quests while you code. SideQuest displays brief, non-intrusive promotional prompts at strategic moments in your workflow — typically after you finish a response in Claude. Each quest you open earns 2.5 NIS, and your earnings are tracked in real-time.

## Quick Start

```bash
curl -fsSL https://get.trysidequest.ai/install.sh | bash
```

Then authenticate:
```
/sidequest:login
```

The native SideQuest app will auto-launch and run in your menu bar. Quests appear as macOS notifications after you finish Claude responses or after gaps in activity.

## Dependencies

| Dependency | Required Version | Purpose |
|-----------|-----------------|---------|
| python3 | 3.8+ | JSON parsing, context extraction, atomic file I/O |
| curl | any | API communication |
| Node.js | 20+ | OAuth login flow |
| git | any | Commit detection, diff-based context extraction |
| nc (netcat) | any (ships with macOS) | IPC socket health check |
| macOS | 13.0+ (Ventura) | Required for SMAppService and native app |

## Skills Reference

All developer-facing features are available as skills:

### `/sidequest:login`
Authenticate with Google. Run this to set up your account or re-authenticate if you see auth errors.

### `/sidequest:settings`
Enable or disable the plugin permanently. Says "disable" to turn off, "enable" to turn back on.

### `/sidequest:do-not-disturb`
Toggle Do Not Disturb mode. Run once to pause quests, run again to resume.

**Note:** This skill is automatically invoked when you express frustration about quests (e.g., "please pause" or "I'm annoyed").

### `/sidequest:earnings`
Check your earnings dashboard. Shows the number of quests you've opened and your total NIS earnings (2.5 NIS per quest).

### `/sidequest:status`
Run a comprehensive health check. Shows:
- Auth status (token present?)
- Native app running status
- API connectivity
- Timing state (daily quest count, last quest timestamp, cooldown status)
- DND status

**Run this first when something isn't working.**

### `/sidequest:retrigger`
Show the last quest notification again. Useful for testing or if you accidentally dismissed it.

### `/sidequest:feedback`
Send feedback to the SideQuest team about your experience.

## How It Works

### Quest Display Triggers
Quests appear in two scenarios:

1. **After Claude response** — When you submit a prompt and Claude finishes generating a response, the stop hook fires and checks if it's time to show a quest.
2. **After inactivity** — If you've been idle in Claude for 10 minutes, a quest can be shown on next interaction.

### Timing & Frequency Rules
- **Maximum 5 quests per day** — Daily counter resets at midnight.
- **Minimum 20 minutes between quests** — Cooldown prevents quest fatigue.
- **Interaction-based frequency** — Quests show after every 10 interactions (by default; configurable).
- **Do Not Disturb respected** — If you run `/sidequest:do-not-disturb`, quests won't appear until you toggle it off.

### Context Extraction
When a quest is selected, the plugin extracts two layers of context to choose relevant promotional content:

1. **Static context** — Your project's tech stack from `CLAUDE.md` and `package.json`
2. **Dynamic context** — Recent git commit message and file changes (diff)

This context is used to match quests to your work but is **never sent to the server** — all matching happens locally.

## Troubleshooting

### No quests appearing

1. **Check if the native app is running**
   ```bash
   pgrep -x SideQuestApp
   ```
   If nothing prints, the app is not running. Look for the SideQuest icon in your menu bar (top-right corner).

2. **Check socket health** (verifies app-to-plugin communication)
   ```bash
   echo "" | nc -U -w1 ~/.sidequest/sidequest.sock
   ```
   If this fails, the app is not listening on the socket.

3. **Check timing state**
   ```bash
   cat ~/.sidequest/timing-state.json
   ```
   Verify:
   - `daily_quest_count` is less than 5
   - `last_quest_shown_at` is more than 20 minutes ago
   - `daily_reset_date` is today

4. **Check if Do Not Disturb is active**
   ```bash
   cat ~/.sidequest/config.json | python3 -m json.tool | grep do_not_disturb
   ```
   If `do_not_disturb` is `true`, quests are paused.

5. **Review the error log**
   ```bash
   cat ~/.sidequest/hook-errors.log
   ```
   Common errors:
   - `socket connection failed` — App not running
   - `config parse error` — Corrupted `config.json`
   - `API request failed` — Network issue or API down

6. **Run the diagnostics skill**
   ```
   /sidequest:status
   ```
   This provides a comprehensive health check of all components.

### Auth failures

**"Unauthorized" or "invalid token" errors:**

1. Check if your token exists:
   ```bash
   python3 -c "import json; print(json.load(open(open('$HOME/.sidequest/config.json')).get('token', 'MISSING')))"
   ```

2. If token is missing or expired, re-authenticate:
   ```
   /sidequest:login
   ```

### Gatekeeper issues ("App can't be opened" or "unidentified developer")

macOS blocks unsigned third-party apps. Solutions:

**Option 1: Allow via System Settings (easiest)**
1. Open System Settings > Privacy & Security
2. Scroll down to find "SideQuestApp was blocked"
3. Click "Open Anyway"

**Option 2: Remove quarantine attribute**
```bash
xattr -cr ~/Applications/SideQuestApp.app
```

**Option 3: Allow all unsigned apps (not recommended for security)**
```bash
sudo spctl --master-disable
```

### SMAppService auto-launch failures (app doesn't start at login)

If the app doesn't automatically launch when you log in to macOS:

1. Open System Settings > General > Login Items
2. Look for "SideQuestApp" in the "Allow in the Login Items" list
3. If missing, click the "+" button and select `~/Applications/SideQuestApp.app`
4. The app should now auto-launch on next login

The launchd plist at `~/Library/LaunchAgents/ai.sidequest.app.plist` handles KeepAlive, so the app will restart if it crashes.

### Hook errors log

Location: `~/.sidequest/hook-errors.log`

This log captures:
- Config parse errors
- API request failures
- Socket connection failures
- Timing state errors
- Other runtime issues

The log is automatically truncated at 100KB to prevent disk bloat.

**View recent errors:**
```bash
tail -20 ~/.sidequest/hook-errors.log
```

## Disable & Uninstall

### Pause quests temporarily

Use Do Not Disturb:
```
/sidequest:do-not-disturb
```

### Disable permanently (keep plugin installed)

```
/sidequest:settings
```

Then say "disable" when prompted.

This sets `"enabled": false` in your config and immediately stops showing quests. You can re-enable anytime with `/sidequest:settings` → "enable".

### Full uninstall (remove everything)

```bash
curl -fsSL https://get.trysidequest.ai/uninstall.sh | bash
```

Or if you have the repo:
```bash
./scripts/uninstall.sh
```

This removes:
- The native app (`~/Applications/SideQuestApp.app`)
- The plugin (from Claude's plugin directory)
- Launchd plist (`~/Library/LaunchAgents/ai.sidequest.app.plist`)
- All state files under `~/.sidequest/`

**Preserve your auth token for easy reinstall:**
```bash
./scripts/uninstall.sh --keep-config
```

This keeps `~/.sidequest/config.json` with your auth token, so next install skips the login step.

## Configuration Files

Advanced users can manually edit state files in `~/.sidequest/`:

### `config.json`
```json
{
  "token": "64-char-hex-string",
  "enabled": true,
  "api_base": "https://api.trysidequest.ai",
  "do_not_disturb": false
}
```

- `token`: Your auth token (generated via `/sidequest:login`)
- `enabled`: Master on/off switch
- `api_base`: API endpoint (usually should not change)
- `do_not_disturb`: Boolean toggle for Do Not Disturb mode (false if not active)

### `timing-state.json`
```json
{
  "last_hook_fire": 1712960000,
  "last_quest_shown": 1712959000,
  "daily_quest_count": 2,
  "daily_reset_date": "2025-04-12",
  "interactions_since_last_quest": 5
}
```

- `last_hook_fire`: Last time the stop hook was triggered
- `last_quest_shown`: Last time a quest was displayed
- `daily_quest_count`: Number of quests shown today
- `daily_reset_date`: Current date (YYYY-MM-DD) for daily reset logic
- `interactions_since_last_quest`: Counter for interaction-based frequency

### `tech-context.json` (auto-generated)
Cached tech stack tags extracted from CLAUDE.md and package.json. Used for context-aware quest matching.

### `last-quest.json` (auto-generated)
Stores the last quest shown, used by `/sidequest:retrigger`.

### `hook-errors.log`
Diagnostic log of errors. Manually delete if it grows too large.

## Need Help?

- Run `/sidequest:status` for a full health check
- Check `~/.sidequest/hook-errors.log` for diagnostic information
- Run `/sidequest:feedback` to report issues directly to the SideQuest team
