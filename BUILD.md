# Building SideQuest Client — Reproducible Verification Guide

This guide allows you to audit the SideQuest plugin and macOS app source code and verify that the binaries distributed in GitHub Releases were built faithfully from the published source.

## Prerequisites

**System Requirements:**
- macOS 14.0 or later
- Xcode 15.2 or later (Command Line Tools sufficient for plugin, full Xcode required for app)
- Git 2.36 or later
- Bash 5.0 or later

**Check your versions:**
```bash
sw_vers                          # macOS version
xcodebuild -version              # Xcode version (should show 15.2+)
git --version                    # Git version
bash --version                   # Bash version
```

**Optional Tools for Verification:**
- `shasum` (built-in on macOS)
- `codesign` (built-in with Xcode, for app signature verification)
- `spctl` (built-in on macOS, for Gatekeeper/notarization verification)

---

## Building from Source

### Plugin Tarball

The SideQuest plugin is a portable Bash/Python package that installs into the Claude CLI. You can build and verify it locally.

**1. Clone the Repository at a Specific Release Tag**

To audit the exact code that was released, clone at the release tag:

```bash
# Example: clone at plugin release v0.2.0
git clone --depth 1 --branch plugin-v0.2.0 https://github.com/tomer-shavit/sidequest.git
cd sidequest
```

Verify you're at the correct tag:
```bash
git describe --tags HEAD
# Expected output: plugin-v0.2.0
```

**2. Build the Plugin Tarball**

The build script uses deterministic flags (`--sort=name --mtime`) to ensure reproducible archives:

```bash
# Build plugin with current tag version
./scripts/package-plugin.sh

# Output file: dist/sidequest-plugin-0.2.0.tar.gz (version from tag)
# Example output:
# ✓ Plugin packaged: dist/sidequest-plugin-0.2.0.tar.gz
#   Size: 128K
#   SHA256: abc123def456...
#   Version: 0.2.0
```

**3. Compute SHA256 of Local Build**

```bash
shasum -a 256 dist/sidequest-plugin-*.tar.gz
# Output: abc123def456... dist/sidequest-plugin-0.2.0.tar.gz
```

**4. Verify Against GitHub Release**

1. Navigate to https://github.com/tomer-shavit/sidequest/releases/tag/plugin-v0.2.0
2. In the **Release Notes** section, find the SHA256 hash for the plugin tarball
3. Compare with your local build:

```bash
# Expected: Your SHA256 matches the Release Notes exactly
echo "Expected: <paste-from-release-notes>"
echo "Got:      abc123def456..."
```

If they match, the plugin binary was built faithfully from the published source.

---

### macOS App DMG

The SideQuest app is a native macOS application built with Xcode. Code signing and notarization are performed by Apple's infrastructure.

**1. Clone at Release Tag**

```bash
git clone --depth 1 --branch app-v1.8.0 https://github.com/tomer-shavit/sidequest.git
cd sidequest
```

**2. Build the App**

The app requires Xcode (full IDE, not just Command Line Tools):

```bash
cd macOS

# Build archive
xcodebuild \
  -scheme SideQuestApp \
  -configuration Release \
  -derivedDataPath build \
  archive

# Create DMG from archive
cd ..
./macOS/scripts/create-dmg.sh
```

Expected output:
```
dist/SideQuestApp-1.8.0.dmg (size ~50-80MB)
```

**3. Compute SHA256 of Local Build**

```bash
shasum -a 256 dist/SideQuestApp-*.dmg
# Output: abc123def456... dist/SideQuestApp-1.8.0.dmg
```

**4. Verify Against GitHub Release**

1. Navigate to https://github.com/tomer-shavit/sidequest/releases/tag/app-v1.8.0
2. Find the DMG SHA256 in Release Notes
3. Compare:

```bash
echo "Expected: <paste-from-release-notes>"
echo "Got:      abc123def456..."
```

---

## Verifying Code Signatures and Notarization

SideQuest app binaries are code-signed and notarized by Apple. You can verify the signatures locally:

### Verify Code Signature

```bash
# Download the DMG from GitHub Releases
curl -L -o SideQuestApp-1.8.0.dmg \
  https://github.com/tomer-shavit/sidequest/releases/download/app-v1.8.0/SideQuestApp-1.8.0.dmg

# Mount the DMG
hdiutil mount SideQuestApp-1.8.0.dmg

# Verify the signature (detailed output)
codesign -vv --deep --strict /Volumes/SideQuestApp/SideQuestApp.app

# Expected output (last line): valid on disk
```

If signature is invalid, the app has been tampered with after release.

### Verify Notarization Status

Notarization confirms the app was scanned by Apple for malware:

```bash
# Verify notarization (requires Xcode Command Line Tools)
spctl -a -t exec -vvv /Volumes/SideQuestApp/SideQuestApp.app

# Expected output includes "accepted" and shows the notarization ticket date
# Example: accepted source=Notarized Developer ID
```

If notarization check fails, the app cannot be safely launched on other Macs (Gatekeeper will block it).

---

## Reproducibility Notes

### Deterministic Plugin Builds

The plugin build script uses reproducible archive flags:

- `--sort=name` — files ordered alphabetically (reproducible across systems)
- `--mtime=@{EPOCH}` — all files timestamped to commit date (from `git log`)
- `--owner=0 --group=0` — all files owned by root (portable across systems)
- `--numeric-owner` — UIDs/GIDs use numeric values (not user names, which vary)

Two builds of the same tagged version should produce identical SHA256 hashes.

### Xcode App Builds

The macOS app build uses:

- **Xcode version:** Pinned to 15.2 via `.xcode-version` file
- **Build configuration:** Release (optimized, code-signed)
- **Deterministic timestamps:** `SOURCE_DATE_EPOCH` environment variable set to commit timestamp
- **Code signing identity:** Apple Developer ID (read from Xcode project settings)

Note: macOS app binaries cannot be made byte-identical due to Apple's notarization chain and timestamps embedded by the compiler. However, the plugin tarball can be reproduced exactly.

### Environment Variables Used

```bash
# Set automatically during build
export SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
export TZ=UTC
export ZERO_AR_DATE=1  # macOS archiver determinism
```

These ensure consistent timestamps across builds.

---

## Troubleshooting

### Plugin Build Fails

**Error: `package-plugin.sh: No such file or directory`**
- Ensure you're in the repo root (`sidequest/`)
- Verify `scripts/package-plugin.sh` exists: `ls -la scripts/package-plugin.sh`

**Error: `tar: Unknown option --sort=name`**
- macOS ships with BSD tar; install GNU tar via Homebrew:
  ```bash
  brew install gnu-tar
  export PATH="/usr/local/opt/gnu-tar/libexec/gnubin:$PATH"
  ```

### App Build Fails

**Error: `xcodebuild: command not found`**
- Install Xcode: `xcode-select --install`
- Or launch Xcode from `/Applications/` at least once

**Error: `Xcode 15.2 not found` (if using different version)**
- Pinned Xcode version may not be available on your system
- Edit `.xcode-version` to your installed version (e.g., `16.0`)
- Note: reproducibility is best-effort with different Xcode versions

**Error: `Code signing failed`**
- Only Apple Developer ID credentials can sign the app
- For local builds, use ad-hoc signing (remove signing requirements for testing)

### SHA256 Mismatch

**If your local build SHA256 doesn't match the Release:**

1. **Verify your tag:** `git describe --tags HEAD` should match the release tag
2. **Check tool versions:** Xcode or tar version mismatch can affect output
3. **Report the issue:** File a GitHub issue with:
   - Your macOS version
   - Your Xcode version
   - Your local SHA256
   - Link to the Release notes SHA256

---

## Security Considerations

### What This Verification Proves

✓ The published binary was built from the source code at the tagged commit  
✓ The binary has not been tampered with since release  
✓ The macOS app is signed and notarized by Apple  
✓ The plugin tarball is packaged deterministically  

### What This Verification Does NOT Prove

✗ The source code is secure or bug-free (code review is separate)  
✗ The binary is free from all vulnerabilities  
✗ Future builds will be identical (toolchain updates may affect results)  

For security concerns, open an issue on GitHub or contact tomer.shavit5@gmail.com.

---

## FAQ

**Q: Can I install the app I built locally?**
A: Yes. Mount the DMG and drag SideQuestApp.app to /Applications. Verify signature and notarization as described above before running.

**Q: Will my locally-built plugin work with the Claude CLI?**
A: Yes. Extract the tarball and follow the installation instructions in the main README.md.

**Q: Why is the macOS app not byte-identical after rebuild?**
A: Xcode and Apple's notarization chain embed non-deterministic timestamps. However, the binary is verifiable via signature and SHA256 of the distribution artifact (DMG file).

**Q: What if I don't trust GitHub Releases SHA256 links?**
A: Clone the repo and verify signatures directly via `codesign` and `spctl` on the installed app. This proves Apple notarized the code.

---

## References

- [Reproducible Builds](https://reproducible-builds.org/) — Archive metadata standards, SOURCE_DATE_EPOCH spec
- [GNU tar Manual: Making Archives More Reproducible](https://www.gnu.org/software/tar/manual/html_section/Reproducibility.html)
- [macOS Code Signing and Notarization](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)
- [WWDC 2019 Session 703: All About Notarization](https://developer.apple.com/videos/play/wwdc2019/703/)

---

**Last updated:** 2026-04-18  
**Valid for releases:** v0.2.0 (plugin) and v1.8.0 (app) and later, following the same patterns
