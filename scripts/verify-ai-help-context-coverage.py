#!/usr/bin/env python3
"""Verify the iOS screen inventory and AI/Help page-context contracts.

The inventory is checked against both ``appModules`` and IOSContentRouter's
explicit deep/alias registry rather than a historical page count. A newly
navigable surface therefore fails until it has a source-backed disposition.
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_SOURCE = ROOT / "Weird Parts IOS/Weird Parts IOS"
REGISTRY = APP_SOURCE / "Shared/HelpContentRegistry.swift"
NAVIGATION = APP_SOURCE / "Navigation/NavigationConfig.swift"
ROUTER = APP_SOURCE / "Navigation/IOSContentRouter.swift"
ASSISTANT = APP_SOURCE / "AI/IOSAIAssistantPanel.swift"
SUPPLIERS = APP_SOURCE / "Features/Parts/PartsSuppliersPage.swift"
INVENTORY = Path(os.environ.get(
    "AI_CONTEXT_INVENTORY_PATH",
    ROOT / "docs/testing/ai-page-context-inventory.json",
))
ALLOWED_DISPOSITIONS = {
    "dedicated",
    "router-owned",
    "inherited",
    "not-user-facing",
    "retired",
    "gap",
}


def read(path: Path) -> str:
    try:
        return path.read_text()
    except FileNotFoundError:
        print(f"error: missing required file: {path}", file=sys.stderr)
        raise SystemExit(2)


def fail_section(failures: list[str], title: str, items: list[str]) -> None:
    if items:
        failures.append(title)
        failures.extend(f"  - {item}" for item in items)


def main() -> int:
    registry = read(REGISTRY)
    navigation = read(NAVIGATION)
    router = read(ROUTER)
    assistant = read(ASSISTANT)
    suppliers = read(SUPPLIERS)
    try:
        inventory = json.loads(read(INVENTORY))
    except json.JSONDecodeError as error:
        print(f"error: invalid inventory JSON: {error}", file=sys.stderr)
        return 2

    failures: list[str] = []
    screens = inventory.get("screens", [])
    screen_ids = [screen.get("id") for screen in screens]
    duplicate_ids = sorted(screen_id for screen_id, count in Counter(screen_ids).items() if count > 1)
    fail_section(failures, "duplicate inventory screen IDs:", duplicate_ids)

    app_tabs = {
        screen_id: path
        for screen_id, path in re.findall(
            r'AppTab\(id: "([^"]+)"[^\n]*path: "([^"]+)"', navigation
        )
    }
    inventory_by_id = {screen.get("id"): screen for screen in screens}
    fail_section(
        failures,
        "navigable AppTab rows missing from inventory:",
        sorted(set(app_tabs) - set(inventory_by_id)),
    )
    fail_section(
        failures,
        "inventory AppTab paths drifted from NavigationConfig:",
        sorted(
            f"{screen_id}: inventory={inventory_by_id[screen_id].get('path')} source={path}"
            for screen_id, path in app_tabs.items()
            if screen_id in inventory_by_id and inventory_by_id[screen_id].get("path") != path
        ),
    )

    routed_section = router.split("private var routedView", 1)[-1].split(
        "private func officeRoute", 1
    )[0]
    routed_paths = set(re.findall(r'"(/[^"]+)"', routed_section))
    deep_registry_section = router.split("private var deepRoutePageId", 1)[-1].split(
        "/// Publish only route identity", 1
    )[0]
    deep_pairs: list[tuple[str, str]] = []
    for case_list, page_id in re.findall(
        r'case\s+([^:\n]+):\s*return\s+"([^"]+)"',
        deep_registry_section,
    ):
        deep_pairs.extend(
            (path, page_id) for path in re.findall(r'"(/[^"]+)"', case_list)
        )
    deep_path_counts = Counter(path for path, _ in deep_pairs)
    deep_routes = dict(deep_pairs)
    app_paths = set(app_tabs.values())
    expected_deep_paths = routed_paths - app_paths
    fail_section(
        failures,
        "duplicate paths in IOSContentRouter deep/alias registry:",
        sorted(path for path, count in deep_path_counts.items() if count > 1),
    )
    fail_section(
        failures,
        "explicit router paths missing from deep/alias registry:",
        sorted(expected_deep_paths - set(deep_routes)),
    )
    fail_section(
        failures,
        "stale deep/alias registry paths not present in routed switch:",
        sorted(set(deep_routes) - expected_deep_paths),
    )
    fail_section(
        failures,
        "deep/alias registry page IDs missing from inventory:",
        sorted(set(deep_routes.values()) - set(inventory_by_id)),
    )
    fail_section(
        failures,
        "router-owned deep rows not backed by the canonical registry:",
        sorted(
            f"{screen['id']}: {screen.get('path')}"
            for screen in screens
            if screen.get("disposition") == "router-owned"
            and str(screen.get("path", "")).startswith("/")
            and screen.get("path") not in app_paths
            and deep_routes.get(screen.get("path")) != screen.get("id")
        ),
    )

    non_router_audit = inventory.get("nonRouterAudit", {})
    non_router_scope = non_router_audit.get("scope")
    non_router_destinations = non_router_audit.get("destinations", [])
    non_router_failures: list[str] = []
    if not isinstance(non_router_scope, str) or not non_router_scope.strip():
        non_router_failures.append("missing bounded audit scope")
    if not isinstance(non_router_destinations, list) or not non_router_destinations:
        non_router_failures.append("missing canonical non-router destinations")
        non_router_destinations = []
    destination_keys: list[tuple[object, object]] = []
    for destination in non_router_destinations:
        destination_type = destination.get("destination")
        source = destination.get("source")
        expected_occurrences = destination.get("expectedOccurrences")
        screen_id = destination.get("screenId")
        rationale = destination.get("rationale")
        destination_keys.append((source, destination_type))
        label = f"{source}: {destination_type}"
        if not isinstance(destination_type, str) or not destination_type.strip():
            non_router_failures.append(f"{label}: missing destination type")
            continue
        if not isinstance(source, str) or not source.strip() or not (ROOT / source).is_file():
            non_router_failures.append(f"{label}: missing/unreadable presentation source")
            continue
        if not isinstance(expected_occurrences, int) or expected_occurrences < 1:
            non_router_failures.append(f"{label}: expectedOccurrences must be a positive integer")
        else:
            actual_occurrences = read(ROOT / source).count(f"{destination_type}(")
            if actual_occurrences != expected_occurrences:
                non_router_failures.append(
                    f"{label}: expected {expected_occurrences} presentation occurrence(s), found {actual_occurrences}"
                )
        if not isinstance(rationale, str) or not rationale.strip():
            non_router_failures.append(f"{label}: missing disposition rationale")
        if screen_id is not None:
            if screen_id not in inventory_by_id:
                non_router_failures.append(
                    f"{label}: inventory screen {screen_id!r} is missing"
                )
            elif inventory_by_id[screen_id].get("disposition") not in {"dedicated", "inherited"}:
                non_router_failures.append(
                    f"{label}: inventory screen {screen_id!r} must be dedicated or inherited"
                )
    duplicate_destination_keys = sorted(
        f"{source}: {destination}"
        for (source, destination), count in Counter(destination_keys).items()
        if count > 1
    )
    non_router_failures.extend(
        f"duplicate canonical destination {key}" for key in duplicate_destination_keys
    )
    fail_section(
        failures,
        "non-router destination registry failures:",
        non_router_failures,
    )

    malformed: list[str] = []
    for screen in screens:
        screen_id = screen.get("id", "<missing-id>")
        disposition = screen.get("disposition")
        source = screen.get("source")
        if disposition not in ALLOWED_DISPOSITIONS:
            malformed.append(f"{screen_id}: invalid disposition {disposition!r}")
        if disposition == "gap":
            malformed.append(f"{screen_id}: unresolved gap")
        if not isinstance(screen.get("rationale"), str) or not screen["rationale"].strip():
            malformed.append(f"{screen_id}: missing rationale")
        if not isinstance(source, str) or not source.strip() or not (ROOT / source).is_file():
            malformed.append(f"{screen_id}: missing/unreadable source path {source!r}")
        if screen.get("helpPageId") is None and not str(screen.get("helpRationale", "")).strip():
            malformed.append(f"{screen_id}: Help exemption lacks rationale")
    fail_section(failures, "malformed inventory rows:", malformed)

    page_ids = set(re.findall(r'pageId:\s*"([^"]+)"', registry))
    mapping_pairs = re.findall(
        r'"(WiredPart\.[^"]+PageActive)"\s*:\s*"([^"]+)"', registry
    )
    mapping = dict(mapping_pairs)
    if len(mapping_pairs) != len(mapping):
        failures.append(f"duplicate notification mapping count: {len(mapping_pairs) - len(mapping)}")

    declared_pairs = re.findall(
        r'static let (\w+Page(Active|Inactive))\s*=\s*Notification\.Name\("(WiredPart\.[^"]+)"\)',
        navigation,
    )
    declared_by_symbol = {symbol: wire_name for symbol, _, wire_name in declared_pairs}
    declared_active = {symbol for symbol, kind, _ in declared_pairs if kind == "Active"}
    declared_inactive = {symbol for symbol, kind, _ in declared_pairs if kind == "Inactive"}
    observed_active = set(re.findall(r'publisher\(for:\s*\.(\w+PageActive)\)', assistant))
    observed_inactive = set(re.findall(r'publisher\(for:\s*\.(\w+PageInactive)\)', assistant))

    fail_section(
        failures,
        "active declarations without matching inactive declaration:",
        sorted(
            symbol for symbol in declared_active
            if symbol.removesuffix("Active") + "Inactive" not in declared_inactive
        ),
    )
    fail_section(failures, "declared active notifications not observed by assistant:", sorted(declared_active - observed_active))
    fail_section(failures, "declared inactive notifications not observed by assistant:", sorted(declared_inactive - observed_inactive))
    inventory_notifications = {screen.get("notification") for screen in screens}
    fail_section(
        failures,
        "dedicated page-active declarations missing from inventory:",
        sorted(declared_active - inventory_notifications - {"routePageActive"}),
    )

    declared_wire_names = {declared_by_symbol[symbol] for symbol in declared_active}
    fail_section(
        failures,
        "registry maps notifications not declared in NavigationConfig:",
        sorted(set(mapping) - declared_wire_names),
    )
    fail_section(
        failures,
        "assistant-observed page-active notifications missing registry mapping:",
        sorted(
            f".{symbol} ({declared_by_symbol[symbol]})"
            for symbol in observed_active
            if symbol in declared_by_symbol
            and symbol != "routePageActive"
            and declared_by_symbol[symbol] not in mapping
        ),
    )
    fail_section(
        failures,
        "mapped notifications without HelpEntry pageId:",
        sorted(f"{notification} -> {page_id}" for notification, page_id in mapping.items() if page_id not in page_ids),
    )

    dedicated_failures: list[str] = []
    for screen in screens:
        if screen.get("disposition") != "dedicated":
            continue
        screen_id = screen["id"]
        active_symbol = screen.get("notification")
        inactive_symbol = str(active_symbol).removesuffix("Active") + "Inactive"
        source_path = ROOT / screen["source"]
        source_text = read(source_path)
        if active_symbol not in declared_active:
            dedicated_failures.append(f"{screen_id}: .{active_symbol} is not declared")
        if inactive_symbol not in declared_inactive:
            dedicated_failures.append(f"{screen_id}: .{inactive_symbol} is not declared")
        if f".{active_symbol}" not in source_text or f".{inactive_symbol}" not in source_text:
            dedicated_failures.append(f"{screen_id}: source does not reference both active/inactive notifications")
        if "NotificationCenter.default.post" not in source_text:
            dedicated_failures.append(f"{screen_id}: source has no NotificationCenter post")
        help_page_id = screen.get("helpPageId")
        wire_name = declared_by_symbol.get(active_symbol)
        if help_page_id not in page_ids:
            dedicated_failures.append(f"{screen_id}: missing canonical Help entry {help_page_id!r}")
        if wire_name and mapping.get(wire_name) != help_page_id:
            dedicated_failures.append(
                f"{screen_id}: registry mapping is {mapping.get(wire_name)!r}, expected {help_page_id!r}"
            )
    fail_section(failures, "dedicated screen parity failures:", dedicated_failures)

    route_owned = [screen for screen in screens if screen.get("disposition") == "router-owned"]
    route_contract_snippets = [
        "static let routePageActive",
        "static let routePageInactive",
        "postRouteContext()",
        ".onChange(of: path)",
        "name: .routePageInactive",
    ]
    fail_section(
        failures,
        "router-owned lifecycle/freshness contract missing:",
        [snippet for snippet in route_contract_snippets if snippet not in navigation + router],
    )
    if route_owned:
        if ".routePageActive" not in assistant or ".routePageInactive" not in assistant:
            failures.append("assistant does not observe both router-owned active/inactive notifications")
        if "routeContext = nil" not in assistant:
            failures.append("assistant logout/page lifecycle clearing omits routeContext")

    supplier_context_contract = [
        "enum SupplierAIPageContextBuilder",
        "SupplierAIPageContextBuilder.build(",
        ".onChange(of: searchText)",
        ".onChange(of: filterActive)",
        ".onChange(of: sortOption)",
        "Visible suppliers:",
        "Search:",
        "Filter:",
        "Sort:",
    ]
    fail_section(
        failures,
        "supplier page context minimization/freshness contract missing:",
        [snippet for snippet in supplier_context_contract if snippet not in suppliers],
    )
    if "buildSupplierAIContext()" in suppliers:
        failures.append(
            "supplier page context must not use the full service dump; keep the app-layer aggregate allowlist"
        )

    print(f"Inventory screens: {len(screens)}")
    print(f"Navigable AppTabs: {len(app_tabs)}")
    print(f"Explicit deep/alias routes: {len(deep_routes)}")
    print(f"Canonical non-router destinations: {len(non_router_destinations)}")
    print("Inventory dispositions: " + ", ".join(
        f"{name}={count}" for name, count in sorted(Counter(screen.get("disposition") for screen in screens).items())
    ))
    print(f"Help entries: {len(page_ids)}")
    print(f"Registry page-active mappings: {len(mapping)}")
    print(f"Assistant-observed page-active notifications: {len(observed_active)}")

    if failures:
        print("AI help/context coverage check FAILED", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print("AI help/context coverage check passed: inventory is complete and all dedicated/router-owned lifecycle contracts are in parity.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())