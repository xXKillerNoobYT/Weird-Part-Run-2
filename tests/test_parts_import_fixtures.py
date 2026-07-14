import csv
import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "docs" / "testing" / "parts-import-fixtures"


def _manifest_rows() -> dict[str, int]:
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    return {entry["file"]: entry["rows"] for entry in manifest["files"]}


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

    manifest_paths = [entry["file"] for entry in files]
    generated_paths = {
        str(path.relative_to(FIXTURES))
        for path in FIXTURES.rglob("*")
        if path.suffix.lower() in {".csv", ".xlsx", ".pdf", ".docx"}
    }
    assert len(manifest_paths) == 27
    assert len(set(manifest_paths)) == len(manifest_paths), "Manifest paths must be unique"
    assert set(manifest_paths) == generated_paths

    for entry in files:
        path = FIXTURES / entry["file"]
        assert path.exists(), f"Missing fixture {path}"
        assert path.stat().st_size > 200, f"Fixture too small: {path}"


def test_csv_fixtures_have_importable_required_columns_and_30_plus_rows():
    required = {"code", "name", "category"}
    expected_rows = _manifest_rows()
    for path in sorted((FIXTURES / "csv").glob("*.csv")):
        with path.open(newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        relative_path = str(path.relative_to(FIXTURES))
        assert len(rows) == expected_rows[relative_path], path
        assert required.issubset(set(reader.fieldnames or [])), path
        assert all(row["code"].strip() and row["name"].strip() and row["category"].strip() for row in rows)


def test_xlsx_fixtures_are_valid_openxml_with_30_plus_data_rows():
    ns = {"main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    expected_rows = _manifest_rows()
    for path in sorted((FIXTURES / "xlsx").glob("*.xlsx")):
        with zipfile.ZipFile(path) as z:
            names = set(z.namelist())
            assert "xl/workbook.xml" in names
            assert "xl/worksheets/sheet1.xml" in names
            sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
        rows = sheet.findall(".//main:sheetData/main:row", ns)
        relative_path = str(path.relative_to(FIXTURES))
        assert len(rows) - 1 == expected_rows[relative_path], path  # Exclude the header.


def test_docx_fixtures_are_valid_openxml_with_30_plus_rows():
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    expected_rows = _manifest_rows()
    for path in sorted((FIXTURES / "docx").glob("*.docx")):
        with zipfile.ZipFile(path) as z:
            assert "word/document.xml" in set(z.namelist())
            doc = ET.fromstring(z.read("word/document.xml"))
        text = "\n".join(t.text or "" for t in doc.findall(".//w:t", ns))
        table_rows = [
            line
            for line in text.splitlines()
            if line.count(" | ") == 6 and not line.startswith("Code | ")
        ]
        relative_path = str(path.relative_to(FIXTURES))
        assert len(table_rows) == expected_rows[relative_path], path
        assert "verify" in text.lower()


def _pdf_objects(data: bytes) -> dict[int, bytes]:
    return {
        int(match.group(1)): match.group(2)
        for match in re.finditer(rb"(?m)^(\d+) 0 obj\n(.*?)\nendobj$", data, re.DOTALL)
    }


def _pdf_text_lines(content_object: bytes) -> list[str]:
    stream = re.search(rb"stream\n(.*?)\nendstream", content_object, re.DOTALL)
    assert stream is not None, "Page content object is missing its stream"
    strings = re.findall(rb"\(((?:\\.|[^\\)])*)\) Tj", stream.group(1))
    return [
        value.replace(rb"\(", b"(")
        .replace(rb"\)", b")")
        .replace(rb"\\", bytes((92,)))
        .decode("utf-8")
        for value in strings
    ]


def test_pdf_fixtures_resolve_fonts_and_extract_every_table_row():
    expected_rows = _manifest_rows()

    for path in sorted((FIXTURES / "pdf").glob("*.pdf")):
        data = path.read_bytes()
        assert data.startswith(b"%PDF-1.4"), path
        assert b"startxref" in data

        objects = _pdf_objects(data)
        pages = [obj for obj in objects.values() if re.search(rb"/Type /Page\b", obj)]
        assert pages, f"No page objects found in {path}"

        extracted_pages: list[list[str]] = []
        for page in pages:
            font_ref = re.search(rb"/F1 (\d+) 0 R", page)
            content_ref = re.search(rb"/Contents (\d+) 0 R", page)
            assert font_ref is not None, f"Page has no /F1 resource in {path}"
            assert content_ref is not None, f"Page has no content reference in {path}"

            font = objects.get(int(font_ref.group(1)))
            assert font is not None and b"/Type /Font" in font, (
                f"Page /F1 does not resolve to a font object in {path}"
            )
            content = objects.get(int(content_ref.group(1)))
            assert content is not None, f"Page content reference is invalid in {path}"
            extracted_pages.append(_pdf_text_lines(content))

        assert extracted_pages[0], f"Page 1 extraction is empty in {path}"
        assert "Code | Name | Category | Brand | Cost | Unit | Qty" in extracted_pages[0]
        first_page_rows = [
            line
            for line in extracted_pages[0]
            if line.count(" | ") == 6 and not line.startswith("Code | ")
        ]
        assert len(first_page_rows) == 32, f"Page 1 must expose its first 32 parts in {path}"

        all_rows = [
            line
            for page_lines in extracted_pages
            for line in page_lines
            if line.count(" | ") == 6 and not line.startswith("Code | ")
        ]
        relative_path = str(path.relative_to(FIXTURES))
        assert len(all_rows) == expected_rows[relative_path], (
            f"Extracted row count does not match the manifest for {path}"
        )
