#!/usr/bin/env python3
"""Static guards for scheduling sheet dismissal after mutation refresh."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONFIG_PAGE = ROOT / "Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSScheduleConfigPage.swift"
PIPELINE_PAGE = ROOT / "Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSShortTermPipelinePage.swift"


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"Could not find end of {signature}")


class SchedulingSheetRefreshErrorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = CONFIG_PAGE.read_text()
        cls.pipeline = PIPELINE_PAGE.read_text()

    def test_config_mutations_refresh_with_throwing_fetch_before_dismissal(self):
        cases = {
            "private func saveShiftTemplate": "shiftTemplates = try svc.getShiftTemplates()",
            "private func deleteShiftTemplate": "shiftTemplates = try svc.getShiftTemplates()",
            "private func saveHoliday": "holidays = try svc.getHolidays()",
            "private func deleteHoliday": "holidays = try svc.getHolidays()",
        }
        for signature, refresh in cases.items():
            with self.subTest(signature=signature):
                body = function_body(self.config, signature)
                do_block, catch_block = body.split("} catch", 1)
                self.assertIn(refresh, do_block)
                self.assertIn("activeSheet = nil", do_block)
                self.assertNotIn("try?", body)
                self.assertNotIn("?? []", body)
                self.assertNotIn("activeSheet = nil", catch_block)

    def test_callback_mutations_refresh_with_throwing_fetch_before_dismissal(self):
        cases = {
            "private func completeCallback": "complete callback",
            "private func snoozeCallback": "snooze callback",
        }
        for signature, context in cases.items():
            with self.subTest(signature=signature):
                body = function_body(self.pipeline, signature)
                do_block, catch_block = body.split("} catch", 1)
                self.assertIn("try refreshPipelineData()", do_block)
                self.assertIn("activeSheet = nil", do_block)
                self.assertIn(f'context: "{context}"', catch_block)
                self.assertNotIn("loadData()", body)
                self.assertNotIn("activeSheet = nil", catch_block)


if __name__ == "__main__":
    unittest.main(verbosity=2)
