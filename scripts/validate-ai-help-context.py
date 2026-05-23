#!/usr/bin/env python3
"""Static regression checks for AI page-context/help registry wiring.

The iOS AI assistant listens to page-active notifications, maps those events to
`activePageId` values, and uses `HelpContentRegistry` for page-specific help.
This script fails if that wiring drifts out of sync or if an observed page
notification has no production post site.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        print(f"error: missing required file: {path}", file=sys.stderr)
        sys.exit(2)


def run_coverage_guard(repo_root: Path) -> int:
    """Run the canonical registry/mapping guard before extra post-site checks."""
    script = repo_root / "scripts" / "verify-ai-help-context-coverage.py"
    if not script.exists():
        print(f"error: missing required file: {script}", file=sys.stderr)
        return 2

    spec = importlib.util.spec_from_file_location("verify_ai_help_context_coverage", script)
    if spec is None or spec.loader is None:
        print(f"error: unable to load required script: {script}", file=sys.stderr)
        return 2

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        return int(module.main())
    except SystemExit as exc:
        return int(exc.code or 0)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    coverage_status = run_coverage_guard(repo_root)
    if coverage_status != 0:
        return coverage_status

    ios_root = repo_root / "Weird Parts IOS" / "Weird Parts IOS"
    ai_panel = ios_root / "AI" / "IOSAIAssistantPanel.swift"

    ai_text = read(ai_panel)

    errors: list[str] = []

    observed_notifications = set(
        re.findall(r'publisher\(for:\s*\.([A-Za-z0-9_]+Page(?:Active|Inactive))\)', ai_text)
    )

    production_posts: set[str] = set()
    for path in ios_root.rglob("*.swift"):
        if path in {ai_panel, ios_root / "Navigation" / "NavigationConfig.swift"}:
            continue
        text = read(path)
        if "NotificationCenter.default.post" not in text:
            continue

        # Direct post sites, e.g. `post(name: .settingsPageActive, ...)`.
        production_posts.update(
            re.findall(
                r'NotificationCenter\.default\.post\(\s*name:\s*\.([A-Za-z0-9_]+Page(?:Active|Inactive))',
                text,
                flags=re.S,
            )
        )

        # Router-style post sites may post a descriptor variable, e.g.
        # `name: active ? descriptor.activeName : descriptor.inactiveName` with
        # the concrete `.fooPageActive` / `.fooPageInactive` values declared in
        # the same source file. Count those concrete names as production-backed.
        production_posts.update(
            re.findall(r'\.([A-Za-z0-9_]+Page(?:Active|Inactive))\b', text)
        )

    missing_post_sites = sorted(observed_notifications - production_posts)
    if missing_post_sites:
        errors.append(
            "AI-observed page notifications without production post sites: "
            + ", ".join(missing_post_sites)
        )

    if errors:
        print("AI help context validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(
        "AI help context validation passed: "
        f"{len(observed_notifications)} observed notifications, "
        f"{len(production_posts)} production page post sites."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
