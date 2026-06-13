import subprocess
import tempfile
import unittest
from pathlib import Path


class AppStoreReadinessScriptTests(unittest.TestCase):
    def test_readiness_script_passes_with_required_files_and_version(self):
        repo_root = Path(__file__).resolve().parents[1]
        script = repo_root / "scripts" / "check-app-store-readiness.sh"

        result = subprocess.run(
            ["bash", str(script)],
            cwd=repo_root,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(
            result.returncode,
            0,
            msg=f"Script failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        self.assertIn("app-store readiness check passed", result.stdout)

    def test_readiness_script_fails_when_marketing_version_drifts(self):
        repo_root = Path(__file__).resolve().parents[1]
        script_source = repo_root / "scripts" / "check-app-store-readiness.sh"

        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            script = tmp_root / "scripts" / "check-app-store-readiness.sh"
            script.parent.mkdir(parents=True, exist_ok=True)
            script.write_text(script_source.read_text(encoding="utf-8"), encoding="utf-8")
            script.chmod(0o755)

            (tmp_root / "docs" / "app-store" / "screenshots").mkdir(parents=True, exist_ok=True)
            (tmp_root / "docs" / "app-store" / "description.md").write_text("stub", encoding="utf-8")
            (tmp_root / "docs" / "app-store" / "privacy-labels.md").write_text("stub", encoding="utf-8")

            pbxproj = (
                tmp_root
                / "Weird Parts IOS"
                / "Weird Parts.xcodeproj"
                / "project.pbxproj"
            )
            pbxproj.parent.mkdir(parents=True, exist_ok=True)
            pbxproj.write_text("MARKETING_VERSION = 1.0.0.0;\n", encoding="utf-8")

            result = subprocess.run(
                ["bash", str(script)],
                cwd=tmp_root,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid MARKETING_VERSION", result.stderr)


if __name__ == "__main__":
    unittest.main()
