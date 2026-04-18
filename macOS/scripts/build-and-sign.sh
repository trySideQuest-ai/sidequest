#!/bin/bash

# Build and Code Sign SideQuest macOS App
#
# Code Signing Checklist (run before ./build-and-sign.sh):
# 1. Apple Developer account with paid membership
# 2. Generate Developer ID Application certificate (if not already done)
# 3. Install certificate in Keychain (download .p12 from Developer account)
# 4. Verify cert is in Keychain: security find-identity -v -p codesigning
# 5. Look for "Developer ID Application" in output
# If missing: run ./build-ad-hoc.sh instead (for development/testing)

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

echo "Building SideQuest macOS App with Code Signing"
echo "================================================"

# Step 1: Validate Xcode installation
echo -n "Checking Xcode installation... "
if ! xcode-select -p &> /dev/null; then
  echo -e "${RED}ERROR${NC}"
  echo "Xcode is not installed or not properly configured."
  echo "Install Xcode from App Store or run: xcode-select --install"
  exit 1
fi
XCODE_PATH=$(xcode-select -p)
echo -e "${GREEN}OK${NC} ($XCODE_PATH)"

# Step 2: Find Developer ID Application certificate in Keychain
echo -n "Finding Developer ID Application certificate... "
DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | awk -F'"' '{print $2}' | head -1)

if [ -z "$DEVELOPER_ID" ]; then
  echo -e "${RED}NOT FOUND${NC}"
  echo ""
  echo "No Developer ID Application certificate found in Keychain."
  echo ""
  echo "To fix this:"
  echo "1. Log into https://developer.apple.com/account"
  echo "2. Navigate to Certificates > Identifiers & Profiles"
  echo "3. Click '+' to create new certificate"
  echo "4. Select 'Developer ID Application' (NOT 'Apple Development')"
  echo "5. Complete the signing request (use Keychain Access > Certificate Assistant)"
  echo "6. Download the .cer file and double-click to install in Keychain"
  echo ""
  echo "For local testing without a certificate, use: ./build-ad-hoc.sh"
  exit 1
fi
echo -e "${GREEN}OK${NC}"
echo "  Certificate: $DEVELOPER_ID"

# Step 3: Clean previous build
echo -n "Cleaning previous build... "
rm -rf "$BUILD_DIR"
echo -e "${GREEN}OK${NC}"

# Step 4: Build archive with xcodebuild
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

# Step 5: Export archive to .app bundle
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

# Step 6: Verify hardened runtime is enabled
echo -n "Verifying hardened runtime entitlements... "
if codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "hardened-runtime"; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${YELLOW}WARNING${NC}"
  echo "Hardened runtime entitlements not found."
  echo "The app may not notarize. Check entitlements.plist in Xcode."
fi

# Step 7: Code sign with Developer ID certificate
echo ""
echo -n "Code signing with Developer ID certificate... "
if ! codesign \
  -s "$DEVELOPER_ID" \
  --options runtime \
  --timestamp \
  --verbose \
  "$APP_PATH" &>/dev/null; then
  echo -e "${RED}FAILED${NC}"
  echo "Code signing failed. Check that:"
  echo "  - Certificate is valid and not expired"
  echo "  - App bundle is readable: ls -la '$APP_PATH'"
  echo "  - Try re-importing certificate in Keychain Access"
  exit 1
fi
echo -e "${GREEN}OK${NC}"

# Step 8: Verify signature
echo -n "Verifying signature... "
if ! codesign -v "$APP_PATH" &>/dev/null; then
  echo -e "${RED}FAILED${NC}"
  echo "Signature verification failed. App may be corrupted."
  exit 1
fi
echo -e "${GREEN}OK${NC}"

# Success
echo ""
echo "================================================"
echo -e "${GREEN}✓ Signed app ready for distribution:${NC}"
echo "  $APP_PATH"
echo ""
echo "Next steps:"
echo "  1. Test the app: open '$APP_PATH'"
echo "  2. Notarize: ./macOS/scripts/notarize.sh '$APP_PATH'"
echo "  3. Create DMG: ./macOS/scripts/distribute.sh"
echo ""
