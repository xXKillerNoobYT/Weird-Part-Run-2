#!/usr/bin/env python3
"""Static coverage checks for AI page context and HelpContentRegistry drift.

Run from the repo root with:
    python3 tests/static/test_ai_help_context_coverage.py
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]
HELP_REGISTRY = REPO_ROOT / "Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift"
AI_PANEL = REPO_ROOT / "Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift"
NAVIGATION = REPO_ROOT / "Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift"
INVENTORY = REPO_ROOT / "docs/testing/ai-page-context-inventory.json"


def swift_file(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text()


class AIHelpContextCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = HELP_REGISTRY.read_text()
        cls.panel = AI_PANEL.read_text()
        cls.navigation = NAVIGATION.read_text()
        cls.inventory = json.loads(INVENTORY.read_text())
        cls.app_tab_ids = set(re.findall(r'AppTab\(id: "([^"]+)"', cls.navigation))
        cls.help_page_ids = set(re.findall(r'pageId: "([^"]+)"', cls.registry))
        cls.registry_notifications = dict(
            re.findall(r'"(WiredPart\.[^"]+)": "([^"]+)"', cls.registry)
        )
        cls.tracker_notifications = {
            f"WiredPart.{name}": page_id
            for name, page_id in re.findall(
                r'publisher\(for: \.([A-Za-z0-9_]+PageActive)\)\) \{ _ in activePageId = "([^"]+)" \}',
                cls.panel,
            )
        }

    def test_every_tracked_active_page_id_has_registered_help(self):
        missing = {
            notification: page_id
            for notification, page_id in sorted(self.tracker_notifications.items())
            if page_id not in self.help_page_ids
        }
        self.assertEqual({}, missing)

    def test_inventory_covers_every_current_app_tab_without_gaps(self):
        app_tabs = {
            page_id: path
            for page_id, path in re.findall(
                r'AppTab\(id: "([^"]+)"[^\n]*path: "([^"]+)"',
                self.navigation,
            )
        }
        inventory_by_id = {screen["id"]: screen for screen in self.inventory["screens"]}

        self.assertEqual(set(), set(app_tabs) - set(inventory_by_id))
        self.assertNotIn("gap", {screen["disposition"] for screen in self.inventory["screens"]})
        self.assertEqual(
            {},
            {
                page_id: (inventory_by_id[page_id]["path"], path)
                for page_id, path in app_tabs.items()
                if inventory_by_id[page_id]["path"] != path
            },
        )

    def test_every_inventory_exemption_has_source_and_rationale(self):
        failures = []
        for screen in self.inventory["screens"]:
            source = REPO_ROOT / screen["source"]
            if not source.is_file() or not screen["rationale"].strip():
                failures.append(screen["id"])
            if screen.get("helpPageId") is None and not screen.get("helpRationale", "").strip():
                failures.append(f"{screen['id']}:help")
        self.assertEqual([], failures)

    def test_help_notification_mapping_covers_active_page_tracker(self):
        missing = {
            notification: page_id
            for notification, page_id in sorted(self.tracker_notifications.items())
            if notification not in self.registry_notifications
        }
        self.assertEqual({}, missing)

    def test_registry_notifications_resolve_to_existing_help_entries(self):
        missing = {
            notification: page_id
            for notification, page_id in sorted(self.registry_notifications.items())
            if page_id not in self.help_page_ids
        }
        self.assertEqual({}, missing)

    def test_representative_beta_pages_have_help_and_context_coverage(self):
        required_page_ids = {
            "dashboard-home",
            "jobs-list",
            "jobs-questionnaire",
            "warehouse-inventory",
            "warehouse-movements",
            "warehouse-receiving",
            "warehouse-staging",
            "warehouse-returns",
            "warehouse-tools",
            "fleet-vehicles",
            "fleet-trailers",
            "fleet-mileage",
            "fleet-fuel",
            "fleet-inspections",
            "fleet-tracking",
            "fleet-my-truck",
            "people-employees",
            "office-dashboard",
            "reports-timesheets",
            "settings-app-config",
        }
        missing_help = sorted(required_page_ids - self.help_page_ids)
        identity_page_ids = set(self.tracker_notifications.values()) | self.app_tab_ids
        missing_tracker = sorted(required_page_ids - identity_page_ids)
        self.assertEqual([], missing_help, "missing HelpContentRegistry entries")
        self.assertEqual([], missing_tracker, "missing active page tracker mappings")

    def test_known_stale_context_pages_repost_on_filter_search_tab_or_form_changes(self):
        freshness_expectations = {
            "Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: filterActive)",
                "onChange(of: sortOption)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSQuestionnairePage.swift": [
                "onChange(of: answers)",
                "onChange(of: dailyReportText)",
                "onChange(of: breakVerification)",
                "onChange(of: missedBreaks)",
                "onChange(of: companionVotes)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Jobs/LaborPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: activeSheet?.id)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Jobs/JobReportsPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: activeSheet?.id)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseMovementsPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: selectedFilter)",
                "onChange(of: activeSheet?.id)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSReceivingPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: selectedFilter)",
                "onChange(of: activeSheet?.id)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSStagingPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: selectedFilter)",
                "onChange(of: activeTab)",
                "onChange(of: isSelecting)",
                "onChange(of: selectedItems)",
                "onChange(of: activeSheet?.id)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseReturnsPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: selectedFilter)",
                "onChange(of: activeSheet?.id)",
            ],
            "Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseToolsPage.swift": [
                "onChange(of: searchText)",
                "onChange(of: selectedFilter)",
                "onChange(of: activeSheet?.id)",
            ],
        }
        missing = {}
        for path, expected_snippets in freshness_expectations.items():
            contents = swift_file(path)
            absent = [snippet for snippet in expected_snippets if snippet not in contents]
            if absent:
                missing[path] = absent
        self.assertEqual({}, missing)

    def test_supplier_page_uses_aggregate_context_builder_not_full_service_dump(self):
        suppliers = swift_file(
            "Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift"
        )
        self.assertIn("enum SupplierAIPageContextBuilder", suppliers)
        self.assertIn("SupplierAIPageContextBuilder.build(", suppliers)
        self.assertNotIn("buildSupplierAIContext()", suppliers)

    def test_verifier_rejects_omitted_deep_route_inventory_row(self):
        inventory = dict(self.inventory)
        inventory["screens"] = [
            screen for screen in self.inventory["screens"]
            if screen["id"] != "settings-about"
        ]
        with tempfile.TemporaryDirectory() as directory:
            inventory_path = Path(directory) / "inventory.json"
            inventory_path.write_text(json.dumps(inventory))
            environment = os.environ.copy()
            environment["AI_CONTEXT_INVENTORY_PATH"] = str(inventory_path)
            result = subprocess.run(
                [sys.executable, "scripts/verify-ai-help-context-coverage.py"],
                cwd=REPO_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("deep/alias registry page IDs missing from inventory", result.stderr)
        self.assertIn("settings-about", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
