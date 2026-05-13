#!/usr/bin/env python3
"""Report source-only line coverage for WiredPartCore from Swift coverage JSON."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys


DEFAULT_THRESHOLD = 88.0


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def find_coverage_json(core_dir: Path) -> Path:
    configured = os.environ.get("WIREDPARTCORE_COVERAGE_JSON")
    if configured:
        return Path(configured).expanduser().resolve()

    candidates = sorted(
        core_dir.glob(".build/**/debug/codecov/WiredPartCore.json"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(
            "No Swift coverage JSON found. Run `swift test --enable-code-coverage` "
            "from core/ first, or set WIREDPARTCORE_COVERAGE_JSON."
        )
    return candidates[0]


def load_files(coverage_json: Path) -> list[dict]:
    with coverage_json.open(encoding="utf-8") as handle:
        payload = json.load(handle)

    data = payload.get("data")
    if not isinstance(data, list) or not data:
        raise ValueError(f"{coverage_json} does not look like llvm coverage JSON")

    files: list[dict] = []
    for item in data:
        files.extend(item.get("files", []))
    return files


def source_files(files: list[dict], source_dir: Path) -> list[dict]:
    source_prefix = str(source_dir.resolve()) + os.sep
    selected = []
    for item in files:
        filename = item.get("filename")
        if not isinstance(filename, str):
            continue
        resolved = str(Path(filename).resolve())
        line_count = item.get("summary", {}).get("lines", {}).get("count", 0)
        if resolved.startswith(source_prefix) and line_count > 0:
            selected.append(item)
    return selected


def format_percent(value: float) -> str:
    return f"{value:.2f}%"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Report source-only WiredPartCore line coverage from Swift coverage JSON."
    )
    parser.add_argument(
        "--coverage-json",
        type=Path,
        help="Path to llvm coverage JSON. Defaults to the newest core/.build/**/codecov/WiredPartCore.json.",
    )
    parser.add_argument(
        "--core-dir",
        type=Path,
        default=repo_root() / "core",
        help="Path to the Swift package core directory.",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        help="Source directory to include. Defaults to <core-dir>/Sources/WiredPartCore.",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=float(os.environ.get("WIREDPARTCORE_COVERAGE_THRESHOLD", DEFAULT_THRESHOLD)),
        help=f"Minimum source-only line coverage percent. Default: {DEFAULT_THRESHOLD:.0f}.",
    )
    parser.add_argument(
        "--lowest",
        type=int,
        default=10,
        help="Number of lowest-covered source files to print.",
    )
    args = parser.parse_args()

    core_dir = args.core_dir.expanduser().resolve()
    source_dir = (args.source_dir or core_dir / "Sources" / "WiredPartCore").expanduser().resolve()
    coverage_json = (
        args.coverage_json.expanduser().resolve()
        if args.coverage_json
        else find_coverage_json(core_dir)
    )

    files = source_files(load_files(coverage_json), source_dir)
    if not files:
        print(f"error: no covered source files found under {source_dir}", file=sys.stderr)
        return 2

    rows = []
    total_lines = 0
    covered_lines = 0
    for item in files:
        lines = item["summary"]["lines"]
        count = int(lines["count"])
        covered = int(lines["covered"])
        percent = (covered / count * 100.0) if count else 100.0
        total_lines += count
        covered_lines += covered
        rows.append(
            {
                "filename": Path(item["filename"]).resolve().relative_to(core_dir),
                "count": count,
                "covered": covered,
                "percent": percent,
            }
        )

    overall = covered_lines / total_lines * 100.0

    print("WiredPartCore source-only line coverage")
    print(f"Coverage JSON: {coverage_json}")
    print(f"Source root: {source_dir}")
    print(f"Total source lines: {total_lines}")
    print(f"Covered source lines: {covered_lines}")
    print(f"Coverage: {format_percent(overall)}")
    print(f"Threshold: {format_percent(args.threshold)}")
    print()
    print(f"Lowest-covered source files (bottom {min(args.lowest, len(rows))}):")
    for row in sorted(rows, key=lambda item: (item["percent"], item["count"], str(item["filename"])))[: args.lowest]:
        print(
            f"  {format_percent(row['percent']).rjust(7)} "
            f"{str(row['covered']).rjust(5)}/{str(row['count']).ljust(5)} "
            f"{row['filename']}"
        )

    if overall + 1e-9 < args.threshold:
        print()
        print(
            f"error: source-only coverage {format_percent(overall)} is below "
            f"{format_percent(args.threshold)}",
            file=sys.stderr,
        )
        return 1

    print()
    print("Coverage gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
