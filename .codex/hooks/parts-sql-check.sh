#!/bin/bash
# PartsService SQL Column Validator Hook (approved via dev-qa.md 2026-04-18)
#
# PostToolUse hook that fires after Edit/Write on PartsService.swift or PartsModels.swift.
# Non-blocking — warns about known-bad SQL column patterns that have caused 64+ production bugs.
#
# Bad-column list sourced from:
#   /Users/IA/.claude/projects/-Users-IA-GitHub-Weird-Part-Run-2/memory/feedback_sql_patterns.md
#
# Claude Code passes the tool input via stdin as JSON. We extract the file path
# and grep it for known-bad patterns.

set -e

# Read the JSON stdin and extract file_path
INPUT_JSON=$(cat)
FILE=$(echo "$INPUT_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('tool_input', {}).get('file_path', ''))" 2>/dev/null || echo "")

# Only fire for PartsService.swift or PartsModels.swift
case "$FILE" in
    *PartsService*.swift|*PartsModels*.swift) ;;
    *) exit 0 ;;
esac

# Known-bad SQL column patterns (from feedback_sql_patterns.md)
# Each pattern is a regex + description. Non-exhaustive — covers the highest-yield mismatches.
WARNINGS=""

check_pattern() {
    local pattern="$1"
    local description="$2"
    if grep -nE "$pattern" "$FILE" 2>/dev/null | grep -v "^\s*//" > /tmp/parts-sql-hits.$$; then
        WARNINGS+="\n⚠️  $description\n"
        WARNINGS+=$(sed 's/^/    /' /tmp/parts-sql-hits.$$)
        WARNINGS+="\n"
    fi
    rm -f /tmp/parts-sql-hits.$$
}

# Users table — no first_name/last_name, use display_name
check_pattern "(^|[^_])users\.(first_name|last_name)|(^|[^_[:alnum:]])u\.(first_name|last_name)" "users table has no first_name/last_name — use display_name"
# Users table — is_active is the flag, not status
check_pattern "(^|[^_])users\.status[^_]|(^|[^_[:alnum:]])u\.status[^_]" "users table uses is_active (not status)"
# Hats — no soft delete (careful: user_hats DOES have deleted_at — only flag unqualified 'hats' or 'h')
check_pattern "(^|[^_])hats\.deleted_at|(^|[^_[:alnum:]])h\.deleted_at" "hats table has no deleted_at (but user_hats does — check your alias)"
# Parts — code, not part_number
check_pattern "parts\.part_number|p\.part_number" "parts table uses 'code' (not part_number)"
# PO line items — unit_cost, not unit_price
check_pattern "po_line_items\.unit_price" "po_line_items uses unit_cost (not unit_price)"
# Purchase orders — total_cost, not total_amount
check_pattern "purchase_orders\.total_amount" "purchase_orders uses total_cost (not total_amount)"
# Chat messages — sender_id, not user_id
check_pattern "chat_messages\.user_id" "chat_messages uses sender_id (not user_id)"
# Jobs — customer_name (text), not customer_id
check_pattern "jobs\.customer_id|j\.customer_id" "jobs uses customer_name (text, no FK) not customer_id"
# QA threads — subject, not question
check_pattern "qa_threads\.question" "qa_threads uses 'subject' (not question)"
# Labor entries — no updated_at
check_pattern "labor_entries\.updated_at" "labor_entries has no updated_at column"

if [ -n "$WARNINGS" ]; then
    printf "%b\n" "⚠️  PartsService SQL column validator flagged potential issues in $FILE:$WARNINGS" >&2
    printf "See memory/feedback_sql_patterns.md for the full known-bad list.\n" >&2
fi

# Always exit 0 — this is a warning hook, not a blocker
exit 0
