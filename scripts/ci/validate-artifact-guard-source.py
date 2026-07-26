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
NON_PLAIN_USES_PREFIXES = ("&", "*", "!", ">", "|")


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
        elif line.startswith("          "):
            for name in ("run", "uses"):
                if current.get(name, "").startswith(("|", ">")):
                    current[name] += f"\n{line.strip()}"
    return steps


def _strip_yaml_inline_comment(value: str) -> str:
    """Remove a YAML comment while preserving hashes inside quoted scalars."""
    quote: str | None = None
    escaped = False
    for index, character in enumerate(value):
        if quote == '"' and character == "\\" and not escaped:
            escaped = True
            continue
        if character == quote and not escaped:
            quote = None
        elif quote is None and character in {"'", '"'}:
            quote = character
        elif quote is None and character == "#" and (index == 0 or value[index - 1].isspace()):
            return value[:index].rstrip()
        escaped = False
    return value.rstrip()


def _yaml_scalar(value: str) -> str:
    """Extract a checkout candidate from a YAML scalar without trusting its syntax.

    This is deliberately not a general YAML parser.  The policy rejects aliases,
    anchors, tags, and block scalar syntax below, but still extracts their textual
    checkout target so every semantic ``actions/checkout@*`` candidate receives the
    trusted-source check before the unsupported syntax produces its fail-closed
    violation.
    """
    value = _strip_yaml_inline_comment(value.strip())
    if value.startswith((">", "|")):
        return " ".join(
            _strip_yaml_inline_comment(line.strip())
            for line in value.splitlines()[1:]
        ).strip()
    if value.startswith("&") or value.startswith("!"):
        parts = value.split(maxsplit=1)
        return _yaml_scalar(parts[1]) if len(parts) == 2 else ""
    if value.startswith("*"):
        return ""
    if len(value) < 2 or value[0] not in {"'", '"'}:
        return value
    if value[-1] != value[0]:
        return ""
    if value[0] == "'":
        return value[1:-1].replace("''", "'")
    return value[1:-1]


def _is_non_plain_uses_scalar(value: str) -> bool:
    """Reject YAML syntax that can hide a checkout action from this source guard.

    The workflow deliberately uses plain or quoted scalar action references.  This
    validator does not attempt a partial YAML implementation: anchors, aliases,
    tags, and block scalars are rejected so they cannot resolve to a later
    ``actions/checkout@*`` invocation outside the trusted-source condition.
    """
    return value.lstrip().startswith(NON_PLAIN_USES_PREFIXES)


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

    non_plain_uses = [
        step["uses"]
        for step in steps
        if "uses" in step and _is_non_plain_uses_scalar(step["uses"])
    ]
    if non_plain_uses:
        errors.append(
            "uses fields must use plain or quoted scalars; aliases, tags, anchors, "
            "and block scalars are not allowed"
        )

    # Pinning a checkout version is a supply-chain choice, not a trust boundary.
    # Guard every actions/checkout@* invocation so a later version bump cannot
    # bypass the trusted-source condition.
    checkout_steps = [
        step
        for step in steps
        if _yaml_scalar(step.get("uses", "")).startswith("actions/checkout@")
    ]
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
    unsafe_always_quoted_checkout = f"""jobs:
  tracked-artifacts:
    runs-on: {DYNAMIC_RUNNER}
    steps:
      - name: Reject untrusted fork without using the Mac runner
        if: {FORK_CONDITION}
        run: exit 1
      - name: Checkout repository
        if: {TRUSTED_CONDITION}
        uses: actions/checkout@v4
      - name: Checkout repository after fork rejection
        if: always()
        uses: "actions/checkout@v5"
      - name: Run artifact guard
        if: {TRUSTED_CONDITION}
        run: python3 scripts/guard-tracked-artifacts.py
"""
    unsafe_always_single_quoted_checkout = unsafe_always_quoted_checkout.replace(
        'uses: "actions/checkout@v5"', "uses: 'actions/checkout@v5'"
    )
    unsafe_always_quoted_inline_comment_checkout = unsafe_always_quoted_checkout.replace(
        'uses: "actions/checkout@v5"', 'uses: "actions/checkout@v5" # semantic checkout action'
    )
    unsafe_always_anchor_checkout = unsafe_always_quoted_checkout.replace(
        'uses: "actions/checkout@v5"', "uses: &checkout_v5 actions/checkout@v5"
    )
    unsafe_always_tagged_checkout = unsafe_always_quoted_checkout.replace(
        'uses: "actions/checkout@v5"', "uses: !!str actions/checkout@v5"
    )
    unsafe_always_folded_checkout = unsafe_always_quoted_checkout.replace(
        'uses: "actions/checkout@v5"', "uses: >-\n          actions/checkout@v5"
    )
    unsafe_always_literal_checkout = unsafe_always_quoted_checkout.replace(
        'uses: "actions/checkout@v5"', "uses: |-\n          actions/checkout@v5"
    )
    unsafe_always_aliased_checkout = unsafe_always_quoted_checkout.replace(
        "- name: Checkout repository after fork rejection\n        if: always()\n        uses: \"actions/checkout@v5\"",
        "- name: &checkout_v5 actions/checkout@v5\n        if: always()\n        uses: *checkout_v5",
    )
    unsafe_unguarded_repository_code = f"""jobs:
  tracked-artifacts:
    runs-on: {DYNAMIC_RUNNER}
    steps:
      - name: Reject untrusted fork without using the Mac runner
        if: {FORK_CONDITION}
        run: exit 1
      - name: Checkout repository
        if: {TRUSTED_CONDITION}
        uses: actions/checkout@v4
      - name: Run repository-controlled command without source guard
        run: python3 scripts/guard-tracked-artifacts.py
"""
    valid_quoted_checkouts = {
        "double-quoted trusted checkout": trusted_steps.replace(
            "uses: actions/checkout@v4", 'uses: "actions/checkout@v4"'
        ),
        "single-quoted trusted checkout": trusted_steps.replace(
            "uses: actions/checkout@v4", "uses: 'actions/checkout@v4'"
        ),
        "double-quoted trusted checkout with inline comment": trusted_steps.replace(
            "uses: actions/checkout@v4", 'uses: "actions/checkout@v4" # trusted action'
        ),
    }
    fixtures = {
        "dynamic fork-to-self-hosted-Mac runner": unsafe_dynamic_fork_runner,
        "later always() double-quoted actions/checkout@v5 after trusted checkout": unsafe_always_quoted_checkout,
        "later always() single-quoted actions/checkout@v5 after trusted checkout": unsafe_always_single_quoted_checkout,
        "later always() quoted actions/checkout@v5 with inline comment after trusted checkout": unsafe_always_quoted_inline_comment_checkout,
        "later always() anchored actions/checkout@v5 after trusted checkout": unsafe_always_anchor_checkout,
        "later always() explicitly tagged actions/checkout@v5 after trusted checkout": unsafe_always_tagged_checkout,
        "later always() folded actions/checkout@v5 after trusted checkout": unsafe_always_folded_checkout,
        "later always() literal actions/checkout@v5 after trusted checkout": unsafe_always_literal_checkout,
        "later always() aliased actions/checkout@v5 after trusted checkout": unsafe_always_aliased_checkout,
        "unguarded repository-code step": unsafe_unguarded_repository_code,
    }
    valid_failures = {
        name: validate(
            f"""jobs:
  tracked-artifacts:
    runs-on: {DYNAMIC_RUNNER}
    steps:
      - name: Reject untrusted fork without using the Mac runner
        if: {FORK_CONDITION}
        run: exit 1
{steps}"""
        )
        for name, steps in valid_quoted_checkouts.items()
    }
    valid_failures = {name: errors for name, errors in valid_failures.items() if errors}
    if valid_failures:
        print("artifact-guard source validator self-test failed: valid quoted checkout rejected", file=sys.stderr)
        for name, errors in valid_failures.items():
            print(f"- {name}: {errors}", file=sys.stderr)
        return 1
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
