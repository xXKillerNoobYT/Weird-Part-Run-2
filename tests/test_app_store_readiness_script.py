import subprocess
import tempfile
import unittest
from pathlib import Path

PASSING_ICON_CONTENTS = (
    '{\n  "images" : [\n    {\n      "filename" : "AppIcon.png",\n'
    '      "idiom" : "universal",\n      "platform" : "ios",\n'
    '      "size" : "1024x1024"\n    }\n  ]\n}\n'
)

PASSING_PBXPROJ = (
    "MARKETING_VERSION = 1.0.0;\n"
    'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.business";\n'
)

PASSING_INFO_PLIST = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n<dict>\n'
    "\t<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>\n"
    "</dict>\n</plist>\n"
)

INFO_PLIST_WITHOUT_ENCRYPTION_KEY = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n<dict>\n'
    "\t<key>NSCameraUsageDescription</key>\n\t<string>stub</string>\n"
    "</dict>\n</plist>\n"
)


class AppStoreReadinessScriptTests(unittest.TestCase):
    def _run_script(self, root):
        script = root / "scripts" / "check-app-store-readiness.sh"
        return subprocess.run(
            ["bash", str(script)],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )

    def _build_stub_tree(self, tmp_root):
        """Create a repo stub that passes every readiness check."""
        repo_root = Path(__file__).resolve().parents[1]
        script_source = repo_root / "scripts" / "check-app-store-readiness.sh"

        script = tmp_root / "scripts" / "check-app-store-readiness.sh"
        script.parent.mkdir(parents=True, exist_ok=True)
        script.write_text(script_source.read_text(encoding="utf-8"), encoding="utf-8")
        script.chmod(0o755)

        (tmp_root / "docs" / "app-store" / "screenshots").mkdir(parents=True, exist_ok=True)
        (tmp_root / "docs" / "app-store" / "description.md").write_text("stub", encoding="utf-8")
        (tmp_root / "docs" / "app-store" / "privacy-labels.md").write_text("stub", encoding="utf-8")

        pbxproj = tmp_root / "Weird Parts IOS" / "Weird Parts.xcodeproj" / "project.pbxproj"
        pbxproj.parent.mkdir(parents=True, exist_ok=True)
        pbxproj.write_text(PASSING_PBXPROJ, encoding="utf-8")

        appiconset = (
            tmp_root
            / "Weird Parts IOS"
            / "Weird Parts IOS"
            / "Assets.xcassets"
            / "AppIcon.appiconset"
        )
        appiconset.mkdir(parents=True, exist_ok=True)
        (appiconset / "Contents.json").write_text(PASSING_ICON_CONTENTS, encoding="utf-8")
        (appiconset / "AppIcon.png").write_bytes(b"\x89PNG stub")

        info_plist = tmp_root / "Weird Parts IOS" / "Weird-Parts-IOS-Info.plist"
        info_plist.write_text(PASSING_INFO_PLIST, encoding="utf-8")

        return tmp_root, pbxproj, appiconset

    def _info_plist(self, tmp_root):
        return tmp_root / "Weird Parts IOS" / "Weird-Parts-IOS-Info.plist"

    def test_readiness_script_passes_with_required_files_and_version(self):
        repo_root = Path(__file__).resolve().parents[1]
        result = self._run_script(repo_root)

        self.assertEqual(
            result.returncode,
            0,
            msg=f"Script failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        self.assertIn("app-store readiness check passed", result.stdout)

    def test_readiness_script_passes_on_complete_stub_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root, _, _ = self._build_stub_tree(Path(tmp))
            result = self._run_script(tmp_root)

        self.assertEqual(
            result.returncode,
            0,
            msg=f"Stub tree should pass.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )

    def test_readiness_script_fails_when_marketing_version_drifts(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root, pbxproj, _ = self._build_stub_tree(Path(tmp))
            pbxproj.write_text(
                PASSING_PBXPROJ.replace("1.0.0;", "1.0.0.0;"), encoding="utf-8"
            )
            result = self._run_script(tmp_root)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid MARKETING_VERSION", result.stderr)

    def test_readiness_script_fails_when_icon_slot_is_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root, _, appiconset = self._build_stub_tree(Path(tmp))
            (appiconset / "Contents.json").write_text(
                '{\n  "images" : [\n    {\n      "idiom" : "universal",\n'
                '      "platform" : "ios",\n      "size" : "1024x1024"\n    }\n  ]\n}\n',
                encoding="utf-8",
            )
            result = self._run_script(tmp_root)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no image filename", result.stderr)

    def test_readiness_script_fails_when_icon_file_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root, _, appiconset = self._build_stub_tree(Path(tmp))
            (appiconset / "AppIcon.png").unlink()
            result = self._run_script(tmp_root)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing image file", result.stderr)

    def test_readiness_script_fails_when_category_key_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root, pbxproj, _ = self._build_stub_tree(Path(tmp))
            pbxproj.write_text("MARKETING_VERSION = 1.0.0;\n", encoding="utf-8")
            result = self._run_script(tmp_root)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LSApplicationCategoryType", result.stderr)

    def test_readiness_script_fails_when_export_compliance_key_is_missing(self):
        """Without the key every upload blocks as MISSING_EXPORT_COMPLIANCE.

        Build 48 sat unusable on exactly that, and the earlier fix (#1610)
        merged as an empty commit, so nothing caught the regression.
        """
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root, _, _ = self._build_stub_tree(Path(tmp))
            self._info_plist(tmp_root).write_text(
                INFO_PLIST_WITHOUT_ENCRYPTION_KEY, encoding="utf-8"
            )
            result = self._run_script(tmp_root)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ITSAppUsesNonExemptEncryption", result.stderr)


if __name__ == "__main__":
    unittest.main()
