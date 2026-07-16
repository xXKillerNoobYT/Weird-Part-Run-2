import csv
import json
import platform
import re
import shutil
import subprocess
import zipfile
from pathlib import Path
from typing import Optional
from xml.etree import ElementTree as ET

import pytest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "docs" / "testing" / "parts-import-fixtures"

PDFKIT_EXTRACTOR = r"""
import Foundation
import PDFKit

var extracted: [String: String] = [:]
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let document = PDFDocument(url: url) else {
        fputs("PDFKit could not open \(path)\n", stderr)
        exit(2)
    }
    let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
    extracted[url.lastPathComponent] = pages.joined(separator: "\n")
}
let data = try JSONSerialization.data(withJSONObject: extracted, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
"""


def _manifest_rows() -> dict[str, int]:
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    return {entry["file"]: entry["rows"] for entry in manifest["files"]}


def _manifest_entries() -> list[dict]:
    return json.loads((FIXTURES / "manifest.json").read_text())["files"]


def _require_pdfkit_toolchain() -> None:
    if platform.system() != "Darwin":
        pytest.skip("PDFKit extraction requires macOS")
    if shutil.which("xcrun") is None:
        pytest.skip("PDFKit extraction requires xcrun")


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


def test_fixture_pack_has_materially_distinct_layout_signatures():
    entries = _manifest_entries()
    expected_unique = {"csv": 8, "xlsx": 8, "pdf": 6, "docx": 5}
    for fixture_format, expected_count in expected_unique.items():
        format_entries = [entry for entry in entries if entry["format"] == fixture_format]
        assert len({entry["layout"] for entry in format_entries}) == expected_count

    csv_headers = set()
    for path in sorted((FIXTURES / "csv").glob("*.csv")):
        with path.open(newline="", encoding="utf-8") as f:
            csv_headers.add(tuple(next(csv.reader(f))))
        assert b"\r\n" in path.read_bytes(), path
    assert len(csv_headers) == 8


def test_xlsx_fixtures_are_valid_openxml_with_30_plus_data_rows():
    ns = {"main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    expected_rows = _manifest_rows()
    header_signatures = set()
    for path in sorted((FIXTURES / "xlsx").glob("*.xlsx")):
        with zipfile.ZipFile(path) as z:
            assert z.testzip() is None, f"Corrupt ZIP member in {path}"
            names = set(z.namelist())
            assert "xl/workbook.xml" in names
            assert "xl/worksheets/sheet1.xml" in names
            sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
            shared = ET.fromstring(z.read("xl/sharedStrings.xml"))
        shared_values = [node.text or "" for node in shared.findall("main:si/main:t", ns)]
        rows = sheet.findall(".//main:sheetData/main:row", ns)
        cells = sheet.findall(".//main:sheetData/main:row/main:c", ns)
        referenced_values = []
        for cell in cells:
            assert cell.get("t") == "s", f"Unexpected non-shared-string cell in {path}"
            value_node = cell.find("main:v", ns)
            assert value_node is not None and value_node.text is not None
            index = int(value_node.text)
            assert 0 <= index < len(shared_values), f"Out-of-range shared-string index in {path}"
            referenced_values.append(shared_values[index])

        assert len(shared_values) == len(set(shared_values)), f"Duplicate shared strings in {path}"
        assert shared_values == list(dict.fromkeys(referenced_values)), (
            f"Shared strings are not in stable first-seen order in {path}"
        )
        assert int(shared.get("count", "-1")) == len(cells), path
        assert int(shared.get("uniqueCount", "-1")) == len(shared_values), path
        first_row_values = []
        for cell in rows[0].findall("main:c", ns):
            value_node = cell.find("main:v", ns)
            assert value_node is not None and value_node.text is not None
            first_row_values.append(shared_values[int(value_node.text)])
        header_signatures.add(tuple(first_row_values))
        relative_path = str(path.relative_to(FIXTURES))
        assert len(rows) - 1 == expected_rows[relative_path], path  # Exclude the header.
    assert len(header_signatures) == 8


def test_docx_fixtures_are_valid_openxml_with_30_plus_rows():
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    expected_rows = _manifest_rows()
    layouts = set()
    structures = set()
    for path in sorted((FIXTURES / "docx").glob("*.docx")):
        with zipfile.ZipFile(path) as z:
            assert "word/document.xml" in set(z.namelist())
            document_xml = z.read("word/document.xml")
            doc = ET.fromstring(document_xml)
        text = "\n".join(t.text or "" for t in doc.findall(".//w:t", ns))
        layout = re.search(r"Layout ([a-z-]+);", text)
        assert layout is not None
        layouts.add(layout.group(1))
        structures.add((b"<w:tbl>" in document_xml, b"xml:space=\"preserve\"" in document_xml, len(doc.findall(".//w:p", ns))))
        part_codes = re.findall(r"\b[A-Z]{1,3}-\d{2}-\d{3}\b", text)
        relative_path = str(path.relative_to(FIXTURES))
        assert len(part_codes) == expected_rows[relative_path], path
        assert "verify" in text.lower()
    assert len(layouts) == 5
    assert len(structures) == 5


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
    headers = set()
    layouts = set()

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
        layout = re.search(r"Layout ([a-z-]+);", extracted_pages[0][1])
        assert layout is not None
        layouts.add(layout.group(1))
        headers.add(extracted_pages[0][2])

        all_codes = [
            code
            for page_lines in extracted_pages
            for line in page_lines
            for code in re.findall(r"\b[A-Z]{1,3}-\d{2}-\d{3}\b", line)
        ]
        relative_path = str(path.relative_to(FIXTURES))
        assert len(all_codes) == expected_rows[relative_path], (
            f"Extracted row count does not match the manifest for {path}"
        )
    assert len(headers) == 6
    assert len(layouts) == 6


def test_pdfkit_extracts_declared_headers_and_separators_without_invalid_text():
    _require_pdfkit_toolchain()
    entries = [entry for entry in _manifest_entries() if entry["format"] == "pdf"]
    paths = [FIXTURES / entry["file"] for entry in entries]
    result = subprocess.run(
        ["xcrun", "swift", "-e", PDFKIT_EXTRACTOR, *(str(path) for path in paths)],
        check=True,
        capture_output=True,
        text=True,
    )
    extracted = json.loads(result.stdout)

    assert set(extracted) == {path.name for path in paths}
    assert len(entries) == len(paths)
    for entry, path in zip(entries, paths):
        text = extracted[path.name]
        assert "\0" not in text, path
        assert "\ufffd" not in text, path
        assert entry["headerSignature"] in text, path
        assert entry["separator"] in entry["headerSignature"], path
        assert text.count(entry["separator"]) >= entry["rows"], path


@pytest.mark.parametrize(
    ("system_name", "xcrun_path", "reason"),
    [
        ("Linux", "/usr/bin/xcrun", "requires macOS"),
        ("Darwin", None, "requires xcrun"),
    ],
)
def test_pdfkit_contract_skips_when_platform_or_xcrun_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
    system_name: str,
    xcrun_path: Optional[str],
    reason: str,
):
    monkeypatch.setattr(platform, "system", lambda: system_name)
    monkeypatch.setattr(shutil, "which", lambda _command: xcrun_path)

    with pytest.raises(pytest.skip.Exception, match=reason):
        _require_pdfkit_toolchain()
