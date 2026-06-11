#!/usr/bin/env python3
"""Fail when generated local runtime/cache artifacts are tracked by git.

This guard is intentionally independent from .gitignore. Ignore rules prevent new
files from being added accidentally, but they do not protect the repository when a
file is already tracked or is force-added. The script inspects `git ls-files` and
fails on paths that should stay local-only.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import PurePosixPath


BLOCKED_EXAMPLES = [
    ".paperclip/worktrees/WEI-123/state.json",
    ".paperclip/DerivedData-WEI-1188/ModuleCache.noindex/Session.modulevalidation",
    "DerivedData/Build/Intermediates.noindex/file.o",
    "app/DerivedData-WEI-1/Build/Products/App.app",
    "core/.build/debug/WiredPartCoreTests.xctest",
    "core/SourcePackages/checkouts/GRDB.swift/Package.swift",
    "core/SourcePackages/repositories/GRDB.swift.git/config",
    "Wierd Parts.xcworkspace/xcuserdata/local-user.xcuserdatad/UserInterfaceState.xcuserstate",
    "Weird Parts IOS/build/cache.dat",
    "Weird Parts IOS/ModuleCache.noindex/Session.modulevalidation",
    "Weird Parts IOS/CompilationCache.noindex/generic/lock",
    "Weird Parts IOS/Index.noindex/DataStore/v5/records",
    "docs/github-issue-fisher/2026-05-26T06-06-11Z/report.md",
    "docs/github-issue-fisher/latest-report.md",
]

ALLOWED_EXAMPLES = [
    ".gitignore",
    "README.md",
    "core/Package.swift",
    "core/Package.resolved",
    "scripts/guard-tracked-artifacts.py",
    ".github/workflows/artifact-guard.yml",
    "Weird Parts IOS/AppDelegate.swift",
    "docs/build-notes.md",
    "docs/github-issue-fisher/.gitkeep",
]


BLOCKED_SUFFIXES = {
    "ModuleCache.noindex",
    "CompilationCache.noindex",
    "Index.noindex",
    "xcuserdata",
}

BLOCKED_FILE_SUFFIXES = {
    ".xcuserstate",
    ".xcresult",
}


def _parts(path: str) -> tuple[str, ...]:
    return PurePosixPath(path).parts


def is_blocked(path: str) -> bool:
    """Return True when a tracked path is a generated local artifact."""
    normalized = path.replace("\\", "/").strip("/")
    if not normalized:
        return False

    parts = _parts(normalized)

    if parts[0] == ".paperclip":
        return True

    if len(parts) >= 2 and parts[0] == "docs" and parts[1] == "github-issue-fisher":
        return normalized != "docs/github-issue-fisher/.gitkeep"

    for part in parts:
        if part.startswith("DerivedData"):
            return True
        if part in BLOCKED_SUFFIXES:
            return True
        if part == ".build" or part == "build":
            return True

    for index, part in enumerate(parts[:-1]):
        if part == "SourcePackages" and parts[index + 1] in {"checkouts", "repositories"}:
            return True

    return any(normalized.endswith(suffix) for suffix in BLOCKED_FILE_SUFFIXES)


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return [path for path in result.stdout.decode("utf-8", errors="replace").split("\0") if path]


def run_self_test() -> int:
    failures: list[str] = []
    for path in BLOCKED_EXAMPLES:
        if not is_blocked(path):
            failures.append(f"expected blocked but allowed: {path}")
    for path in ALLOWED_EXAMPLES:
        if is_blocked(path):
            failures.append(f"expected allowed but blocked: {path}")

    if failures:
        print("Artifact guard self-test failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"Artifact guard self-test passed ({len(BLOCKED_EXAMPLES)} blocked examples, {len(ALLOWED_EXAMPLES)} allowed examples).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail if generated runtime/cache artifacts are tracked in git.")
    parser.add_argument("--self-test", action="store_true", help="Verify that the guard catches representative artifact paths.")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    blocked = [path for path in tracked_files() if is_blocked(path)]
    if blocked:
        print("Generated local runtime/cache artifacts are tracked by git:", file=sys.stderr)
        for path in blocked[:200]:
            print(f"  {path}", file=sys.stderr)
        if len(blocked) > 200:
            print(f"  ... and {len(blocked) - 200} more", file=sys.stderr)
        print("\nRemove these from the index with `git rm --cached` and keep them ignored.", file=sys.stderr)
        return 1

    print("No tracked Paperclip/Xcode runtime artifacts found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
