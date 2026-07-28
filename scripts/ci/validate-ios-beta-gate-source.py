#!/usr/bin/env python3
"""Fail when the iOS beta-gate source weakens required fail-closed invariants."""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/ios-beta-gate.yml"
RUNNER = ROOT / "scripts/ci/run-ios-beta-gate.sh"

workflow = WORKFLOW.read_text(encoding="utf-8")
runner = RUNNER.read_text(encoding="utf-8")

required_workflow_fragments = {
    "fork jobs route to a GitHub-hosted runner": '["ubuntu-latest"]',
    "trusted jobs route to the labeled Mac runners": '["self-hosted","macOS","ARM64","xcode","ios","local-mac"]',
    "fork path is explicitly rejected": "Reject untrusted fork without using the Mac runner",
    "fork rejection exits nonzero": "exit 1",
    "exact PR head is checked out": "ref: ${{ github.event.pull_request.head.sha }}",
    "iPhone required context remains stable": "- name: iPhone",
    "iPad required context remains stable": "- name: iPad",
    "job timeout is declared": "timeout-minutes: 120",
    "script receives the job timeout": 'JOB_TIMEOUT_SECONDS: "7200"',
    "cleanup and upload margin is reserved": 'CLEANUP_UPLOAD_MARGIN_SECONDS: "1080"',
}

required_runner_fragments = {
    "expected and actual SHAs are compared": '[[ "$actual_sha" == "$expected_sha" ]]',
    "internal timeout budget is calculated": "internal_budget_seconds=$((",
    "job cleanup/upload margin is enforced": "available_internal_budget_seconds=$((job_timeout_seconds - cleanup_upload_margin_seconds))",
    "zero tests fail closed": "(( total > 0 )) || phase_failure=1",
    "skipped tests fail closed": "(( skipped == 0 )) || phase_failure=1",
    "CoreLocation recovery remains bounded": "simulator_boot_recovery_timeout_seconds",
    "recovery is limited to CoreLocation migration": "CoreLocationMigrator.migrator",
    "recovery is limited to the bounded bootstatus timeout": '[[ "$boot_status" == "142" ]]',
    "UI-smoke retry is limited to the bootstrap termination fingerprint": "should_retry_ui_smoke_bootstrap_failure",
    "UI-smoke retry requires Xcode status 65": '[[ "$xcode_status" == "65" ]]',
    "UI-smoke retry preserves first-attempt evidence": "preserve_failed_ui_smoke_attempt",
    "UI-smoke retry rejects a missing first-attempt xcresult": '[[ -d "$ui_result" ]] || fail "first UI-smoke attempt produced no xcresult bundle; refusing bootstrap retry"',
    "UI-smoke retry rejects a missing first-attempt Xcode status": '[[ -f "$artifact_dir/ui-smokes-xcode-status.txt" ]] || fail "first UI-smoke attempt produced no Xcode status; refusing bootstrap retry"',
    "UI-smoke retry rejects a missing first-attempt tee status": '[[ -f "$artifact_dir/ui-smokes-tee-status.txt" ]] || fail "first UI-smoke attempt produced no tee status; refusing bootstrap retry"',
    "UI-smoke retry preserves the required first-attempt Xcode status": 'mv "$artifact_dir/ui-smokes-xcode-status.txt" "$artifact_dir/ui-smokes-attempt-1-xcode-status.txt" || fail "could not preserve first UI-smoke Xcode status"',
    "UI-smoke retry preserves the required first-attempt tee status": 'mv "$artifact_dir/ui-smokes-tee-status.txt" "$artifact_dir/ui-smokes-attempt-1-tee-status.txt" || fail "could not preserve first UI-smoke tee status"',
    "UI-smoke retry preserves the required first-attempt xcresult": 'mv "$ui_result" "$artifact_dir/ui-smokes-attempt-1-${gate_name}.xcresult" || fail "could not preserve first UI-smoke xcresult bundle"',
    "UI-smoke retry remains one bounded pass": "ui_smoke_bootstrap_retry=1",
    "UI-smoke retry uses its separate bounded timeout": "ui_smoke_phase_timeout_seconds",
}

errors: list[str] = []
for description, fragment in required_workflow_fragments.items():
    if fragment not in workflow:
        errors.append(f"workflow invariant missing: {description} ({fragment!r})")
for description, fragment in required_runner_fragments.items():
    if fragment not in runner:
        errors.append(f"runner invariant missing: {description} ({fragment!r})")

legacy_skip_guard = r"(?m)^ {4}if:\s*github\.event\.pull_request\.head\.repo\.full_name == github\.repository\s*$"
if re.search(legacy_skip_guard, workflow):
    errors.append("workflow still has the job-level fork skip guard that can report a successful required context")

if errors:
    print("iOS beta-gate source validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print("iOS beta-gate source validation passed")
