#!/usr/bin/env python3
"""Fail when the artifact-guard workflow can run fork code on a private runner."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/artifact-guard.yml"

FORK_RUNNER = '["ubuntu-latest"]'
TRUSTED_RUNNER = '["self-hosted","macOS","ARM64","xcode","ios","local-mac"]'
FORK_CONDITION = (
    "github.event_name == 'pull_request' && "
    "github.event.pull_request.head.repo.full_name != github.repository"
)
TRUSTED_CONDITION = (
    "github.event_name != 'pull_request' || "
    "github.event.pull_request.head.repo.full_name == github.repository"
)


def validate(workflow: str) -> list[str]:
    """Return fail-closed policy violations for the workflow source."""
    required_fragments = {
        "fork jobs route to GitHub-hosted infrastructure": FORK_RUNNER,
        "same-repository jobs retain the labeled Mac runner": TRUSTED_RUNNER,
        "fork path is explicitly rejected": "Reject untrusted fork without using the Mac runner",
        "fork rejection condition is present": FORK_CONDITION,
        "fork rejection exits nonzero": "exit 1",
        "checkout is limited to trusted PRs and pushes": f"if: {TRUSTED_CONDITION}\n        uses: actions/checkout@v4",
        "source policy validation is limited to trusted PRs and pushes": (
            f"if: {TRUSTED_CONDITION}\n"
            "        run: python3 scripts/ci/validate-artifact-guard-source.py"
        ),
        "artifact guard self-test is limited to trusted PRs and pushes": (
            f"if: {TRUSTED_CONDITION}\n"
            "        run: python3 scripts/guard-tracked-artifacts.py --self-test"
        ),
        "artifact guard execution is limited to trusted PRs and pushes": (
            f"if: {TRUSTED_CONDITION}\n"
            "        run: python3 scripts/guard-tracked-artifacts.py"
        ),
    }
    errors = [
        f"workflow invariant missing: {description} ({fragment!r})"
        for description, fragment in required_fragments.items()
        if fragment not in workflow
    ]

    if "runs-on: [self-hosted, macOS, ARM64, xcode, ios, local-mac]" in workflow:
        errors.append("workflow has an unconditional self-hosted runner assignment")
    if "uses: actions/checkout@v4\n" in workflow and "if: " not in workflow.split(
        "uses: actions/checkout@v4", maxsplit=1
    )[0].rsplit("- name:", maxsplit=1)[-1]:
        errors.append("checkout can run without a trusted-source condition")

    return errors


def run_self_test() -> int:
    unsafe_workflow = """jobs:
  tracked-artifacts:
    runs-on: [self-hosted, macOS, ARM64, xcode, ios, local-mac]
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      - run: python3 scripts/guard-tracked-artifacts.py
"""
    errors = validate(unsafe_workflow)
    if not errors:
        print("artifact-guard source validator self-test failed: unsafe fixture passed", file=sys.stderr)
        return 1

    print(f"artifact-guard source validator self-test passed ({len(errors)} unsafe-policy violations detected).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="Verify that an unsafe workflow fixture is rejected.")
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
