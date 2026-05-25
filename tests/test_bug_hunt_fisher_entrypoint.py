import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "bug-hunt-fisher.sh"


class BugHuntFisherEntrypointTests(unittest.TestCase):
    def test_smoke_check_passes_with_canonical_docs_paths(self):
        result = subprocess.run(
            [str(SCRIPT), "--repo-root", str(REPO_ROOT), "--smoke-check"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, msg=result.stderr)
        self.assertIn("bug-hunt fisher smoke-check passed", result.stdout)

    def test_smoke_check_fails_when_required_plan_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_root = Path(tmp)
            (fake_root / "docs" / "plans").mkdir(parents=True)
            (fake_root / "docs" / "plans" / "hunt-fix-verify-loop.md").write_text("core")
            (fake_root / "docs" / "plans" / "master-issue-list.md").write_text("fishing")

            result = subprocess.run(
                [str(SCRIPT), "--repo-root", str(fake_root), "--smoke-check"],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(0, result.returncode)
            self.assertIn("required plan file missing", result.stderr)
            self.assertIn("docs/hunt-fix-tracker.md", result.stderr)

    def test_issue_selection_order_is_blocked_todo_backlog(self):
        result = subprocess.run(
            [str(SCRIPT), "--repo-root", str(REPO_ROOT)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, msg=result.stderr)
        self.assertIn("1. blocked", result.stdout)
        self.assertIn("2. todo", result.stdout)
        self.assertIn("3. backlog", result.stdout)


if __name__ == "__main__":
    unittest.main()
