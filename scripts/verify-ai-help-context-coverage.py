#!/usr/bin/env python3
"""Verify AI page-active notifications map to existing HelpContentRegistry entries.

This is a lightweight static guard for GH #650 / WEI-1995. It prevents a page from
adding an AI/page-active mapping whose page ID has no corresponding help entry,
which otherwise makes the assistant fall back to generic help silently.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift"
NAVIGATION = ROOT / "Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift"
ASSISTANT = ROOT / "Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift"


def read(path: Path) -> str:
    try:
        return path.read_text()
    except FileNotFoundError:
        print(f"error: missing required file: {path}", file=sys.stderr)
        sys.exit(2)


def main() -> int:
    registry = read(REGISTRY)
    navigation = read(NAVIGATION)
    assistant = read(ASSISTANT)

    page_ids = set(re.findall(r'pageId:\s*"([^"]+)"', registry))
    mapping_pairs = re.findall(
        r'"(WiredPart\.[^"]+PageActive)"\s*:\s*"([^"]+)"',
        registry,
    )
    mapping = dict(mapping_pairs)

    failures: list[str] = []

    duplicate_mappings = len(mapping_pairs) - len(mapping)
    if duplicate_mappings:
        failures.append(f"duplicate notification mapping count: {duplicate_mappings}")

    missing_help = sorted((notification, page_id) for notification, page_id in mapping.items() if page_id not in page_ids)
    if missing_help:
        failures.append("mapped notifications without HelpEntry pageId:")
        failures.extend(f"  - {notification} -> {page_id}" for notification, page_id in missing_help)

    declared_notifications = set(re.findall(r'static let (\w+PageActive)\s*=\s*Notification\.Name\("(WiredPart\.[^"]+)"\)', navigation))
    declared_names = {wire_name for _, wire_name in declared_notifications}
    mapped_unknown = sorted(notification for notification in mapping if notification not in declared_names)
    if mapped_unknown:
        failures.append("registry maps notifications not declared in NavigationConfig:")
        failures.extend(f"  - {notification}" for notification in mapped_unknown)

    observed_names = set(re.findall(r'publisher\(for:\s*\.(\w+PageActive)\)', assistant))
    declared_by_symbol = {symbol: wire_name for symbol, wire_name in declared_notifications}
    observed_unmapped = sorted(
        (symbol, declared_by_symbol[symbol])
        for symbol in observed_names
        if symbol in declared_by_symbol and declared_by_symbol[symbol] not in mapping
    )
    if observed_unmapped:
        failures.append("assistant observes page-active notifications missing registry mapping:")
        failures.extend(f"  - .{symbol} ({wire_name})" for symbol, wire_name in observed_unmapped)

    print(f"Help entries: {len(page_ids)}")
    print(f"Registry page-active mappings: {len(mapping)}")
    print(f"Assistant-observed page-active notifications: {len(observed_names)}")

    if failures:
        print("AI help/context coverage check FAILED", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print("AI help/context coverage check passed: every mapped/observed page-active notification resolves to help content.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
