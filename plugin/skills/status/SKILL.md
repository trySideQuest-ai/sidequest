---
name: status
description: "Comprehensive SideQuest health check and diagnostic tool. Use this when the user asks 'is sidequest working', 'why no quests', 'sidequest not working', 'check sidequest', 'debug sidequest', 'sidequest health', 'diagnostics', 'what's wrong', 'not getting quests', 'sidequest status', or when diagnosing any issue with quest delivery."
---

# /sidequest:status

Comprehensive health check for SideQuest.

## Steps

Perform these checks in order and collect the results:

### 1. Authentication Status

Read the config file:

```bash
cat ~/.sidequest/config.json | python3 -c "
import sys, json
try:
    config = json.load(sys.stdin)
    token = config.get('token')
    if token:
        print('OK')
    else:
        print('NO_TOKEN')
except:
    print('NO_CONFIG')
"
```

- If output is `NO_TOKEN`: Auth status = "Not authenticated"
  - Add advice: "Run /sidequest:login to authenticate."
  
- If output is `NO_CONFIG`: Auth status = "Not configured"
  - Add advice: "Run /sidequest:login to set up SideQuest."
  
- If output is `OK`: Auth status = "Authenticated"

### 2. Native App Status

Test socket connection to the native app:

```bash
echo "" | nc -U -w1 ~/.sidequest/sidequest.sock 2>/dev/null && echo "RUNNING" || echo "NOT_RUNNING"
```

- If output is `RUNNING`: Native App status = "Running (socket connected)"
- If output is `NOT_RUNNING`: Native App status = "NOT RUNNING"
  - Add advice: "Quests can't be delivered. Run: open ~/Applications/SideQuestApp.app"

### 3. API Health

Test connectivity to the API:

```bash
curl -s --max-time 3 https://api.trysidequest.ai/health && echo "OK" || echo "FAILED"
```

- If output contains `OK`: API status = "Healthy"
- If output is `FAILED`: API status = "Unreachable"
  - Add advice: "Check your internet connection."

### 4. Last Quest Timing

Read timing state:

```bash
cat ~/.sidequest/timing-state.json 2>/dev/null | python3 -c "
import sys, json, time
try:
    data = json.load(sys.stdin)
    last_quest = data.get('last_quest_shown', 0)
    daily_count = data.get('daily_quest_count', 0)
    if last_quest:
        print(f'OK:{last_quest}:{daily_count}')
    else:
        print('NEVER')
except:
    print('NO_TIMING')
"
```

- If output is `NO_TIMING` or `NEVER`: Last Quest = "Never"
  - Add: "Your first quest will appear after a git commit or 10-minute coding gap."
  
- If output starts with `OK:`: Parse the timestamp and daily count
  - Convert the timestamp to human-readable format (e.g., "2 hours ago", "30 minutes ago", "today at 3:45 PM")
  - Display as: "Last Quest = {time_ago} ({daily_count}/5 today)"
  - If daily_count >= 5: Add note "Daily limit reached. Quests resume tomorrow."

### 5. Do Not Disturb Status

Check if Do Not Disturb is active:

```bash
cat ~/.sidequest/config.json | python3 -c "
import sys, json, time
try:
    config = json.load(sys.stdin)
    do_not_disturb = config.get('do_not_disturb')
    now = int(time.time())
    if do_not_disturb and do_not_disturb > now:
        remaining = do_not_disturb - now
        print(f'ACTIVE:{do_not_disturb}')
    else:
        print('OFF')
except:
    print('OFF')
"
```

- If output is `OFF`: Do Not Disturb status = "Off"
- If output starts with `ACTIVE:`: Parse the timestamp
  - Convert to human-readable resume time (e.g., "until 5:30 PM today")
  - Display as: "Do Not Disturb active until {time}"
  - Add: "Run /sidequest:do-not-disturb to cancel early."

### 6. Plugin Enabled/Disabled

Check the enabled flag:

```bash
cat ~/.sidequest/config.json | python3 -c "
import sys, json
try:
    config = json.load(sys.stdin)
    enabled = config.get('enabled', True)
    print('ENABLED' if enabled else 'DISABLED')
except:
    print('UNKNOWN')
"
```

- If output is `ENABLED`: Plugin status = "Enabled"
- If output is `DISABLED`: Plugin status = "Disabled"
  - Add advice: "Run /sidequest:settings enable to turn on quests."
- If output is `UNKNOWN`: Plugin status = "Unknown (config error)"

### 7. Error Log Check

Check for recent errors:

```bash
tail -5 ~/.sidequest/hook-errors.log 2>/dev/null | grep -c . || echo "0"
```

- If output is `0` or file doesn't exist: No recent errors
- If output is > 0: Tell the user: "Recent errors detected in ~/.sidequest/hook-errors.log"

## Display Format

Build the status display in this order:

```
SideQuest Status
================
Auth:       {status from step 1}
Native App: {status from step 2}
API:        {status from step 3}
Last Quest: {status from step 4}
DND:        {status from step 5}
Plugin:     {status from step 6}
```

Then add relevant advice:

**If everything is good:**
```
Everything operational. Next quest will appear after a git commit or 10-min gap.
```

**If native app is NOT RUNNING:**
```
⚠️  Native app not running — quests can't be delivered.
Fix: Run `open ~/Applications/SideQuestApp.app`
```

**If API is unreachable:**
```
⚠️  API unreachable — check your internet connection and try again.
```

**If not authenticated:**
```
⚠️  Not authenticated. Run /sidequest:login to set up SideQuest.
```

**If plugin is disabled:**
```
⚠️  Plugin is disabled. Run /sidequest:settings enable to resume.
```

**If DND is active:**
```
⚠️  Do Not Disturb active. Quests will resume at {resume_time}.
```

## Error Handling

- If any command fails unexpectedly, use safe defaults rather than erroring out
- If a file is missing, treat it as "not yet initialized" not as an error
- If socket connection fails, that's expected if the app isn't running — don't alarm
- Display helpful next steps for each issue
