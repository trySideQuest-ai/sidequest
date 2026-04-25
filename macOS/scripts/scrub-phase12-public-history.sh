#!/bin/bash
# Scrub Phase 12 public history for auditor-safe commit subjects
# This script rewrites commit history to remove internal phase numbers from subjects.
#
# Usage: Run this from the client/ directory after review:
#   cd client
#   bash macOS/scripts/scrub-phase12-public-history.sh
#
# WARNING: This performs a destructive rewrite of git history.
# Only run after verifying the commits to be rewritten.
# Will require: git push --force-with-lease origin main

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

echo "Phase 12 Public History Scrubber"
echo "=================================="
echo ""
echo "This script will rewrite these commit subjects:"
echo ""
echo "  c818c3d: feat(12-06): extend IPCListener to handle embedding requests"
echo "           -> feat: extend IPCListener to handle embedding requests"
echo ""
echo "  4c74672: feat(12-07,12-08): add parity tests + version bumps"
echo "           -> feat: add embedding parity tests + version bumps"
echo ""
echo "No commits will be rewritten until you explicitly run this script."
echo "After rewriting, you will need to run:"
echo ""
echo "  git push --force-with-lease origin main"
echo ""
echo "Dry-run: To see what would change without actually rewriting, run:"
echo "  git log --oneline | grep '12-0' | head -2"
echo ""
echo "To proceed with rewriting, modify this script to uncomment the rewrite section below."
echo ""

# Rewrite section (disabled by default - uncomment to enable)
# This uses git filter-repo if available, otherwise falls back to git rebase

# Check if git filter-repo is installed
if command -v git-filter-repo &> /dev/null; then
  echo "Using git-filter-repo for safe history rewriting..."

  # Create a temporary commit map file
  MAPFILE=$(mktemp)

  # Define the old and new subjects
  # We'll use a simpler approach: just git rebase with --exec

  echo "ERROR: git-filter-repo method not yet implemented. Use git rebase instead:"
  exit 1
fi

# Alternative: Use git rebase (safer but requires manual intervention)
echo ""
echo "To rewrite commits safely using git rebase:"
echo ""
echo "1. Start an interactive rebase from before these commits:"
echo "   git rebase -i c818c3d~1"
echo ""
echo "2. For both commits with phase numbers, change 'pick' to 'reword'"
echo ""
echo "3. Edit each commit subject to remove the phase number:"
echo "   OLD: feat(12-06): extend IPCListener to handle embedding requests"
echo "   NEW: feat: extend IPCListener to handle embedding requests"
echo ""
echo "   OLD: feat(12-07,12-08): add parity tests + version bumps"
echo "   NEW: feat: add embedding parity tests + version bumps"
echo ""
echo "4. After the rebase completes, force-push:"
echo "   git push --force-with-lease origin main"
echo ""
echo "5. Verify the history is correct:"
echo "   git log --oneline | head -10"
echo ""
