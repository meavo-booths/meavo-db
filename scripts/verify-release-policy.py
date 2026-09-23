#!/usr/bin/env python3
"""Check installed release-policy copies and the source of a main pull request.

The manifest detects drift; it is not proof of human authorization. GitHub must
separately require a human review and this check without a bypass on main.
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

BEGIN = "<!-- BEGIN MEAVO RELEASE POLICY -->"
END = "<!-- END MEAVO RELEASE POLICY -->"
MANIFEST = ".github/meavo-release-policy.json"
FILES = (
    "RELEASE_POLICY.md",
    ".cursor/rules/release-process.mdc",
    ".github/workflows/release-policy.yml",
    "scripts/verify-release-policy.py",
)
BLOCKS = ("AGENTS.md", "CLAUDE.md", "CONTRIBUTING.md")


def digest(content):
    return hashlib.sha256(content).hexdigest()


def managed_block(text):
    """Return one unambiguous, complete managed block, without a final newline."""
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise ValueError("expected exactly one complete release-policy block")
    start = text.index(BEGIN)
    end = text.index(END) + len(END)
    if (end < start or (start and text[start - 1] != "\n")
            or (end < len(text) and text[end] != "\n")
            or not text[start + len(BEGIN):].startswith("\n")
            or text[text.index(END) - 1] != "\n"):
        raise ValueError("release-policy markers must be ordered on their own lines")
    return text[start:end]


def checked_path(root, relative):
    """Never follow symlinks for managed files or their containing directories."""
    path = root / relative
    for candidate in (path, *path.parents):
        if candidate == root:
            break
        if candidate.is_symlink():
            raise ValueError(f"managed path is a symlink: {relative}")
    return path


def verify(root):
    errors = []
    try:
        manifest = json.loads(checked_path(root, MANIFEST).read_text())
        if not isinstance(manifest, dict) or set(manifest) != {"version", "files", "blocks"}:
            raise ValueError("invalid manifest fields")
        if manifest["version"] != 1:
            raise ValueError("unsupported manifest version")
        for section, expected in (("files", FILES), ("blocks", BLOCKS)):
            hashes = manifest[section]
            if not isinstance(hashes, dict) or set(hashes) != set(expected):
                raise ValueError(f"manifest must list every required {section} entry")
            if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value)
                   for value in hashes.values()):
                raise ValueError(f"invalid {section} hash")
    except (OSError, ValueError, TypeError) as exc:
        return [f"{MANIFEST}: {exc}"]

    for name in FILES:
        try:
            actual = checked_path(root, name).read_bytes()
            if digest(actual) != manifest["files"][name]:
                errors.append(f"{name}: differs from installed canonical policy")
        except (OSError, ValueError) as exc:
            errors.append(f"{name}: {exc}")
    for name in BLOCKS:
        try:
            document = checked_path(root, name).read_bytes().decode("utf-8")
            block = managed_block(document)
            if not document.startswith(BEGIN):
                errors.append(f"{name}: release-policy block must be first")
            if digest(block.encode("utf-8")) != manifest["blocks"][name]:
                errors.append(f"{name}: managed block differs from canonical policy")
        except (OSError, ValueError) as exc:
            errors.append(f"{name}: {exc}")
    return errors


def verify_event(event_path, event_name):
    """Read untrusted PR values as JSON data, never shell commands."""
    try:
        event = json.loads(Path(event_path).read_text())
        if not isinstance(event, dict):
            raise ValueError("event must be an object")
        if event_name == "push":
            if event.get("ref") not in ("refs/heads/main", "refs/heads/staging"):
                raise ValueError("unexpected push branch for release-policy workflow")
            return []
        if event_name != "pull_request":
            raise ValueError("unsupported event; expected pull_request or push")
        pr = event["pull_request"]
        base = pr["base"]
        if not isinstance(base["ref"], str) or not base["ref"]:
            raise ValueError("missing pull-request base branch")
        if base["ref"] == "main":
            repository = event["repository"]["full_name"]
            if (not isinstance(repository, str) or not repository
                    or base["repo"]["full_name"] != repository
                    or pr["head"]["repo"]["full_name"] != repository
                    or pr["head"]["ref"] != "staging"):
                raise ValueError("main pull requests must originate from this repository's staging branch")
        return []
    except (OSError, ValueError, KeyError, TypeError) as exc:
        return [f"GitHub event: {exc}"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1])
    parser.add_argument("--event", type=Path)
    parser.add_argument("--event-name")
    args = parser.parse_args()
    if bool(args.event) != bool(args.event_name):
        parser.error("--event and --event-name must be used together")
    errors = verify(args.target.resolve())
    if args.event:
        errors.extend(verify_event(args.event, args.event_name))
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    print("Release policy copies verified; main PR source checked when an event was supplied.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
