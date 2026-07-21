#!/usr/bin/env python3
"""Validate checkout-hosted replacements for iOS XCTest source contracts."""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


REQUIRED_METADATA = ("id", "testSource", "target", "invariant", "replacement", "executableCoverage")
RULE_KEYS = {
    "contains",
    "not_contains",
    "ordered",
    "regex_not_contains",
    "sections",
    "directory_count",
    "directory_scan",
    "occurrences",
}


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ValueError(f"missing manifest: {path}")
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {path}: {error}") from error
    if value.get("schemaVersion") != 1:
        raise ValueError("manifest schemaVersion must be 1")
    entries = value.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("manifest entries must be a non-empty array")
    return value


def require_string_list(value: Any, field: str, identifier: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{identifier}: {field} must be an array of strings")
    return value


def source_files(directory: Path, pattern: str) -> list[Path]:
    return sorted(path for path in directory.iterdir() if path.is_file() and fnmatch.fnmatch(path.name, pattern))


def section_slice(source: str, spec: dict[str, Any], identifier: str) -> tuple[str, list[str]]:
    errors: list[str] = []
    start = spec.get("start")
    end = spec.get("end")
    if not isinstance(start, str) or not start:
        return "", [f"{identifier}: section requires non-empty start"]
    start_match = re.search(start, source) if spec.get("startRegex") else None
    if spec.get("startRegex"):
        if not start_match:
            return "", [f"{identifier}: section start regex not found: {start!r}"]
        body_start = start_match.start()
        search_from = start_match.end()
    else:
        start_index = source.find(start)
        if start_index < 0:
            return "", [f"{identifier}: section start not found: {start!r}"]
        body_start = start_index
        search_from = start_index + len(start)

    if end is None:
        return source[body_start:], []
    if not isinstance(end, str) or not end:
        return "", [f"{identifier}: section end must be a non-empty string"]
    tail = source[search_from:]
    if spec.get("endRegex"):
        end_match = re.search(end, tail)
        if not end_match:
            return "", [f"{identifier}: section end regex not found after {start!r}: {end!r}"]
        return source[body_start:search_from + end_match.start()], errors
    end_index = tail.find(end)
    if end_index < 0:
        return "", [f"{identifier}: section end not found after {start!r}: {end!r}"]
    return source[body_start:search_from + end_index], errors


def validate_fragments(identifier: str, source: str, rule: dict[str, Any], label: str = "target") -> list[str]:
    errors: list[str] = []
    for fragment in require_string_list(rule.get("contains"), f"{label}.contains", identifier):
        if fragment not in source:
            errors.append(f"{identifier}: expected {label} to contain {fragment!r}")
    for fragment in require_string_list(rule.get("not_contains"), f"{label}.not_contains", identifier):
        if fragment in source:
            errors.append(f"{identifier}: {label} must not contain {fragment!r}")
    for pattern in require_string_list(rule.get("regex_not_contains"), f"{label}.regex_not_contains", identifier):
        if re.search(pattern, source):
            errors.append(f"{identifier}: {label} must not match regex {pattern!r}")
    ordered = rule.get("ordered", [])
    if not isinstance(ordered, list):
        raise ValueError(f"{identifier}: {label}.ordered must be an array")
    for pair in ordered:
        if not isinstance(pair, list) or len(pair) != 2 or not all(isinstance(item, str) for item in pair):
            raise ValueError(f"{identifier}: {label}.ordered entries must be two-string arrays")
        first, second = pair
        first_index = source.find(first)
        second_index = source.find(second)
        if first_index < 0 or second_index < 0:
            errors.append(f"{identifier}: ordered fragments must both exist in {label}: {first!r}, {second!r}")
        elif first_index >= second_index:
            errors.append(f"{identifier}: expected {first!r} before {second!r} in {label}")
    return errors


def validate_directory_count(repo_root: Path, identifier: str, specs: Any) -> list[str]:
    if specs is None:
        return []
    if not isinstance(specs, list):
        raise ValueError(f"{identifier}: directory_count must be an array")
    errors: list[str] = []
    for spec in specs:
        if not isinstance(spec, dict):
            raise ValueError(f"{identifier}: directory_count entries must be objects")
        directory_value = spec.get("directory")
        if not isinstance(directory_value, str) or not directory_value:
            raise ValueError(f"{identifier}: directory_count.directory must be a string")
        directory = repo_root / directory_value
        if not directory.is_dir():
            errors.append(f"{identifier}: missing directory: {directory_value}")
            continue
        pattern = spec.get("pattern", "*.swift")
        if not isinstance(pattern, str):
            raise ValueError(f"{identifier}: directory_count.pattern must be a string")
        contains = spec.get("contains")
        if not isinstance(contains, str) or not contains:
            raise ValueError(f"{identifier}: directory_count.contains must be a string")
        matches = 0
        for path in source_files(directory, pattern):
            if contains in path.read_text(encoding="utf-8"):
                matches += 1
        minimum = spec.get("min")
        if not isinstance(minimum, int):
            raise ValueError(f"{identifier}: directory_count.min must be an integer")
        if matches < minimum:
            errors.append(f"{identifier}: expected at least {minimum} files in {directory_value} containing {contains!r}, found {matches}")
    return errors


def validate_directory_scan(repo_root: Path, identifier: str, specs: Any) -> list[str]:
    if specs is None:
        return []
    if not isinstance(specs, list):
        raise ValueError(f"{identifier}: directory_scan must be an array")
    errors: list[str] = []
    for spec in specs:
        if not isinstance(spec, dict):
            raise ValueError(f"{identifier}: directory_scan entries must be objects")
        directory_value = spec.get("directory")
        if not isinstance(directory_value, str) or not directory_value:
            raise ValueError(f"{identifier}: directory_scan.directory must be a string")
        directory = repo_root / directory_value
        if not directory.is_dir():
            errors.append(f"{identifier}: missing directory: {directory_value}")
            continue
        allowlist = set(require_string_list(spec.get("allowlist"), "directory_scan.allowlist", identifier))
        pattern = spec.get("pattern", "*.swift")
        regex = spec.get("not_matches_regex")
        if not isinstance(pattern, str) or not isinstance(regex, str) or not regex:
            raise ValueError(f"{identifier}: directory_scan requires pattern and not_matches_regex strings")
        violations = []
        for path in source_files(directory, pattern):
            relative = str(path.relative_to(repo_root))
            if relative in allowlist:
                continue
            if re.search(regex, path.read_text(encoding="utf-8"), flags=re.DOTALL):
                violations.append(relative)
        if violations:
            errors.append(f"{identifier}: directory scan found forbidden matches: {', '.join(violations)}")
    return errors


def validate_occurrences(identifier: str, source: str, specs: Any) -> list[str]:
    if specs is None:
        return []
    if not isinstance(specs, list):
        raise ValueError(f"{identifier}: occurrences must be an array")
    errors: list[str] = []
    for spec in specs:
        if not isinstance(spec, dict):
            raise ValueError(f"{identifier}: occurrences entries must be objects")
        fragment = spec.get("contains")
        minimum = spec.get("min")
        if not isinstance(fragment, str) or not fragment or not isinstance(minimum, int):
            raise ValueError(f"{identifier}: occurrences entries require contains string and min integer")
        count = source.count(fragment)
        if count < minimum:
            errors.append(f"{identifier}: expected at least {minimum} occurrences of {fragment!r}, found {count}")
    return errors


def validate_entry(repo_root: Path, entry: dict[str, Any]) -> list[str]:
    identifier = entry.get("id", "<missing id>")
    missing = [key for key in REQUIRED_METADATA if not isinstance(entry.get(key), str) or not entry[key]]
    if missing:
        return [f"{identifier}: missing required metadata: {', '.join(missing)}"]
    rule = entry.get("rule")
    if not isinstance(rule, dict) or not set(rule).intersection(RULE_KEYS):
        return [f"{identifier}: rule must declare at least one supported rule key"]

    target = repo_root / entry["target"]
    if not target.is_file():
        return [f"{identifier}: missing regular target source: {entry['target']}"]
    try:
        errors = validate_fragments(identifier, target.read_text(encoding="utf-8"), rule)
        errors.extend(validate_occurrences(identifier, target.read_text(encoding="utf-8"), rule.get("occurrences")))
        for index, spec in enumerate(rule.get("sections", [])):
            if not isinstance(spec, dict):
                raise ValueError(f"{identifier}: sections entries must be objects")
            source, section_errors = section_slice(target.read_text(encoding="utf-8"), spec, identifier)
            errors.extend(section_errors)
            if not section_errors:
                errors.extend(validate_fragments(identifier, source, spec, f"section[{index}]"))
        errors.extend(validate_directory_count(repo_root, identifier, rule.get("directory_count")))
        errors.extend(validate_directory_scan(repo_root, identifier, rule.get("directory_scan")))
        return errors
    except ValueError as error:
        return [str(error)]


def validate(repo_root: Path, manifest_path: Path, quiet: bool = False) -> int:
    try:
        manifest = load_manifest(manifest_path)
    except ValueError as error:
        if not quiet:
            print(f"source-policy validation failed: {error}", file=sys.stderr)
        return 2
    errors = [error for entry in manifest["entries"] for error in validate_entry(repo_root, entry)]
    if errors:
        if not quiet:
            print("XCTest source-policy validation failed:", file=sys.stderr)
            for error in errors:
                print(f"- {error}", file=sys.stderr)
        return 1
    if not quiet:
        print(f"XCTest source-policy validation passed: {len(manifest['entries'])} migrated invariants.")
    return 0


def self_test() -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "Sources").mkdir()
        (root / "Sources" / "App.swift").write_text(
            "let safe = true\nfunc save() {\n dismiss()\n await onSave()\n}\nlet token = 42\n",
            encoding="utf-8",
        )
        (root / "Sources" / "Other.swift").write_text("rowAccessibility()\n", encoding="utf-8")
        manifest = {
            "schemaVersion": 1,
            "entries": [{
                "id": "self-test",
                "testSource": "Tests/SelfTest.swift:testInvariant",
                "target": "Sources/App.swift",
                "invariant": "Safe source contract remains true.",
                "replacement": "checkout-hosted validator",
                "executableCoverage": "not applicable: static source policy",
                "rule": {
                    "contains": ["let safe = true"],
                    "not_contains": ["unsafe = true"],
                    "ordered": [["dismiss()", "await onSave()"]],
                    "regex_not_contains": [r"token\s*=\s*0"],
                    "sections": [{"start": "func save()", "contains": ["dismiss()"], "not_contains": ["unsafe"]}],
                    "directory_count": [{"directory": "Sources", "pattern": "*.swift", "contains": "rowAccessibility()", "min": 1}],
                    "directory_scan": [{"directory": "Sources", "pattern": "*.swift", "not_matches_regex": r"NavigationLink\s*\{\s*Text\s*\(", "allowlist": []}],
                    "occurrences": [{"contains": "let", "min": 2}],
                },
            }],
        }
        manifest_path = root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        if validate(root, manifest_path) != 0:
            return 1
        (root / "Sources" / "App.swift").write_text("let unsafe = true\n", encoding="utf-8")
        if validate(root, manifest_path, quiet=True) != 1:
            print("self-test did not produce the expected intentional violation", file=sys.stderr)
            return 1
    print("XCTest source-policy validator self-test passed (including intentional violation).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate checkout-hosted XCTest source-policy invariants.")
    parser.add_argument("--manifest", type=Path, default=Path("docs/testing/xctest-source-policy-manifest.json"))
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    return validate(args.repo_root.resolve(), args.manifest)


if __name__ == "__main__":
    raise SystemExit(main())
