-- 034: Notebook attachments (files/photos per entry)
-- GAP-040: Attach files and photos to notebook entries.

CREATE TABLE IF NOT EXISTS notebook_attachments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id    INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    file_path   TEXT    NOT NULL,
    file_name   TEXT    NOT NULL,
    file_type   TEXT,              -- MIME type
    file_size   INTEGER,           -- bytes
    uploaded_by INTEGER REFERENCES users(id),
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notebook_attachments_entry
    ON notebook_attachments(entry_id);
