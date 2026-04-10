---
name: saved
description: View all your saved SideQuest quests
---

# Saved Quests

Display all quests the user has saved for later. Quests may be saved from either the native app or the plugin.

## Steps

1. Read saved quests from both possible locations using Bash:

```bash
python3 -c "
import json, os

paths = [
    os.path.expanduser('~/.sidequest/saved-quests.json'),
    os.path.join(os.environ.get('CLAUDE_PLUGIN_DATA', ''), 'saved-quests.json')
]

seen_ids = set()
all_quests = []

for p in paths:
    if os.path.exists(p):
        try:
            with open(p) as f:
                quests = json.load(f)
            for q in quests:
                qid = q.get('quest_id', '')
                if qid and qid not in seen_ids:
                    seen_ids.add(qid)
                    all_quests.append(q)
        except: pass

if not all_quests:
    print('NO_SAVED_QUESTS')
else:
    print(json.dumps(all_quests, indent=2))
"
```

2. If the output is `NO_SAVED_QUESTS`, say: "You don't have any saved quests yet. When a quest appears, press **Save** or use **Cmd+Ctrl+S** to save it for later."

3. Otherwise, display the quests in a clean table or list format showing:
   - Quest title (`display_text`)
   - Brand/sponsor (`brand_name` or `sponsor_name`)
   - Category (if available)
   - Tracking URL
   - When it was saved (`saved_at` if available)

4. After listing, remind the user they can open any quest by clicking the tracking URL.
