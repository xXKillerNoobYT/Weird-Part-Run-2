-- =============================================================
-- MIGRATION 038: Chat & Q&A System
-- =============================================================
-- Phase 9: Offline-first messaging with Q&A escalation chain.
-- 7 tables: chat_channels, chat_channel_members, qa_threads,
--           chat_messages, chat_read_receipts, chat_mentions,
--           rfi_objects
-- Sync: BaseRepo._track_change() handles _shop_change_log
--        automatically — no SQL triggers needed.
-- =============================================================


-- ═══════════════════════════════════════════════════════════════
-- 1. CHAT CHANNELS — one per job (auto-created), plus DMs
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_channels (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_type    TEXT    NOT NULL CHECK(channel_type IN ('job', 'dm', 'general')),
    job_id          INTEGER REFERENCES jobs(id),           -- non-null for job channels
    name            TEXT,                                    -- display name (null for DMs)
    created_by      INTEGER REFERENCES users(id),
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(channel_type, job_id)                            -- one channel per job
);

CREATE INDEX IF NOT EXISTS idx_chat_channels_job   ON chat_channels(job_id);
CREATE INDEX IF NOT EXISTS idx_chat_channels_type  ON chat_channels(channel_type);


-- ═══════════════════════════════════════════════════════════════
-- 2. CHANNEL MEMBERSHIP — who can see what
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_channel_members (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id  INTEGER NOT NULL REFERENCES chat_channels(id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    role        TEXT    DEFAULT 'member' CHECK(role IN ('member', 'admin')),
    muted_until TEXT,                                       -- null = not muted
    joined_at   TEXT    DEFAULT (datetime('now')),
    UNIQUE(channel_id, user_id)
);


-- ═══════════════════════════════════════════════════════════════
-- 3. Q&A THREADS — structured escalation tracking
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS qa_threads (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER NOT NULL REFERENCES chat_channels(id),
    job_id          INTEGER REFERENCES jobs(id),
    asked_by        INTEGER NOT NULL REFERENCES users(id),
    subject         TEXT    NOT NULL,
    current_level   TEXT    NOT NULL DEFAULT 'worker'
        CHECK(current_level IN ('worker', 'lead', 'foreman', 'supervisor', 'office')),
    assigned_to     INTEGER REFERENCES users(id),
    status          TEXT    NOT NULL DEFAULT 'open'
        CHECK(status IN ('open', 'escalated', 'answered', 'sent_to_gc', 'closed')),
    priority        TEXT    DEFAULT 'normal'
        CHECK(priority IN ('low', 'normal', 'urgent')),
    answered_by     INTEGER REFERENCES users(id),
    answered_at     TEXT,
    closed_at       TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_qa_threads_job      ON qa_threads(job_id, status);
CREATE INDEX IF NOT EXISTS idx_qa_threads_assigned  ON qa_threads(assigned_to, status);


-- ═══════════════════════════════════════════════════════════════
-- 4. MESSAGES — the core message table
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_messages (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id       INTEGER NOT NULL REFERENCES chat_channels(id) ON DELETE CASCADE,
    sender_id        INTEGER NOT NULL REFERENCES users(id),
    message_type     TEXT    NOT NULL DEFAULT 'text'
        CHECK(message_type IN ('text', 'photo', 'file', 'system',
                                'qa_question', 'qa_answer', 'qa_escalation')),
    content          TEXT,                                   -- text content or caption
    media_path       TEXT,                                   -- relative path to photo/file
    media_mime_type  TEXT,
    media_size_bytes INTEGER,
    reply_to_id      INTEGER REFERENCES chat_messages(id),   -- threading
    pinned_at        TEXT,                                   -- null = not pinned
    pinned_by        INTEGER REFERENCES users(id),
    edited_at        TEXT,                                   -- null = never edited
    deleted_at       TEXT,                                   -- soft delete
    created_at       TEXT    DEFAULT (datetime('now')),

    -- Q&A specific (null for regular chat messages)
    qa_thread_id     INTEGER REFERENCES qa_threads(id),
    qa_level         TEXT    CHECK(qa_level IN ('worker', 'lead', 'foreman', 'supervisor', 'office'))
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_channel    ON chat_messages(channel_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender     ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_qa_thread  ON chat_messages(qa_thread_id);


-- ═══════════════════════════════════════════════════════════════
-- 5. READ RECEIPTS — who has seen what
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_read_receipts (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id           INTEGER NOT NULL REFERENCES chat_channels(id) ON DELETE CASCADE,
    user_id              INTEGER NOT NULL REFERENCES users(id),
    last_read_message_id INTEGER REFERENCES chat_messages(id),
    read_at              TEXT    DEFAULT (datetime('now')),
    UNIQUE(channel_id, user_id)
);


-- ═══════════════════════════════════════════════════════════════
-- 6. @MENTIONS
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_mentions (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id        INTEGER NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
    mentioned_user_id INTEGER NOT NULL REFERENCES users(id),
    acknowledged_at   TEXT                                   -- null = unacknowledged
);

CREATE INDEX IF NOT EXISTS idx_chat_mentions_user ON chat_mentions(mentioned_user_id, acknowledged_at);


-- ═══════════════════════════════════════════════════════════════
-- 7. RFI OBJECTS — GC communication (placeholder for Phase 13)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS rfi_objects (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    qa_thread_id    INTEGER NOT NULL REFERENCES qa_threads(id),
    job_id          INTEGER NOT NULL REFERENCES jobs(id),
    gc_contact_id   INTEGER REFERENCES contacts(id),
    subject         TEXT    NOT NULL,
    body            TEXT    NOT NULL,                        -- formatted question + context
    status          TEXT    NOT NULL DEFAULT 'draft'
        CHECK(status IN ('draft', 'sent_text', 'sent_email', 'sent_app', 'answered', 'closed')),
    sent_via        TEXT    CHECK(sent_via IN ('sms', 'email', 'app')),
    sent_at         TEXT,
    response_text   TEXT,
    responded_at    TEXT,
    created_by      INTEGER NOT NULL REFERENCES users(id),
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════
-- PERMISSIONS
-- ═══════════════════════════════════════════════════════════════

-- use_chat: Send/receive messages — all users
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'use_chat' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- manage_channels: Create/delete channels, manage members — office only
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'manage_channels' FROM hats WHERE name IN ('Admin', 'Manager');

-- ask_qa: Ask Q&A questions — all users
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'ask_qa' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- escalate_qa: Escalate Q&A threads up the chain — all users
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'escalate_qa' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- answer_qa: Answer Q&A threads — all users (gated by assignment logic)
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'answer_qa' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- send_rfi: Send RFIs to GCs — office only
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'send_rfi' FROM hats WHERE name IN ('Admin', 'Manager');

-- view_all_qa: View all Q&A threads across all jobs — office only
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'view_all_qa' FROM hats WHERE name IN ('Admin', 'Manager');
