import unittest
from pathlib import Path


class PE047CategoriesColorPickerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repo_root = Path(__file__).resolve().parents[1]
        cls.picker = (
            cls.repo_root
            / "Weird Parts IOS"
            / "Weird Parts IOS"
            / "Features"
            / "Parts"
            / "CategoriesColorPicker.swift"
        ).read_text(encoding="utf-8")
        cls.forms = (
            cls.repo_root
            / "Weird Parts IOS"
            / "Weird Parts IOS"
            / "Features"
            / "Parts"
            / "CategoriesFormSheets.swift"
        ).read_text(encoding="utf-8")

    def test_named_only_variants_render_as_text_pills_not_no_color_circles(self):
        self.assertIn("private var namedOnlyPill", self.picker)
        self.assertIn("Named-only variant", self.picker)
        self.assertIn("Text(color.name)", self.picker)
        self.assertIn("Capsule()", self.picker)
        self.assertNotIn("// \"None\" / no-color indicator", self.picker)

    def test_picker_copy_refers_to_shared_variants_pool(self):
        self.assertIn('Text("Shared variants")', self.picker)
        self.assertIn('Label("Add New Variant", systemImage: "plus")', self.picker)
        self.assertIn('Text("No variants in the shared pool. Add a variant to create catalog entries.")', self.picker)

    def test_color_form_creates_hex_null_for_named_only_variants(self):
        self.assertIn('Text("Named-only variants save without a hex value', self.forms)
        self.assertIn('try service.createColor(name: trimmedName, hexCode: hex, partNumber: pn, sortOrder: sortOrder)', self.forms)
        self.assertNotIn('try service.createColor(name: trimmedName, hexCode: hex ?? "", partNumber: pn, sortOrder: sortOrder)', self.forms)


if __name__ == "__main__":
    unittest.main()
