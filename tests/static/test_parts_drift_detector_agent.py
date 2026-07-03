#!/usr/bin/env python3
"""Static guard for the project-scoped parts-drift-detector agent.

Run from the repo root with:
    python3 tests/static/test_parts_drift_detector_agent.py
"""

from pathlib import Path
import re
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT = REPO_ROOT / ".claude/agents/parts-drift-detector.md"


class PartsDriftDetectorAgentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.agent_text = AGENT.read_text(encoding="utf-8") if AGENT.exists() else ""

    def test_agent_definition_exists_with_claude_frontmatter(self):
        self.assertTrue(AGENT.exists())
        self.assertTrue(self.agent_text.startswith("---\n"))
        self.assertIn("name: parts-drift-detector", self.agent_text)
        self.assertIn("tools: Read, Grep, Glob", self.agent_text)

    def test_agent_covers_required_plan_inputs_and_code_targets(self):
        required_paths = [
            "docs/plans/parts-section-audit-fix-plan.md",
            "docs/plans/colors-parts-redesign.md",
            "docs/plans/forecasting-page-redesign.md",
            "docs/plans/inventory-intelligence-system.md",
            "Weird Parts IOS/Weird Parts IOS/Features/Parts/",
            "core/Sources/WiredPartCore/Services/PartsService.swift",
            "core/Sources/WiredPartCore/Models/Parts/",
            "core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift",
        ]
        missing = [path for path in required_paths if path not in self.agent_text]
        self.assertEqual([], missing)

    def test_agent_requires_structured_drift_output_sections(self):
        required_sections = [
            "## Summary",
            "## planned_but_not_coded",
            "## coded_but_not_planned",
            "## stale_tracker_or_plan_status",
            "## Non-findings / deferred items checked",
        ]
        missing = [section for section in required_sections if section not in self.agent_text]
        self.assertEqual([], missing)

    def test_agent_requires_file_line_citations_for_findings(self):
        citation_rules = [
            "Every non-empty finding must have citations.",
            "at least one plan `file:line` and one code `file:line`",
            "Do not paste large code blocks; cite paths and lines.",
        ]
        missing = [rule for rule in citation_rules if rule not in self.agent_text]
        self.assertEqual([], missing)

    def test_agent_defines_both_drift_directions_and_status_staleness(self):
        expected_terms = [
            "planned_but_not_coded",
            "coded_but_not_planned",
            "stale_tracker_or_plan_status",
            "NEEDS OWNER DECISION",
        ]
        missing = [term for term in expected_terms if term not in self.agent_text]
        self.assertEqual([], missing)
        self.assertRegex(
            self.agent_text,
            re.compile(r"Report `planned_but_not_coded` when.*absent", re.DOTALL),
        )
        self.assertRegex(
            self.agent_text,
            re.compile(r"Report `coded_but_not_planned` when.*not documented", re.DOTALL),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
