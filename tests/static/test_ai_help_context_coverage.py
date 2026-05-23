#!/usr/bin/env python3
"""Static coverage checks for AI page context and HelpContentRegistry drift.

Run from the repo root with:
    python3 tests/static/test_ai_help_context_coverage.py
"""

from pathlib import Path
import re
import sys
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]
HELP_REGISTRY = REPO_ROOT / "Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift"
AI_PANEL = REPO_ROOT / "Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift"


class AIHelpContextCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = HELP_REGISTRY.read_text()
        cls.panel = AI_PANEL.read_text()
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

    def test_help_notification_mapping_matches_active_page_tracker(self):
        self.assertEqual(self.tracker_notifications, self.registry_notifications)

    def test_representative_beta_pages_have_help_and_context_coverage(self):
        required_page_ids = {
            "dashboard-home",
            "jobs-list",
            "jobs-questionnaire",
            "warehouse-inventory",
            "fleet-vehicles",
            "people-employees",
            "office-dashboard",
            "reports-timesheets",
            "settings-app-config",
        }
        missing_help = sorted(required_page_ids - self.help_page_ids)
        missing_tracker = sorted(required_page_ids - set(self.tracker_notifications.values()))
        self.assertEqual([], missing_help, "missing HelpContentRegistry entries")
        self.assertEqual([], missing_tracker, "missing active page tracker mappings")


if __name__ == "__main__":
    unittest.main(verbosity=2)
