# SideQuest Plugin for Claude Code

Shows contextual quests inside your AI coding agent.

## Install

```
/plugin marketplace add sidequest-ai/sidequest-plugin
/plugin install sidequest@sidequest-ai
/sidequest:login
```

## Commands

- `/sidequest:login` — Authenticate with Google
- `/sidequest:feedback` — Share feedback about the quest experience

## Disable (without uninstalling)

Edit `$CLAUDE_PLUGIN_DATA/config.json` and set `"enabled": false`.

## Uninstall

```
/plugin uninstall sidequest@sidequest-ai
```
