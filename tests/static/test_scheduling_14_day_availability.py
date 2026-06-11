#!/usr/bin/env python3
"""Static guards for the Scheduling 14-day availability UX vertical slice."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
AVAILABILITY_PAGE = ROOT / "Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSWeeklyAvailabilityPage.swift"
SUB_SCHEDULE_PAGE = ROOT / "Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSSubSchedulePage.swift"


class SchedulingFourteenDayAvailabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.availability = AVAILABILITY_PAGE.read_text()
        cls.sub_schedule = SUB_SCHEDULE_PAGE.read_text()

    def test_availability_defaults_to_rolling_fourteen_day_preview(self):
        self.assertIn("Planning Preview", self.availability)
        self.assertIn("fourteenDayStart", self.availability)
        self.assertIn("fourteenDayRangeLabel", self.availability)
        self.assertIn("by: 14", self.availability)
        self.assertIn("value: 13", self.availability)
        self.assertNotIn("weekOffset", self.availability)

    def test_availability_renders_two_seven_day_bands_with_today_and_weekend_treatment(self):
        self.assertIn("Week 1", self.availability)
        self.assertIn("Week 2", self.availability)
        self.assertIn("weekBand", self.availability)
        self.assertIn("isToday", self.availability)
        self.assertIn("isWeekend", self.availability)
        self.assertRegex(self.availability, r"ForEach\(0\.\.<7")

    def test_availability_copy_and_accessibility_explain_cross_scheduling_model(self):
        self.assertIn("Previous 14 days", self.availability)
        self.assertIn("Jump to today", self.availability)
        self.assertIn("Next 14 days", self.availability)
        self.assertIn("Use Calendar for assigned employee jobs; use Sub Schedule for contractor commitments.", self.availability)
        self.assertIn("14-day planning preview", self.availability)
        self.assertIn("available", self.availability)
        self.assertIn("unavailable", self.availability)

    def test_sub_schedule_has_add_edit_and_empty_state_cta(self):
        self.assertIn("Add subcontractor schedule", self.sub_schedule)
        self.assertIn("CreateSubcontractorScheduleSheet", self.sub_schedule)
        self.assertIn("Add subcontractor schedule for", self.sub_schedule)
        self.assertIn("onTapGesture { activeSheet = .edit(row) }", self.sub_schedule)
        self.assertIn("scopeOfWork", self.sub_schedule)
        self.assertIn("arrivalTime", self.sub_schedule)


if __name__ == "__main__":
    unittest.main(verbosity=2)
