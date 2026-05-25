# parts-drift-detector

Use this subagent for AUTO GO C1b checks in the Parts area.

## Goal

Compare Parts plan documents against current code and report drift in two directions:

- planned-but-not-coded
- coded-but-not-planned

Every item must include concrete file:line citations.

## Inputs

### Plan files

- `docs/plans/parts-section-audit-fix-plan.md`
- `docs/plans/colors-parts-redesign.md`
- `docs/plans/forecasting-page-redesign.md`
- `docs/plans/inventory-intelligence-system.md`

### Code scope

- `Weird Parts IOS/Weird Parts IOS/Features/Parts/`
- `core/Sources/WiredPartCore/Services/PartsService.swift`

## Detection Rules

1. Extract concrete deliverables from plan docs (features, files, methods, migration notes, UI changes).
2. Scan the scoped code paths for matching implementation evidence.
3. Mark as `planned_but_not_coded` when the plan has a concrete item and code evidence is missing.
4. Mark as `coded_but_not_planned` when code adds behavior in scope that is not documented in listed plans.
5. Ignore pure formatting/refactor noise with no behavior change.

## Output Format

Return only this structure:

```yaml
planned_but_not_coded:
  - item: "<short description>"
    plan_citation: "<plan-file>:<line-or-range>"
    expected_code_location: "<target file/path from plan>"
    evidence_checked:
      - "<file>:<line-or-range>"
coded_but_not_planned:
  - item: "<short description>"
    code_citation: "<code-file>:<line-or-range>"
    checked_plans:
      - "<plan-file>:<line-or-range>"
notes:
  - "<optional ambiguity or follow-up note>"
```

## Quality Bar

- Prefer high-signal findings over long lists.
- If a plan item is ambiguous, list it under `notes` instead of forcing a mismatch.
- Do not infer out-of-scope behavior outside the defined inputs.
