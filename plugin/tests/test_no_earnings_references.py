"""Verify the public repo contains no live earnings / payout / NIS copy.

The rev-share feature was retired on 2026-04-21. Public-facing docs
must not advertise it. The retired-stub SKILL.md for /sidequest:earnings
is the ONE allowed exception.
"""

import os
import re

PLUGIN_ROOT = os.path.join(os.path.dirname(__file__), "..")
REPO_ROOT = os.path.abspath(os.path.join(PLUGIN_ROOT, ".."))


# Forbidden patterns. Word boundaries used to avoid `learn`, `Tunisia`, etc.
FORBIDDEN = [
    re.compile(r"\bearn\b", re.IGNORECASE),
    re.compile(r"\bearnings\b", re.IGNORECASE),
    re.compile(r"\bpayout\b", re.IGNORECASE),
    re.compile(r"2\.5\s*NIS\b"),
    re.compile(r"\bNIS\b"),
]

# Files allowed to mention the retired feature.
# - earnings/SKILL.md is the retired stub itself (must signal retirement).
# - test files reference the forbidden words as the strings being tested for.
EXEMPT = {
    os.path.join(REPO_ROOT, "plugin/skills/earnings/SKILL.md"),
    os.path.join(REPO_ROOT, "plugin/tests/test_no_earnings_references.py"),
    os.path.join(REPO_ROOT, "plugin/tests/test_skill_renames.py"),
}


def iter_text_files():
    """Yield every public-facing text file we want to scan."""
    for base in [REPO_ROOT]:
        for dirpath, dirnames, filenames in os.walk(base):
            # Prune ignored directories.
            dirnames[:] = [
                d for d in dirnames
                if d not in {".git", "node_modules", "__pycache__", ".pytest_cache",
                             "build", "dist", "DerivedData", "worktrees"}
            ]
            for fn in filenames:
                if fn.lower().endswith(
                    (".md", ".yml", ".yaml", ".json", ".sh", ".py", ".swift",
                     ".plist", ".js", ".ts", ".html", ".txt")
                ):
                    yield os.path.join(dirpath, fn)


def test_no_forbidden_strings_in_public_docs():
    offenders = []
    for path in iter_text_files():
        if path in EXEMPT:
            continue
        try:
            with open(path, encoding="utf-8") as fp:
                text = fp.read()
        except (UnicodeDecodeError, OSError):
            continue
        for pat in FORBIDDEN:
            for m in pat.finditer(text):
                # Compute line + column for the offender for a useful error.
                pre = text[: m.start()]
                line = pre.count("\n") + 1
                col = m.start() - (pre.rfind("\n") + 1) + 1
                offenders.append(f"{path}:{line}:{col}: {pat.pattern} matched {m.group(0)!r}")

    assert not offenders, (
        "Forbidden earnings/payout/NIS copy found in public files:\n  "
        + "\n  ".join(offenders[:50])
    )
