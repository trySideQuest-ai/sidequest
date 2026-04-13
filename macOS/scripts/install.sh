#!/bin/bash

# SideQuest Installer Script
#
# Usage:
#   ./install.sh                                    # Install latest version
#   ./install.sh --version 1.0.0                   # Install specific version
#   ./install.sh --skip-launch                     # Install but don't launch
#
# This script downloads the notarized DMG, mounts it, copies the app to /Applications,
# and registers the app for auto-launch.

set -euo pipefail

# Configuration
DMG_BUCKET="https://s3.amazonaws.com/sidequest-releases"
VERSION="latest"
INSTALL_PATH="/Applications/SideQuest.app"
APP_NAME="SideQuest"
EXECUTABLE_NAME="SideQuest"
SKIP_LAUNCH=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --install-path)
      INSTALL_PATH="$2"
      shift 2
      ;;
    --skip-launch)
      SKIP_LAUNCH=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--version VERSION] [--install-path PATH] [--skip-launch]"
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
echo "🚀 Installing SideQuest"
echo "========================"
echo ""

# Step 1: Check macOS version
echo -n "Checking macOS version... "
MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MACOS_VERSION" -lt 12 ]; then
  echo -e "${RED}FAILED${NC}"
  echo "SideQuest requires macOS 12 or later. You are running macOS $MACOS_VERSION."
  echo "Please upgrade macOS to use SideQuest."
  exit 1
fi
echo -e "${GREEN}OK${NC} (macOS $MACOS_VERSION)"

# Step 2: Check disk space
echo -n "Checking disk space in /Applications... "
AVAILABLE_SPACE=$(df /Applications | awk 'NR==2 {print $4}')
REQUIRED_SPACE=$((500 * 1024)) # 500 MB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
  echo -e "${YELLOW}WARNING${NC}"
  echo "  Only $(echo "scale=1; $AVAILABLE_SPACE / 1024 / 1024" | bc)MB available"
  echo "  We recommend at least 500MB free space"
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
  fi
else
  echo -e "${GREEN}OK${NC}"
fi

# Step 3: Check for existing installation
if [ -d "$INSTALL_PATH" ]; then
  echo ""
  echo -e "${YELLOW}⚠️  SideQuest is already installed${NC}"
  read -p "Overwrite existing installation? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
  fi
fi

# Step 4: Create temporary directory
echo ""
echo -n "Creating temporary directory... "
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT
echo -e "${GREEN}OK${NC}"

# Step 5: Download DMG
echo -n "📥 Downloading SideQuest (v$VERSION)... "
DMG_URL="$DMG_BUCKET/SideQuest-$VERSION.dmg"
DMG_PATH="$TEMP_DIR/SideQuest.dmg"

if ! curl -fsSL --max-time 300 -o "$DMG_PATH" "$DMG_URL" 2>/dev/null; then
  echo -e "${RED}FAILED${NC}"
  echo ""
  echo "❌ Download failed. Please check:"
  echo "   - Internet connection is working"
  echo "   - Version '$VERSION' exists (default is 'latest')"
  echo "   - Server is accessible: $DMG_BUCKET"
  exit 1
fi

if [ ! -f "$DMG_PATH" ] || [ ! -s "$DMG_PATH" ]; then
  echo -e "${RED}FAILED${NC}"
  echo "❌ Downloaded file is empty or missing"
  exit 1
fi

echo -e "${GREEN}✓${NC}"

# Step 6: Mount DMG
echo -n "📦 Mounting disk image... "
MOUNT_PATH=$(mktemp -d)

if ! hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_PATH" -nobrowse -quiet; then
  echo -e "${RED}FAILED${NC}"
  rm -rf "$MOUNT_PATH"
  echo ""
  echo "❌ Failed to mount DMG. The disk image may be corrupted."
  echo "   Try downloading again or contact support@trysidequest.ai"
  exit 1
fi

trap "hdiutil detach '$MOUNT_PATH' 2>/dev/null || true; rm -rf '$MOUNT_PATH' '$TEMP_DIR'" EXIT
echo -e "${GREEN}✓${NC}"

# Step 7: Find the app in the mounted DMG
if [ ! -d "$MOUNT_PATH/$APP_NAME.app" ]; then
  echo -e "${RED}❌ ERROR${NC}: $APP_NAME.app not found in DMG"
  exit 1
fi

# Step 8: Copy app to /Applications
echo -n "📦 Installing to /Applications... "

# Remove old installation if overwriting
if [ -d "$INSTALL_PATH" ]; then
  rm -rf "$INSTALL_PATH"
fi

# Use ditto to preserve code signature and resource forks
if ! ditto "$MOUNT_PATH/$APP_NAME.app" "$INSTALL_PATH" 2>/dev/null; then
  echo -e "${RED}FAILED${NC}"
  echo ""
  echo "❌ Installation failed. Please check:"
  echo "   - You have write permissions to /Applications"
  echo "   - Sufficient disk space is available"
  echo "   - The disk is not full"
  exit 1
fi

# Fix execute permissions on the main executable
if [ -f "$INSTALL_PATH/Contents/MacOS/$EXECUTABLE_NAME" ]; then
  chmod +x "$INSTALL_PATH/Contents/MacOS/$EXECUTABLE_NAME"
fi

echo -e "${GREEN}✓${NC}"

# Step 9: Unmount DMG and cleanup
echo -n "🔧 Cleaning up... "
hdiutil detach "$MOUNT_PATH" 2>/dev/null || true
rm -rf "$MOUNT_PATH"
echo -e "${GREEN}✓${NC}"

# Step 10: Setup launchd KeepAlive for auto-restart on crash
echo -n "🔄 Setting up launchd auto-restart... "

LAUNCHD_LOADED=false
PLIST_SRC=""
# Check multiple locations for the plist template
for candidate in \
  "$SCRIPT_DIR/../../plugin/resources/ai.sidequest.app.plist" \
  "$SCRIPT_DIR/../plugin/resources/ai.sidequest.app.plist"; do
  if [ -f "$candidate" ]; then
    PLIST_SRC="$candidate"
    break
  fi
done

if [ -n "$PLIST_SRC" ]; then
  PLIST_DEST="$HOME/Library/LaunchAgents/ai.sidequest.app.plist"
  mkdir -p "$HOME/Library/LaunchAgents" 2>/dev/null
  sed "s|__APP_PATH__|$INSTALL_PATH|g" "$PLIST_SRC" > "$PLIST_DEST"
  chmod 644 "$PLIST_DEST"
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  launchctl load "$PLIST_DEST" 2>/dev/null || true
  LAUNCHD_LOADED=true
  echo -e "${GREEN}✓${NC}"
else
  echo -e "${YELLOW}SKIPPED${NC} (plist template not found)"
fi

# Step 11: Launch app (if not skipped and launchd didn't already start it)
if [ "$SKIP_LAUNCH" = false ] && [ "$LAUNCHD_LOADED" = false ]; then
  echo ""
  echo "🚀 Launching SideQuest..."
  open "$INSTALL_PATH"
fi

# Final message
echo ""
echo "================================================"
echo -e "${GREEN}✅ SideQuest is installed and ready!${NC}"
echo "================================================"
echo ""
echo "📍 Location: /Applications/SideQuest.app"
echo ""
echo "🔑 Auto-Launch & Auto-Restart:"
echo "   The app will register itself for auto-launch on first run."
echo "   If the app isn't starting at login, add it manually in Login Items."
echo "   To verify: System Settings > General > Login Items"
echo ""
echo "📚 For help: https://docs.trysidequest.ai"
echo ""
