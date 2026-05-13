#!/usr/bin/env python3
"""
parts-sql-schema-checker — Cross-reference PartsService SQL against the migration schema.

Reads:
  - core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift — builds table→columns map
  - core/Sources/WiredPartCore/Services/PartsService.swift (default) — extracts SQL strings

Reports mismatches where a `table.column` or bare `column` reference in SQL doesn't
exist in the migration schema. Focuses on qualified references (table.column) because
bare column references produce too many false positives in complex queries.

Exit codes:
  0 — no mismatches
  1 — mismatches found
  2 — parse error / missing files

Usage:
  ./check.py                          # check PartsService.swift (default)
  ./check.py --service OrdersService  # check another service
  ./check.py --all                    # check every *.swift in Services/
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path("/Users/IA/GitHub/Weird-Part-Run-2")
MIGRATIONS = REPO_ROOT / "core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift"
SERVICES_DIR = REPO_ROOT / "core/Sources/WiredPartCore/Services"

# Swift column builder variants we care about. We match the *literal* column name
# argument, ignoring the column type.
COLUMN_PATTERN = re.compile(
    r'\bt\.(?:column|add)\(\s*(?:column:\s*)?"([a-zA-Z_][a-zA-Z0-9_]*)"'
)
# autoIncrementedPrimaryKey("id") / primaryKey(...)
PRIMARY_KEY_PATTERN = re.compile(
    r'\bt\.(?:autoIncrementedPrimaryKey|primaryKey)\(\s*"([a-zA-Z_][a-zA-Z0-9_]*)"'
)
# db.create(table: "x") { t in ... }  AND  db.alter(table: "x") { t in ... }
TABLE_BLOCK_PATTERN = re.compile(
    r'\bdb\.(?:create|alter)\(\s*table:\s*"([a-zA-Z_][a-zA-Z0-9_]*)"'
    r'(?:,\s*ifNotExists:\s*(?:true|false))?'
    r'\s*\)\s*\{\s*t\s+in',
    re.MULTILINE,
)

# Helper-call pattern: addColumnIfMissing(db, table: "x", column: "y", ...)
# Used elsewhere in migrations to idempotently add columns outside an alter block.
ADD_COLUMN_HELPER_PATTERN = re.compile(
    r'\baddColumnIfMissing\(\s*[a-zA-Z_][a-zA-Z0-9_]*\s*,\s*'
    r'table:\s*"([a-zA-Z_][a-zA-Z0-9_]*)"\s*,\s*'
    r'column:\s*"([a-zA-Z_][a-zA-Z0-9_]*)"'
)

# Raw SQL ALTER TABLE ... ADD COLUMN inside db.execute(sql: "...")
EXECUTE_ADD_COLUMN_PATTERN = re.compile(
    r'\bALTER\s+TABLE\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+ADD\s+COLUMN\s+([a-zA-Z_][a-zA-Z0-9_]*)',
    re.IGNORECASE,
)

# Raw SQL CREATE TABLE ... (col TYPE, ...) inside db.execute(sql: "...")
EXECUTE_CREATE_TABLE_PATTERN = re.compile(
    r'\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(([^)]+)\)',
    re.IGNORECASE | re.DOTALL,
)


def parse_migrations(path: Path) -> dict[str, set[str]]:
    """Return {table_name: {column_names}} by walking migration file top-to-bottom."""
    if not path.exists():
        print(f"ERROR: migrations file not found: {path}", file=sys.stderr)
        sys.exit(2)

    source = path.read_text()
    # Scan line-by-line keeping a "current_table" cursor. When we see a new
    # db.create / db.alter block, switch cursor. Columns add to the current
    # table's column set.
    tables: dict[str, set[str]] = {}
    current_table: str | None = None
    brace_depth = 0  # depth inside the current table block
    in_block = False

    for line in source.splitlines():
        if not in_block:
            m = TABLE_BLOCK_PATTERN.search(line)
            if m:
                current_table = m.group(1)
                tables.setdefault(current_table, set())
                in_block = True
                brace_depth = 1  # the `{` that opens the block
                # scan the rest of the line for columns too (rare but possible)
                line = line[m.end():]
            else:
                continue

        # Track braces to know when the block ends.
        open_ct = line.count("{")
        close_ct = line.count("}")
        brace_depth += open_ct - close_ct

        # Column refs on this line
        for col_match in COLUMN_PATTERN.finditer(line):
            tables[current_table].add(col_match.group(1))
        for pk_match in PRIMARY_KEY_PATTERN.finditer(line):
            tables[current_table].add(pk_match.group(1))

        if brace_depth <= 0:
            in_block = False
            current_table = None

    # Second pass: pick up addColumnIfMissing helper calls and raw SQL execute()
    # column additions that happen outside db.create/db.alter blocks.
    for m in ADD_COLUMN_HELPER_PATTERN.finditer(source):
        table, column = m.group(1), m.group(2)
        tables.setdefault(table, set()).add(column)

    for m in EXECUTE_ADD_COLUMN_PATTERN.finditer(source):
        table, column = m.group(1), m.group(2)
        tables.setdefault(table, set()).add(column)

    # CREATE TABLE ... (col TYPE, ...) — parse the column list
    for m in EXECUTE_CREATE_TABLE_PATTERN.finditer(source):
        table, body = m.group(1), m.group(2)
        for col_def in body.split(","):
            col_def = col_def.strip()
            # First identifier is the column name (skip constraint lines)
            if col_def.upper().startswith(("PRIMARY", "FOREIGN", "UNIQUE", "CHECK", "CONSTRAINT")):
                continue
            m2 = re.match(r'"?([a-zA-Z_][a-zA-Z0-9_]*)"?', col_def)
            if m2:
                tables.setdefault(table, set()).add(m2.group(1))

    return tables


# --- SQL extraction from Swift ---------------------------------------------

SQL_KEYWORDS_RE = re.compile(
    r"\b(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|WITH)\b", re.IGNORECASE
)


def extract_sql_strings(path: Path) -> list[tuple[int, str]]:
    """Return list of (line_number, sql_string) from a Swift file.

    Captures:
      - Triple-quoted strings containing SQL keywords.
      - Single-quoted strings that contain SQL keywords AND run at least 20 chars.
    """
    source = path.read_text()
    lines = source.splitlines()
    results: list[tuple[int, str]] = []

    # Triple-quoted blocks
    i = 0
    while i < len(lines):
        line = lines[i]
        idx = line.find('"""')
        if idx != -1:
            start_line = i + 1  # 1-indexed
            buf = [line[idx + 3:]]
            i += 1
            closed = False
            while i < len(lines):
                next_line = lines[i]
                close_idx = next_line.find('"""')
                if close_idx != -1:
                    buf.append(next_line[:close_idx])
                    closed = True
                    i += 1
                    break
                buf.append(next_line)
                i += 1
            joined = "\n".join(buf)
            if closed and SQL_KEYWORDS_RE.search(joined):
                results.append((start_line, joined))
            continue
        i += 1

    # Single-line strings with SQL keywords
    single_quote_re = re.compile(r'"((?:[^"\\]|\\.){20,})"')
    for lineno, line in enumerate(lines, start=1):
        # Skip if inside a triple-quoted block start (we'll handle those separately)
        if '"""' in line:
            continue
        for m in single_quote_re.finditer(line):
            sql = m.group(1)
            if SQL_KEYWORDS_RE.search(sql):
                results.append((lineno, sql))

    return results


# --- Qualified column reference extraction ----------------------------------

# Matches `alias.column` where alias is a single lowercase letter or short identifier
# followed by a dot and a snake_case column. Excludes method calls via the heuristic
# that SQL column names are snake_case.
QUALIFIED_REF_RE = re.compile(
    r"\b([a-z][a-z0-9_]{0,25})\.([a-z_][a-z_0-9]{2,40})\b"
)

# Alias → table bindings we extract per query
ALIAS_BINDING_RE = re.compile(
    r"\b(?:FROM|JOIN|UPDATE|INTO)\s+([a-z_][a-z_0-9]*)\s+(?:AS\s+)?([a-z][a-z0-9_]{0,25})\b",
    re.IGNORECASE,
)
# Plain FROM/UPDATE/INTO without alias (use table name itself as alias)
BARE_TABLE_RE = re.compile(
    r"\b(?:FROM|UPDATE|INTO)\s+([a-z_][a-z_0-9]*)(?!\s+(?:AS\s+)?[a-z])", re.IGNORECASE
)

# Known Swift/ObjC property accesses that look like alias.column but aren't SQL.
# (Any identifier that appears BEFORE the SQL string is a Swift variable, so we
# rely on the query being in isolation.)
# However, WITHIN a SQL string, common false positives:
SWIFT_PROP_BLOCKLIST = {
    "self", "row", "rows", "try", "let", "var", "func", "return", "print",
    "logger", "error", "result", "dbConn", "dbConnection", "env", "db",
    "date",  # date('now', ...) — SQLite function
}


def find_alias_bindings(sql: str) -> dict[str, str]:
    """Return {alias_or_table_name: table_name} from FROM/JOIN/UPDATE/INTO clauses."""
    bindings: dict[str, str] = {}
    for m in ALIAS_BINDING_RE.finditer(sql):
        table, alias = m.group(1), m.group(2)
        # Skip bindings where "alias" is actually a keyword
        if alias.lower() in ("on", "using", "where", "set", "values", "select", "group", "order", "having", "limit", "inner", "left", "right", "outer", "cross", "natural", "join", "into", "as"):
            continue
        bindings[alias] = table
    # Also bind bare table names to themselves
    for m in BARE_TABLE_RE.finditer(sql):
        table = m.group(1)
        bindings.setdefault(table, table)
    return bindings


# --- Core check --------------------------------------------------------------

def check_service(service_path: Path, schema: dict[str, set[str]]) -> list[str]:
    """Return list of mismatch reports for a single service file."""
    mismatches: list[str] = []
    sqls = extract_sql_strings(service_path)

    for lineno, sql in sqls:
        bindings = find_alias_bindings(sql)
        # Strip string literals in SQL (e.g. 'completed') to avoid false positives
        sql_clean = re.sub(r"'[^']*'", "''", sql)

        for ref_match in QUALIFIED_REF_RE.finditer(sql_clean):
            alias, column = ref_match.group(1), ref_match.group(2)

            if alias in SWIFT_PROP_BLOCKLIST:
                continue

            # Resolve alias → table
            table = bindings.get(alias)
            if table is None:
                # Maybe the alias IS a table name directly (e.g. "parts.name" without FROM alias)
                if alias in schema:
                    table = alias
                else:
                    continue  # unknown alias — skip rather than false-positive

            columns = schema.get(table)
            if columns is None:
                # Table not in our schema (could be a view, temp table, unhandled migration)
                continue

            if column not in columns:
                # Allow SQLite built-in pseudo-columns
                if column in ("rowid", "oid", "_rowid_"):
                    continue
                mismatches.append(
                    f"{service_path.name}:{lineno}  {alias}.{column}  "
                    f"— column '{column}' not in table '{table}' "
                    f"(has: {', '.join(sorted(columns)[:8])}{'...' if len(columns) > 8 else ''})"
                )

    return mismatches


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--service",
        default="PartsService",
        help="Service to check (e.g. 'PartsService', 'OrdersService')",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Check every *.swift in Services/",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print schema summary only",
    )
    args = parser.parse_args()

    schema = parse_migrations(MIGRATIONS)

    if args.summary:
        print(f"Parsed {len(schema)} tables from {MIGRATIONS.name}:")
        for table in sorted(schema):
            print(f"  {table}: {len(schema[table])} columns")
        return 0

    if args.all:
        service_paths = sorted(SERVICES_DIR.glob("*.swift"))
    else:
        service_paths = [SERVICES_DIR / f"{args.service}.swift"]

    all_mismatches: list[str] = []
    for path in service_paths:
        if not path.exists():
            print(f"SKIP: {path.name} — not found", file=sys.stderr)
            continue
        mismatches = check_service(path, schema)
        all_mismatches.extend(mismatches)

    if all_mismatches:
        print(f"❌ {len(all_mismatches)} SQL schema mismatch(es):")
        for m in all_mismatches:
            print(f"  {m}")
        return 1

    scope = "all services" if args.all else args.service
    print(f"✅ No SQL schema mismatches in {scope}.")
    print(f"   ({len(schema)} tables, {sum(len(c) for c in schema.values())} columns in schema)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
