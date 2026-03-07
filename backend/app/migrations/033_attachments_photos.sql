-- 033: Order attachments + tool photos
-- GAP-025: Order attachments (photos, docs, slips)
-- GAP-034: Tool photo support

-- ── Order Attachments ───────────────────────────────────────────
-- Polymorphic attachments for JPOs, POs, and Returns.

CREATE TABLE IF NOT EXISTS order_attachments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL CHECK(entity_type IN ('jpo', 'po', 'return')),
    entity_id   INTEGER NOT NULL,
    file_path   TEXT    NOT NULL,
    file_name   TEXT    NOT NULL,
    file_type   TEXT,              -- MIME type (image/jpeg, application/pdf, etc.)
    file_size   INTEGER,           -- bytes
    description TEXT,
    uploaded_by INTEGER REFERENCES users(id),
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_attachments_entity
    ON order_attachments(entity_type, entity_id);

-- ── Tool Photos ─────────────────────────────────────────────────
-- Add photo_path to tools table (already has columns for most fields)

ALTER TABLE tools ADD COLUMN photo_path TEXT;

-- ── Certification Documents ────────────────────────────────────
-- GAP-031: Add document_path for scanned certificates

ALTER TABLE certifications ADD COLUMN document_path TEXT;
