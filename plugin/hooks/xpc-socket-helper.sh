#!/bin/bash

# SideQuest IPC Socket Helper
# Sends quest data to native app via Unix domain socket
# Called by: plugin/hooks/stop-hook
# Args: quest_id tracking_id display_text subtitle tracking_url [reward_amount] [brand_name] [category]
# Exit: Always 0 (silent failure on any error)

QUEST_ID="$1"
TRACKING_ID="$2"
DISPLAY_TEXT="$3"
SUBTITLE="$4"
TRACKING_URL="$5"
REWARD_AMOUNT="${6:-250}"
BRAND_NAME="${7:-Unknown}"
CATEGORY="${8:-DevTool}"
SOCKET_PATH="$HOME/.sidequest/sidequest.sock"

# Validate required arguments
if [ -z "$QUEST_ID" ] || [ -z "$DISPLAY_TEXT" ]; then
  exit 0
fi

# Check if socket exists (app is running)
if [ ! -S "$SOCKET_PATH" ]; then
  exit 0
fi

# Build JSON and send via Unix socket using python3
# Single python3 call handles both JSON encoding and socket send
python3 -c "
import json, socket, sys, os

payload = json.dumps({
    'questId': sys.argv[1],
    'trackingId': sys.argv[2],
    'display_text': sys.argv[3],
    'subtitle': sys.argv[4],
    'tracking_url': sys.argv[5],
    'reward_amount': int(sys.argv[6]),
    'brand_name': sys.argv[7],
    'category': sys.argv[8]
}).encode()

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(2)
sock.connect(os.path.expanduser('~/.sidequest/sidequest.sock'))
sock.sendall(payload)
sock.close()
" "$QUEST_ID" "$TRACKING_ID" "$DISPLAY_TEXT" "$SUBTITLE" "$TRACKING_URL" "$REWARD_AMOUNT" "$BRAND_NAME" "$CATEGORY" 2>/dev/null

exit 0
