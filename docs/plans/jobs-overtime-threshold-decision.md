# Jobs Overtime Threshold Decision (WEI-767)

## Decision

Use **Option B**: calculate overtime in `JobsService.clockOut` using a **per-worker, per-day aggregate**.

- For the labor entry being closed, sum prior completed hours for the same worker on the same `date(clock_in)`.
- Consume the 8-hour regular bucket with prior same-day hours first.
- Assign overflow to `overtime_hours` on the current entry (the entry that crosses the threshold).

## Scope

- Applies to current default behavior for labor entries and downstream cost/report consumers that read `regular_hours` and `overtime_hours`.
- Weekly overtime configuration is **not** introduced in this issue.

## Reasoning

- Preserves existing data model and job attribution with minimal change.
- Fixes under-counted OT when workers switch jobs mid-day without requiring migration/backfill.
