#!/bin/bash

# Package the SideQuest plugin for distribution
#
# Creates a deterministic tarball so auditors on any platform (macOS or Linux)
# produce byte-identical output for the same source tree.
#
# Usage:
#   ./scripts/package-plugin.sh                    # Package with default version
#   ./scripts/package-plugin.sh --output dist/     # Custom output dir
#   ./scripts/package-plugin.sh --version 0.2.0    # Package with specific version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_DIR="$PROJECT_ROOT/plugin"
VERSION="0.2.0"
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

STAGING="$TEMP_DIR/sidequest-plugin"
mkdir -p "$STAGING"

cp -r "$PLUGIN_DIR/.claude-plugin" "$STAGING/"
cp -r "$PLUGIN_DIR/hooks" "$STAGING/"
cp -r "$PLUGIN_DIR/scripts" "$STAGING/"
cp -r "$PLUGIN_DIR/skills" "$STAGING/"
cp "$PLUGIN_DIR/VERSION" "$STAGING/" 2>/dev/null || true
cp "$PLUGIN_DIR/README.md" "$STAGING/" 2>/dev/null || true

find "$STAGING" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$STAGING" -name "*.pyc" -delete 2>/dev/null || true
find "$STAGING" -name ".DS_Store" -delete 2>/dev/null || true

TARBALL="$OUTPUT_DIR/sidequest-plugin-$VERSION.tar.gz"

# Deterministic tarball via Python tarfile — works identically on macOS (BSD)
# and Linux (GNU). Normalizes: mtime, uid/gid, uname/gname, file order.
python3 - "$TEMP_DIR" "sidequest-plugin" "$TARBALL" <<'PYEOF'
import gzip, io, os, sys, tarfile

src_root, arcname, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
src_tree = os.path.join(src_root, arcname)

DETERMINISTIC_MTIME = 1735689600  # 2025-01-01 00:00:00 UTC
entries = []
for root, dirs, files in os.walk(src_tree):
    dirs.sort()
    for d in dirs:
        full = os.path.join(root, d)
        rel = os.path.relpath(full, src_root)
        entries.append((rel, full, True))
    for f in sorted(files):
        full = os.path.join(root, f)
        rel = os.path.relpath(full, src_root)
        entries.append((rel, full, False))

entries.sort(key=lambda e: e[0])

# Write gzip with mtime=0 so the gzip header is also deterministic.
with open(out_path, 'wb') as raw:
    with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode='w', format=tarfile.USTAR_FORMAT) as tar:
            for rel, full, is_dir in entries:
                info = tar.gettarinfo(full, arcname=rel)
                info.mtime = DETERMINISTIC_MTIME
                info.uid = 0
                info.gid = 0
                info.uname = ''
                info.gname = ''
                if is_dir:
                    info.mode = 0o755
                    tar.addfile(info)
                else:
                    # Preserve executable bit, normalize everything else
                    exec_bit = 0o111 if (info.mode & 0o111) else 0
                    info.mode = 0o644 | exec_bit
                    with open(full, 'rb') as fh:
                        tar.addfile(info, fh)
PYEOF

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
