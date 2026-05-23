#!/usr/bin/env python3
"""Static regression checks for AI page-context/help registry wiring.

The iOS AI assistant listens to page-active notifications, maps those events to
`activePageId` values, and uses `HelpContentRegistry` for page-specific help.
This script fails if that wiring drifts out of sync or if an observed page
notification has no production post site.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    ios_root = repo_root / "Weird Parts IOS" / "Weird Parts IOS"
    ai_panel = ios_root / "AI" / "IOSAIAssistantPanel.swift"
    help_registry = ios_root / "Shared" / "HelpContentRegistry.swift"

    ai_text = read(ai_panel)
    registry_text = read(help_registry)

    active_page_ids = set(re.findall(r'activePageId\s*=\s*"([^"]+)"', ai_text))
    registry_page_ids = set(re.findall(r'pageId:\s*"([^"]+)"', registry_text))
    mapped_page_ids = set(re.findall(r'"WiredPart\.[^"]+PageActive"\s*:\s*"([^"]+)"', registry_text))

    errors: list[str] = []

    missing_help_entries = sorted(active_page_ids - registry_page_ids)
    if missing_help_entries:
        errors.append(
            "activePageId values without HelpContentRegistry entries: "
            + ", ".join(missing_help_entries)
        )

    missing_mapped_entries = sorted(mapped_page_ids - registry_page_ids)
    if missing_mapped_entries:
        errors.append(
            "notificationToPageId values without HelpContentRegistry entries: "
            + ", ".join(missing_mapped_entries)
        )

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
        f"{len(active_page_ids)} active page IDs, "
        f"{len(mapped_page_ids)} registry notification mappings, "
        f"{len(observed_notifications)} observed notifications, "
        f"{len(production_posts)} production page post sites."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
