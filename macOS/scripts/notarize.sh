#!/bin/bash

# Notarize SideQuest macOS App with Apple Notary Service
#
# This script submits the signed .app or .dmg to Apple's notarization service,
# polls for completion (with explicit 30-minute timeout and automatic 3x retry),
# and staples the notarization ticket to the app bundle.
#
# Prerequisites:
# 1. App must be code-signed with Developer ID certificate (from build-and-sign.sh)
# 2. Apple Developer account with app-specific password
#
# Environment variables (required before running):
#   export APPLE_ID=<your-apple-developer-email>
#   export APPLE_TEAM_ID=<your-10-char-team-id>
#   export APPLE_PASSWORD=<your-app-specific-password>
#
# Or store password in macOS Keychain:
#   security add-generic-password -s "apple-notarization" -a "$APPLE_ID" -w <your-password>
#
# Usage:
#   ./macOS/scripts/notarize.sh build/Release/SideQuest.app [--timeout 30m]
#   ./macOS/scripts/notarize.sh build/Release/SideQuest.dmg --timeout 30m

set -euo pipefail

# Configuration
APP_PATH="${1:-.}"
TIMEOUT="${2:-30m}"
MAX_RETRIES=3

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
trap 'log_error "Notarization failed"; exit 1' ERR

# Step 1: Validate input
log "Validating input..."

if [ -z "$APP_PATH" ] || [ "$APP_PATH" = "." ]; then
  log_error "Usage: $0 <path-to-.app-or-.dmg> [--timeout 30m]"
  exit 1
fi

if [ ! -f "$APP_PATH" ] && [ ! -d "$APP_PATH" ]; then
  log_error "Path does not exist: $APP_PATH"
  exit 1
fi

IS_DMG=0
IS_APP=0

if [[ "$APP_PATH" == *.dmg ]]; then
  if [ ! -f "$APP_PATH" ]; then
    log_error "DMG file not found: $APP_PATH"
    exit 1
  fi
  IS_DMG=1
  log_success "DMG file found: $APP_PATH"
elif [[ "$APP_PATH" == *.app ]]; then
  if [ ! -d "$APP_PATH" ]; then
    log_error ".app bundle not found: $APP_PATH"
    exit 1
  fi
  IS_APP=1
  log_success ".app bundle found: $APP_PATH"
else
  log_error "Input must be .app bundle or .dmg file: $APP_PATH"
  exit 1
fi

# Step 2: Validate environment variables
log "Checking environment variables..."

if [ -z "${APPLE_ID:-}" ]; then
  log_error "APPLE_ID environment variable not set"
  echo ""
  echo "Set your Apple Developer email:"
  echo "  export APPLE_ID=<your-apple-developer-email>"
  exit 1
fi
log_success "APPLE_ID set: $APPLE_ID"

if [ -z "${APPLE_TEAM_ID:-}" ]; then
  log_error "APPLE_TEAM_ID environment variable not set"
  echo ""
  echo "Get your Team ID from:"
  echo "  Apple Developer account > Settings > Team ID (10-character code)"
  echo ""
  echo "Set it with:"
  echo "  export APPLE_TEAM_ID=<your-10-char-team-id>"
  exit 1
fi
log_success "APPLE_TEAM_ID set: $APPLE_TEAM_ID"

# Step 3: Check for app-specific password
log "Checking for Apple app-specific password..."

APPLE_PASSWORD_SOURCE=""
if [ -n "${APPLE_PASSWORD:-}" ]; then
  APPLE_PASSWORD_SOURCE="environment variable"
  log_success "Using APPLE_PASSWORD from environment"
else
  # Try to read from Keychain
  KEYCHAIN_PASSWORD=$(security find-generic-password -s "apple-notarization" -a "$APPLE_ID" -w 2>/dev/null || true)
  if [ -n "$KEYCHAIN_PASSWORD" ]; then
    APPLE_PASSWORD="$KEYCHAIN_PASSWORD"
    APPLE_PASSWORD_SOURCE="Keychain"
    log_success "Found password in Keychain"
  fi
fi

if [ -z "${APPLE_PASSWORD:-}" ]; then
  log_error "App-specific password not found"
  echo ""
  echo "Generate app-specific password:"
  echo "  1. Go to https://appleid.apple.com"
  echo "  2. Sign in with your Apple ID"
  echo "  3. Navigate to 'Sign in and security' > 'App passwords'"
  echo "  4. Generate new password for 'SideQuest Notarization'"
  echo "  5. Copy password and set environment variable:"
  echo "     export APPLE_PASSWORD=<your-app-specific-password>"
  echo ""
  echo "Or save password to Keychain (one-time setup):"
  echo "  security add-generic-password -s 'apple-notarization' -a '\$APPLE_ID' -w <your-password>"
  exit 1
fi

# Step 4: Prepare for submission
log "Preparing for submission..."

ZIP_FILE=""
STAPLE_PATH="$APP_PATH"

if [ $IS_APP -eq 1 ]; then
  # Create ZIP archive for submission
  ZIP_FILE="${APP_PATH%.app}.zip"
  log "Creating ZIP archive for submission: $ZIP_FILE"

  if [ -f "$ZIP_FILE" ]; then
    rm -f "$ZIP_FILE"
  fi

  if ! ditto -c -k --sequesterRsrc "$APP_PATH" "$ZIP_FILE"; then
    log_error "Failed to create ZIP archive"
    exit 1
  fi

  log_success "ZIP archive created: $ZIP_FILE"
else
  # Use DMG directly for notarization
  ZIP_FILE="$APP_PATH"
  log_success "Using DMG directly for notarization"
fi

# Step 5: Submit to notarization service with retry logic
log "Submitting to Apple notarization service..."
log_info "Timeout: $TIMEOUT"
log_info "Max retries: $MAX_RETRIES"
log_info "This may take several minutes to start processing..."

for attempt in $(seq 1 $MAX_RETRIES); do
  log ""
  log "====== Notarization attempt $attempt/$MAX_RETRIES ======"

  SUBMIT_OUTPUT=$(xcrun notarytool submit \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait \
    --timeout "$TIMEOUT" \
    "$ZIP_FILE" 2>&1 || true)

  echo "$SUBMIT_OUTPUT"

  # Extract REQUEST_ID from output
  REQUEST_ID=$(echo "$SUBMIT_OUTPUT" | grep -oP 'id: \K[a-f0-9-]+' | head -1 || true)

  if [ -z "$REQUEST_ID" ]; then
    log_error "Failed to extract submission ID from notarization service"
    if [ $attempt -lt $MAX_RETRIES ]; then
      BACKOFF=$((2 ** attempt))
      log_info "Retrying in ${BACKOFF}s..."
      sleep "$BACKOFF"
      continue
    else
      echo ""
      echo "Full output from notarytool:"
      echo "$SUBMIT_OUTPUT"
      exit 1
    fi
  fi

  log_success "Submission ID: $REQUEST_ID"

  # Step 6: Check final status with explicit "Accepted" match
  log "Checking notarization status..."

  # Extract status from output
  STATUS=$(echo "$SUBMIT_OUTPUT" | grep -i "status:" | tail -1 || true)
  log_info "Status: $STATUS"

  # Explicitly check for "Accepted" string
  if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    log_success "Notarization accepted!"

    # Step 7: Staple notarization ticket to app
    log "Stapling notarization ticket to app..."

    if ! xcrun stapler staple "$STAPLE_PATH"; then
      log_error "Failed to staple notarization ticket"
      echo ""
      echo "Try again manually with:"
      echo "  xcrun stapler staple \"$STAPLE_PATH\""
      exit 1
    fi

    log_success "Notarization ticket stapled"

    # Step 8: Validate staple
    log "Validating staple..."

    if ! xcrun stapler validate "$STAPLE_PATH"; then
      log_error "Staple validation failed"
      exit 1
    fi

    log_success "Staple validation passed"

    # Step 9: Clean up
    if [ $IS_APP -eq 1 ] && [ -f "$ZIP_FILE" ]; then
      rm -f "$ZIP_FILE"
      log_success "Cleaned up temporary ZIP archive"
    fi

    # Success
    echo ""
    echo "=================================================="
    log_success "Notarization complete!"
    echo "=================================================="
    echo ""
    log_success "App is notarized and ready for distribution"
    echo "  Stapled: $STAPLE_PATH"
    echo ""
    exit 0
  elif echo "$SUBMIT_OUTPUT" | grep -qi "Invalid\|Rejected"; then
    log_error "Notarization rejected"
    echo ""
    echo "Fetching detailed rejection log (REQUEST_ID: $REQUEST_ID)..."
    echo ""

    xcrun notarytool log "$REQUEST_ID" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" || true

    if [ $attempt -lt $MAX_RETRIES ]; then
      BACKOFF=$((2 ** attempt))
      log_info "Retrying in ${BACKOFF}s..."
      sleep "$BACKOFF"
      continue
    else
      exit 1
    fi
  else
    # Status unclear or still in progress
    log_error "Could not determine notarization status or status is not Accepted"
    echo ""
    echo "Request ID: $REQUEST_ID"
    echo ""
    echo "Check status manually with:"
    echo "  xcrun notarytool info \"$REQUEST_ID\" \\"
    echo "    --apple-id \"$APPLE_ID\" \\"
    echo "    --password \"$APPLE_PASSWORD\" \\"
    echo "    --team-id \"$APPLE_TEAM_ID\""
    echo ""
    if [ $attempt -lt $MAX_RETRIES ]; then
      BACKOFF=$((2 ** attempt))
      log_info "Retrying in ${BACKOFF}s..."
      sleep "$BACKOFF"
      continue
    else
      echo "Error: Notarization failed after $MAX_RETRIES attempts"
      exit 1
    fi
  fi
done

log_error "Notarization failed after $MAX_RETRIES attempts"
exit 1
