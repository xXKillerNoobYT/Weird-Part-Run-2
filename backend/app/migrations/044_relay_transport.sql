-- Migration 044: Peer-to-Peer Relay Transport & Delivery Receipts
-- Adds:
--  - _relay_manifests: advertises what undelivered data a device carries
--  - _delivery_receipts: shop-issued confirmations that relayed data arrived
--  - _relay_packages: audit trail of device-to-device data transfers

-- Relay manifests — device advertises what undelivered data it's carrying
-- so peers can decide what to accept. Updated on every sync cycle.
CREATE TABLE IF NOT EXISTS _relay_manifests (
    device_id TEXT PRIMARY KEY REFERENCES _device_registry(device_id) ON DELETE CASCADE,
    pending_change_count INTEGER NOT NULL DEFAULT 0,
    pending_media_count  INTEGER NOT NULL DEFAULT 0,
    change_hashes_json   TEXT,       -- JSON array of change-log hashes for dedup
    media_hashes_json    TEXT,       -- JSON array of media blob hashes for dedup
    origin_device_ids_json TEXT,     -- JSON array of original source device IDs
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Delivery receipts — shop confirms that data originally from device A
-- (relayed through device B, C, ...) has been received and applied.
-- The receipt flows back to the originating device so it can purge.
CREATE TABLE IF NOT EXISTS _delivery_receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    -- Who sent the data originally
    origin_device_id TEXT NOT NULL,
    -- Which device actually delivered it to the shop
    delivered_by_device_id TEXT NOT NULL,
    -- What was delivered
    receipt_type TEXT NOT NULL DEFAULT 'changes'
      CHECK(receipt_type IN ('changes', 'media', 'mixed')),
    change_count INTEGER NOT NULL DEFAULT 0,
    media_count  INTEGER NOT NULL DEFAULT 0,
    -- Hashes for dedup — origin device can match these to purge
    delivered_hashes_json TEXT,
    -- Receipt status: the origin device must acknowledge receipt
    -- so we know it can safely purge its copies
    acknowledged_by_origin INTEGER NOT NULL DEFAULT 0,
    acknowledged_at TEXT,
    -- Timestamps
    issued_at TEXT NOT NULL DEFAULT (datetime('now')),
    -- Optional relay chain (JSON array of device_ids in relay order)
    relay_chain_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_delivery_receipts_origin
  ON _delivery_receipts(origin_device_id, acknowledged_by_origin);

CREATE INDEX IF NOT EXISTS idx_delivery_receipts_delivered_by
  ON _delivery_receipts(delivered_by_device_id, issued_at DESC);

-- Relay packages audit — records data transferred device-to-device.
-- The actual data transfer happens over BT/LAN, this is the audit trail.
CREATE TABLE IF NOT EXISTS _relay_packages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    -- Transfer participants
    sender_device_id   TEXT NOT NULL,
    receiver_device_id TEXT NOT NULL,
    -- What the sender originally got this data from
    origin_device_id   TEXT NOT NULL,
    -- Counts of what was transferred
    change_count INTEGER NOT NULL DEFAULT 0,
    media_count  INTEGER NOT NULL DEFAULT 0,
    -- Integrity
    package_hash TEXT,            -- SHA256 of the package for dedup
    -- Status: 'created' → 'transferred' → 'confirmed'
    status TEXT NOT NULL DEFAULT 'created'
      CHECK(status IN ('created', 'transferred', 'confirmed', 'failed')),
    failure_reason TEXT,
    -- Timestamps
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    transferred_at TEXT,
    confirmed_at   TEXT
);

CREATE INDEX IF NOT EXISTS idx_relay_packages_sender
  ON _relay_packages(sender_device_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_relay_packages_receiver
  ON _relay_packages(receiver_device_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_relay_packages_origin
  ON _relay_packages(origin_device_id, status);
