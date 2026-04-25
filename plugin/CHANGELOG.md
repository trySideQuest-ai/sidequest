# Plugin Changelog

## 0.10.1 — 2026-04-27

- feat: capture `client_version` (plugin VERSION + macOS app `CFBundleShortVersionString`) in `/quest` payload so the analytics dashboard can break out plugin/app version distribution.
- feat: measure IPC round-trip duration around the embed call in `hooks/stop-hook` and report it as `inference_ms`. Server records both fields in `events.metadata`; missing values record null on the server side, so older plugins continue to work unchanged.

## 0.10.0 — 2026-04-26

- feat: stop-hook PHASE 6.5 IPC vector injection — sends last user/assistant message to native app and forwards 2x384-dim embeddings to `/quest`.
- feat: read `~/.sidequest/remote-config.json` first; remote kill-switch + cooldown + daily cap apply globally.
