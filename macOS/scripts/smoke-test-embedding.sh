#!/bin/bash
# Boot smoke test — proves the embedding pipeline works end-to-end on a real
# installed bundle. Catches the failure modes that have shipped at least
# once already (recursive dispatch_sync, modelVersion mismatch, force-cast
# on MLFeatureProvider). Run after every build, before tagging a release.
#
# Usage:
#   scripts/smoke-test-embedding.sh [path/to/SideQuestApp.app]
#
# Default app path: ~/Applications/SideQuestApp.app
#
# Exit codes:
#   0   PASS — app launched, bootstrap completed, IPC returned 768-dim
#       L2-normalized vector with no NaN
#   1   App bundle missing
#   2   App failed to launch / died during bootstrap
#   3   Bootstrap timeout (60s) — never logged "service wired"
#   4   IPC socket missing or no listener
#   5   IPC response missing user_vec / asst_vec or wrong dim
#   6   Vector contains NaN/Inf or L2 norm out of [0.97, 1.03]

set -uo pipefail

APP_PATH="${1:-$HOME/Applications/SideQuestApp.app}"
SOCKET="$HOME/.sidequest/sidequest.sock"
SUBSYSTEM="ai.sidequest.app"
BOOT_TIMEOUT_S=60
IPC_TIMEOUT_S=30

red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[1;33m%s\033[0m\n" "$*"; }

if [[ ! -d "$APP_PATH" ]]; then
  red "FAIL: app bundle not found at $APP_PATH"
  exit 1
fi

echo "Smoke test target: $APP_PATH"

# Clean slate
pkill -9 -f "SideQuestApp" 2>/dev/null || true
rm -f "$SOCKET"
sleep 1

# Launch
open -a "$APP_PATH"
sleep 2

PID="$(pgrep -f "SideQuestApp" | head -1 || true)"
if [[ -z "$PID" ]]; then
  red "FAIL: app did not launch"
  exit 2
fi
echo "App launched, PID=$PID"

# Wait for bootstrap. The log line is the durable signal that the
# embedding service is wired and IPC will return real vectors.
DEADLINE=$(( $(date +%s) + BOOT_TIMEOUT_S ))
BOOTSTRAP_LINE=""
while [[ $(date +%s) -lt $DEADLINE ]]; do
  if ! kill -0 "$PID" 2>/dev/null; then
    red "FAIL: app died during bootstrap (PID $PID gone)"
    yellow "Most recent crash report:"
    ls -t ~/Library/Logs/DiagnosticReports/SideQuestApp-*.ips 2>/dev/null | head -1 | xargs -I {} sh -c 'grep -oE "asi.*" {} | head -1'
    exit 2
  fi
  LINE="$(/usr/bin/log show --info \
    --predicate "subsystem == '$SUBSYSTEM' and processIdentifier == $PID" \
    --last 5m 2>/dev/null \
    | grep -E "service wired|model not available|tokenizer init failed|null-vector mode" \
    | tail -1)"
  if [[ -n "$LINE" ]]; then
    BOOTSTRAP_LINE="$LINE"
    break
  fi
  sleep 2
done

if [[ -z "$BOOTSTRAP_LINE" ]]; then
  red "FAIL: bootstrap timeout (${BOOT_TIMEOUT_S}s) — never logged completion"
  exit 3
fi

echo "Bootstrap log: $BOOTSTRAP_LINE"

if echo "$BOOTSTRAP_LINE" | grep -q "service wired"; then
  green "Bootstrap OK"
else
  red "FAIL: bootstrap reported degraded mode"
  exit 3
fi

# IPC liveness
if [[ ! -S "$SOCKET" ]]; then
  red "FAIL: IPC socket missing at $SOCKET"
  exit 4
fi

# Send embedding request, parse response
RESP_FILE="$(mktemp)"
echo '{"user_msg":"How do I deploy a Lambda function with the AWS CLI?","asst_msg":"Use aws lambda update-function-code --function-name foo --zip-file fileb://bundle.zip"}' \
  | nc -U -w "$IPC_TIMEOUT_S" "$SOCKET" > "$RESP_FILE"

if [[ ! -s "$RESP_FILE" ]]; then
  red "FAIL: IPC returned empty response (no listener? crashed during inference?)"
  exit 4
fi

echo "IPC response bytes: $(wc -c < "$RESP_FILE")"

# Validate via python: dim, NaN, L2 norm
python3 - "$RESP_FILE" << 'PY'
import json, math, sys
with open(sys.argv[1]) as f:
    try:
        d = json.load(f)
    except Exception as e:
        print(f"FAIL: response is not JSON: {e}")
        sys.exit(5)

ms = d.get("inference_ms")
u = d.get("user_vec")
a = d.get("asst_vec")
print(f"inference_ms={ms}")

for name, vec in (("user_vec", u), ("asst_vec", a)):
    if vec is None:
        print(f"FAIL: {name} is null — service likely degraded or input rejected")
        sys.exit(5)
    if len(vec) != 768:
        print(f"FAIL: {name} dim={len(vec)}, expected 768 (Gemma-300M)")
        sys.exit(5)
    if any(math.isnan(x) or math.isinf(x) for x in vec):
        print(f"FAIL: {name} contains NaN or Inf")
        sys.exit(6)
    norm = math.sqrt(sum(x * x for x in vec))
    if not (0.97 <= norm <= 1.03):
        print(f"FAIL: {name} L2 norm={norm:.4f}, expected ~1.0 (model output should be L2-normalized)")
        sys.exit(6)
    print(f"PASS: {name} dim=768, L2 norm={norm:.4f}, sample={[round(x,4) for x in vec[:3]]}")
PY
RC=$?
rm -f "$RESP_FILE"

if [[ $RC -ne 0 ]]; then
  exit $RC
fi

# Confirm app still alive (inference didn't crash it)
if ! kill -0 "$PID" 2>/dev/null; then
  red "FAIL: app died after returning IPC response"
  exit 2
fi

green "SMOKE TEST PASSED — embedding pipeline works end-to-end"
exit 0
