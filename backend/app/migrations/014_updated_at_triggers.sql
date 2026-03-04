-- ═══════════════════════════════════════════════════════════════════════
-- Migration 014: Auto-update updated_at Triggers
--
-- SQLite's DEFAULT only fires on INSERT. Without triggers, updated_at
-- columns stay frozen at creation time unless explicitly SET in SQL.
--
-- This migration adds AFTER UPDATE triggers for every table that has
-- an updated_at column. The trigger sets updated_at = datetime('now')
-- on any row modification, ensuring timestamps always stay current
-- regardless of whether the application code remembers to set it.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Foundation tables (001) ──────────────────────────────────────

CREATE TRIGGER IF NOT EXISTS trg_users_updated_at
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE users SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_settings_updated_at
    AFTER UPDATE ON settings
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE settings SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ─── Parts & Inventory tables (002) ──────────────────────────────

CREATE TRIGGER IF NOT EXISTS trg_part_categories_updated_at
    AFTER UPDATE ON part_categories
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE part_categories SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_part_styles_updated_at
    AFTER UPDATE ON part_styles
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE part_styles SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_part_types_updated_at
    AFTER UPDATE ON part_types
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE part_types SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_brands_updated_at
    AFTER UPDATE ON brands
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE brands SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_suppliers_updated_at
    AFTER UPDATE ON suppliers
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE suppliers SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_parts_updated_at
    AFTER UPDATE ON parts
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE parts SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_stock_updated_at
    AFTER UPDATE ON stock
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE stock SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ─── Companions tables (007) ─────────────────────────────────────

CREATE TRIGGER IF NOT EXISTS trg_companion_rules_updated_at
    AFTER UPDATE ON companion_rules
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE companion_rules SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ─── Jobs & Labor tables (009) ───────────────────────────────────

CREATE TRIGGER IF NOT EXISTS trg_jobs_updated_at
    AFTER UPDATE ON jobs
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE jobs SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ─── Clock-Out & Reports tables (010) ────────────────────────────

CREATE TRIGGER IF NOT EXISTS trg_clock_out_questions_updated_at
    AFTER UPDATE ON clock_out_questions
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE clock_out_questions SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ─── Notebooks tables (013) ──────────────────────────────────────

CREATE TRIGGER IF NOT EXISTS trg_notebook_templates_updated_at
    AFTER UPDATE ON notebook_templates
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE notebook_templates SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_notebooks_updated_at
    AFTER UPDATE ON notebooks
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE notebooks SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_notebook_entries_updated_at
    AFTER UPDATE ON notebook_entries
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE notebook_entries SET updated_at = datetime('now') WHERE id = NEW.id;
END;
