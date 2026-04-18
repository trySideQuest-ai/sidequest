---
name: earnings
description: "View your SideQuest earnings and payment status. Use this when the user asks 'how much did I earn', 'my earnings', 'sidequest balance', 'how many quests have I opened', 'payment status', 'total earnings', 'how much money', 'quest earnings', or wants to check their earnings dashboard."
---

# /sidequest:earnings

Display your SideQuest earnings summary.

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

3. If a token exists, call the earnings endpoint:

```bash
curl -s -H "Authorization: Bearer <TOKEN>" https://api.trysidequest.ai/user/earnings
```

4. Parse the JSON response. It should contain:
   - `total_clicks` — number of quests you've opened
   - `earned_nis` — total earnings in NIS (Israeli Shekel)
   - `payment_rate_nis` — how much you earn per quest opened

5. Display the earnings in this format:

```
SideQuest Earnings
==================
Quests Opened: {total_clicks}
Earned: {earned_nis} NIS
Rate: {payment_rate_nis} NIS per quest

Payment will be processed at the end of the beta period.
```

6. If the earned amount is 0, add an encouraging message:
   ```
   Get started by opening quests! Each quest you open earns {payment_rate_nis} NIS.
   ```

## Error Handling

- If the API returns a 401 or 403 error, tell the user: "Authentication failed. Run /sidequest:login again."
- If the API returns a 404 error, tell the user: "User not found. This might be a temporary issue — try again in a moment."
- If the API is unreachable or times out, tell the user: "Can't reach the earnings server. Check your internet connection and try again."
- If the response doesn't contain the expected fields, tell the user: "Earnings data is temporarily unavailable. Try again in a moment."
- If JSON parsing fails, tell the user: "Couldn't parse the earnings response. Try again in a moment."

## Implementation Note

The earnings endpoint is protected by bearer token authentication. The token must be included in the Authorization header exactly as `Bearer <TOKEN>`.
