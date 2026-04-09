#!/bin/bash

# Development Ad-Hoc Signing for SideQuest macOS App
#
# Use this for local testing without a Developer ID certificate.
# Ad-hoc signed apps will not notarize and will show security warnings to users.
# For production release, use ./build-and-sign.sh with a Developer ID certificate.

set -euo pipefail

# Configuration
SCHEME="${1:-SideQuestApp}"
CONFIGURATION="${2:-Release}"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/SideQuest.xcarchive"
APP_PATH="$BUILD_DIR/Release/SideQuest.app"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Building SideQuest macOS App with Ad-Hoc Signing"
echo "================================================="

# Step 1: Validate Xcode installation
echo -n "Checking Xcode installation... "
if ! xcode-select -p &> /dev/null; then
  echo -e "${RED}ERROR${NC}"
  echo "Xcode is not installed or not properly configured."
  echo "Install Xcode from App Store or run: xcode-select --install"
  exit 1
fi
XCODE_PATH=$(xcode-select -p)
echo -e "${GREEN}OK${NC}"

# Step 2: Clean previous build
echo -n "Cleaning previous build... "
rm -rf "$BUILD_DIR"
echo -e "${GREEN}OK${NC}"

# Step 3: Build archive with xcodebuild
echo ""
echo "Building archive (this may take a few minutes)..."
cd "$PROJECT_DIR"

if ! xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -arch arm64 \
  -arch x86_64 \
  archive \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates; then
  echo ""
  echo -e "${RED}ERROR: Build failed${NC}"
  echo "Check the output above for details. Common causes:"
  echo "  - Missing CocoaPods dependencies: run 'pod install'"
  echo "  - Xcode version too old: run 'xcode-select --install'"
  echo "  - Project settings: verify scheme '$SCHEME' exists in project"
  exit 1
fi

echo -e "${GREEN}Archive created${NC}"

# Step 4: Export archive to .app bundle
echo -n "Exporting archive to .app bundle... "
mkdir -p "$BUILD_DIR/Release"

# Use xcodebuild -exportArchive to extract the .app from the archive
if ! xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$BUILD_DIR/Release" \
  -exportOptionsPlist /dev/null \
  2>/dev/null || [ ! -d "$APP_PATH" ]; then
  # Fallback: Extract .app directly from archive if xcodebuild export fails
  if [ -d "$ARCHIVE_PATH/Products/Applications/SideQuestApp.app" ]; then
    cp -r "$ARCHIVE_PATH/Products/Applications/SideQuestApp.app" "$APP_PATH"
  else
    echo -e "${RED}FAILED${NC}"
    echo "Could not export .app from archive."
    exit 1
  fi
fi
echo -e "${GREEN}OK${NC}"

# Step 5: Ad-hoc code sign (no certificate needed)
echo ""
echo -n "Ad-hoc code signing... "
if ! codesign \
  -s - \
  --options runtime \
  --timestamp \
  "$APP_PATH" &>/dev/null; then
  echo -e "${RED}FAILED${NC}"
  echo "Ad-hoc code signing failed. Check app bundle integrity."
  exit 1
fi
echo -e "${GREEN}OK${NC}"

# Step 6: Verify signature
echo -n "Verifying signature... "
if ! codesign -v "$APP_PATH" &>/dev/null; then
  echo -e "${RED}FAILED${NC}"
  echo "Signature verification failed. App may be corrupted."
  exit 1
fi
echo -e "${GREEN}OK${NC}"

# Success
echo ""
echo "================================================="
echo -e "${GREEN}✓ Ad-hoc signed app ready (development use only):${NC}"
echo "  $APP_PATH"
echo ""
echo "This app has ad-hoc signing and will NOT notarize."
echo "For production release, use: ./build-and-sign.sh"
echo ""
echo "To test locally:"
echo "  open '$APP_PATH'"
echo ""
