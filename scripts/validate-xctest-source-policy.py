#!/usr/bin/env python3
"""Validate checkout-hosted replacements for iOS XCTest source contracts.

Device XCTest targets cannot reliably read checkout sources.  This validator runs
in CI against the checkout and evaluates the same source invariants described in
``docs/testing/xctest-source-policy-manifest.json``.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


REQUIRED_RULE_KEYS = {"contains", "not_contains", "ordered", "regex", "not_regex", "count", "scoped", "directory_scan", "paths"}
CHECKOUT_READ_PATTERNS = ("#filePath", "StaticString", "String(contentsOfFile:", "String(contentsOf:")
COHORT_TEST_DIRECTORY = Path("Weird Parts IOS/Weird Parts IOSTests")


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


def source_files(directory: Path, pattern: str) -> list[Path]:
    return sorted(
        path for path in directory.rglob("*")
        if path.is_file() and fnmatch.fnmatch(path.name, pattern)
    )


def validate_directory_scan(repo_root: Path, identifier: str, specs: Any) -> list[str]:
    if specs is None:
        return []
    if not isinstance(specs, list):
        return [f"{identifier}: directory_scan must be an array"]

    errors: list[str] = []
    for spec in specs:
        if not isinstance(spec, dict):
            errors.append(f"{identifier}: directory_scan entries must be objects")
            continue
        directory_value = spec.get("directory")
        pattern = spec.get("pattern", "*.swift")
        required = spec.get("required_regex")
        when_contains = spec.get("when_contains")
        min_matching_files = spec.get("min_matching_files")
        if (
            not isinstance(directory_value, str)
            or not directory_value
            or not isinstance(pattern, str)
            or not isinstance(required, str)
            or not required
            or (when_contains is not None and (not isinstance(when_contains, list) or not all(isinstance(fragment, str) for fragment in when_contains)))
            or (min_matching_files is not None and (not isinstance(min_matching_files, int) or min_matching_files < 0))
        ):
            errors.append(f"{identifier}: directory_scan requires directory, pattern, required_regex, optional string-array when_contains, and optional non-negative min_matching_files")
            continue
        directory = repo_root / directory_value
        if not directory.is_dir():
            errors.append(f"{identifier}: missing directory: {directory_value}")
            continue
        matching_files = 0
        for path in source_files(directory, pattern):
            source = path.read_text(encoding="utf-8")
            matches = all(fragment in source for fragment in when_contains) if when_contains is not None else re.search(spec.get("when_regex", "."), source, flags=re.DOTALL)
            if matches:
                matching_files += 1
                if not re.search(required, source, flags=re.DOTALL):
                    errors.append(f"{identifier}: {path.relative_to(repo_root)} is missing required directory policy")
        if min_matching_files is not None and matching_files < min_matching_files:
            errors.append(f"{identifier}: expected at least {min_matching_files} matching files in {directory_value}, found {matching_files}")
    return errors


def validate_paths(repo_root: Path, identifier: str, specs: Any) -> list[str]:
    """Validate exact checkout paths that a migrated XCTest previously inspected."""
    if specs is None:
        return []
    if not isinstance(specs, dict):
        return [f"{identifier}: paths must be an object"]

    errors: list[str] = []
    for key, expected in (("exists", True), ("not_exists", False)):
        paths = specs.get(key, [])
        if not isinstance(paths, list) or not all(isinstance(path, str) and path for path in paths):
            errors.append(f"{identifier}: paths.{key} must be a string array")
            continue
        for relative_path in paths:
            actual = (repo_root / relative_path).exists()
            if actual != expected:
                state = "exist" if expected else "not exist"
                errors.append(f"{identifier}: expected path to {state}: {relative_path}")
    return errors


def validate_rule(
    identifier: str,
    source: str,
    rule: Any,
    scope: str = "target",
    repo_root: Path | None = None,
) -> list[str]:
    """Evaluate one composable static source-policy rule against an exact scope."""
    errors: list[str] = []
    if not isinstance(rule, dict) or not set(rule).intersection(REQUIRED_RULE_KEYS):
        return [f"{identifier}: {scope} rule must declare contains, not_contains, ordered, regex, not_regex, count, scoped, directory_scan, or paths"]

    for fragment in rule.get("contains", []):
        if fragment not in source:
            errors.append(f"{identifier}: expected {scope} to contain {fragment!r}")
    for fragment in rule.get("not_contains", []):
        if fragment in source:
            errors.append(f"{identifier}: {scope} must not contain {fragment!r}")
    for first, second in rule.get("ordered", []):
        first_index = source.find(first)
        second_index = source.find(second)
        if first_index < 0 or second_index < 0:
            errors.append(f"{identifier}: ordered {scope} fragments must both exist: {first!r}, {second!r}")
        elif first_index >= second_index:
            errors.append(f"{identifier}: expected {first!r} before {second!r} in {scope}")
    for pattern in rule.get("regex", []):
        if not re.search(pattern, source, flags=re.DOTALL):
            errors.append(f"{identifier}: expected {scope} to match regex {pattern!r}")
    for pattern in rule.get("not_regex", []):
        if re.search(pattern, source, flags=re.DOTALL):
            errors.append(f"{identifier}: {scope} must not match regex {pattern!r}")
    for count_rule in rule.get("count", []):
        if not isinstance(count_rule, dict) or not isinstance(count_rule.get("fragment"), str):
            errors.append(f"{identifier}: {scope} count rules require a string fragment")
            continue
        actual = source.count(count_rule["fragment"])
        if "exact" in count_rule and actual != count_rule["exact"]:
            errors.append(f"{identifier}: expected {scope} fragment {count_rule['fragment']!r} exactly {count_rule['exact']} times, found {actual}")
        if "min" in count_rule and actual < count_rule["min"]:
            errors.append(f"{identifier}: expected {scope} fragment {count_rule['fragment']!r} at least {count_rule['min']} times, found {actual}")
        if "max" in count_rule and actual > count_rule["max"]:
            errors.append(f"{identifier}: expected {scope} fragment {count_rule['fragment']!r} at most {count_rule['max']} times, found {actual}")
    for scope_rule in rule.get("scoped", []):
        if not isinstance(scope_rule, dict) or not isinstance(scope_rule.get("start"), str) or not isinstance(scope_rule.get("end"), str):
            errors.append(f"{identifier}: scoped rules require string start and end markers")
            continue
        start = source.find(scope_rule["start"])
        end = source.find(scope_rule["end"], start + len(scope_rule["start"])) if start >= 0 else -1
        if start < 0 or end < 0:
            errors.append(f"{identifier}: scoped markers must both exist: {scope_rule['start']!r}, {scope_rule['end']!r}")
            continue
        errors.extend(validate_rule(
            identifier,
            source[start:end],
            scope_rule.get("rule", {}),
            f"scope {scope_rule['start']!r}…{scope_rule['end']!r}",
            repo_root,
        ))
    if repo_root is not None:
        errors.extend(validate_directory_scan(repo_root, identifier, rule.get("directory_scan")))
        errors.extend(validate_paths(repo_root, identifier, rule.get("paths")))
    return errors


def validate_entry(repo_root: Path, entry: dict[str, Any]) -> list[str]:
    identifier = entry.get("id", "<missing id>")
    required_metadata = ("testSource", "invariant", "replacement", "executableCoverage", "target")
    missing = [key for key in required_metadata if not isinstance(entry.get(key), str) or not entry[key]]
    if missing:
        return [f"{identifier}: missing required metadata: {', '.join(missing)}"]

    target = repo_root / entry["target"]
    if not target.is_file():
        return [f"{identifier}: target must be a readable source file: {entry['target']}"]
    try:
        source = target.read_text(encoding="utf-8")
    except FileNotFoundError:
        return [f"{identifier}: missing target source: {entry['target']}"]
    return validate_rule(identifier, source, entry.get("rule"), "target", repo_root=repo_root)


def validate_checkout_reads(repo_root: Path, manifest: dict[str, Any]) -> list[str]:
    """Fail if any XCTest file represented in the manifest still reads the checkout."""
    directory = repo_root / COHORT_TEST_DIRECTORY
    errors: list[str] = []
    test_sources = {
        repo_root / entry["testSource"].split(":", 1)[0]
        for entry in manifest["entries"]
        if isinstance(entry.get("testSource"), str)
        and entry["testSource"].split(":", 1)[0].startswith(str(COHORT_TEST_DIRECTORY))
    }
    for test_source in sorted(test_sources):
        if not test_source.is_file():
            continue
        source = test_source.read_text(encoding="utf-8")
        for pattern in CHECKOUT_READ_PATTERNS:
            if pattern in source:
                errors.append(
                    f"{test_source.relative_to(repo_root)}: runtime checkout read remains ({pattern})"
                )
    return errors


def validate(repo_root: Path, manifest_path: Path) -> int:
    try:
        manifest = load_manifest(manifest_path)
    except ValueError as error:
        print(f"source-policy validation failed: {error}", file=sys.stderr)
        return 2

    errors = [error for entry in manifest["entries"] for error in validate_entry(repo_root, entry)]
    errors.extend(validate_checkout_reads(repo_root, manifest))
    if errors:
        print("XCTest source-policy validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"XCTest source-policy validation passed: {len(manifest['entries'])} migrated invariants.")
    return 0


def self_test() -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        target = root / "App.swift"
        target.write_text("let safe = true\nlet orderedFirst = 1\nlet orderedSecond = 2\n", encoding="utf-8")
        context_page = root / "Pages" / "Context.swift"
        context_page.parent.mkdir()
        context_page.write_text(
            "let searchText = \"\"\nNotificationCenter.default.post(name: .context, object: nil)\n.onChange(of: searchText) {}\n",
            encoding="utf-8",
        )
        test_source = root / COHORT_TEST_DIRECTORY / "SelfTest.swift"
        test_source.parent.mkdir(parents=True)
        test_source.write_text("final class SelfTest {}\n", encoding="utf-8")
        manifest = {
            "schemaVersion": 1,
            "entries": [{
                "id": "self-test",
                "testSource": f"{COHORT_TEST_DIRECTORY}/SelfTest.swift:testInvariant",
                "target": "App.swift",
                "invariant": "Safe source contract remains true.",
                "replacement": "checkout-hosted validator",
                "executableCoverage": "not applicable: static source policy",
                "rule": {
                    "contains": ["let safe = true"],
                    "not_contains": ["unsafe = true"],
                    "ordered": [["orderedFirst", "orderedSecond"]],
                    "regex": [r"orderedFirst\s*=\s*1"],
                    "not_regex": [r"unsafe\s*=\s*true"],
                    "count": [{"fragment": "ordered", "exact": 2}],
                    "scoped": [{"start": "let safe", "end": "orderedSecond", "rule": {"contains": ["orderedFirst"]}}],
                    "directory_scan": [{
                        "directory": "Pages",
                        "pattern": "*.swift",
                        "when_contains": ["searchText", "NotificationCenter.default.post"],
                        "required_regex": r"\.onChange\(of: searchText\)",
                        "min_matching_files": 1,
                    }],
                    "paths": {
                        "exists": ["App.swift"],
                        "not_exists": ["Legacy/App.swift"],
                    },
                },
            }],
        }
        manifest_path = root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        if validate(root, manifest_path) != 0:
            return 1
        test_source.write_text(
            "let sourceURL = URL(fileURLWithPath: \"App.swift\")\n"
            "let source = try String(contentsOf: sourceURL, encoding: .utf8)\n",
            encoding="utf-8",
        )
        if validate(root, manifest_path) != 1:
            print("self-test did not reject a registered checkout source read", file=sys.stderr)
            return 1
        test_source.write_text("final class SelfTest {}\n", encoding="utf-8")
        target.write_text("let unsafe = true\n", encoding="utf-8")
        if validate(root, manifest_path) != 1:
            print("self-test did not produce the expected intentional violation", file=sys.stderr)
            return 1
        target.write_text("let safe = true\nlet orderedFirst = 1\nlet orderedSecond = 2\n", encoding="utf-8")
        context_page.write_text("let searchText = \"\"\nNotificationCenter.default.post(name: .context, object: nil)\n", encoding="utf-8")
        if validate(root, manifest_path) != 1:
            print("self-test did not reject a matching file missing its directory policy", file=sys.stderr)
            return 1
        context_page.write_text(
            "let searchText = \"\"\nNotificationCenter.default.post(name: .context, object: nil)\n.onChange(of: searchText) {}\n",
            encoding="utf-8",
        )
        manifest["entries"][0]["rule"]["directory_scan"][0]["min_matching_files"] = 2
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        if validate(root, manifest_path) != 1:
            print("self-test did not reject a directory policy adoption-floor regression", file=sys.stderr)
            return 1
        manifest["entries"][0]["rule"]["directory_scan"][0]["min_matching_files"] = 1
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        legacy_target = root / "Legacy" / "App.swift"
        legacy_target.parent.mkdir()
        legacy_target.write_text("let legacy = true\n", encoding="utf-8")
        if validate(root, manifest_path) != 1:
            print("self-test did not reject a forbidden checkout path", file=sys.stderr)
            return 1
    print("XCTest source-policy validator self-test passed (including intentional violation).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate checkout-hosted XCTest source-policy invariants.")
    parser.add_argument("--manifest", type=Path, default=Path("docs/testing/xctest-source-policy-manifest.json"))
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--self-test", action="store_true", help="Run pass and intentional-violation checks in a temporary checkout.")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    return validate(args.repo_root.resolve(), args.manifest)


if __name__ == "__main__":
    raise SystemExit(main())
