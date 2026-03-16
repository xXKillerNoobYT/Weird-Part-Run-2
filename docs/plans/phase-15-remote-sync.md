# Phase 13: Remote Sync (ON HOLD)

> **Date:** 2026-03-07
> **Status:** 🔒 On Hold — concept-level outline, not scheduled
> **Dependencies:** Phase 11 (Sync/BT) fully working, Phase 9 (Chat), Phase 12 (AI optional)
> **Architecture docs:** `docs/plans/Device Sync management.md`, `docs/plans/Device security protocols.md`
> **Related concept:** Shared channels + cross-company RFI bridge from `docs/plans/Q&A Part of the App`
> **Estimated work:** 15-25 days (highly uncertain — internet sync is complex)

---

## Vision

**Phase 11 gives us LAN + Bluetooth sync.** Devices sync with the shop over Wi-Fi and with each other via BT mesh. This covers the core use case: one shop, one crew, one local network.

**Phase 13 adds internet-based sync** for scenarios where devices or shops need to communicate beyond the local network:

1. **Remote worker sync** — a worker on a distant job site syncs with the shop over the internet
2. **Shop↔Shop sync** — two companies on the same system exchange data (GC↔Sub RFI bridge)
3. **Multi-site company** — one company with shops in multiple locations

This phase is ON HOLD because:
- LAN + BT covers 95% of the daily workflow
- Internet sync introduces authentication, NAT traversal, bandwidth, and security complexity
- The cost-benefit ratio doesn't justify building this before V1.0 is stable
- We need real-world usage data from Phase 11 before designing the internet layer

---

## Planned Capabilities

### 1. Remote Device Sync (Internet)

**Scenario:** A worker is at a remote job site with no LAN access to the shop. They have cellular data.

**Approach:**
- Shop exposes a sync API on a public port (or via reverse proxy / VPN)
- Device connects to shop URL over HTTPS (same sync protocol as LAN, just over internet)
- Encryption: TLS + device certificate mutual auth (same as LAN but stricter)
- Data: Same push/pull protocol. Larger payloads compressed. Media deferred to Wi-Fi.

**Challenges:**
- NAT traversal (shop behind router — needs port forwarding or UPnP)
- Dynamic IP (shop's public IP may change — DDNS or static IP needed)
- Bandwidth (cellular data costs — need smart sync to minimize transfer)
- Security (shop exposed to internet — needs firewall rules, rate limiting, fail2ban)

### 2. Shop↔Shop Sync (Cross-Company)

**Scenario:** A GC shop and a subcontractor shop are both on this system. They need to exchange RFIs, shared job data, and Q&A threads.

**From the concept doc:**
- Only shop↔shop communication (never device↔device cross-company)
- Shared channels define scope (which jobs, what data, what permissions)
- All data sanitized/redacted according to shared channel rules
- Supervisor-level approval required to create shared channels

**New concepts needed:**
- `shared_channel` — defines the scope of sharing between two companies
- `shared_visibility` — per-record tag marking what's visible to the partner
- `shared_redactions` — per-field rules for what gets stripped before sharing

**Protocol:**
```
1. Both companies' shops are on a trusted network (or VPN / internet)
2. GC supervisor + Sub supervisor agree to share (in-person or via secure init)
3. Both log into their own shops → shops exchange company certs (mutual auth)
4. Shared channel created with agreed scope:
   - Job IDs to share
   - Data types (Q&A, RFI, schedule, contact info)
   - Permissions (read-only, read-write, media yes/no)
   - Expiry date
5. Shops sync shared channel data on schedule (hourly? on-demand?)
6. Partner data stored in separate namespace with origin_company_id
7. All actions auditable — who shared what, when, with whom
```

### 3. Multi-Site Company

**Scenario:** A company has two shops (e.g., main office + satellite office). Both need access to the full company dataset.

**Approach:**
- Both shops are in the same "company cluster" (same company_id)
- Sync over internet (VPN preferred) using same protocol as LAN cluster
- One shop designated as "primary" for conflict resolution
- Other shop(s) are "secondary" — sync with primary, can operate independently if disconnected

### 4. File-Based Sync (Fallback)

**Scenario:** No internet, no BT (e.g., extremely remote site). Worker has a laptop or USB drive.

**Approach:**
- Export a sync package (encrypted file) to USB or local file
- Carry to shop → import sync package
- Same change log format, just transported via file instead of network

---

## Security Considerations

### Internet Exposure
- Shop sync API behind reverse proxy (nginx/Caddy) with TLS termination
- Rate limiting: max N requests per device per minute
- Fail2ban: auto-block IPs with repeated auth failures
- Device certificates required for all connections (no anonymous access)
- Company certificates cross-verified for shop↔shop

### Cross-Company Data
- Separate database namespace for partner data
- Redaction engine strips sensitive fields before sharing
- Audit log for all cross-company data exchange
- Shared channels revocable at any time by either party
- Auto-expiry on shared channels (must be renewed)

### Key Exchange for Shop↔Shop
- In-person QR code exchange (most secure)
- Or: both shops verify via phone call + shared secret phrase
- Never over email/text (too interceptable)

---

## Database Additions (Conceptual)

```sql
-- Shared channels for cross-company sync
CREATE TABLE shared_channels (
    id TEXT PRIMARY KEY,
    owner_company_id TEXT NOT NULL,
    partner_company_id TEXT NOT NULL,
    scope_json TEXT NOT NULL,        -- {job_ids: [], data_types: [], permissions: {}}
    created_by_user_id INTEGER,
    approved_by_partner_user_id INTEGER,
    expires_at TEXT,
    revoked_at TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Track what's been shared
CREATE TABLE shared_data_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    shared_channel_id TEXT NOT NULL,
    direction TEXT CHECK(direction IN ('outbound', 'inbound')),
    table_name TEXT NOT NULL,
    record_id INTEGER NOT NULL,
    redactions_applied TEXT,        -- JSON list of redacted fields
    synced_at TEXT DEFAULT (datetime('now'))
);
```

---

## Open Questions (To Resolve Before Building)

1. **NAT traversal strategy:** Port forwarding? UPnP? VPN? Tailscale/ZeroTier?
2. **Dynamic IP handling:** DDNS service? Hardcoded IP? Discovery mechanism?
3. **Bandwidth management:** How much data per sync? Compression? Delta-only?
4. **Multi-site primary election:** What happens if primary shop goes down?
5. **Shared channel granularity:** Per-job? Per-record? Per-field?
6. **Regulatory:** Any data residency concerns with cross-company sharing?
7. **USB sync format:** Encrypted ZIP? Custom binary? SQLite diff file?

---

## Success Criteria (When Built)

- [ ] Remote workers sync over internet (HTTPS + mutual cert auth)
- [ ] Shop firewall/proxy config documented and tested
- [ ] Shop↔Shop sync exchanges RFI data between paired companies
- [ ] Shared channels enforce scope and permissions
- [ ] Data redactions applied before cross-company sharing
- [ ] Multi-site shops sync over VPN with primary/secondary roles
- [ ] File-based sync works as fallback (export → USB → import)
- [ ] All internet sync encrypted end-to-end
- [ ] Audit log tracks all cross-boundary data exchange
- [ ] Shared channels auto-expire and are revocable

---

## Why This Is On Hold

1. **V1.0 doesn't need it.** LAN + BT covers the daily workflow for a single-shop company.
2. **Complexity is high.** Internet sync + security + NAT + cross-company = significant engineering effort.
3. **Need usage data first.** Phase 11 usage will reveal real sync patterns and inform the design.
4. **GC integration is aspirational.** Getting GCs to use the same system is a business development challenge, not just a tech one.
5. **Priority is stability.** Better to have bulletproof local sync than fragile internet sync.
