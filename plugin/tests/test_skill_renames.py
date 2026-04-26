"""Tests for the sq- skill rename pass.

Verifies that every renamed skill exists with the new name,
every old name still exists as an alias stub that forwards,
and that the retired :earnings + check stubs are in place.
"""

import os
import re

PLUGIN_ROOT = os.path.join(os.path.dirname(__file__), "..")
SKILLS_DIR = os.path.join(PLUGIN_ROOT, "skills")


# Each entry: (old_name, new_name). For retire-only entries, new_name is None.
RENAMES = [
    ("login", "sq-login"),
    ("status", "sq-status"),
    ("settings", "sq-settings"),
    ("feedback", "sq-feedback"),
    ("retrigger", "sq-retrigger"),
    ("do-not-disturb", "sq-do-not-disturb"),
    ("reinstall", "sq-update"),
    ("sq-reinstall", "sq-update"),
    ("uninstall", "sq-uninstall"),
]

# :check forwards to :sq-status (no new dir of its own).
ALIAS_ONLY = [
    ("check", "sq-status"),
]

# Retired entirely (no forward target).
RETIRED = ["earnings"]


def read_skill_md(skill_dir):
    """Return the SKILL.md contents as a string."""
    path = os.path.join(SKILLS_DIR, skill_dir, "SKILL.md")
    with open(path, encoding="utf-8") as fp:
        return fp.read()


def parse_frontmatter_name(skill_md):
    """Extract the `name:` field from YAML frontmatter."""
    m = re.search(r"^name:\s*(\S+)", skill_md, re.MULTILINE)
    assert m, f"SKILL.md missing `name:` frontmatter:\n{skill_md[:200]}"
    return m.group(1)


def test_new_sq_skills_exist_with_correct_name():
    """Every renamed skill exists at sq-<name>/SKILL.md and the name field matches."""
    for _old, new in RENAMES:
        path = os.path.join(SKILLS_DIR, new, "SKILL.md")
        assert os.path.isfile(path), f"missing renamed skill: {new}/SKILL.md"
        name = parse_frontmatter_name(read_skill_md(new))
        assert name == new, f"{new}/SKILL.md frontmatter name is {name!r}, want {new!r}"


def test_alias_stubs_for_renamed_skills():
    """Every old name still exists as a stub that forwards to its new name."""
    for old, new in RENAMES:
        path = os.path.join(SKILLS_DIR, old, "SKILL.md")
        assert os.path.isfile(path), f"missing alias stub: {old}/SKILL.md"
        body = read_skill_md(old)
        name = parse_frontmatter_name(body)
        assert name == old, f"{old}/SKILL.md name is {name!r}, want {old!r}"
        assert f"/sidequest:{new}" in body, (
            f"{old}/SKILL.md does not forward to /sidequest:{new}"
        )


def test_check_alias_forwards_to_sq_status():
    """:check forwards to :sq-status (legacy diagnostic name)."""
    for old, target in ALIAS_ONLY:
        path = os.path.join(SKILLS_DIR, old, "SKILL.md")
        assert os.path.isfile(path), f"missing alias stub: {old}/SKILL.md"
        body = read_skill_md(old)
        assert f"/sidequest:{target}" in body, (
            f"{old}/SKILL.md does not forward to /sidequest:{target}"
        )


def test_retired_earnings_stub():
    """:earnings exists but is marked retired (no forward target)."""
    for old in RETIRED:
        path = os.path.join(SKILLS_DIR, old, "SKILL.md")
        assert os.path.isfile(path), f"missing retired stub: {old}/SKILL.md"
        body = read_skill_md(old).lower()
        assert "retired" in body or "removed" in body, (
            f"{old}/SKILL.md does not signal retirement"
        )
        # Sanity: must NOT contain earnings/payout copy.
        assert "earn" not in body or "no earn" in body or "earnings retired" in body, (
            f"{old}/SKILL.md still contains live earnings copy"
        )


def test_no_new_sq_skill_lists_old_name_in_active_doc():
    """sq-<x> skill bodies must not reference old /sidequest:<bare> commands.

    Canonical sq- skills should always steer users to the sq- name, not the
    deprecated alias — otherwise the LLM follows the old name to the alias
    stub which then forwards back, an extra hop and a worse experience.
    """
    for _old, new in RENAMES:
        body = read_skill_md(new)
        for old_name, _new_name in RENAMES:
            ref = f"/sidequest:{old_name} "
            assert ref not in body, (
                f"{new}/SKILL.md references old command {ref.strip()}; "
                f"use /sidequest:sq-{old_name} instead"
            )
            # Catch line-end occurrences too.
            for terminator in ("\n", ".", ",", "`", '"', "'", ")"):
                ref2 = f"/sidequest:{old_name}{terminator}"
                assert ref2 not in body, (
                    f"{new}/SKILL.md references old command "
                    f"/sidequest:{old_name} (followed by {terminator!r}); "
                    f"use /sidequest:sq-{old_name} instead"
                )
