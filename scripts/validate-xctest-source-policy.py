#!/usr/bin/env python3
"""Validate checkout-hosted replacements for iOS XCTest source contracts.

Device XCTest targets cannot reliably read checkout sources.  This validator runs
in CI against the checkout and evaluates the same source invariants described in
``docs/testing/xctest-source-policy-manifest.json``.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path
from typing import Any


REQUIRED_RULE_KEYS = {"contains", "not_contains", "ordered"}


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


def validate_entry(repo_root: Path, entry: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    identifier = entry.get("id", "<missing id>")
    required_metadata = ("testSource", "invariant", "replacement", "executableCoverage", "target")
    missing = [key for key in required_metadata if not isinstance(entry.get(key), str) or not entry[key]]
    if missing:
        return [f"{identifier}: missing required metadata: {', '.join(missing)}"]

    rule = entry.get("rule")
    if not isinstance(rule, dict) or not set(rule).intersection(REQUIRED_RULE_KEYS):
        return [f"{identifier}: rule must declare contains, not_contains, or ordered"]

    target = repo_root / entry["target"]
    try:
        source = target.read_text(encoding="utf-8")
    except FileNotFoundError:
        return [f"{identifier}: missing target source: {entry['target']}"]

    for fragment in rule.get("contains", []):
        if fragment not in source:
            errors.append(f"{identifier}: expected target to contain {fragment!r}")
    for fragment in rule.get("not_contains", []):
        if fragment in source:
            errors.append(f"{identifier}: target must not contain {fragment!r}")
    for first, second in rule.get("ordered", []):
        first_index = source.find(first)
        second_index = source.find(second)
        if first_index < 0 or second_index < 0:
            errors.append(f"{identifier}: ordered fragments must both exist: {first!r}, {second!r}")
        elif first_index >= second_index:
            errors.append(f"{identifier}: expected {first!r} before {second!r}")
    return errors


def validate(repo_root: Path, manifest_path: Path) -> int:
    try:
        manifest = load_manifest(manifest_path)
    except ValueError as error:
        print(f"source-policy validation failed: {error}", file=sys.stderr)
        return 2

    errors = [error for entry in manifest["entries"] for error in validate_entry(repo_root, entry)]
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
        manifest = {
            "schemaVersion": 1,
            "entries": [{
                "id": "self-test",
                "testSource": "Tests/SelfTest.swift:testInvariant",
                "target": "App.swift",
                "invariant": "Safe source contract remains true.",
                "replacement": "checkout-hosted validator",
                "executableCoverage": "not applicable: static source policy",
                "rule": {"contains": ["let safe = true"], "not_contains": ["unsafe = true"], "ordered": [["orderedFirst", "orderedSecond"]]},
            }],
        }
        manifest_path = root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        if validate(root, manifest_path) != 0:
            return 1
        target.write_text("let unsafe = true\n", encoding="utf-8")
        if validate(root, manifest_path) != 1:
            print("self-test did not produce the expected intentional violation", file=sys.stderr)
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
