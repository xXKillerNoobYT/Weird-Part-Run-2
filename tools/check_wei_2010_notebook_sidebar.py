#!/usr/bin/env python3
"""Source-level regression checks for WEI-2010 notebook page-sidebar UX."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DETAIL = ROOT / "Weird Parts IOS" / "Weird Parts IOS" / "Features" / "Notebooks" / "IOSNotebookDetailPage.swift"
source = DETAIL.read_text()

checks = [
    ("page model derives sections as selectable notebook pages", "private struct NotebookPage" in source and "derivedPreview" in source),
    ("selected page state drives regular and compact detail panes", "@State private var selectedPageId" in source and "@State private var compactPageId" in source),
    ("regular width renders persistent page sidebar plus selected page surface", "pageSidebar" in source and "selectedPageSurface" in source and "notebookPageSidebar" in source),
    ("compact width starts with page list and drills into one selected page", "compactPageList" in source and "compactSelectedPageSurface" in source and "Back to pages" in source),
    ("page rows expose title, derived preview, metadata, count/status, and selection", "pageSidebarRow" in source and "notebookPageRow_" in source and "blockCountText" in source and "updatedText" in source),
    ("selected page content is scoped to the selected section entries", re.search(r"ForEach\(page\.section\.entries\).*entryRow", source, re.S) is not None),
    ("empty page copy is clear", "This page has no blocks yet." in source),
    ("old full hierarchy dump is not rendered as the primary content", "// Section Groups (collapsible)" not in source and "// Ungrouped sections" not in source),
]

failed = [name for name, ok in checks if not ok]
if failed:
    print("WEI-2010 notebook sidebar checks failed:")
    for name in failed:
        print(f"- {name}")
    sys.exit(1)

print("WEI-2010 notebook sidebar source checks passed")
