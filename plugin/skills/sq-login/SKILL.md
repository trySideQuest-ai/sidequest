---
name: sq-login
description: Authenticate with SideQuest using Google OAuth
---

# SideQuest Login

Run the OAuth login script to authenticate with Google:

1. Execute the following command using Bash:

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/oauth-login.js"
```

2. A browser window will open for Google authentication.
3. After authenticating, the token is saved automatically.
4. Report the result to the user.

If the script fails, tell the user to check their internet connection and try again.
