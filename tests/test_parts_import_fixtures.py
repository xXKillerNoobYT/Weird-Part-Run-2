import csv
import json
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "docs" / "testing" / "parts-import-fixtures"


def test_parts_import_fixture_manifest_contract():
    manifest_path = FIXTURES / "manifest.json"
    assert manifest_path.exists(), "Run scripts/generate_parts_import_fixtures.py first"
    manifest = json.loads(manifest_path.read_text())
    files = manifest["files"]

    assert sum(1 for f in files if f["format"] == "pdf") == 6
    assert sum(1 for f in files if f["format"] == "csv") == 8
    assert sum(1 for f in files if f["format"] == "xlsx") == 8
    assert sum(1 for f in files if f["format"] == "docx") == 5
    assert all(f["rows"] >= 30 for f in files)

    for entry in files:
        path = FIXTURES / entry["file"]
        assert path.exists(), f"Missing fixture {path}"
        assert path.stat().st_size > 200, f"Fixture too small: {path}"


def test_csv_fixtures_have_importable_required_columns_and_30_plus_rows():
    required = {"code", "name", "category"}
    for path in sorted((FIXTURES / "csv").glob("*.csv")):
        with path.open(newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        assert len(rows) >= 30, path
        assert required.issubset(set(reader.fieldnames or [])), path
        assert all(row["code"].strip() and row["name"].strip() and row["category"].strip() for row in rows)


def test_xlsx_fixtures_are_valid_openxml_with_30_plus_data_rows():
    ns = {"main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    for path in sorted((FIXTURES / "xlsx").glob("*.xlsx")):
        with zipfile.ZipFile(path) as z:
            names = set(z.namelist())
            assert "xl/workbook.xml" in names
            assert "xl/worksheets/sheet1.xml" in names
            sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
        rows = sheet.findall(".//main:sheetData/main:row", ns)
        assert len(rows) >= 31, path  # header + 30 data rows


def test_docx_fixtures_are_valid_openxml_with_30_plus_rows():
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    for path in sorted((FIXTURES / "docx").glob("*.docx")):
        with zipfile.ZipFile(path) as z:
            assert "word/document.xml" in set(z.namelist())
            doc = ET.fromstring(z.read("word/document.xml"))
        text = "\n".join(t.text or "" for t in doc.findall(".//w:t", ns))
        assert text.count(" | ") >= 31, path  # header + 30 data rows
        assert "verify" in text.lower()


def test_pdf_fixtures_have_pdf_header_and_30_plus_table_rows():
    for path in sorted((FIXTURES / "pdf").glob("*.pdf")):
        data = path.read_bytes()
        assert data.startswith(b"%PDF-1.4"), path
        # Generated text stream contains escaped table separators as plain bytes.
        assert data.count(b" | ") >= 31, path
        assert b"startxref" in data
