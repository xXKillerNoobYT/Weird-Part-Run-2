#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# E2E Integration Test — Local Services / SQLite Layer
#
# Tests the full data layer that powers the Tauri app by exercising CRUD
# operations against both simulator databases. Validates:
# - All 17 migrations (116 tables)
# - Auth (users, hats, hat_permissions)
# - Parts hierarchy (part_categories → part_styles → part_types → parts)
# - Jobs & Labor (create, clock in/out, soft delete)
# - Orders (JPOs, POs, returns, receiving)
# - Warehouse (stock, movements)
# - Notebooks (sections, entries, tasks)
# - Fleet (vehicles, assignments)
# - Tools & Kits
# - People (contacts, scheduling, certifications)
# - Chat & Q&A
# - Reports & Billing
# - Sync infrastructure (_change_log, _vector_clock, _conflict_log)
#
# Usage: ./tests/e2e-local-services.sh [ipad|iphone|both]
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
# Note: no -e so individual test failures don't kill the whole suite

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}✗${NC} $1"; }
skip() { SKIP=$((SKIP + 1)); echo -e "  ${YELLOW}○${NC} $1 (skipped)"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ── Find databases ──
IPAD_DEVICE="AF96C9F9-DD1D-4AF5-8A55-64805B5955A5"
IPHONE_DEVICE="7E22D950-7EEA-41D4-A82A-E28C765BA886"

find_db() {
  find ~/Library/Developer/CoreSimulator/Devices/"$1"/data/Containers/Data/Application \
    -name "wiredpart.db" 2>/dev/null | head -1
}

IPAD_DB=$(find_db "$IPAD_DEVICE")
IPHONE_DB=$(find_db "$IPHONE_DEVICE")

TARGET="${1:-both}"
DATABASES=()

[[ "$TARGET" == "ipad" || "$TARGET" == "both" ]] && [ -n "$IPAD_DB" ] && DATABASES+=("iPad:$IPAD_DB")
[[ "$TARGET" == "iphone" || "$TARGET" == "both" ]] && [ -n "$IPHONE_DB" ] && DATABASES+=("iPhone:$IPHONE_DB")

if [ ${#DATABASES[@]} -eq 0 ]; then
  echo -e "${RED}No databases found. Are simulators running?${NC}"; exit 1
fi

q()  { sqlite3 "$DB" "$1" 2>/dev/null; }
qi() { local r; r=$(sqlite3 "$DB" "$1" 2>/dev/null); echo "${r:-0}"; }
has_table() { [ "$(qi "SELECT COUNT(*) FROM sqlite_master WHERE name='$1' AND type='table';")" -eq 1 ]; }
has_col()   { [ "$(qi "SELECT COUNT(*) FROM pragma_table_info('$1') WHERE name='$2';")" -eq 1 ]; }

# ═══════════════════════════════════════════════════════════════════════════════

test_migrations() {
  section "TEST 1: Migrations (17 total)"

  local count; count=$(qi "SELECT COUNT(*) FROM _migrations;")
  [ "$count" -eq 17 ] && pass "All 17 migrations applied" || fail "Expected 17, got $count"

  for m in 000_change_log 001_foundation 002_parts_inventory 003_jobs_labor \
           004_notebooks 005_orders 006_fleet_tools_scheduling 007_chat \
           008_soft_delete_and_sync 009_people_full 010_costs_receiving \
           011_reports_pto 012_warehouse_attachments 013_tools_supplier_extras \
           014_contacts_costs_profiles 015_job_team_suppliers 016_companions_alternatives; do
    [ "$(qi "SELECT COUNT(*) FROM _migrations WHERE name='$m';")" -eq 1 ] && pass "$m" || fail "$m missing"
  done

  local tables; tables=$(qi "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
  [ "$tables" -ge 110 ] && pass "Table count: $tables (≥110)" || fail "Only $tables tables"
}

test_auth() {
  section "TEST 2: Auth & Users"

  local admin; admin=$(q "SELECT display_name FROM users WHERE id=1 AND deleted_at IS NULL;")
  [ "$admin" = "Admin" ] && pass "Admin user exists (id=1)" || fail "Admin user: '$admin'"

  local user_count; user_count=$(qi "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL;")
  [ "$user_count" -eq 1 ] && pass "No duplicate users (count=$user_count)" || fail "User count: $user_count"

  [ "$(qi "SELECT COUNT(*) FROM users WHERE id=1 AND pin_hash IS NOT NULL AND pin_hash != '';")" -eq 1 ] \
    && pass "Admin has PIN hash" || fail "Admin missing PIN hash"

  local hat_count; hat_count=$(qi "SELECT COUNT(*) FROM hats;")
  [ "$hat_count" -ge 1 ] && pass "Hats populated ($hat_count)" || fail "No hats"

  # Permissions are stored as strings in hat_permissions (not a separate table)
  local hp_count; hp_count=$(qi "SELECT COUNT(*) FROM hat_permissions;")
  [ "$hp_count" -ge 1 ] && pass "Hat-permissions populated ($hp_count)" || fail "No hat-permissions"

  [ "$(qi "SELECT COUNT(*) FROM user_hats WHERE user_id=1;")" -ge 1 ] \
    && pass "Admin has hat assigned" || fail "Admin has no hats"
}

test_schema_integrity() {
  section "TEST 3: Schema Integrity (soft deletes + sync)"

  # Soft delete columns on key tables
  for tbl in users parts part_categories part_styles part_types jobs labor_entries \
             notebooks notebook_sections notebook_entries purchase_orders \
             vehicles tools; do
    has_col "$tbl" "deleted_at" && pass "$tbl.deleted_at" || fail "$tbl missing deleted_at"
  done

  # Sync infrastructure tables
  for tbl in _change_log _vector_clock _conflict_log _device_registry _scheduler_state; do
    has_table "$tbl" && pass "$tbl exists" || fail "$tbl missing"
  done
}

test_parts_hierarchy() {
  section "TEST 4: Parts & Inventory"

  for tbl in part_categories part_styles part_types parts brands suppliers \
             part_supplier_links brand_supplier_links type_brand_links \
             type_color_links stock stock_movements part_colors; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done

  # CRUD test
  q "INSERT OR IGNORE INTO part_categories (id, name, is_active, created_at, updated_at) VALUES (9900, 'TEST_CAT', 1, datetime('now'), datetime('now'));"
  [ "$(qi "SELECT COUNT(*) FROM part_categories WHERE id=9900;")" -eq 1 ] && pass "Category INSERT" || fail "Category INSERT"

  q "INSERT OR IGNORE INTO part_styles (id, category_id, name, is_active, created_at, updated_at) VALUES (9900, 9900, 'TEST_STYLE', 1, datetime('now'), datetime('now'));"
  [ "$(qi "SELECT COUNT(*) FROM part_styles WHERE id=9900;")" -eq 1 ] && pass "Style INSERT (FK→category)" || fail "Style INSERT"

  # Soft delete test
  q "UPDATE part_categories SET deleted_at=datetime('now') WHERE id=9900;"
  [ "$(qi "SELECT COUNT(*) FROM part_categories WHERE id=9900 AND deleted_at IS NOT NULL;")" -eq 1 ] \
    && pass "Soft delete works" || fail "Soft delete failed"

  q "DELETE FROM part_styles WHERE id=9900;"
  q "DELETE FROM part_categories WHERE id=9900;"
  pass "Cleanup"
}

test_jobs_labor() {
  section "TEST 5: Jobs & Labor"

  for tbl in jobs labor_entries daily_reports clock_out_questions clock_out_responses \
             job_parts job_customers job_general_contractors job_dispatch \
             job_parts_orders job_preferences job_lead_elevations; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done

  # CRUD: job → labor entry → soft delete
  q "INSERT OR IGNORE INTO jobs (id, job_number, job_name, status, created_by, created_at, updated_at) VALUES (9900, 'TEST-9900', 'TEST_JOB', 'active', 1, datetime('now'), datetime('now'));"
  [ "$(qi "SELECT COUNT(*) FROM jobs WHERE id=9900;")" -eq 1 ] && pass "Job INSERT" || fail "Job INSERT"

  q "INSERT OR IGNORE INTO labor_entries (id, job_id, user_id, clock_in, created_at) VALUES (9900, 9900, 1, datetime('now'), datetime('now'));"
  [ "$(qi "SELECT COUNT(*) FROM labor_entries WHERE id=9900;")" -eq 1 ] && pass "Labor INSERT (FK→job)" || fail "Labor INSERT"

  q "UPDATE labor_entries SET deleted_at=datetime('now') WHERE id=9900;"
  [ "$(qi "SELECT COUNT(*) FROM labor_entries WHERE id=9900 AND deleted_at IS NOT NULL;")" -eq 1 ] \
    && pass "Labor soft delete" || fail "Labor soft delete"

  q "DELETE FROM labor_entries WHERE id=9900;"
  q "DELETE FROM jobs WHERE id=9900;"
  pass "Cleanup"
}

test_notebooks() {
  section "TEST 6: Notebooks & Tasks"

  for tbl in notebooks notebook_sections notebook_entries notebook_templates \
             task_order_links notebook_entry_permissions notebook_entry_tools \
             template_sections template_entries; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_orders() {
  section "TEST 7: Orders & Procurement"

  for tbl in purchase_orders po_line_items jpo_line_items \
             returns return_line_items special_items \
             receiving_sessions receiving_session_items \
             order_attachments order_status_history pulled_staging_tags; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_fleet() {
  section "TEST 8: Fleet & Vehicles"

  for tbl in vehicles vehicle_assignments; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_tools() {
  section "TEST 9: Tools & Kits"

  for tbl in tools tool_movements tool_maintenance_records tool_maintenance_schedules \
             tool_maintenance_types tool_depreciation_entries kit_templates \
             kit_verification_sessions kit_verification_items; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_people_contacts() {
  section "TEST 10: People & Contacts"

  for tbl in certifications wage_history employee_notes user_skills \
             employee_teams employee_team_members entity_contacts \
             customers general_contractors subcontractor_schedules; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_chat() {
  section "TEST 11: Chat & Q&A"

  for tbl in chat_channels chat_channel_members chat_messages chat_mentions \
             chat_read_receipts qa_threads rfi_objects; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_scheduling() {
  section "TEST 12: Scheduling & Dispatch"

  for tbl in job_dispatch employee_default_schedules schedule_exceptions; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_reports_billing() {
  section "TEST 13: Reports & Billing"

  for tbl in billing_periods report_annotations report_share_tokens report_templates \
             pto_policies pto_transactions bill_rate_types; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_warehouse_extras() {
  section "TEST 14: Warehouse & Attachments"

  for tbl in job_trailers trailer_location_events order_attachments \
             receiving_sessions receiving_session_items; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_advanced_features() {
  section "TEST 15: Advanced Features"

  # Migration 016: Companions & alternatives
  for tbl in companion_rules companion_rule_sources companion_rule_targets \
             companion_suggestions companion_suggestion_sources companion_feedback \
             part_alternatives co_occurrence_pairs; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done

  # Migration 015: Job team & supplier prefs
  for tbl in job_team_members job_preferred_suppliers; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done

  # Migration 014: Cost layers & company profiles
  for tbl in cost_layers company_profiles company_cost_settings; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done

  # Migration 013: Depreciation & supplier portal
  for tbl in tool_depreciation_entries supplier_portal_tokens; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_indexes() {
  section "TEST 16: Indexes"

  local idx_count; idx_count=$(qi "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")
  [ "$idx_count" -ge 20 ] && pass "Index count: $idx_count" || fail "Only $idx_count indexes"

  has_table "sqlite_sequence" && pass "Autoincrement sequences" || skip "No autoincrement"
}

test_settings_notifications() {
  section "TEST 17: Settings & Notifications"

  for tbl in settings notifications notification_preferences devices activity_log; do
    has_table "$tbl" && pass "$tbl" || fail "$tbl missing"
  done
}

test_fk_consistency() {
  section "TEST 18: FK & Data Consistency"

  # Admin's hat should reference a valid hat
  local orphan_hats; orphan_hats=$(qi "SELECT COUNT(*) FROM user_hats uh LEFT JOIN hats h ON uh.hat_id=h.id WHERE h.id IS NULL;")
  [ "$orphan_hats" -eq 0 ] && pass "No orphan user_hats" || fail "$orphan_hats orphan user_hats"

  # Hat permissions should reference valid hats
  local orphan_hp; orphan_hp=$(qi "SELECT COUNT(*) FROM hat_permissions hp LEFT JOIN hats h ON hp.hat_id=h.id WHERE h.id IS NULL;")
  [ "$orphan_hp" -eq 0 ] && pass "No orphan hat_permissions" || fail "$orphan_hp orphan hat_permissions"

  # No future timestamps
  local future; future=$(qi "SELECT COUNT(*) FROM users WHERE created_at > datetime('now', '+1 hour');")
  [ "$future" -eq 0 ] && pass "No future timestamps" || fail "$future records with future timestamps"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run all tests
# ═══════════════════════════════════════════════════════════════════════════════

for entry in "${DATABASES[@]}"; do
  DEVICE_NAME="${entry%%:*}"
  DB="${entry#*:}"

  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  Testing: ${DEVICE_NAME}${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"

  test_migrations
  test_auth
  test_schema_integrity
  test_parts_hierarchy
  test_jobs_labor
  test_notebooks
  test_orders
  test_fleet
  test_tools
  test_people_contacts
  test_chat
  test_scheduling
  test_reports_billing
  test_warehouse_extras
  test_advanced_features
  test_indexes
  test_settings_notifications
  test_fk_consistency
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}PASSED: $PASS${NC}  |  ${RED}FAILED: $FAIL${NC}  |  ${YELLOW}SKIPPED: $SKIP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

[ "$FAIL" -gt 0 ] && { echo -e "\n${RED}Some tests failed!${NC}"; exit 1; } || { echo -e "\n${GREEN}All tests passed! ✓${NC}"; exit 0; }
