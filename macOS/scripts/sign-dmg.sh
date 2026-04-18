#!/bin/bash

# Code Sign DMG (Disk Image) with Developer ID Certificate
#
# This script code-signs the DMG distribution file with the Developer ID Application
# certificate. This adds an extra layer of security validation for the distribution container.
#
# Note: The .app bundle inside the DMG is already signed. Signing the DMG itself is optional
# but provides defense-in-depth validation that the entire distribution package is trusted.
#
# Usage:
#   ./macOS/scripts/sign-dmg.sh build/Release/SideQuest.dmg

set -euo pipefail

# Configuration
DMG_PATH="${1:-.}"

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

# Trap errors
trap 'log_error "DMG signing failed"; exit 1' ERR

# Step 1: Validate input
log "Validating input..."

if [ -z "$DMG_PATH" ] || [ "$DMG_PATH" = "." ]; then
  log_error "Usage: $0 <path-to-.dmg-file>"
  exit 1
fi

if [ ! -f "$DMG_PATH" ]; then
  log_error "DMG file not found: $DMG_PATH"
  exit 1
fi

if [[ ! "$DMG_PATH" == *.dmg ]]; then
  log_error "Input must be a .dmg file: $DMG_PATH"
  exit 1
fi

log_success "DMG file found: $DMG_PATH"

# Step 2: Find Developer ID in Keychain
log "Searching for Developer ID Application certificate in Keychain..."

DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | awk -F'"' '{print $2}' | head -1 || true)

if [ -z "$DEVELOPER_ID" ]; then
  log_error "Developer ID Application certificate not found in Keychain"
  echo ""
  echo "To create or install a Developer ID certificate:"
  echo "  1. Go to https://developer.apple.com/account"
  echo "  2. Navigate to Certificates > Identifiers & Profiles"
  echo "  3. Select 'Developer ID Application' certificate"
  echo "  4. Download and install in Keychain"
  echo ""
  echo "To verify available certificates:"
  echo "  security find-identity -v -p codesigning"
  exit 1
fi

log_success "Found certificate: $DEVELOPER_ID"

# Step 3: Code-sign the DMG
log "Code signing DMG with Developer ID certificate..."

if ! codesign \
  -s "$DEVELOPER_ID" \
  --timestamp \
  --verbose \
  "$DMG_PATH"; then
  log_error "Code signing failed"
  echo ""
  echo "Possible causes:"
  echo "  - Certificate is expired or invalid"
  echo "  - DMG file is read-only (check: ls -la $DMG_PATH)"
  echo "  - Disk is full or permission denied"
  echo ""
  echo "Try re-importing certificate in Keychain Access or check:"
  echo "  security find-identity -v -p codesigning"
  exit 1
fi

log_success "DMG code signing complete"

# Step 4: Verify signature
log "Verifying DMG signature..."

if ! codesign -v "$DMG_PATH"; then
  log_error "Signature verification failed"
  exit 1
fi

log_success "Signature verification passed"

# Success
echo ""
echo "=================================================="
log_success "DMG signing complete!"
echo "=================================================="
echo ""
log_success "DMG is code-signed and ready for distribution"
echo "  Path: $DMG_PATH"
echo ""
log_info "The DMG and the signed .app bundle inside are now validated by Apple security."
echo ""
