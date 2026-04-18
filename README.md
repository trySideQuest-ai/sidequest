# SideQuest AI Client

**Developer-focused marketplace in your Claude Code editor**

SideQuest is a contextual quest system that displays relevant promotional opportunities directly in Claude Code. Developers earn money by engaging with quests—short, non-intrusive prompts that appear 3-5 times per day based on the technologies they're actively using.

This repository contains the complete source code for the SideQuest client: a Claude Code plugin that detects contextual moments to show quests, plus a native macOS app that ensures 100% delivery reliability without relying on the LLM to display notifications.

## Installation

```bash
curl -fsSL https://get.trysidequest.ai/install.sh | bash
```

This downloads and installs the plugin into Claude Code and the native macOS app.

## Available Skills

The plugin provides the following commands within Claude Code (use `/sidequest:{skill}` in Claude):

- **`/sidequest:login`** — Authenticate with your email to start earning
- **`/sidequest:check`** — Diagnose setup, verify connectivity, and troubleshoot issues
- **`/sidequest:status`** — View your account status and login information
- **`/sidequest:settings`** — Configure quest frequency and cooldown minutes
- **`/sidequest:earnings`** — View your earnings summary
- **`/sidequest:feedback`** — Report quest relevance to improve matching
- **`/sidequest:retrigger`** — Request an immediate quest (useful for testing)
- **`/sidequest:do-not-disturb`** — Toggle Do Not Disturb mode temporarily

## How It Works

### Plugin (Claude Code)

The plugin (`plugin/` directory) runs as a skill in Claude Code. It:
- Hooks into the end of your response using the `stop-hook` to detect when you finish a response
- Extracts contextual information about the technologies you're using
- Communicates with the SideQuest API to fetch relevant quests
- Sends IPC messages to the native macOS app for display
- Stores your preferences locally (~/.sidequest/)

### Native App (macOS)

The macOS app (`macOS/` directory) is a native notification application that:
- Listens on a local Unix socket for quest display requests
- Shows notifications that are visible but non-intrusive
- Prevents notification spam with frequency and cooldown controls
- Handles user interactions (view, dismiss, click-through to quest landing page)

## Security & Privacy

This repository contains the plugin and native app source code. **Before installing, audit the source code to verify it meets your security requirements.**

Key privacy principles:
- **Conversation content is never sent to the server** — only local technology tags are extracted
- **All state is local** — stored in `~/.sidequest/config.json` and `~/.sidequest/timing-state.json`
- **Network requests are minimal** — limited to API calls for quest fetching and event tracking

## Repository Structure

```
├── plugin/                  # Claude Code plugin source
│   ├── skills/             # Plugin skill definitions
│   │   ├── login/
│   │   ├── check/          # Diagnostic skill (renamed from doctor)
│   │   ├── status/
│   │   ├── settings/
│   │   ├── earnings/
│   │   ├── feedback/
│   │   ├── retrigger/
│   │   └── do-not-disturb/
│   ├── hooks/              # Claude Code hooks
│   │   ├── stop-hook       # Quest trigger (executes at end of response)
│   │   └── session-start   # Context extraction (executes at session start)
│   └── README.md           # Plugin-specific documentation
├── macOS/                   # Native macOS app source (Xcode project)
│   ├── SideQuestApp.xcodeproj
│   ├── SideQuestApp/
│   └── build/              # Build artifacts (gitignored)
├── LICENSE                 # MIT License
└── README.md               # This file
```

## Development & Building

See `plugin/README.md` for plugin development and testing instructions.

To build the macOS app, open `macOS/SideQuestApp.xcodeproj` in Xcode 15+ and build the target.

## License

MIT License — See LICENSE file for full text.

## Feedback

For issues, questions, or feature requests, please open a GitHub issue.
