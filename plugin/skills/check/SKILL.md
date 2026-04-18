---
name: check
description: "Full diagnostic check for SideQuest — verifies auth token, native app running, socket responding, API reachable, config valid, remote config cached, DND status. Use when the user asks 'sidequest check', 'check sidequest', 'full check', 'why aren't quests working', 'debug my setup', or 'run diagnostics'."
---

# /sidequest:check

Full diagnostic check for SideQuest with fix suggestions for every issue.

## Steps

Run ALL checks below and collect results. Every check must produce a status line and optional fix suggestion.

### 1. Auth Token

```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.sidequest/config.json')
if not os.path.isfile(path):
    print('NO_CONFIG')
else:
    try:
        with open(path) as f:
            c = json.load(f)
        token = c.get('token', '')
        if token and len(token) == 64:
            print('OK')
        elif token:
            print('INVALID_FORMAT')
        else:
            print('MISSING')
    except json.JSONDecodeError:
        print('CORRUPT')
"
```

| Output | Status | Fix |
|--------|--------|-----|
| OK | Auth token valid (64-char hex) | — |
| NO_CONFIG | Config file missing | Run `/sidequest:login` |
| MISSING | Token not set | Run `/sidequest:login` |
| INVALID_FORMAT | Token format unexpected | Run `/sidequest:login` to re-authenticate |
| CORRUPT | Config JSON corrupted | Delete `~/.sidequest/config.json` and run `/sidequest:login` |

### 2. Native App Running

```bash
pgrep -f SideQuestApp > /dev/null 2>&1 && echo "RUNNING" || echo "NOT_RUNNING"
```

| Output | Status | Fix |
|--------|--------|-----|
| RUNNING | Native app running | — |
| NOT_RUNNING | Not running | Run: `open ~/Applications/SideQuestApp.app` |

### 3. Socket Responding

```bash
echo "" | nc -U -w1 ~/.sidequest/sidequest.sock 2>/dev/null && echo "OK" || echo "NO_RESPONSE"
```

| Output | Status | Fix |
|--------|--------|-----|
| OK | Socket accepting connections | — |
| NO_RESPONSE | Socket not responding | Restart the native app: `pkill SideQuestApp; sleep 1; open ~/Applications/SideQuestApp.app` |

### 4. API Reachable

```bash
curl -s --max-time 3 -o /dev/null -w "%{http_code}" https://api.trysidequest.ai/health
```

| Output | Status | Fix |
|--------|--------|-----|
| 200 | API healthy | — |
| Other | API unreachable (HTTP {code}) | Check internet connection. If persistent, API may be down. |
| Empty/timeout | API unreachable | Check internet connection |

### 5. Config Validity

```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.sidequest/config.json')
if not os.path.isfile(path):
    print('MISSING')
else:
    try:
        with open(path) as f:
            c = json.load(f)
        required = ['token']
        missing = [k for k in required if not c.get(k)]
        if missing:
            print(f'INCOMPLETE:{','.join(missing)}')
        else:
            print('VALID')
    except:
        print('CORRUPT')
"
```

| Output | Status | Fix |
|--------|--------|-----|
| VALID | Config valid | — |
| MISSING | Config file missing | Run `/sidequest:login` |
| INCOMPLETE:... | Missing fields: {fields} | Run `/sidequest:login` to regenerate config |
| CORRUPT | Config JSON corrupted | Delete `~/.sidequest/config.json` and run `/sidequest:login` |

### 6. Remote Config Cached

```bash
python3 -c "
import json, os, time
path = os.path.expanduser('~/.sidequest/remote-config.json')
if not os.path.isfile(path):
    print('MISSING')
else:
    try:
        mtime = os.path.getmtime(path)
        age_hours = (time.time() - mtime) / 3600
        with open(path) as f:
            rc = json.load(f)
        enabled = rc.get('enabled', True)
        version = rc.get('plugin_version', 'unknown')
        print(f'OK:{age_hours:.1f}h:{version}:{enabled}')
    except:
        print('CORRUPT')
"
```

| Output | Status | Fix |
|--------|--------|-----|
| OK:... | Cached ({age}h old, v{version}, enabled={enabled}) | — |
| MISSING | No cached remote config | Will be fetched on next session start |
| CORRUPT | Remote config corrupted | Delete `~/.sidequest/remote-config.json` — will re-fetch |

### 7. DND Status

```bash
python3 -c "
import json, os, time
path = os.path.expanduser('~/.sidequest/config.json')
try:
    with open(path) as f:
        c = json.load(f)
    dnd = c.get('do_not_disturb', 0)
    now = int(time.time())
    if dnd and dnd > now:
        remaining_min = (dnd - now) // 60
        print(f'ACTIVE:{remaining_min}')
    else:
        print('OFF')
except:
    print('OFF')
"
```

| Output | Status | Fix |
|--------|--------|-----|
| OFF | Do Not Disturb off | — |
| ACTIVE:{min} | Do Not Disturb active ({min} minutes remaining) | Run `/sidequest:do-not-disturb` to cancel |

### 8. Error Log

```bash
python3 -c "
import os
path = os.path.expanduser('~/.sidequest/hook-errors.log')
if not os.path.isfile(path):
    print('CLEAN')
else:
    size = os.path.getsize(path)
    with open(path) as f:
        lines = f.readlines()
    recent = [l.strip() for l in lines[-3:] if l.strip()]
    if recent:
        print(f'ERRORS:{len(lines)}')
        for l in recent:
            print(f'  {l}')
    else:
        print('CLEAN')
"
```

| Output | Status | Fix |
|--------|--------|-----|
| CLEAN | No errors logged | — |
| ERRORS:{count} | {count} entries in error log | Review `~/.sidequest/hook-errors.log` for details |

## Display Format

Present results as a diagnostic report:

```
SideQuest Check
═══════════════

  Auth Token:    {status}
  Native App:    {status}
  Socket:        {status}
  API:           {status}
  Config:        {status}
  Remote Config: {status}
  DND:           {status}
  Error Log:     {status}

{If all OK:}
  All systems operational. Quests will appear after git commits or 10-min coding gaps.

{If issues found:}
  Issues Found:
  1. {issue} — Fix: {fix suggestion}
  2. {issue} — Fix: {fix suggestion}
```

## Error Handling

- If any check command fails, report that check as "Unknown" with advice to retry
- Never let a diagnostic check crash — catch all errors and report gracefully
- If multiple issues found, list them all with numbered fix suggestions
