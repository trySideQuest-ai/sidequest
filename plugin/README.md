# SideQuest Plugin (Contributor Reference)

Internal docs for the plugin. End users should read the [top-level README](../README.md).

## What this is

A Claude Code plugin (`stop-hook` + `session-start` hooks plus skills) that ships local context to the SideQuest API and forwards selected quests to the native macOS app over a Unix socket.

## Dependencies

| Dependency | Required Version | Purpose |
|---|---|---|
| python3 | 3.8+ | JSON parsing, context extraction, atomic file I/O |
| curl | any | API communication |
| Node.js | 20+ | OAuth login flow |
| git | any | Commit detection, diff-based context extraction |
| nc (netcat) | any (macOS built-in) | IPC socket health check |
| macOS | 13.0+ (Ventura) | Required for SMAppService and native app |

## Skills

Source under `plugin/skills/`. Each skill is a directory with a `SKILL.md` (frontmatter + body). Skills with the `sq-` prefix are canonical; bare names are alias stubs that forward to their `sq-<name>` counterpart for muscle-memory backwards compatibility.

| Canonical skill | Forwards from | What it does |
|---|---|---|
| `sq-login` | `login` | OAuth via Google, writes the token to `~/.sidequest/config.json` |
| `sq-status` | `status`, `check` | Diagnostic — auth, app, API, timing, DND |
| `sq-settings` | `settings` | Plugin on/off toggle |
| `sq-do-not-disturb` | `do-not-disturb` | 2-hour pause |
| `sq-retrigger` | `retrigger` | Re-show last quest |
| `sq-feedback` | `feedback` | Send feedback |
| `sq-reinstall` | `reinstall` | Pull latest plugin + app from remote-config.json |
| `sq-uninstall` | `uninstall` | Wipe everything |

## Quest triggers + frequency

Quests appear in two scenarios:

1. **After a Claude response** — the stop-hook fires and decides whether to show a quest.
2. **After inactivity** — if you've been idle in Claude for 10 minutes, a quest can be shown on next interaction.

Hard caps:

- **Max 5 quests/day** — counter resets at midnight (local time).
- **Min 20 minutes between quests** — cooldown prevents fatigue.
- **Interaction-based frequency** — by default, every 10 interactions; configurable.
- **Do Not Disturb** — `/sidequest:sq-do-not-disturb` pauses for 2 hours.

## Context extraction

When a quest is selected, the plugin extracts two layers of context:

1. **Static context** — tech stack from `CLAUDE.md` and `package.json`.
2. **Dynamic context** — recent git commit message and changed-file paths.

Both layers are mapped to anonymous tag IDs locally. **The source strings never leave your machine.** Only the tag IDs travel to the API.

## Local files

- `~/.sidequest/config.json` — auth token, settings, DND flag
- `~/.sidequest/timing-state.json` — daily counter, cooldown, last-shown timestamp
- `~/.sidequest/tech-context.json` — cached anonymized tag IDs
- `~/.sidequest/sidequest.sock` — Unix socket (plugin ↔ native app)
- `~/.sidequest/last-quest.json` — last quest shown (for `sq-retrigger`)
- `~/.sidequest/hook-errors.log` — diagnostic log (auto-truncated at 100KB)

## Troubleshooting (beyond `/sidequest:sq-status`)

`/sidequest:sq-status` covers auth, app, API, and timing diagnostics. The cases below are not yet automated:

### Gatekeeper blocks the app

macOS may block the unsigned third-party app on first launch. Three options:

1. **Allow via System Settings.** Open System Settings → Privacy & Security → scroll to "SideQuestApp was blocked" → "Open Anyway".
2. **Remove the quarantine attribute:**
   ```bash
   xattr -cr ~/Applications/SideQuestApp.app
   ```
3. (Not recommended.) Disable Gatekeeper globally: `sudo spctl --master-disable`.

### Auto-launch fails (app does not start at login)

If the app does not start when you log in to macOS:

1. System Settings → General → Login Items → look for `SideQuestApp` in the "Allow in the Login Items" list.
2. If missing, click `+` and select `~/Applications/SideQuestApp.app`.
3. The launchd plist at `~/Library/LaunchAgents/ai.sidequest.app.plist` handles KeepAlive — the app restarts on crash.

### Hook errors log

`~/.sidequest/hook-errors.log` captures config parse errors, API failures, socket failures, and timing-state errors. Auto-truncated at 100KB. To inspect recent issues:

```bash
tail -20 ~/.sidequest/hook-errors.log
```

## Disable + uninstall

**Pause:** `/sidequest:sq-do-not-disturb`.

**Disable:** `/sidequest:sq-settings`, then "disable". Sets `"enabled": false` in `~/.sidequest/config.json`. Re-enable the same way.

**Full uninstall:**
```bash
curl -fsSL https://get.trysidequest.ai/uninstall.sh | bash
```
Or `/sidequest:sq-uninstall` inside Claude Code.

Add `--keep-config` to the uninstall script to preserve the auth token for an easy reinstall.

## Tests

```bash
cd plugin
pytest -v
```

Layout:
- `tests/test_skill_renames.py` — sq- skill structure + alias stubs
- `tests/test_extract_context.py` — context extraction logic
- `tests/test_auto_update.py` — version compare, SHA256 verify, atomic swap
- `tests/test_remote_config.py` — remote config fetch + cache + fallback
- `tests/test_plugin_disabled.py` — `plugin_disabled` event one-shot
