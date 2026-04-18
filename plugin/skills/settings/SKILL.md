---
name: settings
description: "Enable or disable SideQuest quests. Use this when the user says 'turn off quests', 'stop sidequest', 'enable sidequest', 'disable the plugin', 'turn off the plugin', 'disable quests', 'stop showing quests', 'I want to pause quests permanently', 'disable the sidequest plugin', or similar requests to permanently toggle the plugin on/off."
---

# /sidequest:settings

Enable or disable the SideQuest plugin.

## Steps

1. Read the config file:

```bash
cat ~/.sidequest/config.json
```

2. Parse the JSON and check the current `enabled` value (true or false).

3. If the user says "enable" or "on":
   - Update `enabled` to `true`
   
4. If the user says "disable" or "off":
   - Update `enabled` to `false`

5. Write the updated config back using Python:

```bash
python3 -c "
import json, os, tempfile
config_path = os.path.expanduser('~/.sidequest/config.json')
with open(config_path) as f:
    config = json.load(f)
config['enabled'] = <NEW_VALUE>
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config_path))
with os.fdopen(fd, 'w') as f:
    json.dump(config, f, indent=2)
os.rename(tmp, config_path)
"
```

6. Display the new status to the user:

```
SideQuest Plugin Status
======================
Plugin: <ENABLED or DISABLED>
```

7. If enabled, add:
   ```
   Quests will appear while you code.
   ```

8. If disabled, add:
   ```
   Quests are paused. Run /sidequest:settings enable to resume.
   ```

## Error Handling

- If `~/.sidequest/config.json` doesn't exist, tell the user: "SideQuest not configured. Run /sidequest:login first."
- If JSON parsing fails, tell the user: "Config file is corrupted. Run /sidequest:login to reset."
