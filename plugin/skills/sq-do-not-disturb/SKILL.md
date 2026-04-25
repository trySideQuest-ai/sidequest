---
name: sq-do-not-disturb
description: "Do Not Disturb mode — pause quests for 2 hours. Use this when the user says 'stop showing me stuff', 'too many quests', 'quest fatigue', 'these are annoying', 'I'm getting too many notifications', 'not now', 'leave me alone', 'stop interrupting', 'I need a break', 'pause quests for a bit', 'quiet mode', 'mute notifications', or expresses frustration about quest frequency."
---

# /sidequest:sq-do-not-disturb

Pause quests for 2 hours, or cancel an active timer.

## Steps

1. Read the current config:

```bash
cat ~/.sidequest/config.json
```

2. Check the current value of `do_not_disturb` in the config.

3. Decide action:
   - If `do_not_disturb` is set and the timestamp is **in the future** → the user wants to **cancel**. Remove the field.
   - Otherwise → the user wants to **activate**. Set `do_not_disturb` to current time + 7200 (2 hours).

4. To **activate**, update the config using Python:

```bash
python3 -c "
import json, os, time, tempfile
config_path = os.path.expanduser('~/.sidequest/config.json')
with open(config_path) as f:
    config = json.load(f)
config['do_not_disturb'] = int(time.time()) + 7200
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config_path))
with os.fdopen(fd, 'w') as f:
    json.dump(config, f, indent=2)
os.rename(tmp, config_path)
"
```

5. To **cancel**, update the config using Python:

```bash
python3 -c "
import json, os, tempfile
config_path = os.path.expanduser('~/.sidequest/config.json')
with open(config_path) as f:
    config = json.load(f)
config.pop('do_not_disturb', None)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config_path))
with os.fdopen(fd, 'w') as f:
    json.dump(config, f, indent=2)
os.rename(tmp, config_path)
"
```

6. Display confirmation:

If activated:
```
Do Not Disturb: ON
==================
Quests paused for 2 hours.
Resumes at: {human_readable_time}

Run /sidequest:sq-do-not-disturb again to cancel early.
```

If cancelled:
```
Do Not Disturb: OFF
===================
Quests will resume normally.
```

## Error Handling

- If `~/.sidequest/config.json` doesn't exist, tell the user: "SideQuest not configured. Run /sidequest:sq-login first."
- If JSON parsing fails, tell the user: "Config file is corrupted. Run /sidequest:sq-login to reset."

## Implementation Note

The stop-hook checks `do_not_disturb` automatically. It stores a Unix timestamp — quests are suppressed while current time < timestamp. Once the timer expires, quests resume without any action needed.
