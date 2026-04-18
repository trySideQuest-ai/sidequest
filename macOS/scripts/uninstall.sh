#!/bin/bash

# SideQuest Uninstaller Script
#
# Usage:
#   ./uninstall.sh                    # Interactive uninstall (prompts for confirmation)
#   ./uninstall.sh --force            # Force uninstall without prompts
#   ./uninstall.sh --keep-data        # Uninstall but keep cached data
#
# This script uninstalls SideQuest by removing the app bundle and cleaning up
# login items, caches, and preferences.

set -euo pipefail

# Configuration
APP_NAME="SideQuest"
INSTALL_PATH="/Applications/SideQuest.app"
BUNDLE_ID="com.sidequest.app"
FORCE=false
KEEP_DATA=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE=true
      shift
      ;;
    --keep-data)
      KEEP_DATA=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--force] [--keep-data]"
      exit 1
      ;;
  esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display banner
echo ""
echo "🗑️  Uninstalling SideQuest"
echo "=========================="
echo ""

# Step 1: Check if app is installed
if [ ! -d "$INSTALL_PATH" ]; then
  echo "ℹ️  SideQuest is not installed at $INSTALL_PATH"
  echo "Nothing to uninstall."
  exit 0
fi

# Step 2: Confirm uninstall (unless --force)
if [ "$FORCE" = false ]; then
  echo "This will remove:"
  echo "  - /Applications/SideQuest.app"
  echo "  - Login item registration"
  echo ""
  read -p "Continue with uninstallation? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled"
    exit 0
  fi
fi

# Step 3: Stop the app if it's running
echo -n "Stopping SideQuest if running... "
pkill -f "$INSTALL_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1
echo -e "${GREEN}✓${NC}"

# Step 4: Remove app bundle
echo -n "🗑️  Removing app bundle... "
if rm -rf "$INSTALL_PATH"; then
  echo -e "${GREEN}✓${NC}"
else
  echo -e "${RED}FAILED${NC}"
  echo ""
  echo "❌ Failed to remove app. You may need administrator privileges."
  echo "   Try: sudo $0 --force"
  exit 1
fi

# Step 5: Remove login items and launchd KeepAlive
echo -n "🔑 Removing from login items... "

# Remove LaunchAgent plist files
rm -f ~/.config/sidequest/launchagent.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/${BUNDLE_ID}.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/${BUNDLE_ID}*.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/ai.sidequest.app.plist 2>/dev/null || true

# Also unload from launchctl if still loaded
launchctl unload ~/Library/LaunchAgents/${BUNDLE_ID}.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/ai.sidequest.app.plist 2>/dev/null || true

echo -e "${GREEN}✓${NC}"

# Step 6: Optional: Remove cached data and preferences
if [ "$KEEP_DATA" = false ]; then
  read -p "Remove local data and cache? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -n "Removing local data... "
    rm -rf ~/Library/Caches/${BUNDLE_ID}* 2>/dev/null || true
    rm -rf ~/Library/Preferences/${BUNDLE_ID}* 2>/dev/null || true
    rm -rf ~/.sidequest* 2>/dev/null || true
    rm -rf ~/.config/sidequest 2>/dev/null || true
    echo -e "${GREEN}✓${NC}"
  fi
fi

# Final message
echo ""
echo "================================================"
echo -e "${GREEN}✅ SideQuest has been uninstalled${NC}"
echo "================================================"
echo ""
echo "All app files and login items have been removed."
echo ""
echo "📝 Note: User data and cache may still exist in:"
echo "   - ~/Library/Caches/"
echo "   - ~/Library/Preferences/"
echo ""
echo "To completely remove all traces, run:"
echo "   rm -rf ~/Library/Preferences/${BUNDLE_ID}*"
echo "   rm -rf ~/Library/Caches/${BUNDLE_ID}*"
echo ""
