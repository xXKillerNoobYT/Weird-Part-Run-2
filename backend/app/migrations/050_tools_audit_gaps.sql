-- =============================================================
-- MIGRATION 050: Tools Audit Gaps
-- Closes remaining audit items:
--   1. Tool Transfer — atomic endpoint (no schema, just service)
--   2. Tool Photos UI — (frontend only, photo_path already exists)
--   3. Tool Depreciation — full module with multiple methods
--   4. Tool Calibration — enhanced calibration tracking via maintenance
--   5. Barcode Support — Code128 alongside QR (frontend only)
--   6. Tool Reports/Export — CSV export endpoint
--   7. Todo-Tool Linking — link tools to notebook task entries
-- =============================================================


-- ═══ 1. DEPRECIATION FIELDS ON TOOLS ═════════════════════════════════
-- Add depreciation configuration to each tool.

ALTER TABLE tools ADD COLUMN depreciation_method TEXT
    CHECK (depreciation_method IS NULL OR depreciation_method IN (
        'straight_line', 'declining_balance', 'sum_of_years'
    ));

ALTER TABLE tools ADD COLUMN salvage_value REAL DEFAULT 0;

ALTER TABLE tools ADD COLUMN useful_life_years INTEGER;


-- ═══ 2. DEPRECIATION ENTRIES — Annual schedule ═══════════════════════
-- Pre-computed depreciation rows per year for each tool.
-- Generated/recalculated on demand by the depreciation service.

CREATE TABLE IF NOT EXISTS tool_depreciation_entries (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    year_number         INTEGER NOT NULL,                 -- 1, 2, 3, ...
    fiscal_year         TEXT    NOT NULL,                 -- "2024", "2025"
    beginning_value     REAL    NOT NULL,                 -- book value at start of year
    depreciation_amount REAL    NOT NULL,                 -- amount depreciated this year
    accumulated         REAL    NOT NULL,                 -- total depreciation to date
    ending_value        REAL    NOT NULL,                 -- book value at end of year
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tool_id, year_number)
);

CREATE INDEX IF NOT EXISTS idx_tool_depr_tool ON tool_depreciation_entries(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_depr_year ON tool_depreciation_entries(fiscal_year);


-- ═══ 3. CALIBRATION ENHANCEMENTS ON MAINTENANCE RECORDS ══════════════
-- Additional fields for calibration-type maintenance records.
-- Tracks certificate info and calibration standards.

ALTER TABLE tool_maintenance_records ADD COLUMN calibration_certificate TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_provider TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_standard TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_result TEXT
    CHECK (calibration_result IS NULL OR calibration_result IN (
        'pass', 'fail', 'adjusted', 'out_of_tolerance'
    ));

-- Convenience column: next calibration due date, auto-updated
-- when a calibration-type maintenance is logged.
ALTER TABLE tools ADD COLUMN calibration_due_date TEXT;


-- ═══ 4. TODO-TOOL LINKING ════════════════════════════════════════════
-- Junction table linking notebook task entries to required tools.
-- "Before this todo, grab these tools."

CREATE TABLE IF NOT EXISTS notebook_entry_tools (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id    INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    tool_id     INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    notes       TEXT,                                     -- "Need the 3/4 die"
    created_by  INTEGER NOT NULL REFERENCES users(id),
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(entry_id, tool_id)
);

CREATE INDEX IF NOT EXISTS idx_nb_entry_tools_entry ON notebook_entry_tools(entry_id);
CREATE INDEX IF NOT EXISTS idx_nb_entry_tools_tool  ON notebook_entry_tools(tool_id);
