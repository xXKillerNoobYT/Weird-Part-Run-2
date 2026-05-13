---
name: parts-sql-schema-checker
description: Cross-reference SQL column references in PartsService (or any service) against AppDatabase+Migrations.swift. Flags every qualified alias.column reference where the column doesn't exist in the referenced table. Used as part of hunt-fix Scanner 4 (SQL integrity) and standalone before touching a large service file.
---

# parts-sql-schema-checker

Fast, deterministic SQL column validator for the WiredPart Swift core. Catches the single highest-yield bug class in this project (64+ historical SQL column mismatches) in under 3 seconds.

## When to use

- **Every hunt-fix iteration's Scanner 4.** Run before manually grepping for SQL bugs.
- **Before committing** any large edit to `PartsService.swift`, `OrdersService.swift`, or any other file in `core/Sources/WiredPartCore/Services/`.
- **When adding a new migration.** Run `--all` after adding a column, to confirm no queries reference the column with the wrong table.
- **When onboarding a new service method.** Invoke with `--service NewServiceName` to get targeted feedback.

## How to invoke

All invocations are from the repo root.

```bash
# Default — check PartsService only
python3 .agents/skills/parts-sql-schema-checker/check.py

# Check a specific service
python3 .agents/skills/parts-sql-schema-checker/check.py --service OrdersService

# Check every *.swift in Services/
python3 .agents/skills/parts-sql-schema-checker/check.py --all

# Dump the parsed schema (220+ tables, ~2400 columns) for debugging
python3 .agents/skills/parts-sql-schema-checker/check.py --summary
```

## Exit codes

- `0` — no mismatches detected
- `1` — mismatches found (output lists file:line + alias.column + nearest valid columns)
- `2` — migrations file missing / parse error

## What it catches

- `alias.column` where the bound table has no such column (e.g. `lst.part_category` when `location_stock_targets` doesn't have it).
- Works across INNER JOIN, LEFT JOIN, UPDATE, INSERT INTO, DELETE FROM alias resolution.

## What it deliberately does NOT catch (and why)

- **Bare column references** (unqualified `SELECT name FROM parts`). Too many false positives from subqueries, CTEs, and COALESCE wrappers.
- **Computed columns / aliases** (`COALESCE(...) AS x`, `ROW_NUMBER() OVER (...)`).
- **Dynamic SQL** assembled from string interpolation. The interpolated parts aren't visible to the parser.
- **SQL inside backticks or raw Swift string interpolation** with `\\(...)` segments — parser sees them as opaque.

If you need to validate something in the "not caught" set, read the migration and the query side-by-side.

## How the parser handles migrations

Three source patterns extract column names:

1. `t.column("name", .type)` / `t.add(column: "name", .type)` / `t.autoIncrementedPrimaryKey("id")` inside a `db.create(table: "x") { t in ... }` or `db.alter(table: "x") { t in ... }` block.
2. `addColumnIfMissing(db, table: "x", column: "y", ...)` helper calls (idempotent column adds outside a block).
3. Raw `db.execute(sql: "ALTER TABLE x ADD COLUMN y ...")` and `CREATE TABLE x (...)` strings.

If a future migration uses a different idiom, this file is the place to add the pattern — the parser is designed for incremental extension.

## Integration with hunt-fix

`hunt-fix-loop` Scanner 4 should prefer this skill over manual greps when the focus area is `parts`, `orders`, or any service file with dense SQL. Add the following to the Scanner 4 step:

```bash
python3 .agents/skills/parts-sql-schema-checker/check.py --all
```

A clean exit = Scanner 4 PASS for column references. (Other SQL issues — missing soft-delete filters, `status = 'complete'` vs `'completed'` — are still Scanner 4's responsibility; this skill only handles column existence.)

## Known limitations

- **220 tables parsed, ~2438 columns.** If the parser misses a column because of an unusual migration idiom, the skill will falsely flag valid SQL. Fix by extending the parser, not by silencing the check.
- Aliases shorter than 1 character (e.g. `a.x`) are matched; aliases longer than 25 characters are not.
- Column names shorter than 3 characters (e.g. `id`) are NOT matched by the qualified-ref regex to avoid matching Swift method calls like `.id`. Note: `t.column("id", ...)` IS parsed correctly because it's inside the migration-side regex, which has its own rules.

## Owner

Created 2026-04-18 as part of hunt-fix iteration 7 to close GitHub issue #254.
Lives under `.agents/skills/` (project-scoped) so it travels with the repo.
