#!/usr/bin/env python3
"""Capture and restore canonical skills maintained in personal Git repositories."""

import argparse
import json
import re
import subprocess
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
REPOSITORY = SKILL.parents[3]
MANIFEST = SKILL / "references/repository-skills.json"


def run(*args, cwd):
    return subprocess.check_output(
        args, cwd=cwd, text=True, stderr=subprocess.PIPE
    ).strip()


def identity(origin):
    match = re.fullmatch(
        r"(?:https://github\.com/|git@github\.com:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?",
        origin,
    )
    if not match:
        raise ValueError("Repository skill requires a credential-free GitHub origin")
    return match[1]


def capture(home, manifest):
    personal = home / "git"
    records = []
    for link in sorted((home / ".agents/skills").iterdir()):
        if not link.is_symlink():
            continue
        source = link.resolve()
        if not source.is_relative_to(personal):
            print(
                f"Skipped linked skill outside the personal repository tree: {link.name}"
            )
            continue
        if not (source / "SKILL.md").is_file():
            raise ValueError(f"Missing linked skill entrypoint: {link.name}")
        root = Path(run("git", "rev-parse", "--show-toplevel", cwd=source)).resolve()
        if root == REPOSITORY or not root.is_relative_to(personal):
            raise ValueError(f"Unsupported repository skill location: {link.name}")
        subdirectory = source.relative_to(root).as_posix()
        if run("git", "status", "--porcelain", "--", subdirectory, cwd=root):
            raise ValueError(
                f"Commit the repository skill before capturing it: {link.name}"
            )
        revision = run("git", "rev-parse", "HEAD", cwd=root)
        entrypoint = "SKILL.md" if subdirectory == "." else f"{subdirectory}/SKILL.md"
        run("git", "cat-file", "-e", f"{revision}:{entrypoint}", cwd=root)
        records.append(
            {
                "name": link.name,
                "revision": revision,
                "repository": identity(
                    run("git", "remote", "get-url", "origin", cwd=root)
                ),
                "checkout": root.relative_to(home).as_posix(),
                "skill_path": subdirectory,
            }
        )
    if manifest.exists():
        previous = json.loads(manifest.read_text())
        if previous["version"] != 1:
            raise ValueError("Unsupported repository skill manifest version")
        current_names = {record["name"] for record in records}
        for record in previous["skills"]:
            if record["name"] not in current_names:
                records.append(record)
                print(
                    f"Preserved repository skill reference absent on this machine: {record['name']}"
                )
    records.sort(key=lambda record: record["name"])
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({"version": 1, "skills": records}, indent=2) + "\n")
    print(f"Captured {len(records)} repository skill revisions")


def restore(home, manifest, dry_run):
    data = json.loads(manifest.read_text())
    if data["version"] != 1:
        raise ValueError("Unsupported repository skill manifest version")
    gh_wrapper = home / ".local/bin/gh"
    gh = str(gh_wrapper) if gh_wrapper.is_file() else "gh"
    pending = []
    revisions = {}
    for record in data["skills"]:
        name, revision = record["name"], record["revision"]
        checkout, subdirectory = Path(record["checkout"]), Path(record["skill_path"])
        if not re.fullmatch(r"[a-z0-9-]+", name) or not re.fullmatch(
            r"[a-f0-9]{40}", revision
        ):
            raise ValueError("Invalid skill name or pinned revision")
        if (
            checkout.is_absolute()
            or ".." in checkout.parts
            or not checkout.parts
            or checkout.parts[0] != "git"
        ):
            raise ValueError("Checkout must stay in the personal git tree")
        if subdirectory.is_absolute() or ".." in subdirectory.parts:
            raise ValueError("Skill path must stay inside its repository")
        repository = identity("https://github.com/" + record["repository"])
        root = home / checkout
        if revisions.setdefault(root, (repository, revision)) != (repository, revision):
            raise ValueError(
                "Skills in one checkout must use the same repository revision"
            )
        target = root / subdirectory
        link = home / ".agents/skills" / name
        if not root.resolve().is_relative_to(
            (home / "git").resolve()
        ) or not target.resolve().is_relative_to(root.resolve()):
            raise ValueError("Repository skill path escapes through a symlink")
        exists = root.exists()
        if exists:
            if (
                identity(run("git", "remote", "get-url", "origin", cwd=root))
                != repository
            ):
                raise ValueError(f"Existing checkout has a different origin: {name}")
            if run("git", "rev-parse", "HEAD", cwd=root) != revision or run(
                "git", "status", "--porcelain", "--", str(subdirectory), cwd=root
            ):
                raise ValueError(
                    f"Existing checkout differs from the pinned skill; left unchanged: {name}"
                )
        if (link.exists() or link.is_symlink()) and (
            not link.is_symlink() or link.resolve() != target.resolve()
        ):
            raise ValueError(f"Existing canonical skill would be replaced: {name}")
        pending.append((name, repository, revision, root, target, link, exists))
    cloned = set()
    for name, repository, revision, root, target, link, exists in pending:
        print(
            f"{'Check' if exists else 'Clone'} {repository} at {revision[:12]} -> {name}"
        )
        if dry_run:
            continue
        if not exists and root not in cloned:
            root.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [gh, "repo", "clone", repository, str(root), "--", "--no-checkout"],
                cwd=REPOSITORY,
                check=True,
            )
            subprocess.run(
                ["git", "checkout", "--detach", revision], cwd=root, check=True
            )
            cloned.add(root)
        if not (target / "SKILL.md").is_file():
            raise ValueError(f"Pinned skill entrypoint is absent: {name}")
        link.parent.mkdir(parents=True, exist_ok=True)
        if not link.is_symlink():
            link.symlink_to(target, target_is_directory=True)
    if not dry_run:
        subprocess.run([str(home / ".agents/link.sh")], cwd=REPOSITORY, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("capture", "restore"))
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Check a restore without cloning or changing links",
    )
    args = parser.parse_args()
    if args.action == "capture":
        if args.dry_run:
            parser.error("--dry-run applies to restore")
        capture(Path.home(), MANIFEST)
    else:
        restore(Path.home(), MANIFEST, args.dry_run)


if __name__ == "__main__":
    main()
