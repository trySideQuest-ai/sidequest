#!/bin/bash

# Package the SideQuest plugin for distribution
#
# Creates a tarball that the setup script downloads and extracts
# into ~/.claude/plugins/cache/sidequest-plugin/sidequest/<version>/
#
# Usage:
#   ./scripts/package-plugin.sh                    # Package latest
#   ./scripts/package-plugin.sh --output dist/     # Custom output dir
#   ./scripts/package-plugin.sh --version 0.2.0    # Package with specific version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_DIR="$PROJECT_ROOT/plugin"
VERSION="0.1.0"
OUTPUT_DIR="$PROJECT_ROOT/dist"

while [[ $# -gt 0 ]]; do
  case $1 in
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

# Create plugin directory structure
STAGING="$TEMP_DIR/sidequest-plugin"
mkdir -p "$STAGING"

# Copy plugin files
cp -r "$PLUGIN_DIR/.claude-plugin" "$STAGING/"
cp -r "$PLUGIN_DIR/hooks" "$STAGING/"
cp -r "$PLUGIN_DIR/scripts" "$STAGING/"
cp -r "$PLUGIN_DIR/skills" "$STAGING/"
cp "$PLUGIN_DIR/VERSION" "$STAGING/" 2>/dev/null || true
cp "$PLUGIN_DIR/README.md" "$STAGING/" 2>/dev/null || true

# Remove __pycache__ and other artifacts
find "$STAGING" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$STAGING" -name "*.pyc" -delete 2>/dev/null || true

# Create tarball with deterministic timestamp for reproducible builds
# Note: macOS tar doesn't support --sort=name, --owner, --group, --numeric-owner flags
# but deterministic mtime helps; GitHub Actions runner uses GNU tar with full flags
TARBALL="$OUTPUT_DIR/sidequest-plugin-$VERSION.tar.gz"

# Use different tar flags based on tar version
if tar --version 2>&1 | grep -q GNU; then
  # GNU tar (available on GitHub Actions Ubuntu runner)
  tar \
    --sort=name \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mtime='2026-01-01 00:00 UTC' \
    -czf "$TARBALL" \
    -C "$TEMP_DIR" \
    "sidequest-plugin"
else
  # BSD tar (macOS)
  tar \
    -czf "$TARBALL" \
    -C "$TEMP_DIR" \
    "sidequest-plugin"
fi

SHA256=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)

echo "Plugin packaged: $TARBALL"
echo "Size: $(du -h "$TARBALL" | cut -f1)"
echo "SHA256: $SHA256"
echo "Version: $VERSION"
echo ""
echo "Upload to S3:"
echo "  aws s3 cp $TARBALL s3://sidequest-releases/"
echo ""
echo "Update remote-config.json with:"
echo "  \"plugin_version\": \"$VERSION\","
echo "  \"plugin_sha256\": \"$SHA256\","
echo "  \"plugin_tarball_url\": \"https://get.trysidequest.ai/sidequest-plugin-$VERSION.tar.gz\""
