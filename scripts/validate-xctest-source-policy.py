#!/usr/bin/env python3
"""Validate checkout-hosted replacements for XCTest source contracts."""

from __future__ import annotations

import argparse
import contextlib
import fnmatch
import io
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


REQUIRED_METADATA = ("id", "testSource", "target", "invariant", "replacement", "executableCoverage")
RULE_KEYS = {
    "contains", "not_contains", "ordered", "regex", "regex_not_contains", "count",
    "sections", "scoped", "function_scoped", "directory_count", "directory_scan", "occurrences",
}
SCOPED_WRAPPER_KEYS = {"start", "end", "rule"}
FUNCTION_SCOPED_WRAPPER_KEYS = {"after", "rule"}
SECTION_METADATA_KEYS = {"start", "end", "startRegex", "endRegex"}
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
    if not isinstance(value.get("entries"), list) or not value["entries"]:
        raise ValueError("manifest entries must be a non-empty array")
    return value


def require_string_list(value: Any, field: str, identifier: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{identifier}: {field} must be an array of strings")
    return value


def validate_rule_keys(identifier: str, rule: Any, label: str = "rule") -> list[str]:
    if not isinstance(rule, dict):
        return [f"{identifier}: {label} must be an object"]
    unknown = sorted(set(rule).difference(RULE_KEYS))
    if unknown:
        return [
            f"{identifier}: {label} contains unsupported key(s): {', '.join(unknown)}; "
            f"supported keys: {', '.join(sorted(RULE_KEYS))}"
        ]
    if not set(rule).intersection(RULE_KEYS):
        return [f"{identifier}: {label} must declare at least one supported rule key"]
    return []


def validate_scoped_wrapper_keys(identifier: str, spec: Any, index: int) -> list[str]:
    label = f"scoped[{index}]"
    if not isinstance(spec, dict):
        return [f"{identifier}: {label} must be an object"]
    unknown = sorted(set(spec).difference(SCOPED_WRAPPER_KEYS))
    if unknown:
        return [
            f"{identifier}: {label} contains unsupported key(s): {', '.join(unknown)}; "
            f"supported keys: {', '.join(sorted(SCOPED_WRAPPER_KEYS))}"
        ]
    return []


def validate_function_scoped_wrapper_keys(identifier: str, spec: Any, index: int) -> list[str]:
    label = f"function_scoped[{index}]"
    if not isinstance(spec, dict):
        return [f"{identifier}: {label} must be an object"]
    unknown = sorted(set(spec).difference(FUNCTION_SCOPED_WRAPPER_KEYS))
    if unknown:
        return [
            f"{identifier}: {label} contains unsupported key(s): {', '.join(unknown)}; "
            f"supported keys: {', '.join(sorted(FUNCTION_SCOPED_WRAPPER_KEYS))}"
        ]
    return []


def source_files(directory: Path, pattern: str) -> list[Path]:
    return sorted(path for path in directory.iterdir() if path.is_file() and fnmatch.fnmatch(path.name, pattern))


def section_slice(source: str, spec: dict[str, Any], identifier: str) -> tuple[str, list[str]]:
    start, end = spec.get("start"), spec.get("end")
    if not isinstance(start, str) or not start:
        return "", [f"{identifier}: section requires non-empty start"]
    start_match = re.search(start, source) if spec.get("startRegex") else None
    if spec.get("startRegex"):
        if not start_match:
            return "", [f"{identifier}: section start regex not found: {start!r}"]
        body_start, search_from = start_match.start(), start_match.end()
    else:
        body_start = source.find(start)
        if body_start < 0:
            return "", [f"{identifier}: section start not found: {start!r}"]
        search_from = body_start + len(start)
    if end is None:
        return source[body_start:], []
    if not isinstance(end, str) or not end:
        return "", [f"{identifier}: section end must be a non-empty string"]
    tail = source[search_from:]
    end_match = re.search(end, tail) if spec.get("endRegex") else None
    end_index = end_match.start() if end_match else tail.find(end)
    if end_index < 0:
        return "", [f"{identifier}: section end not found after {start!r}: {end!r}"]
    return source[body_start:search_from + end_index], []


def validate_fragments(identifier: str, source: str, rule: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    for fragment in require_string_list(rule.get("contains"), f"{label}.contains", identifier):
        if fragment not in source:
            errors.append(f"{identifier}: expected {label} to contain {fragment!r}")
    for fragment in require_string_list(rule.get("not_contains"), f"{label}.not_contains", identifier):
        if fragment in source:
            errors.append(f"{identifier}: {label} must not contain {fragment!r}")
    for pattern in require_string_list(rule.get("regex"), f"{label}.regex", identifier):
        if not re.search(pattern, source, flags=re.DOTALL):
            errors.append(f"{identifier}: expected {label} to match regex {pattern!r}")
    for pattern in require_string_list(rule.get("regex_not_contains"), f"{label}.regex_not_contains", identifier):
        if re.search(pattern, source, flags=re.DOTALL):
            errors.append(f"{identifier}: {label} must not match regex {pattern!r}")
    ordered = rule.get("ordered", [])
    if not isinstance(ordered, list):
        raise ValueError(f"{identifier}: {label}.ordered must be an array")
    for pair in ordered:
        if not isinstance(pair, list) or len(pair) != 2 or not all(isinstance(item, str) for item in pair):
            raise ValueError(f"{identifier}: {label}.ordered entries must be two-string arrays")
        first, second = pair
        if first not in source or second not in source:
            errors.append(f"{identifier}: ordered fragments must both exist in {label}: {first!r}, {second!r}")
        elif source.find(first) >= source.find(second):
            errors.append(f"{identifier}: expected {first!r} before {second!r} in {label}")
    return errors


def validate_counts(identifier: str, source: str, specs: Any, key: str) -> list[str]:
    if specs is None:
        return []
    if not isinstance(specs, list):
        raise ValueError(f"{identifier}: {key} must be an array")
    errors: list[str] = []
    for spec in specs:
        if not isinstance(spec, dict):
            raise ValueError(f"{identifier}: {key} entries must be objects")
        fragment = spec.get("fragment", spec.get("contains"))
        if not isinstance(fragment, str) or not fragment:
            raise ValueError(f"{identifier}: {key} entries require a non-empty fragment/contains string")
        actual = source.count(fragment)
        for bound_key, predicate, words in (("exact", lambda: actual != spec["exact"], "exactly"), ("min", lambda: actual < spec["min"], "at least"), ("max", lambda: actual > spec["max"], "at most")):
            if bound_key in spec:
                if not isinstance(spec[bound_key], int):
                    raise ValueError(f"{identifier}: {key}.{bound_key} must be an integer")
                if predicate():
                    errors.append(f"{identifier}: expected {fragment!r} {words} {spec[bound_key]} times, found {actual}")
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
        directory_value, contains, minimum = spec.get("directory"), spec.get("contains"), spec.get("min")
        if not isinstance(directory_value, str) or not directory_value or not isinstance(contains, str) or not contains or not isinstance(minimum, int):
            raise ValueError(f"{identifier}: directory_count entries require directory, contains, and integer min")
        directory = repo_root / directory_value
        if not directory.is_dir():
            errors.append(f"{identifier}: missing directory: {directory_value}")
            continue
        pattern = spec.get("pattern", "*.swift")
        if not isinstance(pattern, str):
            raise ValueError(f"{identifier}: directory_count.pattern must be a string")
        matches = sum(contains in path.read_text(encoding="utf-8") for path in source_files(directory, pattern))
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
        directory_value, regex = spec.get("directory"), spec.get("not_matches_regex")
        if not isinstance(directory_value, str) or not directory_value or not isinstance(regex, str) or not regex:
            raise ValueError(f"{identifier}: directory_scan requires directory and not_matches_regex strings")
        directory = repo_root / directory_value
        if not directory.is_dir():
            errors.append(f"{identifier}: missing directory: {directory_value}")
            continue
        pattern = spec.get("pattern", "*.swift")
        if not isinstance(pattern, str):
            raise ValueError(f"{identifier}: directory_scan.pattern must be a string")
        allowlist = set(require_string_list(spec.get("allowlist"), "directory_scan.allowlist", identifier))
        violations = [str(path.relative_to(repo_root)) for path in source_files(directory, pattern) if str(path.relative_to(repo_root)) not in allowlist and re.search(regex, path.read_text(encoding="utf-8"), flags=re.DOTALL)]
        if violations:
            errors.append(f"{identifier}: directory scan found forbidden matches: {', '.join(violations)}")
    return errors


def validate_rule(repo_root: Path, identifier: str, source: str, rule: Any, label: str = "target") -> list[str]:
    errors = validate_rule_keys(identifier, rule, f"{label} rule")
    if errors:
        return errors
    assert isinstance(rule, dict)
    errors.extend(validate_fragments(identifier, source, rule, label))
    errors.extend(validate_counts(identifier, source, rule.get("count"), "count"))
    errors.extend(validate_counts(identifier, source, rule.get("occurrences"), "occurrences"))
    for index, spec in enumerate(rule.get("sections", [])):
        if not isinstance(spec, dict):
            raise ValueError(f"{identifier}: sections entries must be objects")
        section, section_errors = section_slice(source, spec, identifier)
        errors.extend(section_errors)
        if not section_errors:
            section_rule = {
                key: value for key, value in spec.items() if key not in SECTION_METADATA_KEYS
            }
            if section_rule:
                errors.extend(validate_rule(repo_root, identifier, section, section_rule, f"section[{index}]"))
    for index, spec in enumerate(rule.get("scoped", [])):
        scoped_key_errors = validate_scoped_wrapper_keys(identifier, spec, index)
        if scoped_key_errors:
            errors.extend(scoped_key_errors)
            continue
        assert isinstance(spec, dict)
        if not isinstance(spec.get("start"), str) or not isinstance(spec.get("end"), str):
            raise ValueError(f"{identifier}: scoped entries require string start and end markers")
        start = source.find(spec["start"])
        end = source.find(spec["end"], start + len(spec["start"])) if start >= 0 else -1
        if start < 0 or end < 0:
            errors.append(f"{identifier}: scoped markers must both exist: {spec['start']!r}, {spec['end']!r}")
        else:
            errors.extend(validate_rule(repo_root, identifier, source[start:end], spec.get("rule"), "scoped"))
    for index, spec in enumerate(rule.get("function_scoped", [])):
        function_scoped_key_errors = validate_function_scoped_wrapper_keys(identifier, spec, index)
        if function_scoped_key_errors:
            errors.extend(function_scoped_key_errors)
            continue
        assert isinstance(spec, dict)
        marker = spec.get("after")
        if not isinstance(marker, str) or not marker:
            raise ValueError(f"{identifier}: function_scoped entries require a non-empty after marker")
        marker_start = source.find(marker)
        opening_brace = source.find("{", marker_start + len(marker)) if marker_start >= 0 else -1
        if opening_brace < 0:
            errors.append(f"{identifier}: function scope marker must precede an opening brace: {marker!r}")
            continue
        depth = 0
        closing_brace = -1
        for position in range(opening_brace, len(source)):
            if source[position] == "{":
                depth += 1
            elif source[position] == "}":
                depth -= 1
                if depth == 0:
                    closing_brace = position
                    break
        if closing_brace < 0:
            errors.append(f"{identifier}: function scope marker has no balanced closing brace: {marker!r}")
            continue
        errors.extend(
            validate_rule(repo_root, identifier, source[opening_brace:closing_brace], spec.get("rule"), "function_scoped")
        )
    errors.extend(validate_directory_count(repo_root, identifier, rule.get("directory_count")))
    errors.extend(validate_directory_scan(repo_root, identifier, rule.get("directory_scan")))
    return errors


def validate_entry(repo_root: Path, entry: Any) -> list[str]:
    if not isinstance(entry, dict):
        return ["<missing id>: entry must be an object"]
    identifier = entry.get("id", "<missing id>")
    missing = [key for key in REQUIRED_METADATA if not isinstance(entry.get(key), str) or not entry[key]]
    if missing:
        return [f"{identifier}: missing required metadata: {', '.join(missing)}"]
    target = repo_root / entry["target"]
    if not target.is_file():
        return [f"{identifier}: missing regular target source: {entry['target']}"]
    try:
        return validate_rule(repo_root, identifier, target.read_text(encoding="utf-8"), entry.get("rule"))
    except ValueError as error:
        return [str(error)]


def validate_checkout_reads(repo_root: Path, manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for entry in manifest["entries"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("testSource"), str):
            continue
        test_source = entry["testSource"].split(":", 1)[0]
        if not test_source.startswith(str(COHORT_TEST_DIRECTORY)):
            continue
        path = repo_root / test_source
        if path.is_file():
            source = path.read_text(encoding="utf-8")
            for pattern in CHECKOUT_READ_PATTERNS:
                if pattern in source:
                    errors.append(f"{test_source}: runtime checkout read remains ({pattern})")
    return sorted(set(errors))


def validate(repo_root: Path, manifest_path: Path, quiet: bool = False) -> int:
    try:
        manifest = load_manifest(manifest_path)
    except ValueError as error:
        if not quiet:
            print(f"source-policy validation failed: {error}", file=sys.stderr)
        return 2
    errors = [error for entry in manifest["entries"] for error in validate_entry(repo_root, entry)]
    errors.extend(validate_checkout_reads(repo_root, manifest))
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
        (root / "Sources" / "App.swift").write_text("let safe = true\nfunc save() {\n dismiss()\n await onSave()\n}\nlet token = 42\n", encoding="utf-8")
        (root / "Sources" / "Other.swift").write_text("rowAccessibility()\n", encoding="utf-8")
        manifest = {"schemaVersion": 1, "entries": [{"id": "self-test", "testSource": "Tests/SelfTest.swift:testInvariant", "target": "Sources/App.swift", "invariant": "Safe source contract remains true.", "replacement": "checkout-hosted validator", "executableCoverage": "not applicable: static source policy", "rule": {"contains": ["let safe = true"], "not_contains": ["unsafe = true"], "ordered": [["dismiss()", "await onSave()"]], "regex_not_contains": [r"token\s*=\s*0"], "sections": [{"start": "func save()", "contains": ["dismiss()"], "not_contains": ["unsafe"]}], "scoped": [{"start": "func save()", "end": "await onSave()", "rule": {"contains": ["dismiss()"]}}], "directory_count": [{"directory": "Sources", "pattern": "*.swift", "contains": "rowAccessibility()", "min": 1}], "directory_scan": [{"directory": "Sources", "pattern": "*.swift", "not_matches_regex": r"NavigationLink\s*\{\s*Text\s*\(", "allowlist": []}], "occurrences": [{"contains": "let", "min": 2}]}}]}
        manifest_path = root / "docs" / "testing" / "xctest-source-policy-manifest.json"
        manifest_path.parent.mkdir(parents=True)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        if validate(root, manifest_path) != 0:
            return 1
        typo_manifest = json.loads(json.dumps(manifest))
        typo_manifest["entries"][0]["rule"]["contians"] = ["let safe = true"]
        (root / "typo-manifest.json").write_text(json.dumps(typo_manifest), encoding="utf-8")
        typo_errors = io.StringIO()
        with contextlib.redirect_stderr(typo_errors):
            typo_status = validate(root, root / "typo-manifest.json")
        if typo_status != 1 or "unsupported key(s): contians" not in typo_errors.getvalue():
            print("self-test did not reject the misspelled rule key with an actionable error", file=sys.stderr)
            return 1
        nested_typo_manifest = json.loads(json.dumps(manifest))
        nested_typo_manifest["entries"][0]["rule"]["sections"][0]["contians"] = ["dismiss()"]
        (root / "nested-typo-manifest.json").write_text(json.dumps(nested_typo_manifest), encoding="utf-8")
        nested_typo_errors = io.StringIO()
        with contextlib.redirect_stderr(nested_typo_errors):
            nested_typo_status = validate(root, root / "nested-typo-manifest.json")
        nested_diagnostic = nested_typo_errors.getvalue()
        if (
            nested_typo_status != 1
            or "section[0] rule contains unsupported key(s): contians" not in nested_diagnostic
            or "supported keys:" not in nested_diagnostic
        ):
            print("self-test did not reject the nested misspelled rule key with an actionable error", file=sys.stderr)
            return 1
        scoped_wrapper_typo_manifest = json.loads(json.dumps(manifest))
        scoped_wrapper_typo_manifest["entries"][0]["rule"]["scoped"] = [{
            "start": "missing scoped start",
            "end": "missing scoped end",
            "rule": {"contains": ["dismiss()"]},
            "contians": ["dismiss()"],
        }]
        (root / "scoped-wrapper-typo-manifest.json").write_text(
            json.dumps(scoped_wrapper_typo_manifest), encoding="utf-8"
        )
        scoped_wrapper_typo_errors = io.StringIO()
        with contextlib.redirect_stderr(scoped_wrapper_typo_errors):
            scoped_wrapper_typo_status = validate(root, root / "scoped-wrapper-typo-manifest.json")
        scoped_wrapper_diagnostic = scoped_wrapper_typo_errors.getvalue()
        if (
            scoped_wrapper_typo_status != 1
            or "self-test: scoped[0] contains unsupported key(s): contians" not in scoped_wrapper_diagnostic
            or "supported keys: end, rule, start" not in scoped_wrapper_diagnostic
            or "scoped markers must both exist" in scoped_wrapper_diagnostic
        ):
            print("self-test did not reject the scoped-wrapper misspelled key with an actionable error", file=sys.stderr)
            return 1
        outside_checkout = root / "outside-checkout"
        outside_checkout.mkdir()
        external = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--repo-root", str(root)], cwd=outside_checkout, capture_output=True, text=True, check=False)
        if external.returncode != 0:
            print(f"self-test default manifest lookup failed outside checkout: {external.stderr}", file=sys.stderr)
            return 1
        (root / "Sources" / "App.swift").write_text("let unsafe = true\n", encoding="utf-8")
        if validate(root, manifest_path, quiet=True) != 1:
            print("self-test did not produce the expected intentional violation", file=sys.stderr)
            return 1
    print("XCTest source-policy validator self-test passed (intentional violation, unknown-key rejection, and external-CWD default-manifest lookup).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate checkout-hosted XCTest source-policy invariants.")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    repo_root = args.repo_root.resolve()
    manifest_path = args.manifest if args.manifest is not None else repo_root / "docs/testing/xctest-source-policy-manifest.json"
    return validate(repo_root, manifest_path)


if __name__ == "__main__":
    raise SystemExit(main())
