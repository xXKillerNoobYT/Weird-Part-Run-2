/**
 * Migration 008: Soft Delete + Sync Infrastructure
 *
 * Adds `deleted_at` column to all mutable tables that support DELETE operations.
 * This is critical for P2P sync — a hard delete is indistinguishable from
 * "never existed" on another device.
 *
 * Also adds:
 * - `_conflict_log` — tracks sync conflict resolutions for admin review
 * - `_vector_clock` — tracks per-device sync progress for efficient P2P sync
 * - `_device_registry` — tracks known peer devices for sync
 *
 * Tables that do NOT get deleted_at:
 * - `_migrations`, `_change_log` — internal system tables
 * - `activity_log` — append-only audit trail, never deleted
 * - `settings` — key-value store, never deleted (just updated)
 * - `hats`, `hat_permissions` — system-defined, never deleted
 * - Lookup/seed tables (bill_rate_types, clock_out_questions, etc.)
 */

export const migration = {
  name: '008_soft_delete_and_sync',
  sql: `
-- ═══════════════════════════════════════════════════════════════════
-- PART 1: Add deleted_at to all mutable user-facing tables
-- ═══════════════════════════════════════════════════════════════════

-- Foundation
ALTER TABLE users ADD COLUMN deleted_at TEXT;
ALTER TABLE user_hats ADD COLUMN deleted_at TEXT;
ALTER TABLE devices ADD COLUMN deleted_at TEXT;
ALTER TABLE notifications ADD COLUMN deleted_at TEXT;
ALTER TABLE notification_preferences ADD COLUMN deleted_at TEXT;
ALTER TABLE job_lead_elevations ADD COLUMN deleted_at TEXT;

-- Parts & Inventory
ALTER TABLE part_categories ADD COLUMN deleted_at TEXT;
ALTER TABLE part_styles ADD COLUMN deleted_at TEXT;
ALTER TABLE part_types ADD COLUMN deleted_at TEXT;
ALTER TABLE part_colors ADD COLUMN deleted_at TEXT;
ALTER TABLE brands ADD COLUMN deleted_at TEXT;
ALTER TABLE suppliers ADD COLUMN deleted_at TEXT;
ALTER TABLE parts ADD COLUMN deleted_at TEXT;
ALTER TABLE brand_supplier_links ADD COLUMN deleted_at TEXT;
ALTER TABLE part_supplier_links ADD COLUMN deleted_at TEXT;
ALTER TABLE stock ADD COLUMN deleted_at TEXT;
ALTER TABLE stock_movements ADD COLUMN deleted_at TEXT;
ALTER TABLE pulled_staging_tags ADD COLUMN deleted_at TEXT;

-- Jobs & Labor
ALTER TABLE jobs ADD COLUMN deleted_at TEXT;
ALTER TABLE job_parts ADD COLUMN deleted_at TEXT;
ALTER TABLE labor_entries ADD COLUMN deleted_at TEXT;
ALTER TABLE clock_out_responses ADD COLUMN deleted_at TEXT;
ALTER TABLE one_time_questions ADD COLUMN deleted_at TEXT;
ALTER TABLE daily_reports ADD COLUMN deleted_at TEXT;

-- Notebooks
ALTER TABLE notebook_templates ADD COLUMN deleted_at TEXT;
ALTER TABLE template_sections ADD COLUMN deleted_at TEXT;
ALTER TABLE template_entries ADD COLUMN deleted_at TEXT;
ALTER TABLE notebooks ADD COLUMN deleted_at TEXT;
ALTER TABLE notebook_sections ADD COLUMN deleted_at TEXT;
ALTER TABLE notebook_entries ADD COLUMN deleted_at TEXT;
ALTER TABLE notebook_entry_permissions ADD COLUMN deleted_at TEXT;
ALTER TABLE task_order_links ADD COLUMN deleted_at TEXT;

-- Orders
ALTER TABLE job_parts_orders ADD COLUMN deleted_at TEXT;
ALTER TABLE jpo_line_items ADD COLUMN deleted_at TEXT;
ALTER TABLE purchase_orders ADD COLUMN deleted_at TEXT;
ALTER TABLE po_line_items ADD COLUMN deleted_at TEXT;
ALTER TABLE returns ADD COLUMN deleted_at TEXT;
ALTER TABLE return_line_items ADD COLUMN deleted_at TEXT;
ALTER TABLE special_items ADD COLUMN deleted_at TEXT;
ALTER TABLE job_preferences ADD COLUMN deleted_at TEXT;

-- Fleet, Tools & Scheduling
ALTER TABLE vehicles ADD COLUMN deleted_at TEXT;
ALTER TABLE vehicle_assignments ADD COLUMN deleted_at TEXT;
ALTER TABLE tools ADD COLUMN deleted_at TEXT;
ALTER TABLE kit_templates ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_movements ADD COLUMN deleted_at TEXT;
ALTER TABLE kit_verification_sessions ADD COLUMN deleted_at TEXT;
ALTER TABLE kit_verification_items ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_maintenance_types ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_maintenance_schedules ADD COLUMN deleted_at TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN deleted_at TEXT;
ALTER TABLE customers ADD COLUMN deleted_at TEXT;
ALTER TABLE general_contractors ADD COLUMN deleted_at TEXT;
ALTER TABLE employee_default_schedules ADD COLUMN deleted_at TEXT;
ALTER TABLE schedule_exceptions ADD COLUMN deleted_at TEXT;
ALTER TABLE job_dispatch ADD COLUMN deleted_at TEXT;
ALTER TABLE subcontractor_schedules ADD COLUMN deleted_at TEXT;

-- Chat
ALTER TABLE chat_channels ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_channel_members ADD COLUMN deleted_at TEXT;
ALTER TABLE qa_threads ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_messages ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_read_receipts ADD COLUMN deleted_at TEXT;
ALTER TABLE chat_mentions ADD COLUMN deleted_at TEXT;
ALTER TABLE rfi_objects ADD COLUMN deleted_at TEXT;

-- ═══════════════════════════════════════════════════════════════════
-- PART 2: Sync infrastructure tables
-- ═══════════════════════════════════════════════════════════════════

-- Conflict log — records every LWW overwrite so admins can review
CREATE TABLE IF NOT EXISTS _conflict_log (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name    TEXT    NOT NULL,
    record_id     TEXT    NOT NULL,
    field_name    TEXT    NOT NULL,
    local_value   TEXT,
    remote_value  TEXT,
    winner        TEXT    NOT NULL CHECK (winner IN ('local', 'remote')),
    local_device  TEXT    NOT NULL,
    remote_device TEXT    NOT NULL,
    local_ts      TEXT    NOT NULL,
    remote_ts     TEXT    NOT NULL,
    resolved_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    reviewed      INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_conflict_log_table ON _conflict_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_conflict_log_unreviewed ON _conflict_log(reviewed) WHERE reviewed = 0;

-- Vector clock — tracks what each peer device has already seen
-- Enables efficient delta sync (only send changes the other device hasn't seen)
CREATE TABLE IF NOT EXISTS _vector_clock (
    device_id     TEXT    NOT NULL,
    peer_id       TEXT    NOT NULL,
    last_sequence INTEGER NOT NULL DEFAULT 0,
    updated_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (device_id, peer_id)
);

-- Device registry — known peer devices for sync
CREATE TABLE IF NOT EXISTS _device_registry (
    device_id      TEXT PRIMARY KEY,
    device_name    TEXT,
    platform       TEXT,
    role           TEXT    CHECK (role IN ('office', 'field', 'admin')),
    certificate    TEXT,
    last_seen_at   TEXT,
    last_sync_at   TEXT,
    is_trusted     INTEGER NOT NULL DEFAULT 0,
    is_deactivated INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Add sequence number to change log for vector clock sync
ALTER TABLE _change_log ADD COLUMN sequence INTEGER;

-- Create auto-incrementing sequence trigger for change log
-- (sequence is device-local, monotonically increasing)
CREATE TRIGGER IF NOT EXISTS trg_change_log_sequence
    AFTER INSERT ON _change_log
    WHEN NEW.sequence IS NULL
BEGIN
    UPDATE _change_log
    SET sequence = (SELECT COALESCE(MAX(sequence), 0) + 1 FROM _change_log)
    WHERE id = NEW.id;
END;
  `,
};
