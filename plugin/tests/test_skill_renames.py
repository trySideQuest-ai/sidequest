"""Tests for the sq- skill rename pass.

Verifies that every renamed skill exists with the new name
and that no deprecated alias / retired stub directories remain.
"""

import os
import re

PLUGIN_ROOT = os.path.join(os.path.dirname(__file__), "..")
SKILLS_DIR = os.path.join(PLUGIN_ROOT, "skills")


# Canonical sq- skill directories. Every entry must exist with frontmatter `name` matching.
SQ_SKILLS = [
    "sq-login",
    "sq-status",
    "sq-settings",
    "sq-feedback",
    "sq-retrigger",
    "sq-do-not-disturb",
    "sq-update",
    "sq-uninstall",
]

# Old-name directories that must NOT exist anymore (deprecated aliases removed in v0.13.1).
REMOVED_ALIASES = [
    "login",
    "status",
    "settings",
    "feedback",
    "retrigger",
    "do-not-disturb",
    "reinstall",
    "uninstall",
    "check",
    "earnings",
]


def read_skill_md(skill_dir):
    path = os.path.join(SKILLS_DIR, skill_dir, "SKILL.md")
    with open(path, encoding="utf-8") as fp:
        return fp.read()


def parse_frontmatter_name(skill_md):
    m = re.search(r"^name:\s*(\S+)", skill_md, re.MULTILINE)
    assert m, f"SKILL.md missing `name:` frontmatter:\n{skill_md[:200]}"
    return m.group(1)


def test_sq_skills_exist_with_correct_name():
    for new in SQ_SKILLS:
        path = os.path.join(SKILLS_DIR, new, "SKILL.md")
        assert os.path.isfile(path), f"missing skill: {new}/SKILL.md"
        name = parse_frontmatter_name(read_skill_md(new))
        assert name == new, f"{new}/SKILL.md frontmatter name is {name!r}, want {new!r}"


def test_deprecated_alias_dirs_removed():
    for old in REMOVED_ALIASES:
        path = os.path.join(SKILLS_DIR, old)
        assert not os.path.exists(path), (
            f"deprecated alias dir still present: {path}; remove it — only sq- prefixed skills are allowed"
        )


def test_no_sq_skill_references_removed_alias():
    """sq-<x> skill bodies must not reference removed bare /sidequest:<old> commands."""
    for new in SQ_SKILLS:
        body = read_skill_md(new)
        for old in REMOVED_ALIASES:
            for terminator in (" ", "\n", ".", ",", "`", '"', "'", ")"):
                ref = f"/sidequest:{old}{terminator}"
                assert ref not in body, (
                    f"{new}/SKILL.md references removed command "
                    f"/sidequest:{old} (followed by {terminator!r})"
                )
