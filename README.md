<picture>
  <img alt="SideQuest — the right tool, right when you need it" src="assets/banner.webp" width="100%">
</picture>

<h1 align="center">Contextual dev-tool discovery for Claude Code</h1>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#quests">Quests</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="BUILD.md">Verify Build</a> ·
  <a href="https://github.com/tomer-shavit/sidequest/issues">Issues</a>
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/github/license/tomer-shavit/sidequest">
  <img alt="macOS" src="https://img.shields.io/badge/platform-macOS%2013%2B-blue">
  <img alt="Plugin" src="https://img.shields.io/github/v/tag/tomer-shavit/sidequest?filter=plugin-v*&label=plugin">
</p>

SideQuest watches what you're working on inside Claude Code and surfaces one contextual dev-tool suggestion when it actually fits — a native macOS card you can dismiss with a keystroke, capped at 5 a day. No feed. No email. No LLM mediation. Conversation content stays on your machine; matching runs on anonymous IDs and on-device embeddings.

---

## Install

```bash
curl -fsSL https://get.trysidequest.ai/install.sh | bash
```

Installs the plugin into Claude Code, downloads the native macOS notification app, and runs Google OAuth (browser opens). macOS 13+ required.

That's it. Quests appear when context says they're useful.

Auditing the install script? See [BUILD.md](BUILD.md) — covers source review, SHA256 verification against the repo copy, and release-tag pinning.

---

<p align="center">
  <img alt="SideQuest quest card firing in Claude Code Desktop" src="assets/notification.png" width="100%">
</p>
<p align="center"><sub>A quest fires in the corner of Claude Code Desktop. Native, dismissable, capped at 5/day.</sub></p>

## Why SideQuest

- **Right tool, right moment.** While you're debugging Postgres, get a pointer to a faster connection pooler. Not a feed. Not a newsletter. A timed nudge inside the editor where you already are.
- **Native, not LLM-mediated.** Quests render through a real macOS notification card via the SideQuest app — 100% delivery. Doesn't depend on Claude choosing to surface anything.
- **Privacy by design.** Your words stay on your Mac. Only anonymous IDs and a local embedding of your last turn (text → numbers, on-device) reach our servers. See [Privacy](#privacy).
- **Cap-respected.** Max 5/day. 20-minute cooldown. One ⌘⌃D dismiss permanently mutes. Do-Not-Disturb is one slash command away.
- **Open + audit-ready.** MIT. Reproducible plugin tarballs. Source-pinned binaries. See [BUILD.md](BUILD.md) to verify.

## Quests

Skills available inside Claude Code:

| Skill | What it does |
|---|---|
| `/sidequest:sq-login` | Sign in with Google. One-time. |
| `/sidequest:sq-status` | Health check — auth, app, API, timing. Run first when stuck. |
| `/sidequest:sq-settings` | Toggle the plugin on or off. |
| `/sidequest:sq-do-not-disturb` | Pause quests for 2 hours. |
| `/sidequest:sq-retrigger` | Re-show the last quest. |
| `/sidequest:sq-feedback` | Send feedback. |
| `/sidequest:sq-reinstall` | Pull the latest plugin + app. |
| `/sidequest:sq-uninstall` | Remove everything. |

## Privacy

**What stays on your machine:**
- Conversation content (Claude messages, prompts, code)
- Project files, repo contents, file paths
- Anything Claude reads or writes

**What we send to the API (only when a quest fires):**
- Anonymous user ID (UUID, not your email)
- Anonymous session/tracking ID (UUID per quest)
- Anonymous tag IDs (e.g. `tag_4791` — never the source string)
- An on-device embedding of your last turn — your text is turned into a list of numbers locally on your Mac; only those numbers leave, never the words
- Quest engagement: shown / clicked / dismissed
- Plugin + app version (for compatibility checks)

**Storage on your machine:**
- `~/.sidequest/config.json` — auth token, settings
- `~/.sidequest/timing-state.json` — quest cap state
- `~/.sidequest/tech-context.json` — anonymized tag IDs
- `~/.sidequest/sidequest.sock` — Unix socket (plugin ↔ app)

**Code paths to inspect:**
- Outbound network calls: [`plugin/hooks/stop-hook`](plugin/hooks/stop-hook)
- On-device embedding (where text becomes numbers): [`macOS/SideQuestApp/Models/EmbeddingModel.swift`](macOS/SideQuestApp/Models/EmbeddingModel.swift)
- Tag anonymization: [`plugin/hooks/extract-context.py`](plugin/hooks/extract-context.py)

## How it works

**Plugin** (Claude Code hook). A stop-hook and session-start hook. Pulls anonymous tag IDs from your project context and hands your last turn to the native app for on-device embedding, then asks the API for the matching quest and passes it back to the app to display. Source: [`plugin/hooks/`](plugin/hooks/).

**Native app** (macOS). Embeds your last turn locally — text in, numbers out, words never leave the app. Renders each quest as a native floating card, top-right. Handles open/skip keyboard. Auto-launches at login. Source: [`macOS/`](macOS/).

**API.** Takes the anonymous IDs + the on-device embedding, returns one quest from the catalog. **Never sees your prompt content.**

## Updates + uninstall

Updates are silent. The session-start hook compares your installed plugin/app version against the latest published version and pulls the new tarball/DMG when they differ.

To remove everything:

```bash
curl -fsSL https://get.trysidequest.ai/uninstall.sh | bash
```

Or, in Claude Code:

```
/sidequest:sq-uninstall
```

## Verify the build

This repo publishes deterministic plugin tarballs and source-pinned macOS DMGs. Anyone can clone at a release tag, rebuild, and confirm the SHA256 matches the asset on GitHub Releases. See [BUILD.md](BUILD.md) for the step-by-step verification guide.

## Support

- Run `/sidequest:sq-status` for a self-diagnosis.
- Open an [issue](https://github.com/tomer-shavit/sidequest/issues) for bugs or feature requests.
- Email [71125175+tomer-shavit@users.noreply.github.com](mailto:71125175+tomer-shavit@users.noreply.github.com) for security disclosures (also see [SECURITY.md](SECURITY.md)).

## License

MIT — see [LICENSE](LICENSE).
