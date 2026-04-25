---
name: sq-feedback
description: Share feedback about the SideQuest quest experience
---

# SideQuest Feedback

Ask the user what feedback they'd like to share about the quest experience, then send it to the server.

1. Ask: "What feedback would you like to share about the quest experience?"
2. Read the auth token from `${CLAUDE_PLUGIN_DATA}/config.json`
3. Send the feedback using Bash:

```bash
curl -s -X POST https://api.trysidequest.ai/feedback \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"text": "<USER_FEEDBACK>"}'
```

4. Report success or failure to the user.

If no token exists, tell the user to run `/sidequest:sq-login` first.
