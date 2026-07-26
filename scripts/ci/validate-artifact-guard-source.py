#!/usr/bin/env python3
"""Fail when the artifact-guard workflow can run fork code on a private runner."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
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
RUBY_STEP_PARSER = r"""
require "json"
require "psych"

def walk(node, &block)
  yield node
  (node.respond_to?(:children) && node.children || []).each { |child| walk(child, &block) }
end

def anchors_for(document)
  anchors = {}
  walk(document) do |node|
    if node.is_a?(Psych::Nodes::Scalar) && node.anchor
      anchors[node.anchor] = node
    end
  end
  anchors
end

def scalar_metadata(node, anchors)
  case node
  when Psych::Nodes::Scalar
    { "kind" => "scalar", "value" => node.value, "style" => node.style,
      "tag" => node.tag, "anchor" => node.anchor }
  when Psych::Nodes::Alias
    target = anchors[node.anchor]
    { "kind" => "alias", "value" => target&.value, "style" => target&.style,
      "tag" => target&.tag, "anchor" => node.anchor }
  else
    { "kind" => "unsupported", "value" => nil, "style" => nil,
      "tag" => nil, "anchor" => nil }
  end
end

def mapping_entries(mapping)
  mapping.children.each_slice(2).each_with_object({}) do |(key, value), entries|
    entries[key.value] = value if key.is_a?(Psych::Nodes::Scalar)
  end
end

def step_syntax_errors(step)
  errors = []
  walk(step) do |node|
    if node.is_a?(Psych::Nodes::Alias)
      errors << "workflow step contains a YAML alias"
    elsif node.is_a?(Psych::Nodes::Mapping)
      node.children.each_slice(2) do |key, _value|
        if key.is_a?(Psych::Nodes::Scalar) && key.value == "<<"
          errors << "workflow step contains a YAML mapping merge key"
        end
      end
    end
  end
  errors.uniq
end

document = Psych.parse_stream(STDIN.read)
anchors = anchors_for(document)
steps = []
walk(document) do |node|
  next unless node.is_a?(Psych::Nodes::Mapping)
  entries = mapping_entries(node)
  step_list = entries["steps"]
  next unless step_list.is_a?(Psych::Nodes::Sequence)
  step_list.children.each do |step|
    # A sequence alias can materialize a complete step mapping without exposing
    # its fields in this AST position. Reject it rather than silently omitting a
    # semantic checkout from the policy scan.
    unless step.is_a?(Psych::Nodes::Mapping)
      error = step.is_a?(Psych::Nodes::Alias) ?
        "workflow step contains a YAML alias" :
        "workflow step must be a YAML mapping"
      steps << { "syntax_errors" => [error] }
      next
    end
    step_entries = mapping_entries(step)
    steps << %w[if uses run].each_with_object({ "syntax_errors" => step_syntax_errors(step) }) do |field, result|
      result[field] = scalar_metadata(step_entries[field], anchors) if step_entries.key?(field)
    end
  end
end
puts JSON.generate({ "steps" => steps })
"""

PLAIN_OR_QUOTED_YAML_STYLES = {1, 2, 3}


def _steps(workflow: str) -> list[dict[str, dict[str, object]]]:
    """Parse workflow steps structurally and preserve YAML scalar metadata.

    Psych resolves the YAML tree rather than inferring fields from indentation, so
    legal sequence styles such as ``- uses: ...`` cannot conceal an action. The
    validator fails closed if the parser is unavailable or the workflow is invalid.
    """
    try:
        result = subprocess.run(
            ["ruby", "-e", RUBY_STEP_PARSER],
            input=workflow,
            text=True,
            capture_output=True,
            check=True,
        )
        parsed = json.loads(result.stdout)
    except (FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        raise ValueError(f"structural YAML parser failed: {error}") from error
    steps = parsed.get("steps")
    if not isinstance(steps, list):
        raise ValueError("structural YAML parser did not return workflow steps")
    return steps


def _value(step: dict[str, dict[str, object]], field: str) -> str:
    value = step.get(field, {}).get("value")
    return value if isinstance(value, str) else ""


def _has_unsupported_uses_syntax(step: dict[str, dict[str, object]]) -> bool:
    uses = step["uses"]
    return (
        uses.get("kind") != "scalar"
        or uses.get("style") not in PLAIN_OR_QUOTED_YAML_STYLES
        or uses.get("tag") is not None
        or uses.get("anchor") is not None
    )


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

    try:
        steps = _steps(workflow)
    except ValueError as error:
        return [*errors, str(error)]
    reject_steps = [
        step
        for step in steps
        if _value(step, "if") == FORK_CONDITION and "exit 1" in _value(step, "run")
    ]
    if not reject_steps:
        errors.append("fork rejection must be a fork-conditioned nonzero-exit run step")

    if any("uses" in step and _has_unsupported_uses_syntax(step) for step in steps):
        errors.append(
            "uses fields must use plain or quoted scalars; aliases, tags, anchors, "
            "and block scalars are not allowed"
        )
    if any(step.get("syntax_errors") for step in steps):
        errors.append("workflow steps must not use YAML aliases or mapping merge keys")

    # Pinning a checkout version is a supply-chain choice, not a trust boundary.
    # Guard every actions/checkout@* invocation so a later version bump cannot
    # bypass the trusted-source condition.
    checkout_steps = [
        step
        for step in steps
        if _value(step, "uses").startswith("actions/checkout@")
    ]
    if not checkout_steps:
        errors.append("workflow must have a trusted checkout step")
    for step in checkout_steps:
        if _value(step, "if") != TRUSTED_CONDITION:
            errors.append("checkout can run without the exact trusted-source condition")

    # A run step executes repository-controlled content after checkout; require the
    # trusted source guard on every normal run, not merely on the first such step.
    for step in steps:
        run = _value(step, "run")
        if not run or step in reject_steps:
            continue
        if _value(step, "if") != TRUSTED_CONDITION:
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
    unsafe_always_inline_mapping_checkout = unsafe_always_quoted_checkout.replace(
        "- name: Checkout repository after fork rejection\n        if: always()\n        uses: \"actions/checkout@v5\"",
        "- uses: actions/checkout@v5\n        if: always()",
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
    unsafe_always_merged_checkout = unsafe_always_quoted_checkout.replace(
        "- name: Checkout repository after fork rejection\n        if: always()\n        uses: \"actions/checkout@v5\"",
        f"- &trusted_checkout\n        name: Trusted checkout template\n        if: {TRUSTED_CONDITION}\n        uses: actions/checkout@v4\n      - <<: *trusted_checkout\n        name: Checkout repository after fork rejection\n        if: always()",
    )
    unsafe_aliased_step_checkout = f"""jobs:
  tracked-artifacts:
    runs-on: {DYNAMIC_RUNNER}
    steps:
      - name: Reject untrusted fork without using the Mac runner
        if: {FORK_CONDITION}
        run: exit 1
      - &trusted_checkout
        name: Trusted checkout template
        if: {TRUSTED_CONDITION}
        uses: actions/checkout@v4
      - *trusted_checkout
      - name: Run artifact guard
        if: {TRUSTED_CONDITION}
        run: python3 scripts/guard-tracked-artifacts.py
"""
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
        "later always() inline-mapping actions/checkout@v5 after trusted checkout": unsafe_always_inline_mapping_checkout,
        "later always() anchored actions/checkout@v5 after trusted checkout": unsafe_always_anchor_checkout,
        "later always() explicitly tagged actions/checkout@v5 after trusted checkout": unsafe_always_tagged_checkout,
        "later always() folded actions/checkout@v5 after trusted checkout": unsafe_always_folded_checkout,
        "later always() literal actions/checkout@v5 after trusted checkout": unsafe_always_literal_checkout,
        "later always() aliased actions/checkout@v5 after trusted checkout": unsafe_always_aliased_checkout,
        "later always() merged actions/checkout@v4 after trusted checkout": unsafe_always_merged_checkout,
        "aliased workflow-step checkout after trusted checkout": unsafe_aliased_step_checkout,
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
