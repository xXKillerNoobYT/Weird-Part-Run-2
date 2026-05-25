import unittest
from pathlib import Path


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "Weird Parts IOS"
    / "Weird Parts IOS"
    / "Scanning"
    / "QRScanSheet.swift"
)


class QRScanSheetMainActorTests(unittest.TestCase):
    def test_start_scanning_error_paths_update_state_on_main_actor(self):
        text = SOURCE.read_text(encoding="utf-8")
        start = text.index("private func startScanning()")
        end = text.index("// MARK: - Processing")
        section = text[start:end]

        self.assertIn(
            'case .error(let msg):\n                        await MainActor.run {\n                            scanError = msg',
            section,
        )
        self.assertIn(
            'case .permissionDenied:\n                        await MainActor.run {\n                            scanError = "Camera permission required. Enable in Settings."\n                            isScanning = false',
            section,
        )
        self.assertIn(
            "catch {\n                await MainActor.run {\n                    scanError = userFriendlyError(error, context: \"scan item\")\n                    isScanning = false",
            section,
        )

    def test_matching_result_auto_dismiss_behavior_remains(self):
        text = SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "if result.entityType == expected {\n                        await MainActor.run { dismiss() }\n                        onResult(result)",
            text,
        )
        self.assertIn(
            "await MainActor.run { dismiss() }\n                    onResult(result)",
            text,
        )


if __name__ == "__main__":
    unittest.main()
