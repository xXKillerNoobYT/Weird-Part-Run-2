-- Migration 055: Remote Sync & Cross-Company Sharing (Phase 13)
--
-- Adds:
--   _remote_sync_config       — shop-level internet sync settings (public URL, TLS, proxy)
--   _remote_sync_peers        — known remote shops for shop↔shop or multi-site sync
--   _remote_sync_sessions     — audit trail of internet-based sync sessions
--   _shared_data_log          — per-record audit of cross-company data exchange
--   _redaction_rules          — per-channel field-level redaction rules
--   _file_sync_packages       — exported/imported file-based sync packages
--   ALTER _shared_channels    — auto_expire_days, renewal fields, description
--   ALTER _shared_channel_members — last_sync_at, data_exchange_count
--   Permission: manage_remote_sync

-- ═══════════════════════════════════════════════════════════════════
-- Remote Sync Configuration (per-shop)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _remote_sync_config (
    id              INTEGER PRIMARY KEY CHECK (id = 1),      -- singleton row
    is_enabled      INTEGER NOT NULL DEFAULT 0,
    public_url      TEXT,                                    -- e.g. https://shop.example.com or DDNS
    listen_port     INTEGER DEFAULT 8443,                    -- HTTPS port for remote sync
    tls_cert_path   TEXT,                                    -- path to TLS certificate
    tls_key_path    TEXT,                                    -- path to TLS private key
    proxy_mode      TEXT DEFAULT 'none'
        CHECK(proxy_mode IN ('none','reverse_proxy','vpn','tailscale')),
    proxy_details   TEXT,                                    -- JSON: {upstream_url, trusted_proxies[], etc.}
    rate_limit_rpm  INTEGER DEFAULT 60,                      -- requests per minute per device
    max_payload_kb  INTEGER DEFAULT 5120,                    -- 5 MB default max payload
    require_cert_auth INTEGER DEFAULT 1,                     -- require mutual TLS / device certificate
    allowed_cidrs   TEXT,                                    -- JSON array of allowed IP ranges, NULL = any
    failban_enabled INTEGER DEFAULT 1,
    failban_max_attempts INTEGER DEFAULT 5,
    failban_lockout_minutes INTEGER DEFAULT 30,
    multi_site_role TEXT DEFAULT 'standalone'
        CHECK(multi_site_role IN ('standalone','primary','secondary')),
    primary_shop_url TEXT,                                   -- URL of primary shop (when role = secondary)
    primary_shop_id  TEXT,                                   -- node_id of primary (refs _shop_cluster_nodes)
    sync_interval_minutes INTEGER DEFAULT 15,                -- how often secondaries pull from primary
    compress_payloads INTEGER DEFAULT 1,                     -- gzip sync payloads for bandwidth savings
    media_defer_to_wifi INTEGER DEFAULT 1,                   -- defer media sync to Wi-Fi connections
    updated_at      TEXT DEFAULT (datetime('now')),
    updated_by      INTEGER REFERENCES users(id)
);

-- Seed the singleton config row
INSERT OR IGNORE INTO _remote_sync_config (id) VALUES (1);

-- ═══════════════════════════════════════════════════════════════════
-- Remote Sync Peers (known remote shops)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _remote_sync_peers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id         TEXT NOT NULL UNIQUE,                    -- UUID of the remote shop
    peer_name       TEXT NOT NULL,                           -- human-readable name
    peer_url        TEXT NOT NULL,                           -- HTTPS URL to reach the peer
    peer_type       TEXT NOT NULL DEFAULT 'partner'
        CHECK(peer_type IN ('partner','multi_site','primary','secondary')),
    company_id      TEXT,                                    -- company_id of peer (for cross-company)
    public_key      TEXT,                                    -- peer shop's Ed25519 public key (base64)
    shared_secret   TEXT,                                    -- encrypted shared secret for initial handshake
    is_verified     INTEGER DEFAULT 0,                       -- 1 = peer identity confirmed
    is_active       INTEGER DEFAULT 1,
    last_sync_at    TEXT,
    last_sync_status TEXT DEFAULT 'never'
        CHECK(last_sync_status IN ('never','success','failed','partial')),
    total_syncs     INTEGER DEFAULT 0,
    total_changes_sent  INTEGER DEFAULT 0,
    total_changes_received INTEGER DEFAULT 0,
    error_count     INTEGER DEFAULT 0,
    last_error      TEXT,
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

-- ═══════════════════════════════════════════════════════════════════
-- Remote Sync Sessions (internet sync audit trail)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _remote_sync_sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT NOT NULL UNIQUE,                    -- UUID
    peer_id         TEXT NOT NULL,                           -- _remote_sync_peers.peer_id or device_id
    session_type    TEXT NOT NULL
        CHECK(session_type IN ('device_remote','shop_to_shop','multi_site','file_import','file_export')),
    direction       TEXT NOT NULL CHECK(direction IN ('push','pull','bidirectional')),
    transport       TEXT DEFAULT 'https'
        CHECK(transport IN ('https','vpn','file')),
    status          TEXT DEFAULT 'started'
        CHECK(status IN ('started','authenticating','transferring','applying','completed','failed')),
    changes_sent    INTEGER DEFAULT 0,
    changes_received INTEGER DEFAULT 0,
    conflicts       INTEGER DEFAULT 0,
    bytes_transferred INTEGER DEFAULT 0,
    auth_method     TEXT,                                    -- 'mutual_tls','device_cert','shared_secret','file_key'
    ip_address      TEXT,
    error_message   TEXT,
    started_at      TEXT DEFAULT (datetime('now')),
    completed_at    TEXT,
    duration_ms     INTEGER
);

CREATE INDEX IF NOT EXISTS idx_remote_sessions_peer
    ON _remote_sync_sessions(peer_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_remote_sessions_type
    ON _remote_sync_sessions(session_type, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_remote_sessions_status
    ON _remote_sync_sessions(status) WHERE status != 'completed';

-- ═══════════════════════════════════════════════════════════════════
-- Shared Data Log (cross-company data exchange audit)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _shared_data_log (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    shared_channel_id   INTEGER NOT NULL REFERENCES _shared_channels(id),
    direction           TEXT NOT NULL CHECK(direction IN ('outbound','inbound')),
    table_name          TEXT NOT NULL,
    record_id           INTEGER NOT NULL,
    operation           TEXT NOT NULL CHECK(operation IN ('INSERT','UPDATE','DELETE')),
    redactions_applied  TEXT,                                -- JSON list of redacted field names
    data_hash           TEXT,                                -- SHA-256 of shared payload (integrity)
    peer_id             TEXT,                                -- which peer shop sent/received
    session_id          TEXT,                                -- links to _remote_sync_sessions
    synced_at           TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_shared_data_channel
    ON _shared_data_log(shared_channel_id, synced_at DESC);
CREATE INDEX IF NOT EXISTS idx_shared_data_table
    ON _shared_data_log(table_name, record_id);

-- ═══════════════════════════════════════════════════════════════════
-- Redaction Rules (per-channel field-level redaction)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _redaction_rules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER NOT NULL REFERENCES _shared_channels(id) ON DELETE CASCADE,
    table_name      TEXT NOT NULL,
    field_name      TEXT NOT NULL,
    redaction_type  TEXT NOT NULL DEFAULT 'remove'
        CHECK(redaction_type IN ('remove','mask','hash','truncate','replace')),
    replacement_value TEXT,                                  -- for 'replace' type
    is_active       INTEGER DEFAULT 1,
    created_at      TEXT DEFAULT (datetime('now')),

    UNIQUE(channel_id, table_name, field_name)
);

-- ═══════════════════════════════════════════════════════════════════
-- File-Based Sync Packages
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _file_sync_packages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    package_id      TEXT NOT NULL UNIQUE,                    -- UUID
    package_type    TEXT NOT NULL
        CHECK(package_type IN ('full_export','incremental_export','import')),
    direction       TEXT NOT NULL CHECK(direction IN ('export','import')),
    file_name       TEXT NOT NULL,
    file_path       TEXT,
    file_size_bytes INTEGER DEFAULT 0,
    encryption_method TEXT DEFAULT 'aes-256-gcm',
    key_hint        TEXT,                                    -- hint for decryption key (not the key itself)
    tables_included TEXT,                                    -- JSON list of table names
    record_count    INTEGER DEFAULT 0,
    changes_since   TEXT,                                    -- timestamp cutoff for incremental
    changes_until   TEXT,                                    -- latest change included
    status          TEXT DEFAULT 'created'
        CHECK(status IN ('created','exporting','encrypted','ready','importing','applied','failed','expired')),
    created_by      INTEGER REFERENCES users(id),
    applied_by      INTEGER REFERENCES users(id),
    applied_at      TEXT,
    error_message   TEXT,
    expires_at      TEXT,                                    -- file auto-cleanup date
    created_at      TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_file_sync_status
    ON _file_sync_packages(status);

-- ═══════════════════════════════════════════════════════════════════
-- Extend _shared_channels with auto-expire and description
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE _shared_channels ADD COLUMN description TEXT;
ALTER TABLE _shared_channels ADD COLUMN auto_expire_days INTEGER;        -- auto-renew window, NULL = manual
ALTER TABLE _shared_channels ADD COLUMN last_renewed_at TEXT;
ALTER TABLE _shared_channels ADD COLUMN renewed_by INTEGER REFERENCES users(id);
ALTER TABLE _shared_channels ADD COLUMN revoked_at TEXT;
ALTER TABLE _shared_channels ADD COLUMN revoked_by INTEGER REFERENCES users(id);
ALTER TABLE _shared_channels ADD COLUMN revoke_reason TEXT;

-- ═══════════════════════════════════════════════════════════════════
-- Extend _shared_channel_members with sync tracking
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE _shared_channel_members ADD COLUMN last_sync_at TEXT;
ALTER TABLE _shared_channel_members ADD COLUMN data_sent_count INTEGER DEFAULT 0;
ALTER TABLE _shared_channel_members ADD COLUMN data_received_count INTEGER DEFAULT 0;

-- ═══════════════════════════════════════════════════════════════════
-- Fail2ban tracking for remote sync
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _remote_failban (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    ip_address      TEXT NOT NULL,
    failure_count   INTEGER DEFAULT 1,
    first_failure   TEXT DEFAULT (datetime('now')),
    last_failure    TEXT DEFAULT (datetime('now')),
    locked_until    TEXT,                                    -- NULL = not locked
    reason          TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_failban_ip
    ON _remote_failban(ip_address);

-- ═══════════════════════════════════════════════════════════════════
-- Permission for remote sync management
-- ═══════════════════════════════════════════════════════════════════
INSERT OR IGNORE INTO permissions (key, label, description, category)
VALUES ('manage_remote_sync', 'Manage Remote Sync',
        'Configure internet sync, manage remote peers, shared channels, and file sync packages',
        'admin');

-- Grant to Admin and Manager hats
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_id)
SELECT h.id, p.id FROM hats h, permissions p
WHERE h.name = 'Admin' AND p.key = 'manage_remote_sync';

INSERT OR IGNORE INTO hat_permissions (hat_id, permission_id)
SELECT h.id, p.id FROM hats h, permissions p
WHERE h.name = 'Manager' AND p.key = 'manage_remote_sync';

-- Add remote sync log types to retention config
INSERT OR IGNORE INTO _log_retention_config (log_type, device_retention_days, shop_retention_days) VALUES
    ('remote_sync_sessions', 90, 365),
    ('shared_data_log',      90, 365),
    ('file_sync_packages',   30, 180),
    ('remote_failban',       30, 90);
