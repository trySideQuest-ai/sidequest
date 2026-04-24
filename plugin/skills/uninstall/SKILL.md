---
name: uninstall
description: "Fully remove SideQuest from this machine. Deletes the native app, plugin, auth token, local config, caches, and launchd agents. Use when the user asks 'uninstall sidequest', 'remove sidequest', 'delete sidequest', 'get rid of sidequest', or 'i don't want this anymore'."
---

# /sidequest:uninstall

Fully removes SideQuest (plugin + native app + local data) from this machine via the hosted uninstall script.

## What It Does

Runs `curl -fsSL https://get.trysidequest.ai/uninstall.sh | bash` which:

1. Stops the running native app
2. Deletes `~/Applications/SideQuestApp.app`
3. Removes the plugin from Claude Code plugins cache + deregisters from `~/.claude/settings.json`
4. Deletes `~/.sidequest/` (auth token, config, tech-context, sockets, timing state)
5. Removes any launchd agents, caches, and quarantine attributes
6. Verifies zero traces remain

Your account on the server stays intact — re-installing later restores access with the same login.

## Steps

### 1. Confirm with user

Before running, confirm intent:

> "This will remove the SideQuest app, plugin, auth token, and all local data on this machine. Your server-side account stays — if you reinstall later, your login still works. Proceed? (yes/no)"

If user says yes, proceed. Otherwise stop.

### 2. Run uninstaller

```bash
curl -fsSL https://get.trysidequest.ai/uninstall.sh | bash
```

Capture exit status. Uninstaller prints its own progress + final verification report.

### 3. Report outcome

If exit status `0`:

> "✓ SideQuest removed. If you change your mind, visit https://get.trysidequest.ai or run the install one-liner again."

If non-zero:

> "Uninstall reported errors (exit code {N}). Some traces may remain. Manual cleanup: `rm -rf ~/.sidequest ~/Applications/SideQuestApp.app` and check `~/.claude/settings.json` for a `sidequest` entry under `enabledPlugins`."

## Error Handling

- If user declines, stop immediately — do not run uninstaller
- If network unavailable, uninstaller will fail fast with curl exit code; suggest manual cleanup
- Never attempt partial file deletion from this skill — let the script do all removals for auditability
- Do not touch server-side state (user record, events) — uninstall is local-only by design
