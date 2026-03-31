# Encrypt LAN Sync Traffic
**GitHub Issue:** #10
**Priority:** Medium
**Estimated effort:** Medium (needs crypto work)

## What's Wrong
Device-to-device sync uses plain HTTP. Data in transit (database contents) is unencrypted. Anyone on the same LAN could sniff sync traffic.

## Context
- Sync is LAN-only (not internet-facing) — reduces risk
- Ed25519 certificate auth already exists in SyncCrypto.swift — requests are signed
- But payload data (the actual rows being synced) is in plaintext

## Options

### Option A: TLS with Self-Signed Certs (recommended) I pick this one
- Generate a self-signed TLS cert per device
- Pin certs during device pairing
- All sync traffic encrypted automatically
- **Effort:** Medium — need to set up TLS on the local HTTP server

### Option B: Application-Layer Encryption
- Use existing Ed25519 keys to derive a shared secret (ECDH)
- Encrypt sync payloads with AES-GCM before sending
- **Effort:** Medium — more manual but doesn't require TLS server config

### Option C: Accept the Risk
- LAN-only, signed requests, physical access required
- Most small shop environments trust their own network
- **Effort:** None

## Decision Needed
Which option fits your security needs? For most small shops, Option C is fine. For shops with customer PII or regulatory requirements, Option A or B.

## Files Involved
- `core/Sources/WiredPartCore/Sync/PeerManager.swift:412` — constructs `http://` URLs
- `core/Sources/WiredPartCore/Sync/SyncEngine.swift:106` — HTTP client
- `core/Sources/WiredPartCore/Sync/SyncServer.swift` — HTTP server
- `core/Sources/WiredPartCore/Sync/SyncCrypto.swift` — existing Ed25519 keys
