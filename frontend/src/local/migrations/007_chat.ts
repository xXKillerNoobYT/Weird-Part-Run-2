/**
 * Migration 007: Chat & Q&A System
 *
 * Chat channels, messages, read receipts, mentions,
 * Q&A threads with escalation, and RFI objects.
 * Consolidated from: backend migration 038_chat_system.sql
 */

export const migration = {
  name: '007_chat',
  sql: `
-- ═══ CHAT CHANNELS ═══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_channels (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_type    TEXT    NOT NULL DEFAULT 'job'
        CHECK (channel_type IN ('job','dm','group')),
    job_id          INTEGER REFERENCES jobs(id),
    name            TEXT,
    created_by      INTEGER NOT NULL REFERENCES users(id),
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_channels_job ON chat_channels(job_id);
CREATE INDEX IF NOT EXISTS idx_chat_channels_type ON chat_channels(channel_type);

CREATE TABLE IF NOT EXISTS chat_channel_members (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER NOT NULL REFERENCES chat_channels(id),
    user_id         INTEGER NOT NULL REFERENCES users(id),
    role            TEXT    NOT NULL DEFAULT 'member'
        CHECK (role IN ('admin','member','observer')),
    muted_until     TEXT,
    joined_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    left_at         TEXT,
    UNIQUE(channel_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_ccm_channel ON chat_channel_members(channel_id);
CREATE INDEX IF NOT EXISTS idx_ccm_user ON chat_channel_members(user_id);

-- ═══ Q&A THREADS ═════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS qa_threads (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER REFERENCES chat_channels(id),
    job_id          INTEGER NOT NULL REFERENCES jobs(id),
    asked_by        INTEGER NOT NULL REFERENCES users(id),
    subject         TEXT    NOT NULL,
    current_level   TEXT    NOT NULL DEFAULT 'worker'
        CHECK (current_level IN ('worker','lead','foreman','supervisor','office')),
    assigned_to     INTEGER REFERENCES users(id),
    status          TEXT    NOT NULL DEFAULT 'open'
        CHECK (status IN ('open','escalated','answered','closed','rfi_sent')),
    priority        TEXT    NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low','normal','high','urgent')),
    answer_text     TEXT,
    answered_by     INTEGER REFERENCES users(id),
    answered_at     TEXT,
    closed_at       TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_qa_job ON qa_threads(job_id);
CREATE INDEX IF NOT EXISTS idx_qa_status ON qa_threads(status);
CREATE INDEX IF NOT EXISTS idx_qa_assigned ON qa_threads(assigned_to);

-- ═══ CHAT MESSAGES ═══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER NOT NULL REFERENCES chat_channels(id),
    sender_id       INTEGER NOT NULL REFERENCES users(id),
    message_type    TEXT    NOT NULL DEFAULT 'text'
        CHECK (message_type IN ('text','photo','system','qa_question','qa_answer','qa_escalation')),
    content         TEXT,
    media_path      TEXT,
    reply_to_id     INTEGER REFERENCES chat_messages(id),
    pinned_at       TEXT,
    pinned_by       INTEGER REFERENCES users(id),
    qa_thread_id    INTEGER REFERENCES qa_threads(id),
    qa_level        TEXT,
    edited_at       TEXT,
    deleted_at      TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_cm_channel ON chat_messages(channel_id, created_at);
CREATE INDEX IF NOT EXISTS idx_cm_sender ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_cm_qa ON chat_messages(qa_thread_id);

-- ═══ READ RECEIPTS ═══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_read_receipts (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id          INTEGER NOT NULL REFERENCES chat_channels(id),
    user_id             INTEGER NOT NULL REFERENCES users(id),
    last_read_message_id INTEGER NOT NULL,
    read_at             TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(channel_id, user_id)
);

-- ═══ MENTIONS ════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS chat_mentions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id          INTEGER NOT NULL REFERENCES chat_messages(id),
    mentioned_user_id   INTEGER NOT NULL REFERENCES users(id),
    acknowledged_at     TEXT
);
CREATE INDEX IF NOT EXISTS idx_mentions_user ON chat_mentions(mentioned_user_id, acknowledged_at);

-- ═══ RFI OBJECTS ═════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rfi_objects (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    qa_thread_id    INTEGER NOT NULL REFERENCES qa_threads(id),
    job_id          INTEGER NOT NULL REFERENCES jobs(id),
    gc_contact_id   INTEGER,
    subject         TEXT    NOT NULL,
    body            TEXT    NOT NULL,
    status          TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','sent','responded','closed')),
    response_text   TEXT,
    responded_at    TEXT,
    sent_via        TEXT
        CHECK (sent_via IS NULL OR sent_via IN ('sms','email','in_person','other')),
    sent_at         TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_rfi_qa ON rfi_objects(qa_thread_id);
CREATE INDEX IF NOT EXISTS idx_rfi_job ON rfi_objects(job_id);
CREATE INDEX IF NOT EXISTS idx_rfi_status ON rfi_objects(status);
  `,
};
