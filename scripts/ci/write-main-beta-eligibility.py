#!/usr/bin/env python3
"""Write fail-closed WPR2 main-beta lane and aggregate eligibility records.

This is intentionally local-only: it reads descriptor/metadata files and performs no
network or credential access. An ineligible record is always written before failure.
"""
from __future__ import annotations

import argparse
import json
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def fail_record(reason: str, **extra: Any) -> dict[str, Any]:
    return {"schemaVersion": 1, "eligible": False, "reason": reason, **extra}


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep or not key:
            raise ValueError(f"invalid descriptor line: {raw!r}")
        values[key] = value.replace("\\ ", " ")
    return values


def read_metadata(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, sep, value = line.partition("=")
        if sep:
            values[key] = value
    return values


def write(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def lane(args: argparse.Namespace) -> int:
    descriptor = read_env(Path(args.descriptor))
    expected = args.expected_sha.lower()
    record: dict[str, Any]
    try:
        if not SHA_RE.fullmatch(expected):
            raise ValueError("expected SHA is not a 40-character lowercase hex commit")
        metadata_path = Path(args.metadata)
        if not metadata_path.is_file():
            raise ValueError("lane metadata is missing")
        meta = read_metadata(metadata_path)
        required = [
            "expected_sha", "actual_sha", "xcode_version", "xcode_build",
            "unit-regression_result", "unit-regression_total_tests",
            "unit-regression_failed_tests", "unit-regression_skipped_tests",
            "ui-smokes_result", "ui-smokes_total_tests",
            "ui-smokes_failed_tests", "ui-smokes_skipped_tests",
        ]
        missing = [key for key in required if not meta.get(key)]
        if missing:
            raise ValueError("lane metadata missing: " + ", ".join(missing))
        if meta["expected_sha"] != expected or meta["actual_sha"] != expected:
            raise ValueError("lane SHA does not match expected SHA")
        if meta["xcode_version"] != descriptor["WPR2_XCODE_VERSION"] or meta["xcode_build"] != descriptor["WPR2_XCODE_BUILD"]:
            raise ValueError("lane Xcode version/build does not match descriptor")
        phases: dict[str, dict[str, int | str]] = {}
        for phase in ("unit-regression", "ui-smokes"):
            result = meta[f"{phase}_result"]
            total = int(meta[f"{phase}_total_tests"])
            failed = int(meta[f"{phase}_failed_tests"])
            skipped = int(meta[f"{phase}_skipped_tests"])
            if result != "Passed" or total <= 0 or failed != 0 or skipped != 0:
                raise ValueError(f"{phase} result is not a nonzero zero-failure zero-skip pass")
            phases[phase] = {"result": result, "total": total, "failed": failed, "skipped": skipped}
        record = {
            "schemaVersion": 1, "eligible": True, "reason": "all lane assertions passed",
            "deviceClass": args.device_class, "commitSha": expected,
            "selectedToolchain": {"version": meta["xcode_version"], "build": meta["xcode_build"]},
            "runtime": meta.get("runtime", ""), "deviceType": meta.get("device_type", ""),
            "phases": phases,
        }
    except (OSError, ValueError, KeyError) as exc:
        record = fail_record(str(exc), deviceClass=args.device_class, commitSha=expected)
    write(Path(args.output), record)
    return 0 if record["eligible"] else 1


def aggregate(args: argparse.Namespace) -> int:
    descriptor = read_env(Path(args.descriptor))
    expected = args.expected_sha.lower()
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    record: dict[str, Any]
    try:
        if not SHA_RE.fullmatch(expected):
            raise ValueError("expected SHA is not a 40-character lowercase hex commit")
        lanes = {"iphone": json.loads(Path(args.iphone).read_text(encoding="utf-8")), "ipad": json.loads(Path(args.ipad).read_text(encoding="utf-8"))}
        for name, value in lanes.items():
            if value.get("eligible") is not True:
                raise ValueError(f"{name} lane is missing or ineligible: {value.get('reason', 'unknown reason')}")
            if value.get("commitSha") != expected:
                raise ValueError(f"{name} lane SHA does not match expected SHA")
            toolchain = value.get("selectedToolchain", {})
            if toolchain.get("version") != descriptor["WPR2_XCODE_VERSION"] or toolchain.get("build") != descriptor["WPR2_XCODE_BUILD"]:
                raise ValueError(f"{name} lane toolchain does not match descriptor")
        record = {
            "schemaVersion": 1, "eligible": True, "reason": "both exact-SHA device lanes passed",
            "repository": args.repository, "commitSha": expected, "ref": args.ref,
            "workflowRunId": args.workflow_run_id, "workflowAttempt": args.workflow_attempt,
            "createdAt": now,
            "selectedToolchain": {"version": descriptor["WPR2_XCODE_VERSION"], "build": descriptor["WPR2_XCODE_BUILD"]},
            "lanes": lanes,
        }
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        record = fail_record(str(exc), repository=args.repository, commitSha=expected, ref=args.ref,
                             workflowRunId=args.workflow_run_id, workflowAttempt=args.workflow_attempt,
                             createdAt=now)
    write(Path(args.output), record)
    return 0 if record["eligible"] else 1


def self_test() -> int:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        descriptor = root / "toolchain.env"
        descriptor.write_text("WPR2_XCODE_VERSION=26.3\nWPR2_XCODE_BUILD=17C529\n", encoding="utf-8")
        metadata = root / "metadata.txt"
        metadata.write_text("\n".join([
            "expected_sha=" + "a" * 40, "actual_sha=" + "a" * 40,
            "xcode_version=26.3", "xcode_build=17C529", "runtime=iOS-26-5", "device_type=phone",
            "unit-regression_result=Passed", "unit-regression_total_tests=1", "unit-regression_failed_tests=0", "unit-regression_skipped_tests=0",
            "ui-smokes_result=Passed", "ui-smokes_total_tests=1", "ui-smokes_failed_tests=0", "ui-smokes_skipped_tests=0",
        ]) + "\n", encoding="utf-8")
        output = root / "lane.json"
        assert lane(argparse.Namespace(descriptor=str(descriptor), expected_sha="a" * 40, metadata=str(metadata), output=str(output), device_class="iphone")) == 0
        assert json.loads(output.read_text())["eligible"] is True
        ipad_output = root / "ipad.json"
        assert lane(argparse.Namespace(descriptor=str(descriptor), expected_sha="a" * 40, metadata=str(metadata), output=str(ipad_output), device_class="ipad")) == 0
        aggregate_output = root / "aggregate.json"
        aggregate_args = argparse.Namespace(
            descriptor=str(descriptor), expected_sha="a" * 40, iphone=str(output), ipad=str(ipad_output),
            output=str(aggregate_output), repository="owner/repo", ref="refs/heads/main",
            workflow_run_id="1", workflow_attempt="1",
        )
        assert aggregate(aggregate_args) == 0
        assert json.loads(aggregate_output.read_text())["eligible"] is True
        metadata.write_text("expected_sha=" + "a" * 40 + "\n", encoding="utf-8")
        assert lane(argparse.Namespace(descriptor=str(descriptor), expected_sha="a" * 40, metadata=str(metadata), output=str(output), device_class="iphone")) == 1
        assert json.loads(output.read_text())["eligible"] is False
        assert aggregate(aggregate_args) == 1
        assert json.loads(aggregate_output.read_text())["eligible"] is False
    print("main-beta eligibility self-test passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    lane_parser = sub.add_parser("lane")
    lane_parser.add_argument("--descriptor", required=True)
    lane_parser.add_argument("--expected-sha", required=True)
    lane_parser.add_argument("--metadata", required=True)
    lane_parser.add_argument("--output", required=True)
    lane_parser.add_argument("--device-class", required=True, choices=("iphone", "ipad"))
    aggregate_parser = sub.add_parser("aggregate")
    for option in ("descriptor", "expected-sha", "iphone", "ipad", "output", "repository", "ref", "workflow-run-id", "workflow-attempt"):
        aggregate_parser.add_argument(f"--{option}", required=True)
    sub.add_parser("self-test")
    args = parser.parse_args()
    if args.command == "lane": return lane(args)
    if args.command == "aggregate": return aggregate(args)
    return self_test()


if __name__ == "__main__":
    raise SystemExit(main())
