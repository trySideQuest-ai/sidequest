#!/bin/bash

# Create macOS DMG (Disk Image) for SideQuest Distribution
#
# This script packages a notarized/signed .app bundle into a standard macOS DMG
# (disk image) distribution file with an installer script and README.
#
# The DMG includes:
# - SideQuest.app (the main application)
# - Install SideQuest.sh (one-click installer script)
# - README.txt (user instructions)
#
# The DMG is compressed (UDZO format) for smaller file size and faster download.
#
# Usage:
#   ./macOS/scripts/create-dmg.sh build/Release/SideQuest.app [output-path]
#   ./macOS/scripts/create-dmg.sh build/Release/SideQuest.app build/Release/SideQuest.dmg

set -euo pipefail

# Configuration
APP_PATH="${1:-.}"
OUTPUT_DMG="${2:-build/Release/SideQuest.dmg}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function: print timestamp
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
  echo -e "${RED}ERROR${NC}: $*" >&2
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

# Trap errors and cleanup
cleanup() {
  if [ -n "${TEMP_DMG_DIR:-}" ] && [ -d "$TEMP_DMG_DIR" ]; then
    rm -rf "$TEMP_DMG_DIR"
  fi
}
trap cleanup EXIT

# Step 1: Validate input
log "Validating input..."

if [ -z "$APP_PATH" ] || [ "$APP_PATH" = "." ]; then
  log_error "Usage: $0 <path-to-.app-bundle> [output-dmg-path]"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  log_error ".app bundle not found: $APP_PATH"
  exit 1
fi

if [[ ! "$APP_PATH" == *.app ]]; then
  log_error "Input must be .app bundle: $APP_PATH"
  exit 1
fi

log_success ".app bundle found: $APP_PATH"

# Extract app name from path
APP_NAME=$(basename "$APP_PATH")
log "App name: $APP_NAME"

# Ensure output directory exists
OUTPUT_DIR=$(dirname "$OUTPUT_DMG")
mkdir -p "$OUTPUT_DIR"
log "Output directory: $OUTPUT_DIR"

# Step 2: Create temporary folder for DMG contents
log "Creating temporary DMG staging directory..."

TEMP_DMG_DIR=$(mktemp -d)
log_success "Temporary directory: $TEMP_DMG_DIR"

# Step 3: Copy app and create install script
log "Copying app to staging directory..."

if ! ditto "$APP_PATH" "$TEMP_DMG_DIR/$APP_NAME"; then
  log_error "Failed to copy app bundle"
  exit 1
fi

log_success "App copied: $APP_NAME"

# Create install script
log "Creating install script..."

cat > "$TEMP_DMG_DIR/Install SideQuest.sh" << 'INSTALL_SCRIPT'
#!/bin/bash

# SideQuest Installation Script
#
# This script installs SideQuest to /Applications and configures auto-launch.
# It can be double-clicked in Finder or run from the terminal.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Get the directory this script is running from (the DMG mount point)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/SideQuest.app"

if [ ! -d "$APP_BUNDLE" ]; then
  echo -e "${RED}ERROR${NC}: SideQuest.app not found in: $SCRIPT_DIR"
  exit 1
fi

echo "Installing SideQuest..."

# Copy app to /Applications
if [ ! -w "/Applications" ]; then
  echo "Requesting administrator privileges to install to /Applications..."
  sudo ditto "$APP_BUNDLE" "/Applications/SideQuest.app"
  sudo chmod +x "/Applications/SideQuest.app/Contents/MacOS/SideQuest"
else
  ditto "$APP_BUNDLE" "/Applications/SideQuest.app"
  chmod +x "/Applications/SideQuest.app/Contents/MacOS/SideQuest"
fi

# Launch the app to trigger auto-launch setup on first run
echo -e "${GREEN}✓${NC} SideQuest installed to /Applications"
echo ""
echo "Launching SideQuest..."
open "/Applications/SideQuest.app"

echo -e "${GREEN}✓${NC} Installation complete!"
echo ""
echo "SideQuest has been installed and launched."
echo "It will automatically start on your next login."

exit 0
INSTALL_SCRIPT

chmod +x "$TEMP_DMG_DIR/Install SideQuest.sh"
log_success "Install script created"

# Create README
log "Creating README..."

cat > "$TEMP_DMG_DIR/README.txt" << 'README'
SideQuest for macOS (Beta)

Thank you for joining the SideQuest beta! This folder contains the SideQuest application
and an installer script to get you up and running.

INSTALLATION METHODS
====================

Method 1: Using the Installer Script (Recommended)
  1. Double-click "Install SideQuest.sh" in this folder
  2. Enter your password if prompted (needed to write to /Applications)
  3. SideQuest will launch automatically

Method 2: Manual Installation
  1. Drag "SideQuest.app" to your /Applications folder
  2. Launch the app from /Applications or Spotlight (Cmd+Space)

AUTO-LAUNCH
===========

On first launch, SideQuest will ask for permission to automatically start when you log in.
Click "Allow" to enable auto-launch. You can change this later in System Settings if needed.

SUPPORT & FEEDBACK
==================

We'd love to hear your feedback during beta testing!

Report issues or suggest improvements:
  - GitHub Issues: https://github.com/sidequest-ai/sidequest/issues
  - Email: support@trysidequest.ai

Thank you for using SideQuest!
README

log_success "README created"

# Step 4: Create the DMG
log "Creating DMG image..."
log_info "Format: UDZO (compressed read-only)"
log_info "This may take a few minutes..."

if [ -f "$OUTPUT_DMG" ]; then
  log_info "Removing existing DMG: $OUTPUT_DMG"
  rm -f "$OUTPUT_DMG"
fi

if ! hdiutil create \
  -volname "SideQuest" \
  -srcfolder "$TEMP_DMG_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT_DMG" &>/dev/null; then
  log_error "Failed to create DMG"
  exit 1
fi

log_success "DMG created: $OUTPUT_DMG"

# Step 5: Verify DMG was created
log "Verifying DMG..."

if [ ! -f "$OUTPUT_DMG" ] || [ ! -s "$OUTPUT_DMG" ]; then
  log_error "DMG verification failed: file does not exist or is empty"
  exit 1
fi

log_success "DMG verification passed"

# Get file size
DMG_SIZE=$(ls -lh "$OUTPUT_DMG" | awk '{print $5}')

# Success
echo ""
echo "=================================================="
log_success "DMG creation complete!"
echo "=================================================="
echo ""
log_success "Distribution DMG ready: $OUTPUT_DMG"
echo "  Size: $DMG_SIZE"
echo ""
log_info "Contents:"
echo "  - SideQuest.app (notarized and code-signed)"
echo "  - Install SideQuest.sh (one-click installer)"
echo "  - README.txt (user instructions)"
echo ""
log_info "Next steps:"
echo "  1. (Optional) Sign DMG: ./macOS/scripts/sign-dmg.sh \"$OUTPUT_DMG\""
echo "  2. Test on fresh Mac: Download DMG, mount, verify Gatekeeper accepts app"
echo "  3. Distribute: Upload DMG to your server/CDN for user download"
echo ""
