#!/usr/bin/env python3
"""Fail when the artifact-guard workflow can run fork code on a private runner."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/artifact-guard.yml"

FORK_CONDITION = (
    "github.event_name == 'pull_request' && "
    "github.event.pull_request.head.repo.full_name != github.repository"
)
TRUSTED_CONDITION = (
    "github.event_name != 'pull_request' || "
    "github.event.pull_request.head.repo.full_name == github.repository"
)
DYNAMIC_RUNNER = (
    "${{ fromJSON(github.event_name == 'pull_request' && "
    "github.event.pull_request.head.repo.full_name != github.repository && "
    "'[\"ubuntu-latest\"]' || "
    "'[\"self-hosted\",\"macOS\",\"ARM64\",\"xcode\",\"ios\",\"local-mac\"]') }}"
)
STEP_START = re.compile(r"^      -(?:\s|$)")
FIELD = re.compile(r"^        (?P<name>if|uses|run):\s*(?P<value>.*)$")


def _steps(workflow: str) -> list[dict[str, str]]:
    """Extract each workflow step's security-relevant fields without YAML coercion."""
    steps: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in workflow.splitlines():
        if STEP_START.match(line):
            current = {}
            steps.append(current)
            continue
        if current is None:
            continue
        match = FIELD.match(line)
        if match:
            current[match.group("name")] = match.group("value").strip()
        elif current.get("run", "").startswith("|") and line.startswith("          "):
            current["run"] += f"\n{line.strip()}"
    return steps


def validate(workflow: str) -> list[str]:
    """Return fail-closed policy violations for the workflow source."""
    errors: list[str] = []
    lines = workflow.splitlines()

    # The runner expression is security-critical: its fork branch must select only
    # GitHub-hosted infrastructure, while the other branch is the trusted Mac.
    runner_lines = [line.strip() for line in lines if line.startswith("    runs-on:")]
    if runner_lines != [f"runs-on: {DYNAMIC_RUNNER}"]:
        errors.append(
            "dynamic runner must exactly route forks to ubuntu-latest and trusted sources to the labeled Mac"
        )
    if any("runs-on: [self-hosted, macOS, ARM64, xcode, ios, local-mac]" in line for line in lines):
        errors.append("workflow has an unconditional self-hosted runner assignment")

    steps = _steps(workflow)
    reject_steps = [
        step
        for step in steps
        if step.get("if") == FORK_CONDITION and "exit 1" in step.get("run", "")
    ]
    if not reject_steps:
        errors.append("fork rejection must be a fork-conditioned nonzero-exit run step")

    checkout_steps = [step for step in steps if step.get("uses") == "actions/checkout@v4"]
    if not checkout_steps:
        errors.append("workflow must have a trusted checkout step")
    for step in checkout_steps:
        if step.get("if") != TRUSTED_CONDITION:
            errors.append("checkout can run without the exact trusted-source condition")

    # A run step executes repository-controlled content after checkout; require the
    # trusted source guard on every normal run, not merely on the first such step.
    for step in steps:
        run = step.get("run")
        if not run or step in reject_steps:
            continue
        if step.get("if") != TRUSTED_CONDITION:
            errors.append(f"repository-code step is not bound to the trusted-source condition: {run!r}")

    return errors


def run_self_test() -> int:
    trusted_steps = f"""      - name: Checkout repository
        if: {TRUSTED_CONDITION}
        uses: actions/checkout@v4
      - name: Validate source policy
        if: {TRUSTED_CONDITION}
        run: python3 scripts/ci/validate-artifact-guard-source.py
      - name: Run artifact guard
        if: {TRUSTED_CONDITION}
        run: python3 scripts/guard-tracked-artifacts.py
"""
    unsafe_dynamic_fork_runner = f"""jobs:
  tracked-artifacts:
    runs-on: ${{{{ fromJSON(github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository && '[\"self-hosted\",\"macOS\",\"ARM64\",\"xcode\",\"ios\",\"local-mac\"]' || '[\"self-hosted\",\"macOS\",\"ARM64\",\"xcode\",\"ios\",\"local-mac\"]') }}}}
    steps:
      - name: Reject untrusted fork without using the Mac runner
        if: {FORK_CONDITION}
        run: exit 1
{trusted_steps}"""
    unsafe_always_checkout = f"""jobs:
  tracked-artifacts:
    runs-on: {DYNAMIC_RUNNER}
    steps:
      - name: Reject untrusted fork without using the Mac runner
        if: {FORK_CONDITION}
        run: exit 1
      - name: Checkout repository after fork rejection
        if: always()
        uses: actions/checkout@v4
      - name: Run artifact guard
        if: {TRUSTED_CONDITION}
        run: python3 scripts/guard-tracked-artifacts.py
"""
    fixtures = {
        "dynamic fork-to-self-hosted-Mac runner": unsafe_dynamic_fork_runner,
        "later always() checkout": unsafe_always_checkout,
    }
    failures = [name for name, fixture in fixtures.items() if not validate(fixture)]
    if failures:
        print("artifact-guard source validator self-test failed: unsafe fixtures passed", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    violations = sum(len(validate(fixture)) for fixture in fixtures.values())
    print(
        f"artifact-guard source validator self-test passed "
        f"({len(fixtures)} unsafe fixtures, {violations} violations detected)."
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="Verify that unsafe workflow fixtures are rejected.")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    errors = validate(WORKFLOW.read_text(encoding="utf-8"))
    if errors:
        print("Artifact-guard source validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Artifact-guard source validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
