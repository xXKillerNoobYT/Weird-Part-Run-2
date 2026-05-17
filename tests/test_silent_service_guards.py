import re
import unittest
from pathlib import Path


class SilentServiceGuardTests(unittest.TestCase):
    def test_no_one_line_appcore_service_guard_silently_returns(self):
        """appCore service guards must surface an error instead of doing nothing."""
        repo_root = Path(__file__).resolve().parents[1]
        ios_root = repo_root / "Weird Parts IOS" / "Weird Parts IOS"
        pattern = re.compile(
            r"guard\s+let\s+\w+\s*=\s*appCore\.\w+Service\s+else\s*\{\s*return\s*\}"
        )

        offenders: list[str] = []
        for swift_file in ios_root.rglob("*.swift"):
            text = swift_file.read_text(encoding="utf-8")
            for match in pattern.finditer(text):
                line_no = text.count("\n", 0, match.start()) + 1
                offenders.append(f"{swift_file.relative_to(repo_root)}:{line_no}: {match.group(0)}")

        self.assertFalse(
            offenders,
            "Silent appCore service guard returns found:\n" + "\n".join(offenders),
        )


if __name__ == "__main__":
    unittest.main()
