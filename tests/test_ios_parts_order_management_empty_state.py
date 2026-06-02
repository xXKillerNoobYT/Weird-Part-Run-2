import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "Weird Parts IOS" / "Weird Parts IOS" / "Features" / "Orders" / "IOSPartsOrderManagementPage.swift"


class IOSPartsOrderManagementEmptyStateTests(unittest.TestCase):
    def test_missing_supplier_does_not_report_orders_service_unavailable(self):
        text = SOURCE.read_text()

        self.assertIn("private enum PartsOrderManagementEmptyReason", text)
        self.assertIn("case noSuppliersWithActivePOs", text)
        self.assertIn("No suppliers with active purchase orders", text)

        load_data_start = text.index("private func loadData()")
        load_data_end = text.index("private func postAIContext()")
        load_data = text[load_data_start:load_data_end]

        self.assertNotIn("guard let service = appCore.ordersService, let suppId = selectedSupplierId", load_data)
        self.assertIn("Orders service not available", load_data)
        self.assertIn("guard let suppId = selectedSupplierId else", load_data)
        self.assertIn("loadError = nil", load_data)


if __name__ == "__main__":
    unittest.main()
