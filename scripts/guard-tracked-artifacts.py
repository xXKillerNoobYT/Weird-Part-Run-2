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
    ".paperclip/worktrees/WEI-123/evidence.png",
    ".paperclip/DerivedData-WEI-1188/ModuleCache.noindex/Session.modulevalidation",
    "DerivedData/Build/Intermediates.noindex/file.o",
    "DerivedData/Build/capture.png",
    "app/DerivedData-WEI-1/Build/Products/App.app",
    "core/.build/debug/WiredPartCoreTests.xctest",
    "core/SourcePackages/checkouts/GRDB.swift/Package.swift",
    "core/SourcePackages/repositories/GRDB.swift.git/config",
    "Weird Parts.xcworkspace/xcuserdata/local-user.xcuserdatad/UserInterfaceState.xcuserstate",
    "Weird Parts IOS/build/cache.dat",
    "Weird Parts IOS/ModuleCache.noindex/Session.modulevalidation",
    "Weird Parts IOS/CompilationCache.noindex/generic/lock",
    "Weird Parts IOS/Index.noindex/DataStore/v5/records",
    "docs/github-issue-fisher/2026-05-26T06-06-11Z/report.md",
    "docs/github-issue-fisher/latest-report.md",
    # Screenshot/image dumps outside the sanctioned locations (issue #1333 —
    # 26 MB of QA evidence and problem screenshots accumulated in docs/).
    "docs/testing/artifacts/wei-9999/evidence.png",
    "docs/some-report/screenshot.png",
    "docs/readme-assets/unreviewed-screenshot.png",
    "docs/readme-assets/unreviewed-screenshot.jpg",
    "Weird Parts IOS/Weird Parts IOS/debug-capture.jpg",
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
    # Sanctioned image locations: the user's problem-report inbox, Xcode asset
    # catalogs, and the pre-reviewed synthetic README capture register.
    "docs/problems/Screenshot 2026-03-28 at 2.01.57 PM.png",
    "docs/readme-assets/wiredpart-dashboard-synthetic.png",
    "docs/readme-assets/wiredpart-warehouse-synthetic.png",
    "docs/readme-assets/wiredpart-jobs-synthetic.png",
    "Weird Parts IOS/Weird Parts IOS/Assets.xcassets/AppIcon.appiconset/icon.png",
]

# Tracked images are denied by default. Exceptions are the existing
# problem-report inboxes, Xcode asset catalogs, and the exact synthetic README
# captures approved in docs/readme-assets/README-ASSET-REVIEW.md. Everything
# else is a screenshot/evidence dump that belongs in a GitHub issue or PR
# attachment (see docs/testing/artifacts/README.md for the policy).
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".heic", ".webp"}
IMAGE_ALLOWED_PREFIXES = ("docs/problems/",)
IMAGE_ALLOWED_PATH_PARTS = {"Assets.xcassets"}
README_IMAGE_ALLOWED_PATHS = {
    "docs/readme-assets/wiredpart-dashboard-synthetic.png",
    "docs/readme-assets/wiredpart-warehouse-synthetic.png",
    "docs/readme-assets/wiredpart-jobs-synthetic.png",
}

# Any tracked file larger than this is presumed to be a build artifact or
# media dump; raise the limit deliberately if a legitimate need appears.
MAX_TRACKED_FILE_BYTES = 1_000_000


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

    if any(normalized.endswith(suffix) for suffix in BLOCKED_FILE_SUFFIXES):
        return True

    # Image exceptions are limited to the reviewed locations declared above.
    suffix = PurePosixPath(normalized).suffix.lower()
    if suffix in IMAGE_SUFFIXES:
        if normalized in README_IMAGE_ALLOWED_PATHS:
            return False
        if normalized.startswith(IMAGE_ALLOWED_PREFIXES):
            return False
        if any(part in IMAGE_ALLOWED_PATH_PARTS for part in parts):
            return False
        return True

    return False


def is_oversized(size_bytes: int) -> bool:
    """Return True when a tracked file exceeds the repository size limit."""
    return size_bytes > MAX_TRACKED_FILE_BYTES


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

    if is_oversized(MAX_TRACKED_FILE_BYTES):
        failures.append("expected size limit itself to be allowed")
    if not is_oversized(MAX_TRACKED_FILE_BYTES + 1):
        failures.append("expected file above size limit to be blocked")

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

    tracked = tracked_files()
    blocked = [path for path in tracked if is_blocked(path)]

    # Size rule: no tracked file may exceed MAX_TRACKED_FILE_BYTES. Checked
    # against the checkout (CI runs on a full checkout), independently of the
    # path rules above.
    import os

    oversized = []
    for path in tracked:
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if is_oversized(size):
            oversized.append(f"{path} ({size / 1_000_000:.1f} MB)")

    if blocked or oversized:
        if blocked:
            print("Generated local runtime/cache artifacts or stray media are tracked by git:", file=sys.stderr)
            for path in blocked[:200]:
                print(f"  {path}", file=sys.stderr)
            if len(blocked) > 200:
                print(f"  ... and {len(blocked) - 200} more", file=sys.stderr)
        if oversized:
            print(f"Tracked files exceed the {MAX_TRACKED_FILE_BYTES / 1_000_000:.0f} MB limit:", file=sys.stderr)
            for entry in oversized[:50]:
                print(f"  {entry}", file=sys.stderr)
        print("\nRemove these from the index with `git rm --cached` and keep them ignored.", file=sys.stderr)
        print("Screenshots belong in GitHub issue/PR attachments; problem reports go in docs/problems/.", file=sys.stderr)
        return 1

    print("No tracked Paperclip/Xcode runtime artifacts, stray media, or oversized files found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
