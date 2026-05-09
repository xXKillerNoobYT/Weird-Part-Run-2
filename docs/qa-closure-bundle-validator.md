# QA Closure-Bundle Validator

Purpose
- Validate required closure-bundle completeness before closing a parent issue in WEI-149 style QA workflows.

Required fields
- `Artifact Links:` with at least one markdown link bullet (`- [label](url)`).
- `Acceptance Checklist:` where every checklist item is complete (`[x]`) and none are unchecked (`[ ]`).
- `Unresolved Risks:` declared with non-empty text (use `none` when there are no open risks).
- `Reproduction:` with both:
  - `Command: ` wrapped in backticks.
  - `Path: ` wrapped in backticks.

Run
```bash
scripts/qa-closure-bundle-validator.sh <bundle.md>
```

Examples
- Passing bundle: `docs/examples/qa-closure-bundles/pass.md`
- Failing bundle: `docs/examples/qa-closure-bundles/fail.md`

Gate behavior
- `FAIL-CLOSED`: if validation fails, parent closure should be blocked.
- Escalation owner for intentional override: CTO.
