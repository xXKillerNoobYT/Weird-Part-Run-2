#!/usr/bin/env python3
"""Generate deterministic parts-import fixture files for WPR2 QA.

The fixtures intentionally exercise the catalog importer with 30+ rows per file,
different supplier/header layouts, money formats, units, categories, and document
styles. They are not scraped product data; names/SKUs are realistic electrical
parts inspired by distributor catalog categories so tests are repeatable offline.
"""
from __future__ import annotations

import csv
import json
import math
import shutil
import textwrap
import zipfile
from dataclasses import dataclass, asdict
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "testing" / "parts-import-fixtures"

CATEGORIES = [
    ("Wire", "Southwire", "THHN Copper Wire", "ft", 0.18),
    ("Conduit", "Allied Tube", "EMT Conduit", "stick", 6.75),
    ("Fittings", "Bridgeport", "EMT Set-Screw Connector", "ea", 1.42),
    ("Breakers", "Square D", "QO Plug-On Breaker", "ea", 13.85),
    ("Boxes", "Raco", "Steel Device Box", "ea", 2.95),
    ("Lighting", "Lithonia", "LED Flat Panel", "ea", 48.60),
    ("Devices", "Leviton", "Decorator Receptacle", "ea", 3.25),
    ("Fasteners", "Minerallac", "Strut Strap", "ea", 0.62),
]

SUPPLIERS = [
    "Codale Branch Quote",
    "Codale Counter Export",
    "Mountain West Electrical",
    "Industrial Supply House",
    "Jobsite Stock Recount",
    "Service Van Replenishment",
    "Lighting Retrofit Bid",
    "Panel Shop Order",
]

CSV_FIELD_SETS = [
    ["code", "name", "category", "brand", "supplier", "unit", "cost_price", "markup_percent", "quantity", "upc", "notes"],
    ["supplier", "brand", "code", "name", "unit", "quantity", "cost_price", "category", "markup_percent", "notes"],
    ["code", "name", "cost_price", "quantity", "unit", "category", "brand", "supplier"],
    ["name", "code", "category", "supplier", "brand", "upc", "unit", "cost_price", "markup_percent", "quantity"],
    ["name", "category", "code", "brand", "cost_price", "unit", "notes"],
    ["category", "name", "code", "supplier", "cost_price", "markup_percent", "quantity", "upc"],
    ["code", "category", "name", "brand", "supplier", "quantity", "unit", "cost_price", "notes"],
    ["supplier", "category", "brand", "name", "code", "upc", "cost_price", "unit", "markup_percent", "notes", "quantity"],
]

XLSX_FIELD_SETS = [
    CSV_FIELD_SETS[0],
    CSV_FIELD_SETS[1],
    ["name", "code", "brand", "category", "cost_price", "markup_percent", "unit", "quantity", "supplier", "upc", "notes"],
    ["category", "code", "name", "supplier", "brand", "unit", "quantity", "cost_price", "notes"],
    ["code", "category", "name", "cost_price", "brand", "supplier", "upc", "quantity", "unit"],
    ["supplier", "name", "category", "code", "notes", "cost_price", "markup_percent", "brand", "unit", "quantity"],
    ["brand", "name", "code", "category", "supplier", "unit", "cost_price", "upc", "notes"],
    ["upc", "code", "name", "category", "brand", "supplier", "cost_price", "markup_percent", "quantity", "unit", "notes"],
]

PDF_LAYOUTS = [
    ("distributor-table", "Code | Name | Category | Brand | Cost | Unit | Qty", ("code", "name", "category", "brand", "cost_price", "unit", "quantity"), " | "),
    ("counter-quote", "SKU - Description - Manufacturer - Family - Net - UOM - Count", ("code", "name", "brand", "category", "cost_price", "unit", "quantity"), " - "),
    ("inventory-ledger", "Category / Item / Part Code / On Hand / Unit / Make / Cost", ("category", "name", "code", "quantity", "unit", "brand", "cost_price"), " / "),
    ("bid-schedule", "Line; Product; Catalog No.; Brand; Group; Unit Cost; Pack", ("quantity", "name", "code", "brand", "category", "cost_price", "unit"), "; "),
    ("warehouse-pick-list", "PART :: GROUP :: DESCRIPTION :: MAKE :: QTY :: UOM :: PRICE", ("code", "category", "name", "brand", "quantity", "unit", "cost_price"), " :: "),
    ("service-van-recount", "Item,Description,Category,Unit,Count,Brand,Replacement Cost", ("code", "name", "category", "unit", "quantity", "brand", "cost_price"), ","),
]

DOCX_LAYOUT_NAMES = [
    "paragraph-catalog",
    "word-table",
    "tabbed-counter-export",
    "labeled-product-cards",
    "two-line-stock-cards",
]

@dataclass(frozen=True)
class Part:
    code: str
    name: str
    category: str
    brand: str
    supplier: str
    unit: str
    cost_price: str
    markup_percent: str
    quantity: int
    upc: str
    notes: str


def build_parts(count: int, supplier: str, seed: int) -> list[Part]:
    parts: list[Part] = []
    gauges = ["14 AWG", "12 AWG", "10 AWG", "8 AWG", "6 AWG"]
    conduit_sizes = ["1/2 in", "3/4 in", "1 in", "1-1/4 in", "2 in"]
    breaker_sizes = ["15A", "20A", "30A", "40A", "50A"]
    for i in range(count):
        category, brand, base_name, unit, base_cost = CATEGORIES[(i + seed) % len(CATEGORIES)]
        n = i + 1
        if category == "Wire":
            variant = gauges[(i + seed) % len(gauges)]
            name = f"{variant} {base_name} {500 if i % 2 else 250} ft spool"
        elif category == "Conduit":
            variant = conduit_sizes[(i + seed) % len(conduit_sizes)]
            name = f"{variant} {base_name} 10 ft"
        elif category == "Breakers":
            variant = breaker_sizes[(i + seed) % len(breaker_sizes)]
            name = f"{variant} 1-pole {base_name}"
        else:
            name = f"{base_name} #{(i + seed) % 12 + 1}"
        code_prefix = ''.join(word[0] for word in category.split())[:3].upper()
        cost = base_cost * (1 + ((i + seed) % 9) * 0.075)
        parts.append(Part(
            code=f"{code_prefix}-{seed:02d}-{n:03d}",
            name=name,
            category=category,
            brand=brand,
            supplier=supplier,
            unit=unit,
            cost_price=f"{cost:.2f}",
            markup_percent=str(12 + ((i + seed) % 7) * 3),
            quantity=1 + ((i * 3 + seed) % 48),
            upc=f"{880000000000 + seed * 1000 + n}",
            notes=f"Fixture row {n}; verify supplier/category mapping before import.",
        ))
    return parts


def rows(parts: list[Part]) -> list[dict[str, str]]:
    return [asdict(p) for p in parts]


def write_csv(path: Path, parts: list[Part], style: int) -> None:
    fields = CSV_FIELD_SETS[style]
    with path.open("w", newline="", encoding="utf-8") as f:
        # CRLF is deliberate: supplier exports commonly use Windows line endings,
        # and these fixtures guard the production Swift parser's compatibility.
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\r\n")
        writer.writeheader()
        for row in rows(parts):
            if style in (1, 5):
                row = {**row, "cost_price": f"${row['cost_price']}"}
            writer.writerow({k: row[k] for k in fields})


def col_name(index: int) -> str:
    result = ""
    index += 1
    while index:
        index, rem = divmod(index - 1, 26)
        result = chr(65 + rem) + result
    return result


def write_zip_text(z: zipfile.ZipFile, name: str, content: str) -> None:
    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, content.encode("utf-8"))


def make_xlsx(path: Path, sheet_name: str, headers: list[str], data_rows: list[list[str]]) -> None:
    def shared_strings(values: list[str]) -> str:
        sis = ''.join(f"<si><t>{escape(v)}</t></si>" for v in values)
        return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="{len(values)}" uniqueCount="{len(values)}">{sis}</sst>"""

    all_values = headers + [str(v) for row in data_rows for v in row]
    value_index = {v: i for i, v in enumerate(all_values)}
    sheet_rows = []
    for r_idx, row in enumerate([headers] + data_rows, start=1):
        cells = []
        for c_idx, value in enumerate(row):
            ref = f"{col_name(c_idx)}{r_idx}"
            cells.append(f'<c r="{ref}" t="s"><v>{value_index[str(value)]}</v></c>')
        sheet_rows.append(f'<row r="{r_idx}">{"".join(cells)}</row>')
    sheet = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>{''.join(sheet_rows)}</sheetData></worksheet>"""
    workbook = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="{escape(sheet_name)}" sheetId="1" r:id="rId1"/></sheets></workbook>"""
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>"""
    root_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"""
    workbook_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>"""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        write_zip_text(z, "[Content_Types].xml", content_types)
        write_zip_text(z, "_rels/.rels", root_rels)
        write_zip_text(z, "xl/workbook.xml", workbook)
        write_zip_text(z, "xl/_rels/workbook.xml.rels", workbook_rels)
        write_zip_text(z, "xl/worksheets/sheet1.xml", sheet)
        write_zip_text(z, "xl/sharedStrings.xml", shared_strings(all_values))


def write_xlsx(path: Path, parts: list[Part], style: int) -> None:
    headers = XLSX_FIELD_SETS[style]
    data = [[str(asdict(p)[h]) for h in headers] for p in parts]
    make_xlsx(path, f"Import {style + 1}", headers, data)


def pdf_escape(text: str) -> str:
    # The deterministic fixture PDF uses the built-in Type1 Helvetica font,
    # whose text stream must stay PDFDocEncoding/ASCII-compatible. Reject
    # unsupported text here rather than emitting UTF-8 bytes that native PDF
    # consumers extract as NUL or replacement characters.
    text.encode("ascii")
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def write_pdf(path: Path, title: str, parts: list[Part], style: int) -> None:
    # Small valid single-page/multi-page PDF with text operators only.
    objects: list[str] = []
    pages_refs = []
    layout_name, header, field_order, separator = PDF_LAYOUTS[style]
    rows_per_page = [32, 28, 30, 26, 31, 24][style]
    chunks = [parts[i:i + rows_per_page] for i in range(0, len(parts), rows_per_page)]
    # Each page contributes one content object and one page object. Reserve the
    # single font object after those pairs so every page can reference it.
    font_obj_no = len(chunks) * 2 + 1
    for page_no, chunk in enumerate(chunks, start=1):
        lines = [title, f"Layout {layout_name}; page {page_no}; verify OCR extraction before committing.", header]
        lines += [separator.join(str(getattr(p, field)) for field in field_order) for p in chunk]
        font_size = [8, 7, 8, 7, 7, 8][style]
        start_x = [50, 36, 44, 32, 40, 48][style]
        line_step = [14, 12, 13, 11, 12, 13][style]
        content_lines = ["BT", f"/F1 {font_size} Tf", f"{start_x} 760 Td"]
        first = True
        for line in lines:
            if not first:
                content_lines.append(f"0 -{line_step} Td")
            first = False
            content_lines.append(f"({pdf_escape(line[:118])}) Tj")
        content_lines.append("ET")
        stream = "\n".join(content_lines)
        content_obj_no = len(objects) + 1
        objects.append(f"<< /Length {len(stream.encode('utf-8'))} >>\nstream\n{stream}\nendstream")
        page_obj_no = len(objects) + 1
        pages_refs.append(page_obj_no)
        objects.append(f"<< /Type /Page /Parent 0 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 {font_obj_no} 0 R >> >> /Contents {content_obj_no} 0 R >>")
    assert len(objects) + 1 == font_obj_no
    objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    pages_obj_no = len(objects) + 1
    kids = " ".join(f"{n} 0 R" for n in pages_refs)
    objects.append(f"<< /Type /Pages /Kids [{kids}] /Count {len(pages_refs)} >>")
    catalog_obj_no = len(objects) + 1
    objects.append(f"<< /Type /Catalog /Pages {pages_obj_no} 0 R >>")
    # Patch placeholder parent refs.
    objects = [obj.replace("/Parent 0 0 R", f"/Parent {pages_obj_no} 0 R") for obj in objects]
    pdf = ["%PDF-1.4\n"]
    offsets = [0]
    for idx, obj in enumerate(objects, start=1):
        offsets.append(sum(len(x.encode('utf-8')) for x in pdf))
        pdf.append(f"{idx} 0 obj\n{obj}\nendobj\n")
    xref = sum(len(x.encode('utf-8')) for x in pdf)
    pdf.append(f"xref\n0 {len(objects)+1}\n0000000000 65535 f \n")
    for off in offsets[1:]:
        pdf.append(f"{off:010d} 00000 n \n")
    pdf.append(f"trailer\n<< /Size {len(objects)+1} /Root {catalog_obj_no} 0 R >>\nstartxref\n{xref}\n%%EOF\n")
    path.write_bytes("".join(pdf).encode("utf-8"))


def write_docx(path: Path, title: str, parts: list[Part], style: int) -> None:
    layout_name = DOCX_LAYOUT_NAMES[style]
    intro = [title, f"Layout {layout_name}; verify supplier/category/duplicates before import."]
    intro_xml = ''.join(f"<w:p><w:r><w:t>{escape(p)}</w:t></w:r></w:p>" for p in intro)
    if style == 0:
        rows_xml = ''.join(
            f"<w:p><w:r><w:t>{escape(f'{p.code} | {p.name} | {p.category} | {p.brand} | {p.cost_price} | {p.unit} | {p.quantity}')}</w:t></w:r></w:p>"
            for p in parts
        )
        body = intro_xml + "<w:p><w:r><w:t>Code | Name | Category | Brand | Cost | Unit | Qty</w:t></w:r></w:p>" + rows_xml
    elif style == 1:
        def table_row(values: list[str]) -> str:
            return "<w:tr>" + ''.join(f"<w:tc><w:p><w:r><w:t>{escape(value)}</w:t></w:r></w:p></w:tc>" for value in values) + "</w:tr>"
        rows_xml = table_row(["SKU", "Description", "Family", "Make", "Net", "UOM", "Count"])
        rows_xml += ''.join(table_row([p.code, p.name, p.category, p.brand, p.cost_price, p.unit, str(p.quantity)]) for p in parts)
        body = intro_xml + f"<w:tbl>{rows_xml}</w:tbl>"
    elif style == 2:
        rows_xml = ''.join(
            f"<w:p><w:r><w:t xml:space=\"preserve\">{escape(chr(9).join([p.code, p.name, p.brand, p.category, p.unit, str(p.quantity), p.cost_price]))}</w:t></w:r></w:p>"
            for p in parts
        )
        body = intro_xml + "<w:p><w:r><w:t>Code&#9;Name&#9;Brand&#9;Category&#9;Unit&#9;Qty&#9;Cost</w:t></w:r></w:p>" + rows_xml
    elif style == 3:
        rows_xml = ''.join(
            f"<w:p><w:r><w:t>{escape(f'SKU: {p.code}; Product: {p.name}; Group: {p.category}; Make: {p.brand}; Net: {p.cost_price}; Pack: {p.unit}; Count: {p.quantity}')}</w:t></w:r></w:p>"
            for p in parts
        )
        body = intro_xml + rows_xml
    else:
        rows_xml = ''.join(
            f"<w:p><w:r><w:t>{escape(f'{p.code} — {p.name}')}</w:t></w:r></w:p><w:p><w:r><w:t>{escape(f'{p.category} / {p.brand} / {p.unit} / qty {p.quantity} / ${p.cost_price}')}</w:t></w:r></w:p>"
            for p in parts
        )
        body = intro_xml + rows_xml
    document = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>{body}<w:sectPr/></w:body></w:document>"""
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>"""
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>"""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        write_zip_text(z, "[Content_Types].xml", content_types)
        write_zip_text(z, "_rels/.rels", rels)
        write_zip_text(z, "word/document.xml", document)


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "csv").mkdir(parents=True)
    (OUT / "xlsx").mkdir()
    (OUT / "pdf").mkdir()
    (OUT / "docx").mkdir()

    manifest = []
    for i in range(8):
        supplier = SUPPLIERS[i]
        parts = build_parts(36 + (i % 3), supplier, i + 1)
        csv_path = OUT / "csv" / f"parts-import-style-{i+1:02d}.csv"
        xlsx_path = OUT / "xlsx" / f"parts-import-style-{i+1:02d}.xlsx"
        write_csv(csv_path, parts, i)
        write_xlsx(xlsx_path, parts, i)
        manifest.append({"file": str(csv_path.relative_to(OUT)), "format": "csv", "rows": len(parts), "style": i + 1, "supplier": supplier, "layout": f"csv-header-{i + 1}", "headerSignature": CSV_FIELD_SETS[i]})
        manifest.append({"file": str(xlsx_path.relative_to(OUT)), "format": "xlsx", "rows": len(parts), "style": i + 1, "supplier": supplier, "layout": f"xlsx-header-{i + 1}", "headerSignature": XLSX_FIELD_SETS[i]})

    for i in range(6):
        supplier = SUPPLIERS[i]
        parts = build_parts(34 + i, supplier, i + 20)
        pdf_path = OUT / "pdf" / f"parts-import-ocr-style-{i+1:02d}.pdf"
        write_pdf(pdf_path, f"{supplier} - OCR Parts Catalog Fixture", parts, i)
        manifest.append({"file": str(pdf_path.relative_to(OUT)), "format": "pdf", "rows": len(parts), "style": i + 1, "supplier": supplier, "layout": PDF_LAYOUTS[i][0], "headerSignature": PDF_LAYOUTS[i][1], "separator": PDF_LAYOUTS[i][3]})

    for i in range(5):
        supplier = SUPPLIERS[i + 2]
        parts = build_parts(33 + i, supplier, i + 40)
        docx_path = OUT / "docx" / f"parts-import-word-style-{i+1:02d}.docx"
        write_docx(docx_path, f"{supplier} — Word Parts Catalog Fixture", parts, i)
        manifest.append({"file": str(docx_path.relative_to(OUT)), "format": "docx", "rows": len(parts), "style": i + 1, "supplier": supplier, "layout": DOCX_LAYOUT_NAMES[i]})

    (OUT / "manifest.json").write_text(json.dumps({"minimumRowsPerFile": 30, "files": manifest}, indent=2) + "\n", encoding="utf-8")
    readme = """# Parts Import Fixture Pack

Generated by `scripts/generate_parts_import_fixtures.py` for WEI-4507.

This pack gives UI and importer QA repeatable parts-catalog files:

- 6 PDF OCR-style catalogs, each with 30+ parts and a distinct column order,
  delimiter, typography, row density, and named layout.
- 8 CRLF CSV catalogs, each with 30+ parts and a unique header signature;
  two include currency-prefixed costs to exercise production normalization.
- 8 XLSX catalogs, each with 30+ parts and a unique sheet/header signature.
- 5 Word DOCX catalogs, each with 30+ parts and a distinct structure: paragraph
  catalog, table, tabbed export, labeled cards, or two-line stock cards.

The manifest records every fixture's `layout` and, for tabular/PDF fixtures,
its `headerSignature`. Achieved deterministic diversity is therefore 8/8 unique
CSV headers, 8/8 unique XLSX headers, 6/6 PDF layouts, and 5/5 DOCX layouts.

The rows use realistic electrical-distributor categories and supplier names inspired by
Codale-style catalog testing, but they are deterministic synthetic QA data, not live
scraped product data. During import testing, the user should still verify supplier
selection, existing/new supplier handling, category mapping, duplicates, and every
PDF/OCR row before commit.

Regenerate and validate:

```bash
python3 scripts/generate_parts_import_fixtures.py
python3 -m pytest tests/test_parts_import_fixtures.py
```
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")
    print(f"Generated {len(manifest)} fixture files under {OUT}")

if __name__ == "__main__":
    main()
