---
name: quest
description: Respond to an active quest — open it, save for later, or skip
---

# Quest Response

Handle the user's response to an active SideQuest quest card. Use this when the user expresses interest, wants to save, or wants to skip — in natural language rather than pressing 1/2/0.

## Determine intent

From the conversation context, determine what the user wants:
- **open** — interested, wants to check it out (e.g. "yeah", "sure", "looks cool", "tell me more")
- **save** — wants to come back later (e.g. "save it", "maybe later", "bookmark that")
- **skip** — not interested (e.g. "nah", "pass", "not now")

## Execute

Read the active quest and perform the action:

For **open**:
```bash
ACTIVE="${CLAUDE_PLUGIN_DATA}/active-quest.json"
TRACKING_URL=$(python3 -c "import json; print(json.load(open('$ACTIVE'))['tracking_url'])")
open "$TRACKING_URL" 2>/dev/null || xdg-open "$TRACKING_URL" 2>/dev/null
rm -f "$ACTIVE"
```
Then say only: "Quest opened in your browser."

For **save**:
```bash
python3 -c "
import json, os
active_path = os.path.join(os.environ['CLAUDE_PLUGIN_DATA'], 'active-quest.json')
saved_dir = os.path.expanduser('~/.sidequest')
os.makedirs(saved_dir, exist_ok=True)
saved_path = os.path.join(saved_dir, 'saved-quests.json')
saved = json.load(open(saved_path)) if os.path.exists(saved_path) else []
quest = json.load(open(active_path))
saved.append(quest)
json.dump(saved, open(saved_path, 'w'), indent=2)
os.remove(active_path)
"
```
Then say only: "Quest saved for later."

For **skip**:
```bash
rm -f "${CLAUDE_PLUGIN_DATA}/active-quest.json"
```
Then say only: "Quest dismissed."

If `${CLAUDE_PLUGIN_DATA}/active-quest.json` does not exist, say: "No active quest right now."
