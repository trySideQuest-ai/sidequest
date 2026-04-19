---
name: earnings
description: "View how many SideQuest quests you've opened. Use when user asks 'how many quests have I opened', 'my quest count', 'sidequest activity', 'quest stats', or wants to check their quest activity."
---

# /sidequest:earnings

Display your SideQuest quest activity.

## Steps

1. Read the auth token from the config file:

```bash
cat ~/.sidequest/config.json | python3 -c "
import sys, json
try:
    config = json.load(sys.stdin)
    print(config.get('token', ''))
except:
    print('')
"
```

2. If no token is returned, tell the user: "Not authenticated. Run /sidequest:login first."

3. If a token exists, call the endpoint:

```bash
curl -s -H "Authorization: Bearer <TOKEN>" https://api.trysidequest.ai/user/earnings
```

4. Parse the JSON response. It should contain:
   - `total_clicks` — number of quests you've opened

5. Display the activity in this format:

```
SideQuest Activity
==================
Quests Opened: {total_clicks}
```

6. If `total_clicks` is 0, add an encouraging message:
   ```
   Get started by opening quests!
   ```

## Error Handling

- If the API returns a 401 or 403 error, tell the user: "Authentication failed. Run /sidequest:login again."
- If the API returns a 404 error, tell the user: "User not found. This might be a temporary issue — try again in a moment."
- If the API is unreachable or times out, tell the user: "Can't reach the server. Check your internet connection and try again."
- If the response doesn't contain the expected fields, tell the user: "Activity data is temporarily unavailable. Try again in a moment."
- If JSON parsing fails, tell the user: "Couldn't parse the response. Try again in a moment."

## Implementation Note

The endpoint is protected by bearer token authentication. The token must be included in the Authorization header exactly as `Bearer <TOKEN>`.
