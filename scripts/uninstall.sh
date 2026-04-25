#!/bin/bash

# SideQuest Unified Uninstall
#
# One command to remove everything:
#   curl -fsSL https://get.trysidequest.ai/uninstall.sh | bash
#
# Or run locally:
#   ./scripts/uninstall.sh
#
# This script removes:
#   - Native macOS app (SideQuestApp)
#   - Claude Code plugin (hooks + skills)
#   - Config, state, socket, saved quests
#   - Launch agent registration
#
# Flags:
#   --force       Skip confirmation prompt
#   --keep-config Keep ~/.sidequest/config.json (preserves auth token)

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────

APP_NAME="SideQuestApp"
BUNDLE_ID="ai.sidequest.app"
SIDEQUEST_DIR="$HOME/.sidequest"
CLAUDE_DIR="$HOME/.claude"
PLUGIN_MARKETPLACE="sidequest-plugin"
PLUGIN_KEY="sidequest@sidequest-plugin"
PLUGIN_CACHE_BASE="$CLAUDE_DIR/plugins/cache/$PLUGIN_MARKETPLACE"
PLUGIN_MARKETPLACE_DIR="$CLAUDE_DIR/plugins/marketplaces/$PLUGIN_MARKETPLACE"
PLUGIN_DATA_DIR="$CLAUDE_DIR/plugins/data/sidequest-sidequest-plugin"
PLUGIN_INLINE_DATA="$CLAUDE_DIR/plugins/data/sidequest-inline"
INSTALLED_PLUGINS="$CLAUDE_DIR/plugins/installed_plugins.json"
KNOWN_MARKETPLACES="$CLAUDE_DIR/plugins/known_marketplaces.json"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# Possible app install locations
APP_PATHS=(
  "$HOME/Applications/SideQuestApp.app"
  "/Applications/SideQuestApp.app"
  "/Applications/SideQuest.app"
  "$HOME/Applications/SideQuest.app"
)

FORCE=false
KEEP_CONFIG=false
REMOVED=()

# ─── Parse arguments ─────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case $1 in
    --force)       FORCE=true; shift ;;
    --keep-config) KEEP_CONFIG=true; shift ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: uninstall.sh [--force] [--keep-config]"
      exit 1
      ;;
  esac
done

# ─── Colors ──────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

# ─── Banner ──────────────────────────────────────────────────────────

echo ""
echo "  Uninstalling SideQuest"
echo "  ======================"
echo ""

# ─── Find installed app ─────────────────────────────────────────────

INSTALL_PATH=""
for p in "${APP_PATHS[@]}"; do
  if [ -d "$p" ]; then
    INSTALL_PATH="$p"
    break
  fi
done

APP_EXISTS=false
PLUGIN_EXISTS=false
CONFIG_EXISTS=false

[ -n "$INSTALL_PATH" ] && APP_EXISTS=true
[ -d "$PLUGIN_CACHE_BASE" ] && PLUGIN_EXISTS=true
[ -d "$SIDEQUEST_DIR" ] && CONFIG_EXISTS=true

if [ "$APP_EXISTS" = false ] && [ "$PLUGIN_EXISTS" = false ] && [ "$CONFIG_EXISTS" = false ]; then
  echo "  SideQuest is not installed. Nothing to remove."
  exit 0
fi

# ─── Confirm ─────────────────────────────────────────────────────────

if [ "$FORCE" = false ] && [ -t 0 ]; then
  echo "  This will remove:"
  [ "$APP_EXISTS" = true ] && echo "    - $INSTALL_PATH"
  [ "$PLUGIN_EXISTS" = true ] && echo "    - Claude Code plugin (hooks + skills)"
  [ "$CONFIG_EXISTS" = true ] && echo "    - ~/.sidequest/ (config, state, saved quests)"
  echo ""
  read -p "  Continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
  fi
  echo ""
fi

# ─── Step 1: Stop the app ───────────────────────────────────────────

echo -n "  Stopping app... "
pkill -f "SideQuestApp" 2>/dev/null || true
pkill -f "SideQuest.app" 2>/dev/null || true
sleep 1
echo -e "${GREEN}done${NC}"

# ─── Step 2: Remove app bundle ──────────────────────────────────────

if [ "$APP_EXISTS" = true ]; then
  echo -n "  Removing app... "
  if rm -rf "$INSTALL_PATH" 2>/dev/null; then
    REMOVED+=("$INSTALL_PATH")
    echo -e "${GREEN}done${NC}"
  else
    echo -e "${RED}failed${NC} — try: sudo rm -rf $INSTALL_PATH"
  fi
fi

# ─── Step 3: Remove launch agent ────────────────────────────────────

echo -n "  Removing launch agent... "
launchctl unload ~/Library/LaunchAgents/${BUNDLE_ID}.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/${BUNDLE_ID}.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/${BUNDLE_ID}*.plist 2>/dev/null || true
rm -f ~/.config/sidequest/launchagent.plist 2>/dev/null || true
REMOVED+=("launch agent")
echo -e "${GREEN}done${NC}"

# ─── Step 4: Deregister Claude Code plugin ──────────────────────────

echo -n "  Deregistering plugin... "

if [ -f "$SETTINGS_FILE" ]; then
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    # Remove from enabledPlugins
    data.get('enabledPlugins', {}).pop('$PLUGIN_KEY', None)
    # Remove from extraKnownMarketplaces
    data.get('extraKnownMarketplaces', {}).pop('$PLUGIN_MARKETPLACE', None)
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=4)
except Exception as e:
    print(f'warning: {e}', file=sys.stderr)
" "$SETTINGS_FILE" 2>/dev/null || true
fi

# Also clean installed_plugins.json if it exists
if [ -f "$INSTALLED_PLUGINS" ]; then
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    data.get('plugins', {}).pop('$PLUGIN_KEY', None)
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=4)
except: pass
" "$INSTALLED_PLUGINS" 2>/dev/null || true
fi

# Also clean known_marketplaces.json
if [ -f "$KNOWN_MARKETPLACES" ]; then
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    data.pop('$PLUGIN_MARKETPLACE', None)
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=4)
except: pass
" "$KNOWN_MARKETPLACES" 2>/dev/null || true
fi

REMOVED+=("plugin registration")
echo -e "${GREEN}done${NC}"

# ─── Step 5: Remove plugin files ────────────────────────────────────

if [ -d "$PLUGIN_CACHE_BASE" ]; then
  echo -n "  Removing plugin cache... "
  rm -rf "$PLUGIN_CACHE_BASE" 2>/dev/null || true
  REMOVED+=("plugin cache")
  echo -e "${GREEN}done${NC}"
fi

if [ -d "$PLUGIN_MARKETPLACE_DIR" ]; then
  echo -n "  Removing marketplace source... "
  rm -rf "$PLUGIN_MARKETPLACE_DIR" 2>/dev/null || true
  REMOVED+=("marketplace source")
  echo -e "${GREEN}done${NC}"
fi

# Remove plugin data directories
for data_dir in "$PLUGIN_DATA_DIR" "$PLUGIN_INLINE_DATA"; do
  if [ -d "$data_dir" ]; then
    echo -n "  Removing plugin data ($(basename "$data_dir"))... "
    rm -rf "$data_dir" 2>/dev/null || true
    REMOVED+=("$(basename "$data_dir")")
    echo -e "${GREEN}done${NC}"
  fi
done

# ─── Step 6: Remove config and state ────────────────────────────────

if [ "$CONFIG_EXISTS" = true ]; then
  if [ "$KEEP_CONFIG" = true ]; then
    echo -e "  Config preserved ${DIM}(--keep-config)${NC}"
    # Still remove non-config files
    rm -f "$SIDEQUEST_DIR/sidequest.sock" 2>/dev/null || true
    rm -f "$SIDEQUEST_DIR/saved-quests.json" 2>/dev/null || true
    rm -f "$SIDEQUEST_DIR/last-quest.json" 2>/dev/null || true
    rm -f "$SIDEQUEST_DIR/debug.log" 2>/dev/null || true
    REMOVED+=("state files (config preserved)")
  else
    echo -n "  Removing config and state... "
    rm -rf "$SIDEQUEST_DIR" 2>/dev/null || true
    REMOVED+=("~/.sidequest/")
    echo -e "${GREEN}done${NC}"
  fi
fi

# ─── Step 7: Remove caches and preferences ──────────────────────────

echo -n "  Removing caches... "
rm -rf ~/Library/Caches/${BUNDLE_ID}* 2>/dev/null || true
rm -rf ~/Library/Preferences/${BUNDLE_ID}* 2>/dev/null || true
rm -rf ~/Library/Application\ Support/SideQuest 2>/dev/null || true
rm -rf ~/Library/Application\ Support/${BUNDLE_ID} 2>/dev/null || true
rm -rf ~/.config/sidequest 2>/dev/null || true
REMOVED+=("caches and preferences")
echo -e "${GREEN}done${NC}"

# ─── Step 8: Verify removal ─────────────────────────────────────────

echo ""
echo -n "  Verifying... "
DIRTY=0

# App
for p in "${APP_PATHS[@]}"; do
  [ -d "$p" ] && DIRTY=$((DIRTY + 1))
done
# Process
pgrep -f "$APP_NAME" >/dev/null 2>&1 && DIRTY=$((DIRTY + 1))
# Socket + config
[ -S "$SIDEQUEST_DIR/sidequest.sock" ] && DIRTY=$((DIRTY + 1))
[ "$KEEP_CONFIG" = false ] && [ -d "$SIDEQUEST_DIR" ] && DIRTY=$((DIRTY + 1))
# Plugin files
[ -d "$PLUGIN_CACHE_BASE" ] && DIRTY=$((DIRTY + 1))
[ -d "$PLUGIN_MARKETPLACE_DIR" ] && DIRTY=$((DIRTY + 1))
[ -d "$PLUGIN_DATA_DIR" ] && DIRTY=$((DIRTY + 1))
[ -d "$PLUGIN_INLINE_DATA" ] && DIRTY=$((DIRTY + 1))
# Plugin registration in settings.json
if [ -f "$SETTINGS_FILE" ]; then
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
ep = '$PLUGIN_KEY' in d.get('enabledPlugins', {})
ekm = '$PLUGIN_MARKETPLACE' in d.get('extraKnownMarketplaces', {})
sys.exit(1 if ep or ekm else 0)
" "$SETTINGS_FILE" 2>/dev/null || DIRTY=$((DIRTY + 1))
fi
# known_marketplaces.json
if [ -f "$KNOWN_MARKETPLACES" ]; then
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(1 if '$PLUGIN_MARKETPLACE' in d else 0)
" "$KNOWN_MARKETPLACES" 2>/dev/null || DIRTY=$((DIRTY + 1))
fi
# installed_plugins.json
if [ -f "$INSTALLED_PLUGINS" ]; then
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(1 if '$PLUGIN_KEY' in d.get('plugins', {}) else 0)
" "$INSTALLED_PLUGINS" 2>/dev/null || DIRTY=$((DIRTY + 1))
fi

if [ "$DIRTY" -eq 0 ]; then
  echo -e "${GREEN}clean${NC}"
else
  echo -e "${RED}$DIRTY traces remain${NC}"
fi

# ─── Summary ─────────────────────────────────────────────────────────

echo ""
echo "  ================================================"
if [ "$DIRTY" -eq 0 ]; then
  echo -e "  ${GREEN}SideQuest has been completely removed.${NC}"
else
  echo -e "  ${YELLOW}SideQuest removed with $DIRTY leftover(s) — re-run or remove manually.${NC}"
fi
echo "  ================================================"
echo ""
echo "  Removed:"
for item in "${REMOVED[@]}"; do
  echo "    - $item"
done
echo -e "  ${YELLOW}Restart any open Claude Code sessions to clear cached hooks.${NC}"
echo ""
echo "  To reinstall:"
echo "    curl -fsSL https://get.trysidequest.ai/install.sh | bash"
echo ""
