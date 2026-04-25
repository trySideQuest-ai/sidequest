---
name: sq-reinstall
description: "Reinstall SideQuest to the latest version. Downloads the latest plugin + native app via the hosted installer and replaces your current installation. Use when the user asks 'update sidequest', 'upgrade sidequest', 'reinstall sidequest', 'get the latest version', or sees an update-available banner at session start."
---

# /sidequest:sq-reinstall

Reinstalls SideQuest (plugin + native app) to the latest version by re-running the hosted installer.

## What It Does

Runs `curl -fsSL https://get.trysidequest.ai/install.sh | bash` which:

1. Downloads the latest native app DMG, mounts it, copies to `~/Applications/`
2. Downloads the latest plugin tarball, extracts to Claude plugins cache, registers in Claude config
3. Preserves your existing `~/.sidequest/config.json` (auth token, preferences)
4. Verifies installation end-to-end

## Steps

### 1. Confirm with user

Before running, confirm intent:

> "This will download and reinstall the latest SideQuest (plugin + native app). Your login and settings will be preserved. Proceed? (yes/no)"

If user says yes, proceed. Otherwise stop.

### 2. Run installer

```bash
curl -fsSL https://get.trysidequest.ai/install.sh | bash
```

Capture exit status. Installer prints its own progress.

### 3. Report outcome

If exit status `0`:

> "✓ Reinstall complete. Run `/sidequest:sq-status` to verify everything is working."

If non-zero:

> "Reinstall failed (exit code {N}). Run `/sidequest:sq-status` to see which component failed. You can try again by running `/sidequest:sq-reinstall`."

## Error Handling

- If user declines, stop immediately — do not run installer
- If installer fails mid-run, do not attempt partial recovery — let user re-run after diagnosis
- If network unavailable, installer will fail fast with curl exit code
- Never modify `~/.sidequest/config.json` manually — the installer preserves it by design
