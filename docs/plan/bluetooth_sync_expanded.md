# Bluetooth Sync — Expanded Plan for AI/Scanning Data

> **Created:** 2026-03-15
> **Phase:** 12+ (AI Integration Extension)
> **Dependencies:** Phase 2 (Sync Engine), All new AI capability plans
> **Constraint:** Bluetooth is the only allowed device-to-device communication channel (plus LAN HTTP).

---

## Overview

Expand the existing Bluetooth/LAN sync protocol to handle new data types introduced by the AI integration features: scanned document images, OCR extraction results, part reference images, and camera match results. Defines chunked binary transfer, priority ordering, conflict resolution for AI-generated data, and bandwidth management.

---

## New Sync Data Types

| Data Type | Source | Size Range | Sync Priority | Sync Method |
|-----------|--------|-----------|---------------|-------------|
| OCR extraction results | Document scanning | 1–5 KB | High | Normal record sync |
| Scanned document images | Document scanning | 200 KB–2 MB | Low | Chunked binary sync |
| Part reference images | Camera matching | 100 KB–1 MB | Medium | Chunked binary sync |
| Image match results | Camera matching | < 1 KB | High | Normal record sync |
| Form data from QR scans | QR auto-fill | < 1 KB | High | Normal record sync |
| AI configuration settings | Settings | < 1 KB | Normal | Normal record sync |
| Text prediction history | Predictive typing | N/A | **Never** | Local-only (privacy) |

---

## Chunked Binary Transfer Protocol

For binary data (images) that exceeds the Bluetooth MTU:

### Frame Format

```
┌────────────────────────────────────────────────┐
│  Header (32 bytes)                              │
│  ├─ magic: [0x57, 0x50, 0x42, 0x54]  (4B)     │  "WPBT" = WiredPart Binary Transfer
│  ├─ transfer_id: UUID                  (16B)    │
│  ├─ chunk_index: UInt16                (2B)     │
│  ├─ total_chunks: UInt16               (2B)     │
│  ├─ chunk_size: UInt32                 (4B)     │
│  ├─ total_size: UInt32                 (4B)     │
│  └─ reserved: [0x00]                   (0B)     │
├────────────────────────────────────────────────┤
│  Payload (up to 16,352 bytes)                   │
│  Raw binary data for this chunk                 │
├────────────────────────────────────────────────┤
│  Checksum (4 bytes)                             │
│  CRC32 of header + payload                      │
└────────────────────────────────────────────────┘

Total frame size: ≤ 16,384 bytes (16 KB)
```

### Transfer Flow

```
Device A (sender)                    Device B (receiver)
    │                                      │
    ├─── TRANSFER_START ─────────────────►│
    │    {transfer_id, total_size,         │
    │     total_chunks, content_type,      │
    │     record_table, record_id}         │
    │                                      │
    │◄── TRANSFER_ACK ───────────────────┤
    │    {transfer_id, ready: true}        │
    │                                      │
    ├─── CHUNK[0] ───────────────────────►│
    │◄── CHUNK_ACK[0] ──────────────────┤
    ├─── CHUNK[1] ───────────────────────►│
    │◄── CHUNK_ACK[1] ──────────────────┤
    │    ...                               │
    ├─── CHUNK[N-1] ─────────────────────►│
    │◄── CHUNK_ACK[N-1] ────────────────┤
    │                                      │
    │◄── TRANSFER_COMPLETE ──────────────┤
    │    {transfer_id, hash_verified: T/F} │
    │                                      │
```

### Retry Logic

- Per-chunk retry: 3 attempts with 500ms backoff
- Full transfer retry: 2 attempts if hash verification fails
- Transfer timeout: 5 minutes per transfer (configurable)
- Failed transfers logged to `_sync_transfer_log` for diagnostics

---

## Priority Queue

Sync operations are prioritized to ensure critical data transfers first:

```
Priority 0 (Critical):  Conflict resolution messages
Priority 1 (High):      Record changes (normal CRUD sync)
Priority 2 (High):      OCR extraction results, QR scan data
Priority 3 (Medium):    Part reference images (for catalog indexing)
Priority 4 (Low):       Scanned document images (large, deferrable)
Priority 5 (Background): Bulk image backfill (initial sync of all images)
```

### Bandwidth Management

| Connection Type | Max Concurrent Transfers | Chunk Rate |
|----------------|------------------------|------------|
| Multipeer (BT) | 1 | 16 KB / 200ms |
| Multipeer (Wi-Fi P2P) | 3 | 16 KB / 50ms |
| LAN HTTP | 5 | 64 KB / 10ms |

### Queue Processing

```swift
actor SyncPriorityQueue {
    private var queues: [Priority: [SyncTask]] = [:]

    /// Enqueue a sync task with priority
    func enqueue(_ task: SyncTask, priority: Priority)

    /// Dequeue the highest-priority task
    func dequeueNext() -> SyncTask?

    /// Check if any binary transfers are pending
    func pendingBinaryTransferCount() -> Int

    /// Cancel all transfers for a given record
    func cancel(forRecordId: String, table: String)
}

enum Priority: Int, Comparable {
    case critical = 0
    case high = 1
    case medium = 3
    case low = 4
    case background = 5
}
```

---

## Image Sync Strategy

### Scanned Document Images

1. User scans a document → OCR processes it → extraction results saved
2. **Extraction results** sync immediately (small JSON, Priority 2)
3. **Source image** queued for sync (large binary, Priority 4)
4. If image hasn't synced yet, receiving device shows "Image pending sync" placeholder
5. On next sync session, images transfer in background

### Part Reference Images

1. User saves a reference photo for a part
2. **Part record update** syncs immediately (Priority 1)
3. **Reference image** queued for sync (Priority 3)
4. Receiving device recomputes feature vector from synced image
5. Feature index updated incrementally

### Deduplication

- Images identified by SHA-256 hash
- Before transfer: check if receiver already has image (by hash)
- Skip transfer if hash matches (common after multi-device sync chains)

---

## Conflict Resolution for AI Data

### OCR Extraction Results

| Conflict Scenario | Resolution |
|-------------------|------------|
| Two devices scan same document | LWW — most recent scan wins |
| User edits OCR-extracted field on Device A, Device B has original | Normal field-level LWW |
| Two devices process same image differently | LWW based on processing timestamp |

### Part Reference Images

| Conflict Scenario | Resolution |
|-------------------|------------|
| Two devices upload different reference images for same part | **Keep both** — multiple references improve matching |
| Same image uploaded from two devices | Deduplicated by SHA-256 hash |
| One device deletes reference, another adds one | DELETE wins if timestamp is later; otherwise new image preserved |

### QR Scan Results

No conflicts — QR scans produce new records (receiving line items, clock-ins, etc.) that follow normal sync rules.

---

## Database Changes

### New Tables for Binary Sync

```sql
-- Tracks binary attachment records
CREATE TABLE _binary_attachments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_table TEXT NOT NULL,          -- e.g., 'parts', 'daily_reports'
    record_id INTEGER NOT NULL,
    attachment_type TEXT NOT NULL,       -- 'scanned_document', 'reference_image', 'photo'
    file_path TEXT NOT NULL,            -- local file path
    file_hash TEXT NOT NULL,            -- SHA-256
    file_size INTEGER NOT NULL,         -- bytes
    mime_type TEXT NOT NULL,            -- 'image/jpeg', 'image/png'
    synced_to TEXT DEFAULT '[]',        -- JSON array of device_ids that have this file
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_ba_record ON _binary_attachments(record_table, record_id);
CREATE INDEX idx_ba_hash ON _binary_attachments(file_hash);

-- Tracks in-progress binary transfers
CREATE TABLE _sync_transfer_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transfer_id TEXT NOT NULL UNIQUE,   -- UUID
    direction TEXT NOT NULL,            -- 'send' or 'receive'
    peer_device_id TEXT NOT NULL,
    attachment_id INTEGER REFERENCES _binary_attachments(id),
    total_size INTEGER NOT NULL,
    transferred_size INTEGER DEFAULT 0,
    total_chunks INTEGER NOT NULL,
    completed_chunks INTEGER DEFAULT 0,
    status TEXT NOT NULL,               -- 'pending', 'in_progress', 'completed', 'failed'
    error_message TEXT,
    started_at DATETIME,
    completed_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_stl_status ON _sync_transfer_log(status);
```

---

## Sync Protocol Extensions

### New Message Types

Added to the existing sync protocol JSON schema:

```json
{
  "type": "binary_manifest",
  "device_id": "device-abc",
  "attachments": [
    {
      "id": 1,
      "record_table": "parts",
      "record_id": 42,
      "attachment_type": "reference_image",
      "file_hash": "sha256:abc123...",
      "file_size": 524288,
      "mime_type": "image/jpeg"
    }
  ]
}
```

```json
{
  "type": "binary_request",
  "device_id": "device-xyz",
  "requested_hashes": ["sha256:abc123...", "sha256:def456..."]
}
```

### Sync Session Flow (Extended)

```
1. Normal record sync (push/pull changes)
   ↓
2. Binary manifest exchange
   - Each device sends list of attachments it has
   - Each device identifies which it's missing
   ↓
3. Binary request
   - Receiving device requests missing attachments by hash
   ↓
4. Chunked binary transfers (priority-ordered)
   - Transfers happen in background
   - Record sync continues unblocked
   ↓
5. Completion confirmation
   - Update `synced_to` arrays
```

---

## Bandwidth Estimation

### Typical Sync Scenarios

| Scenario | Record Data | Binary Data | Total | BT Time | LAN Time |
|----------|------------|-------------|-------|---------|----------|
| Normal daily sync (no images) | 50 KB | 0 | 50 KB | 2s | <1s |
| Sync with 5 scanned documents | 55 KB | 5 MB | ~5 MB | 6 min | 5s |
| Sync with 20 part reference images | 60 KB | 10 MB | ~10 MB | 12 min | 10s |
| Initial image backfill (500 parts) | 100 KB | 250 MB | ~250 MB | 5 hrs | 4 min |
| Daily sync with 2 scans + 3 photos | 55 KB | 4 MB | ~4 MB | 5 min | 4s |

### Recommendations

- **BT**: Automatic for records; user-initiated for bulk images ("Sync Images Now")
- **LAN**: Automatic for everything (fast enough)
- **Initial backfill**: Prompt user to use LAN for first image sync
- **Progress indicator**: Show transfer progress for binary syncs

---

## User-Facing Sync Status

### Sync Status View (Enhanced)

```
┌────────────────────────────────┐
│ Sync Status                     │
├────────────────────────────────┤
│ Records: ✅ Up to date          │
│ Images:  🔄 3 of 8 synced      │
│          ████████░░░░ 37%       │
│                                 │
│ Pending Transfers:              │
│  📄 Delivery scan (1.2 MB)     │
│  📷 Part ref: ELB-90 (450 KB)  │
│  📷 Part ref: TEE-2IN (380 KB) │
│                                 │
│ [Sync Images Now] [Skip Images] │
└────────────────────────────────┘
```

---

## Error Handling

| Error | Detection | Recovery |
|-------|-----------|----------|
| Transfer interrupted (out of range) | Chunk ACK timeout | Resume from last successful chunk on reconnect |
| Hash mismatch after transfer | CRC32 or SHA-256 verification | Re-transfer entire file |
| Disk full on receiver | Write failure during reassembly | Alert user; skip image; continue record sync |
| Corrupt chunk received | CRC32 check | Request re-send of specific chunk |
| Transfer stuck (no progress > 60s) | Watchdog timer | Cancel and re-queue |

---

## Acceptance Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Record sync unblocked by binary transfers | Records sync within 5s regardless of pending images | Test with 100MB pending images |
| Chunked transfer reliability | ≥ 99% success rate over BT | 100 transfer tests |
| Resume after disconnect | Transfer resumes within 10s of reconnection | Simulate 5 disconnect/reconnect cycles |
| Deduplication effectiveness | 0 duplicate image transfers | Multi-device chain test (A→B→C) |
| LAN bulk transfer speed | ≥ 5 MB/s | 100MB test file over LAN |
| BT single image transfer | Complete 1MB image in < 90s | 10 transfer tests over BT |
| Priority ordering | Critical/high records always transfer before low images | Mixed workload test |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| BT too slow for image-heavy workflows | High | Medium | Prioritize records; defer images; recommend LAN for bulk |
| Image sync fills device storage | Low | High | Storage quota per device; oldest images pruned first; user warning at 80% |
| Chunked transfer adds sync complexity | Medium | Medium | Extensive integration testing; simple retry logic; detailed transfer logging |
| Multi-device gossip creates transfer storms | Low | Medium | Dedup by hash; `synced_to` tracking prevents redundant sends |
| BT connection instability during large transfers | Medium | Medium | Resume-from-chunk; automatic retry; user can trigger manual "Sync Images" |
