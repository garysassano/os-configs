#!/usr/bin/env python3
"""Exercise repository skill capture and restore with disposable local Git repos."""

import importlib.util
import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "repository_skills", Path(__file__).with_name("repository-skills.py")
)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class RepositorySkillsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=sync.REPOSITORY / ".git")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.root = self.home / "git/diagram-fixture"
        self.skill = self.root / "skill"
        self.skill.mkdir(parents=True)
        (self.skill / "SKILL.md").write_text(
            "---\nname: diagram-fixture\ndescription: Test fixture\n---\n"
        )
        self.git("init", "-q")
        self.git("add", ".")
        self.git(
            "-c",
            "commit.gpgsign=false",
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "Fixture",
        )
        self.git(
            "remote", "add", "origin", "https://github.com/example/diagram-fixture.git"
        )
        self.canonical = self.home / ".agents/skills"
        self.canonical.mkdir(parents=True)
        (self.canonical / "diagram-fixture").symlink_to(self.skill)
        self.manifest = self.base / "repository-skills.json"

    def git(self, *args):
        return sync.run("git", *args, cwd=self.root)

    def capture(self):
        with redirect_stdout(StringIO()):
            sync.capture(self.home, self.manifest)

    def test_capture_excludes_other_account_trees(self):
        excluded = self.home / "git-other/private/skill"
        excluded.mkdir(parents=True)
        (self.canonical / "excluded").symlink_to(excluded)
        self.capture()
        records = json.loads(self.manifest.read_text())["skills"]
        self.assertEqual([r["name"] for r in records], ["diagram-fixture"])
        self.assertEqual(records[0]["revision"], self.git("rev-parse", "HEAD"))
        self.assertNotIn("git-other", self.manifest.read_text())

    def test_dirty_capture_preserves_previous_manifest(self):
        self.capture()
        previous = self.manifest.read_bytes()
        (self.skill / "SKILL.md").write_text("uncommitted")
        with self.assertRaisesRegex(ValueError, "Commit"):
            self.capture()
        self.assertEqual(self.manifest.read_bytes(), previous)

    def test_capture_preserves_references_missing_on_this_machine(self):
        self.capture()
        previous = self.manifest.read_bytes()
        (self.canonical / "diagram-fixture").unlink()
        self.capture()
        self.assertEqual(self.manifest.read_bytes(), previous)

    def test_dry_run_and_conflicting_link_preserve_files(self):
        self.capture()
        with redirect_stdout(StringIO()):
            sync.restore(self.home, self.manifest, True)
        link = self.canonical / "diagram-fixture"
        link.unlink()
        link.mkdir()
        marker = link / "local-work"
        marker.write_text("preserve")
        with self.assertRaisesRegex(ValueError, "would be replaced"):
            sync.restore(self.home, self.manifest, False)
        self.assertEqual(marker.read_text(), "preserve")

    def test_existing_checkout_revision_is_not_changed(self):
        self.capture()
        data = json.loads(self.manifest.read_text())
        data["skills"][0]["revision"] = "0" * 40
        self.manifest.write_text(json.dumps(data))
        before = self.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(ValueError, "left unchanged"):
            sync.restore(self.home, self.manifest, False)
        self.assertEqual(self.git("rev-parse", "HEAD"), before)

    def test_restore_new_clone_and_canonical_link(self):
        self.capture()
        restored_home = self.base / "restored"
        wrapper = restored_home / ".local/bin/gh"
        wrapper.parent.mkdir(parents=True)
        wrapper.write_text("fixture")
        fanout = restored_home / ".agents/link.sh"
        fanout.parent.mkdir(parents=True)
        fanout.write_text("#!/bin/sh\nexit 0\n")
        fanout.chmod(0o755)
        original_run = subprocess.run
        calls = []

        def local_clone(args, **kwargs):
            calls.append((args, kwargs.get("cwd")))
            if args[0] == str(wrapper):
                self.assertEqual(kwargs["cwd"], sync.REPOSITORY)
                result = original_run(
                    ["git", "clone", "-q", "--no-checkout", str(self.root), args[4]],
                    **kwargs,
                )
                original_run(
                    [
                        "git",
                        "remote",
                        "set-url",
                        "origin",
                        "https://github.com/example/diagram-fixture.git",
                    ],
                    cwd=args[4],
                    check=True,
                )
                return result
            return original_run(args, **kwargs)

        with (
            patch.object(sync.subprocess, "run", side_effect=local_clone),
            redirect_stdout(StringIO()),
        ):
            sync.restore(restored_home, self.manifest, False)
        clone = restored_home / "git/diagram-fixture"
        self.assertEqual(
            sync.run("git", "rev-parse", "HEAD", cwd=clone),
            self.git("rev-parse", "HEAD"),
        )
        self.assertEqual(
            (restored_home / ".agents/skills/diagram-fixture").resolve(),
            clone / "skill",
        )
        self.assertEqual(
            (clone / "skill/SKILL.md").read_bytes(),
            (self.skill / "SKILL.md").read_bytes(),
        )
        self.assertEqual(calls[-1][0], [str(fanout)])


if __name__ == "__main__":
    unittest.main()
