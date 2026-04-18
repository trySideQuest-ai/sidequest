---
name: retrigger
description: Retrigger the last SideQuest notification on your screen
---

# Retrigger Last Quest

Re-display the most recent quest notification in the native SideQuest app.

## Steps

1. Read the last quest from the shared data directory:

```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.sidequest/last-quest.json')
if os.path.exists(path):
    with open(path) as f:
        print(f.read())
else:
    print('NO_LAST_QUEST')
"
```

2. If the output is `NO_LAST_QUEST`, say: "No recent quest to retrigger. A quest will be saved automatically the next time one appears."

3. Otherwise, parse the quest JSON and send it to the native app via IPC socket. Run the following, replacing each `<field>` with the actual value from the JSON (use defaults: `subtitle` empty, `reward_amount` 250, `brand_name` "Unknown", `category` "DevTool"):

```bash
python3 -c "
import json, socket, os, sys

payload = json.dumps({
    'questId': sys.argv[1],
    'trackingId': sys.argv[1],
    'display_text': sys.argv[2],
    'subtitle': sys.argv[3],
    'tracking_url': sys.argv[4],
    'reward_amount': int(sys.argv[5]),
    'brand_name': sys.argv[6],
    'category': sys.argv[7]
}).encode()

sock_path = os.path.expanduser('~/.sidequest/sidequest.sock')
if not os.path.exists(sock_path):
    print('SOCKET_NOT_FOUND')
    sys.exit(0)

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(2)
sock.connect(sock_path)
sock.sendall(payload)
sock.close()
print('OK')
" "<quest_id>" "<display_text>" "<subtitle>" "<tracking_url>" "<reward_amount>" "<brand_name>" "<category>"
```

4. If the output is `SOCKET_NOT_FOUND`, say: "Couldn't reach the SideQuest app. Make sure it's running."

5. If the output is `OK`, say: "Quest notification retriggered! You should see it on screen now."

6. If the script errors, say: "Couldn't reach the SideQuest app. Make sure it's running."
