#!/usr/bin/env python3
"""Fail when WPR2 PR or exact-main beta-gate source weakens fail-closed invariants."""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
PR_WORKFLOW = ROOT / ".github/workflows/ios-beta-gate.yml"
MAIN_WORKFLOW = ROOT / ".github/workflows/ios-main-beta-gate.yml"
RUNNER = ROOT / "scripts/ci/run-ios-beta-gate.sh"
VERIFIER = ROOT / "scripts/ci/verify-wpr2-xcode-toolchain.sh"
ELIGIBILITY = ROOT / "scripts/ci/write-main-beta-eligibility.py"
DESCRIPTOR = ROOT / ".github/wpr2-main-build/toolchain.env"

pr_workflow = PR_WORKFLOW.read_text(encoding="utf-8")
main_workflow = MAIN_WORKFLOW.read_text(encoding="utf-8")
runner = RUNNER.read_text(encoding="utf-8")
verifier = VERIFIER.read_text(encoding="utf-8")
eligibility = ELIGIBILITY.read_text(encoding="utf-8")
descriptor = DESCRIPTOR.read_text(encoding="utf-8")

required_pr_fragments = {
    "fork jobs route to a GitHub-hosted runner": '["ubuntu-latest"]',
    "trusted jobs route to labeled Mac runners": '["self-hosted","macOS","ARM64","xcode","ios","local-mac"]',
    "fork path is explicitly rejected": "Reject untrusted fork without using the Mac runner",
    "fork rejection exits nonzero": "exit 1",
    "exact PR head is checked out": "ref: ${{ github.event.pull_request.head.sha }}",
    "iPhone required context remains stable": "- name: iPhone",
    "iPad required context remains stable": "- name: iPad",
    "job timeout is declared": "timeout-minutes: 120",
    "toolchain is verified before Xcode tests": "Verify exact Xcode 26.3 toolchain before simulator work",
    "script receives the job timeout": 'JOB_TIMEOUT_SECONDS: "7200"',
    "UI-smoke phase retains its bounded timeout": 'UI_SMOKE_PHASE_TIMEOUT_SECONDS: "1200"',
    "cleanup and upload margin is reserved": 'CLEANUP_UPLOAD_MARGIN_SECONDS: "1080"',
}

required_main_fragments = {
    "main push trigger is present": 'push:\n    branches: ["main"]',
    "recovery dispatch has a SHA input": "commit_sha:",
    "main workflow has read-only contents permission": "permissions:\n  contents: read",
    "main workflow keeps per-SHA evidence": "cancel-in-progress: false",
    "push uses github.sha only in push mode": "PUSH_SHA: ${{ github.sha }}",
    "dispatch validates 40 hexadecimal characters": "grep -Eq '^[0-9a-f]{40}$'",
    "dispatch verifies origin/main reachability": "git merge-base --is-ancestor",
    "exact validated SHA is checked out": "ref: ${{ needs.resolve-sha.outputs.expected_sha }}",
    "checkout credentials are disabled": "persist-credentials: false",
    "main iPhone check name is distinct": "Main Beta Gate (${{ matrix.name }})",
    "main toolchain verification occurs before tests": "Verify exact Xcode 26.3 toolchain before simulator work",
    "both lanes write fail-closed metadata": "Write fail-closed lane eligibility metadata",
    "aggregate record runs after all outcomes": "if: always()",
    "aggregate binds to both lane records": "--iphone lane-artifacts/iphone/main-beta-lane.json",
    "aggregate record is uploaded": "Upload eligibility record",
}

required_runner_fragments = {
    "shared descriptor is loaded": '. "$toolchain_contract"',
    "toolchain verification is required before normal execution": '"${WPR2_TOOLCHAIN_VERIFIED:-}" == "1"',
    "expected and actual SHAs are compared": '[[ "$actual_sha" == "$expected_sha" ]]',
    "selected Xcode is rechecked": '"$xcode_version" == "$WPR2_XCODE_VERSION"',
    "workspace schemes are listed before simulator work": 'xcodebuild -list -workspace "$workspace/$WPR2_WORKSPACE"',
    "internal timeout budget is calculated": "internal_budget_seconds=$((",
    "job cleanup/upload margin is enforced": "available_internal_budget_seconds=$((job_timeout_seconds - cleanup_upload_margin_seconds))",
    "zero tests fail closed": "(( total > 0 )) || phase_failure=1",
    "disk cleanup deletes only stale DerivedData entries": '-mmin "+${derived_data_stale_minutes}"',
    "disk cleanup stays at the top level of the DerivedData cache": "-mindepth 1 -maxdepth 1",
    "disk budget still fails closed after cleanup": '(( available_kib >= required_kib )) || fail "runner has ${available_gib} GiB free; ${minimum_free_gib} GiB is required"',
    "skipped tests fail closed": "(( skipped == 0 )) || phase_failure=1",
    "CoreLocation recovery remains bounded": "simulator_boot_recovery_timeout_seconds",
    "recovery is limited to CoreLocation migration": "CoreLocationMigrator.migrator",
    "recovery is limited to bounded bootstatus timeout": '[[ "$boot_status" == "142" ]]',
    "UI-smoke retry is limited to bootstrap termination": "should_retry_ui_smoke_bootstrap_failure",
    "UI-smoke retry requires Xcode status 65": '[[ "$xcode_status" == "65" ]]',
    "UI-smoke retry preserves first-attempt evidence": "preserve_failed_ui_smoke_attempt",
    "UI-smoke retry remains one bounded pass": "ui_smoke_bootstrap_retry=1",
    "UI-smoke retry uses its separate bounded timeout": "ui_smoke_phase_timeout_seconds",
    "corrupt-bundle retry detects only the half-written state": '[[ ! -f "$result_bundle/Info.plist" ]]',
    "corrupt-bundle retry keeps a missing bundle a hard fail": '[[ -d "$result_bundle" ]] || return 1',
    "corrupt-bundle retry preserves first-attempt evidence": "preserve_corrupt_phase_attempt",
    "corrupt-bundle retry remains one bounded pass per phase": "corrupt_bundle_retry=1",
}

required_verifier_fragments = {
    "descriptor supplies exact version": "WPR2_XCODE_VERSION",
    "descriptor supplies exact build": "WPR2_XCODE_BUILD",
    "verifier exports only declared developer directory": 'export DEVELOPER_DIR="$WPR2_XCODE_DEVELOPER_DIR"',
    "verifier compares exact Xcode version": '[[ "$actual_version" == "$expected_version" ]]',
    "verifier compares exact Xcode build": '[[ "$actual_build" == "$expected_build" ]]',
    "verifier never switches system xcode": "never modifies xcode-select",
}

required_descriptor_fragments = {
    "exact Xcode version": "WPR2_XCODE_VERSION=26.3",
    "exact Xcode build": "WPR2_XCODE_BUILD=17C529",
    "Xcode developer directory": "WPR2_XCODE_DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer",
    "iOS runtime": "IOS_RUNTIME_VERSION=26.5",
    "iPhone device type": "IPHONE_DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
    "iPad device type": "IPAD_DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Air-13-inch-M2",
    "minimum free disk": "MINIMUM_FREE_GIB=60",
}

errors: list[str] = []
for source_name, source, requirements in (
    ("PR workflow", pr_workflow, required_pr_fragments),
    ("main workflow", main_workflow, required_main_fragments),
    ("runner", runner, required_runner_fragments),
    ("toolchain verifier", verifier, required_verifier_fragments),
    ("toolchain descriptor", descriptor, required_descriptor_fragments),
):
    for description, fragment in requirements.items():
        if fragment not in source:
            errors.append(f"{source_name} invariant missing: {description} ({fragment!r})")

legacy_skip_guard = r"(?m)^ {4}if:\s*github\.event\.pull_request\.head\.repo\.full_name == github\.repository\s*$"
if re.search(legacy_skip_guard, pr_workflow):
    errors.append("PR workflow still has the job-level fork skip guard that can report a successful required context")

for prohibited in ("xcodebuild archive", "-exportArchive", "notarytool", "altool", "fastlane", "app-store-connect", "testflight"):
    for source_name, source in (("main workflow", main_workflow), ("runner", runner), ("toolchain verifier", verifier)):
        if prohibited.lower() in source.lower():
            errors.append(f"{source_name} contains prohibited release/upload path: {prohibited}")

if "requests" in eligibility or "urllib" in eligibility or "subprocess" in eligibility:
    errors.append("eligibility formatter must remain pure local parsing with no network/process execution")

if errors:
    print("iOS beta-gate source validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print("iOS beta-gate source validation passed")
