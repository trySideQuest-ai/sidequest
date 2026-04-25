#!/bin/bash

# SideQuest Unified Installer
#
# One command to install everything:
#   curl -fsSL https://get.trysidequest.ai/install.sh | bash
#
# Or run locally:
#   ./scripts/install.sh
#
# Local testing (uses built DMG from macOS/build/):
#   ./scripts/install.sh --local
#
# This script:
#   1. Downloads and installs the native macOS app
#   2. Installs the Claude Code plugin (hooks + skills)
#   3. Runs OAuth login (opens browser)
#   4. Verifies end-to-end connectivity
#
# Flags:
#   --skip-login     Skip OAuth login step
#   --skip-verify    Skip verification step
#   --local          Use local build artifacts instead of downloading from S3
#   --version X.Y.Z  Install specific app version (default: latest)
#   --uninstall      Remove everything (shortcut for uninstall.sh)

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────

DMG_BUCKET="https://get.trysidequest.ai"
PLUGIN_BUCKET="https://get.trysidequest.ai"
REMOTE_CONFIG_URL="https://get.trysidequest.ai/config.json"
VERSION="latest"
# PLUGIN_VERSION + PLUGIN_TAR_URL + PLUGIN_SHA256 are resolved from
# the remote config after argument parsing. Fallback to 0.2.0 if fetch fails.
PLUGIN_VERSION="0.2.0"
PLUGIN_TAR_URL=""
PLUGIN_SHA256=""
APP_NAME="SideQuestApp"
INSTALL_DIR="$HOME/Applications"
INSTALL_PATH="$INSTALL_DIR/SideQuestApp.app"
BUNDLE_ID="ai.sidequest.app"
SIDEQUEST_DIR="$HOME/.sidequest"
CLAUDE_DIR="$HOME/.claude"
PLUGIN_MARKETPLACE="sidequest-plugin"
PLUGIN_KEY="sidequest@sidequest-plugin"
PLUGIN_MARKETPLACE_DIR="$CLAUDE_DIR/plugins/marketplaces/$PLUGIN_MARKETPLACE"
PLUGIN_DATA_DIR="$CLAUDE_DIR/plugins/data/sidequest-sidequest-plugin"
INSTALLED_PLUGINS_FILE="$CLAUDE_DIR/plugins/installed_plugins.json"
KNOWN_MARKETPLACES_FILE="$CLAUDE_DIR/plugins/known_marketplaces.json"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
API_BASE="https://api.trysidequest.ai"

SKIP_LOGIN=false
SKIP_VERIFY=false
LOCAL_MODE=false
COMPLETED_STEPS=()

# Resolve script directory for --local mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Parse arguments ─────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-login)   SKIP_LOGIN=true; shift ;;
    --skip-verify)  SKIP_VERIFY=true; shift ;;
    --local)        LOCAL_MODE=true; shift ;;
    --version)      VERSION="$2"; shift 2 ;;
    --uninstall)
      if [ "$LOCAL_MODE" = true ]; then
        bash "$SCRIPT_DIR/uninstall.sh" --force
      else
        SCRIPT_URL="https://get.trysidequest.ai/uninstall.sh"
        curl -fsSL "$SCRIPT_URL" | bash
      fi
      exit $?
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: install.sh [--skip-login] [--skip-verify] [--local] [--version VERSION] [--uninstall]"
      exit 1
      ;;
  esac
done

# ─── Colors ──────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

# ─── Resolve plugin version from remote config ───────────────────────
# Fetch config.json from CDN so installers always pull the current
# plugin version + SHA256, not a hardcoded one. Falls back silently
# to the PLUGIN_VERSION default if the fetch fails.

if command -v python3 >/dev/null 2>&1; then
  REMOTE_CFG_OUT=$(curl -fsSL --max-time 5 "$REMOTE_CONFIG_URL" 2>/dev/null | python3 -c "
import json, sys
try:
    cfg = json.load(sys.stdin)
    v   = cfg.get('plugin_version', '')
    url = cfg.get('plugin_tarball_url', '')
    sha = cfg.get('plugin_sha256', '')
    if v: print(f'PLUGIN_VERSION={v}')
    if url: print(f'PLUGIN_TAR_URL={url}')
    if sha: print(f'PLUGIN_SHA256={sha}')
except Exception:
    pass
" 2>/dev/null || true)
  if [ -n "$REMOTE_CFG_OUT" ]; then
    eval "$REMOTE_CFG_OUT"
  fi
fi

PLUGIN_CACHE_DIR="$CLAUDE_DIR/plugins/cache/$PLUGIN_MARKETPLACE/sidequest/$PLUGIN_VERSION"

# ─── Helpers ─────────────────────────────────────────────────────────

step() { echo -e "\n${BLUE}[$1/6]${NC} $2"; }
ok()   { echo -e "  ${GREEN}done${NC}"; }
fail() { echo -e "  ${RED}failed${NC} — $1"; }
warn() { echo -e "  ${YELLOW}warning${NC} — $1"; }

rollback() {
  echo ""
  echo -e "${RED}Setup failed. Rolling back...${NC}"
  for s in "${COMPLETED_STEPS[@]}"; do
    case $s in
      app)
        echo -n "  Removing app... "
        pkill -f "$APP_NAME" 2>/dev/null || true
        rm -rf "$INSTALL_PATH" 2>/dev/null || true
        echo "done"
        ;;
      plugin)
        echo -n "  Removing plugin... "
        rm -rf "$PLUGIN_CACHE_DIR" 2>/dev/null || true
        echo "done"
        ;;
      plugin_register)
        echo -n "  Deregistering plugin... "
        deregister_plugin 2>/dev/null || true
        echo "done"
        ;;
      config)
        echo -n "  Removing config... "
        rm -f "$SIDEQUEST_DIR/config.json" 2>/dev/null || true
        echo "done"
        ;;
    esac
  done
  echo ""
  echo "Rolled back. Fix the issue and run setup again."
  exit 1
}

deregister_plugin() {
  if [ -f "$SETTINGS_FILE" ]; then
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    data.get('enabledPlugins', {}).pop('$PLUGIN_KEY', None)
    data.get('extraKnownMarketplaces', {}).pop('$PLUGIN_MARKETPLACE', None)
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=4)
except: pass
" "$SETTINGS_FILE" 2>/dev/null || true
  fi
}

register_plugin() {
  # Ensure directories exist (fresh Claude Code install may not have them)
  mkdir -p "$CLAUDE_DIR/plugins"
  mkdir -p "$(dirname "$SETTINGS_FILE")"

  python3 -c "
import json, os, sys
from datetime import datetime, timezone

settings_file = sys.argv[1]
marketplace_dir = sys.argv[2]
plugin_marketplace = sys.argv[3]
plugin_key = sys.argv[4]
cache_dir = sys.argv[5]
plugin_version = sys.argv[6]
installed_file = sys.argv[7]
known_file = sys.argv[8]

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')

# 1. settings.json — enabledPlugins + extraKnownMarketplaces
if os.path.exists(settings_file):
    with open(settings_file) as f:
        data = json.load(f)
else:
    data = {}

data.setdefault('enabledPlugins', {})[plugin_key] = True
data.setdefault('extraKnownMarketplaces', {})[plugin_marketplace] = {
    'source': {
        'source': 'directory',
        'path': marketplace_dir
    }
}

with open(settings_file, 'w') as f:
    json.dump(data, f, indent=4)

# 2. installed_plugins.json — register as installed
if os.path.exists(installed_file):
    with open(installed_file) as f:
        ip = json.load(f)
else:
    ip = {'version': 2, 'plugins': {}}

ip['plugins'][plugin_key] = [{
    'scope': 'user',
    'installPath': cache_dir,
    'version': plugin_version,
    'installedAt': now,
    'lastUpdated': now
}]

with open(installed_file, 'w') as f:
    json.dump(ip, f, indent=4)

# 3. known_marketplaces.json — register marketplace
if os.path.exists(known_file):
    with open(known_file) as f:
        km = json.load(f)
else:
    km = {}

km[plugin_marketplace] = {
    'source': {
        'source': 'directory',
        'path': marketplace_dir
    },
    'installLocation': marketplace_dir,
    'lastUpdated': now
}

with open(known_file, 'w') as f:
    json.dump(km, f, indent=4)
" "$SETTINGS_FILE" "$PLUGIN_MARKETPLACE_DIR" "$PLUGIN_MARKETPLACE" "$PLUGIN_KEY" "$PLUGIN_CACHE_DIR" "$PLUGIN_VERSION" "$INSTALLED_PLUGINS_FILE" "$KNOWN_MARKETPLACES_FILE"
}

# ─── Banner ──────────────────────────────────────────────────────────

echo ""
echo "  ____  _     _       ___                  _   "
echo " / ___|(_) __| | ___ / _ \ _   _  ___  ___| |_ "
echo " \___ \| |/ _\` |/ _ \ | | | | | |/ _ \/ __| __|"
echo "  ___) | | (_| |  __/ |_| | |_| |  __/\__ \ |_ "
echo " |____/|_|\__,_|\___|\__\_\\\\\__,_|\___||___/\__|"
echo ""
echo "  One command. Everything works."
echo ""

if [ "$LOCAL_MODE" = true ]; then
  echo -e "  ${DIM}(local mode — using project build artifacts)${NC}"
  echo ""
  # Ensure submodule is initialized in local mode
  if [ ! -d "$PROJECT_DIR/client" ]; then
    echo -e "  ${YELLOW}Initializing git submodule...${NC}"
    (cd "$PROJECT_DIR" && git submodule update --init --recursive 2>/dev/null) || true
  fi
fi

# ─── Preflight checks ───────────────────────────────────────────────

echo -n "Checking macOS version... "
MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MACOS_VERSION" -lt 12 ]; then
  echo -e "${RED}macOS 12+ required${NC}"
  exit 1
fi
echo -e "${GREEN}OK${NC} (macOS $MACOS_VERSION)"

echo -n "Checking for Node.js... "
if ! command -v node &>/dev/null; then
  echo -e "${RED}not found${NC}"
  echo "Node.js is required for OAuth login. Install from https://nodejs.org"
  exit 1
fi
echo -e "${GREEN}OK${NC} ($(node --version))"

echo -n "Checking for Claude Code... "
if [ ! -d "$CLAUDE_DIR" ]; then
  echo -e "${RED}not found${NC}"
  echo "Claude Code must be installed. Visit https://claude.ai/code"
  exit 1
fi
echo -e "${GREEN}OK${NC}"

# ─── Step 1: Install native app ─────────────────────────────────────

step 1 "Installing native app"

# why: TEMP_DIR is used by step 2 (plugin tarball download) regardless of whether
# step 1 takes the install or already-installed branch. Allocating it here avoids
# an unbound-variable failure under set -u when the app is already installed.
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

if [ -d "$INSTALL_PATH" ]; then
  echo -e "  ${DIM}Already installed — skipping${NC}"
else
  mkdir -p "$INSTALL_DIR"

  if [ "$LOCAL_MODE" = true ]; then
    # Local mode: use DMG from project build directory (via submodule)
    DMG_PATH="$PROJECT_DIR/client/macOS/build/SideQuestApp.dmg"
    if [ ! -f "$DMG_PATH" ]; then
      fail "no DMG found at $DMG_PATH — build first with: cd macOS && xcodebuild -scheme SideQuestApp -configuration Release build"
      exit 1
    fi
    echo -e "  Using local DMG: ${DIM}$DMG_PATH${NC}"
  else
    # Remote mode: download from S3
    echo -n "  Downloading SideQuest (v$VERSION)... "
    DMG_URL="$DMG_BUCKET/SideQuestApp-$VERSION.dmg"
    DMG_PATH="$TEMP_DIR/SideQuestApp.dmg"

    if ! curl -fsSL --max-time 300 -o "$DMG_PATH" "$DMG_URL" 2>/dev/null; then
      fail "download failed — check internet connection"
      rollback
    fi
    echo -e "${GREEN}OK${NC}"
  fi

  echo -n "  Mounting and installing... "
  MOUNT_PATH=$(mktemp -d)
  if ! hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_PATH" -nobrowse -quiet 2>/dev/null; then
    fail "could not mount DMG"
    rm -rf "$MOUNT_PATH"
    rollback
  fi

  if ! ditto "$MOUNT_PATH/$APP_NAME.app" "$INSTALL_PATH" 2>/dev/null; then
    hdiutil detach "$MOUNT_PATH" >/dev/null 2>&1 || true
    rm -rf "$MOUNT_PATH"
    fail "could not copy to $INSTALL_DIR"
    rollback
  fi

  chmod +x "$INSTALL_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true
  hdiutil detach "$MOUNT_PATH" >/dev/null 2>&1 || true
  rm -rf "$MOUNT_PATH"
  echo -e "${GREEN}OK${NC}"
fi
COMPLETED_STEPS+=("app")

# Launch the app
if ! pgrep -f "$APP_NAME" >/dev/null 2>&1; then
  echo -n "  Launching SideQuest... "
  open "$INSTALL_PATH"
  sleep 2
  echo -e "${GREEN}OK${NC}"
fi

# ─── Step 2: Install Claude Code plugin ─────────────────────────────

step 2 "Installing Claude Code plugin"

if [ -d "$PLUGIN_CACHE_DIR" ] && [ -f "$PLUGIN_CACHE_DIR/.claude-plugin/plugin.json" ]; then
  echo -e "  ${DIM}Already installed — updating${NC}"
fi

if [ "$LOCAL_MODE" = true ]; then
  # Local mode: copy plugin from project source (via submodule)
  PLUGIN_SRC="$PROJECT_DIR/client/plugin"
  if [ ! -d "$PLUGIN_SRC" ]; then
    fail "plugin source not found at $PLUGIN_SRC (submodule not initialized?)"
    rollback
  fi
  echo -n "  Copying plugin from source... "
  mkdir -p "$PLUGIN_CACHE_DIR"
  # Copy all plugin contents
  rsync -a --delete "$PLUGIN_SRC/" "$PLUGIN_CACHE_DIR/" 2>/dev/null
  echo -e "${GREEN}OK${NC}"
else
  # Remote mode: download tarball from S3
  echo -n "  Downloading plugin (v$PLUGIN_VERSION)... "
  if [ -z "$PLUGIN_TAR_URL" ]; then
    PLUGIN_TAR_URL="$PLUGIN_BUCKET/sidequest-plugin-$PLUGIN_VERSION.tar.gz"
  fi
  PLUGIN_TAR="$TEMP_DIR/sidequest-plugin.tar.gz"

  if ! curl -fsSL --max-time 60 -o "$PLUGIN_TAR" "$PLUGIN_TAR_URL" 2>/dev/null; then
    fail "plugin download failed"
    rollback
  fi

  # SHA256 verification against the hash published in remote config.
  # Silently skipped when PLUGIN_SHA256 is empty (e.g., config.json fetch failed).
  if [ -n "$PLUGIN_SHA256" ]; then
    ACTUAL_SHA=$(shasum -a 256 "$PLUGIN_TAR" | cut -d' ' -f1)
    if [ "$ACTUAL_SHA" != "$PLUGIN_SHA256" ]; then
      fail "plugin integrity check failed (expected $PLUGIN_SHA256, got $ACTUAL_SHA)"
      rollback
    fi
  fi
  echo -e "${GREEN}OK${NC}"

  echo -n "  Extracting to Claude Code... "
  mkdir -p "$PLUGIN_CACHE_DIR"
  if ! tar -xzf "$PLUGIN_TAR" -C "$PLUGIN_CACHE_DIR" --strip-components=1 2>/dev/null; then
    fail "could not extract plugin"
    rollback
  fi
  echo -e "${GREEN}OK${NC}"
fi

# Create marketplace source directory (Claude Code reads this for plugin discovery)
mkdir -p "$PLUGIN_MARKETPLACE_DIR/sidequest"
rsync -a "$PLUGIN_CACHE_DIR/" "$PLUGIN_MARKETPLACE_DIR/sidequest/" 2>/dev/null
mkdir -p "$PLUGIN_MARKETPLACE_DIR/.claude-plugin"
cat > "$PLUGIN_MARKETPLACE_DIR/.claude-plugin/marketplace.json" << MKJSON
{
  "name": "$PLUGIN_MARKETPLACE",
  "owner": {"name": "SideQuest AI", "email": "hello@trysidequest.ai"},
  "plugins": [{
    "name": "sidequest",
    "description": "SideQuest — contextual quests inside your AI coding agent",
    "version": "$PLUGIN_VERSION",
    "source": "./sidequest",
    "author": {"name": "SideQuest AI", "email": "hello@trysidequest.ai"}
  }]
}
MKJSON

# Remove any orphaned marker from cache (left over from previous installs)
rm -f "$PLUGIN_CACHE_DIR/.orphaned_at" 2>/dev/null || true

# Ensure hook scripts are executable
chmod +x "$PLUGIN_CACHE_DIR/hooks/stop-hook" 2>/dev/null || true
chmod +x "$PLUGIN_CACHE_DIR/hooks/quest-intercept" 2>/dev/null || true
chmod +x "$PLUGIN_CACHE_DIR/hooks/session-start" 2>/dev/null || true
chmod +x "$PLUGIN_CACHE_DIR/hooks/run-hook.cmd" 2>/dev/null || true
chmod +x "$PLUGIN_CACHE_DIR/hooks/xpc-socket-helper.sh" 2>/dev/null || true

# Ensure plugin data directory exists
mkdir -p "$PLUGIN_DATA_DIR"

COMPLETED_STEPS+=("plugin")

# ─── Step 3: Register plugin in Claude Code ──────────────────────────

step 3 "Registering plugin"

echo -n "  Updating Claude Code config... "
if ! register_plugin 2>/dev/null; then
  fail "could not register plugin"
  rollback
fi
echo -e "${GREEN}OK${NC}"

COMPLETED_STEPS+=("plugin_register")

# ─── Step 4: OAuth login ────────────────────────────────────────────

step 4 "Authenticating"

if [ "$SKIP_LOGIN" = true ]; then
  echo -e "  ${DIM}Skipped (--skip-login)${NC}"
elif [ -f "$SIDEQUEST_DIR/config.json" ]; then
  # Check if already has a token
  HAS_TOKEN=$(python3 -c "
import json
try:
    with open('$SIDEQUEST_DIR/config.json') as f:
        c = json.load(f)
    print('yes' if c.get('token') else 'no')
except: print('no')
" 2>/dev/null)
  if [ "$HAS_TOKEN" = "yes" ]; then
    echo -e "  ${DIM}Already authenticated — skipping${NC}"
  else
    echo "  Opening browser for Google login..."
    OAUTH_SCRIPT="$PLUGIN_CACHE_DIR/scripts/oauth-login.js"
    if [ -f "$OAUTH_SCRIPT" ]; then
      node "$OAUTH_SCRIPT" || {
        fail "OAuth login failed — you can retry with /sidequest:sq-login in Claude Code"
        warn "Continuing setup without authentication"
      }
    fi
  fi
else
  echo "  Opening browser for Google login..."
  OAUTH_SCRIPT="$PLUGIN_CACHE_DIR/scripts/oauth-login.js"
  if [ -f "$OAUTH_SCRIPT" ]; then
    node "$OAUTH_SCRIPT" || {
      fail "OAuth login failed — you can retry with /sidequest:sq-login in Claude Code"
      warn "Continuing setup without authentication"
    }
  fi
fi

COMPLETED_STEPS+=("config")

# ─── Step 5: Verify connectivity ────────────────────────────────────

step 5 "Verifying"

VERIFY_PASS=0
VERIFY_TOTAL=0

if [ "$SKIP_VERIFY" = true ]; then
  echo -e "  ${DIM}Skipped (--skip-verify)${NC}"
else
  # Check app is installed
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  App installed... "
  if [ -d "$INSTALL_PATH" ]; then
    VERIFY_PASS=$((VERIFY_PASS + 1))
    echo -e "${GREEN}OK${NC} ($INSTALL_PATH)"
  else
    warn "app not found at $INSTALL_PATH"
  fi

  # Check app is running
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  App running... "
  if pgrep -f "$APP_NAME" >/dev/null 2>&1; then
    VERIFY_PASS=$((VERIFY_PASS + 1))
    echo -e "${GREEN}OK${NC}"
  else
    warn "app not running — launch manually from $INSTALL_DIR"
  fi

  # Check IPC socket exists
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  IPC socket... "
  SOCKET_PATH="$SIDEQUEST_DIR/sidequest.sock"
  if [ -S "$SOCKET_PATH" ]; then
    VERIFY_PASS=$((VERIFY_PASS + 1))
    echo -e "${GREEN}OK${NC}"
  else
    warn "socket not ready yet — will be created when app starts"
  fi

  # Check API reachable
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  API endpoint... "
  if curl -sf --max-time 5 "${API_BASE}/health" >/dev/null 2>&1; then
    VERIFY_PASS=$((VERIFY_PASS + 1))
    echo -e "${GREEN}OK${NC}"
  else
    warn "API not reachable — quests will work once connected"
  fi

  # Check auth token exists
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  Authentication... "
  if [ -f "$SIDEQUEST_DIR/config.json" ]; then
    HAS_TOKEN=$(python3 -c "
import json
try:
    with open('$SIDEQUEST_DIR/config.json') as f:
        c = json.load(f)
    print('yes' if c.get('token') else 'no')
except: print('no')
" 2>/dev/null)
    if [ "$HAS_TOKEN" = "yes" ]; then
      VERIFY_PASS=$((VERIFY_PASS + 1))
      echo -e "${GREEN}OK${NC}"
    else
      warn "no token — run /sidequest:sq-login in Claude Code"
    fi
  else
    warn "no config — run /sidequest:sq-login in Claude Code"
  fi

  # Check plugin registered
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  Plugin registered... "
  if [ -f "$SETTINGS_FILE" ]; then
    IS_REGISTERED=$(python3 -c "
import json
try:
    with open('$SETTINGS_FILE') as f:
        d = json.load(f)
    enabled = d.get('enabledPlugins', {}).get('$PLUGIN_KEY', False)
    known = '$PLUGIN_MARKETPLACE' in d.get('extraKnownMarketplaces', {})
    print('yes' if enabled and known else 'no')
except: print('no')
" 2>/dev/null)
    if [ "$IS_REGISTERED" = "yes" ]; then
      VERIFY_PASS=$((VERIFY_PASS + 1))
      echo -e "${GREEN}OK${NC}"
    else
      warn "plugin not properly registered in settings.json"
    fi
  else
    warn "no settings.json found"
  fi

  # Check plugin files exist
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  Plugin files... "
  if [ -f "$PLUGIN_CACHE_DIR/.claude-plugin/plugin.json" ] && [ -f "$PLUGIN_CACHE_DIR/hooks/hooks.json" ]; then
    VERIFY_PASS=$((VERIFY_PASS + 1))
    echo -e "${GREEN}OK${NC}"
  else
    warn "plugin files missing at $PLUGIN_CACHE_DIR"
  fi

  # Check hooks are executable
  VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
  echo -n "  Hook scripts... "
  if [ -x "$PLUGIN_CACHE_DIR/hooks/stop-hook" ] && [ -x "$PLUGIN_CACHE_DIR/hooks/session-start" ]; then
    VERIFY_PASS=$((VERIFY_PASS + 1))
    echo -e "${GREEN}OK${NC}"
  else
    warn "hook scripts not executable"
  fi
fi

# ─── Step 6: Done ───────────────────────────────────────────────────

step 6 "Complete"

echo ""
if [ "$SKIP_VERIFY" = false ] && [ "$VERIFY_TOTAL" -gt 0 ]; then
  echo -e "  Checks passed: ${GREEN}$VERIFY_PASS/$VERIFY_TOTAL${NC}"
  echo ""
fi
echo "  ================================================"
echo -e "  ${GREEN}SideQuest is installed and ready!${NC}"
echo "  ================================================"
echo ""
echo "  App:    $INSTALL_PATH"
echo "  Plugin: Claude Code (hooks + skills registered)"
echo "  Config: ~/.sidequest/config.json"
echo ""
echo "  Start a new Claude Code session to see quests."
echo ""
echo "  Commands:"
echo "    /sidequest:sq-login     Re-authenticate"
echo "    /sidequest:sq-status     Diagnose setup + troubleshoot"
echo "    /sidequest:sq-retrigger Show last quest again"
echo "    /sidequest:sq-reinstall Upgrade to the latest version"
echo ""
echo "  To uninstall:"
echo "    curl -fsSL https://get.trysidequest.ai/uninstall.sh | bash"
echo ""
