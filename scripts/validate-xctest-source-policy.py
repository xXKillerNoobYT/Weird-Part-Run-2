#!/usr/bin/env python3
"""Validate checkout-hosted replacements for iOS XCTest source contracts.

Device XCTest targets cannot reliably read checkout sources.  This validator runs
in CI against the checkout and evaluates the same source invariants described in
``docs/testing/xctest-source-policy-manifest.json``.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


REQUIRED_RULE_KEYS = {"contains", "not_contains", "ordered", "regex", "count", "scoped", "function_scoped"}
CHECKOUT_READ_PATTERNS = ("#filePath", "StaticString", "String(contentsOfFile:")
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


def validate_rule(identifier: str, source: str, rule: Any, scope: str = "target") -> list[str]:
    """Evaluate one composable static source-policy rule against an exact scope."""
    errors: list[str] = []
    if not isinstance(rule, dict) or not set(rule).intersection(REQUIRED_RULE_KEYS):
        return [f"{identifier}: {scope} rule must declare contains, not_contains, ordered, regex, count, or scoped"]

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
        errors.extend(validate_rule(identifier, source[start:end], scope_rule.get("rule", {}), f"scope {scope_rule['start']!r}…{scope_rule['end']!r}"))
    for scope_rule in rule.get("function_scoped", []):
        if not isinstance(scope_rule, dict) or not isinstance(scope_rule.get("after"), str):
            errors.append(f"{identifier}: function_scoped rules require a string after marker")
            continue
        marker = scope_rule["after"]
        marker_start = source.find(marker)
        opening_brace = source.find("{", marker_start + len(marker)) if marker_start >= 0 else -1
        if opening_brace < 0:
            errors.append(f"{identifier}: function scope marker must precede an opening brace: {marker!r}")
            continue
        depth = 0
        closing_brace = -1
        for index in range(opening_brace, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    closing_brace = index
                    break
        if closing_brace < 0:
            errors.append(f"{identifier}: function scope marker has no balanced closing brace: {marker!r}")
            continue
        errors.extend(validate_rule(identifier, source[opening_brace:closing_brace], scope_rule.get("rule", {}), f"function scope {marker!r}"))
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
    return validate_rule(identifier, source, entry.get("rule"), "target")


def validate_checkout_reads(repo_root: Path, manifest: dict[str, Any]) -> list[str]:
    """Fail migrated XCTest cohorts that still read checkout sources at runtime.

    A manifest can describe source policies for a cohort that is being migrated in
    several commits.  Only entries marked ``enforceNoCheckoutReads`` have removed
    their runtime source assertions in this checkout, so only those cohorts can
    safely be subject to the fail-closed checkout-read ban.
    """
    directory = repo_root / COHORT_TEST_DIRECTORY
    errors: list[str] = []
    test_sources = {
        repo_root / entry["testSource"].split(":", 1)[0]
        for entry in manifest["entries"]
        if isinstance(entry.get("testSource"), str)
        and entry.get("enforceNoCheckoutReads") is True
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
        target.write_text(
            "let safe = true\n"
            "let orderedFirst = 1\n"
            "let orderedSecond = 2\n"
            "func scopedPolicy() {\n"
            "    let scopedSafe = true\n"
            "}\n",
            encoding="utf-8",
        )
        manifest = {
            "schemaVersion": 1,
            "entries": [{
                "id": "self-test",
                "testSource": "Tests/SelfTest.swift:testInvariant",
                "target": "App.swift",
                "invariant": "Safe source contract remains true.",
                "replacement": "checkout-hosted validator",
                "executableCoverage": "not applicable: static source policy",
                "rule": {
                    "contains": ["let safe = true"],
                    "not_contains": ["unsafe = true"],
                    "ordered": [["orderedFirst", "orderedSecond"]],
                    "regex": [r"orderedFirst\s*=\s*1"],
                    "count": [{"fragment": "ordered", "exact": 2}],
                    "scoped": [{"start": "let safe", "end": "orderedSecond", "rule": {"contains": ["orderedFirst"]}}],
                    "function_scoped": [{"after": "func scopedPolicy()", "rule": {"contains": ["let scopedSafe = true"], "not_contains": ["unsafe"]}}],
                },
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
