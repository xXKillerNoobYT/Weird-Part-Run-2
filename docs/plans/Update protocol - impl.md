# Update Protocol — Implementation Plan V1.0.0

> **Status:** ✅ Backend implemented (migration, service, router, tests)
> **Migration:** `043_update_protocol.sql`
> **Service:** `update_protocol_service.py`
> **Router:** `updates.py` (mounted at `/api/updates`)
> **Tests:** `test_update_protocol.py` (4 tests)

---

## 1. Overview

Shop-centric, mesh-propagated update pipeline. Shop PCs are the ONLY devices
that fetch updates from the internet (GitHub releases). They validate in a
sandbox, publish to the field, and track fleet-wide staged rollout. No field
device ever touches GitHub or any app store.

---

## 2. Database Tables

| Table | Purpose |
|-------|---------|
| `_update_registry` | Master list of known versions (semver string, strict chain) |
| `_update_validations` | Per-version, per-platform sandbox test results |
| `_fleet_targets` | Per-platform rollout targets + device counts |
| `_device_update_status` | Per-device installed version + pending queue |
| `_update_backup_snapshots` | Pre-update backup records for rollback safety |

---

## 3. Update Lifecycle

```
GitHub Release
  → Shop PC fetches
    → Sandbox validation (per-platform)
      → Approved? → Publish to fleet
                   → Field devices receive via LAN sync
                     → Mesh relay via Bluetooth
                       → Ordered install on each device
                         → Device reports installed version
                           → Fleet counts refresh
                             → Auto-advance target when all caught up
```

---

## 4. API Endpoints (17 total)

### Version Registry
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/updates/versions` | admin | Register new version |
| GET | `/api/updates/versions` | admin | List all versions |
| GET | `/api/updates/versions/{version}` | user | Get version details |
| POST | `/api/updates/versions/{version}/publish` | admin | Publish to fleet |

### Validation Pipeline
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/updates/validations` | admin | Create/reset validation |
| PUT | `/api/updates/validations` | admin | Update with test results |
| GET | `/api/updates/validations` | admin | List validations |

### Fleet Targets (Per-Platform)
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/updates/fleet` | admin | List all platform targets |
| GET | `/api/updates/fleet/{platform}` | user | Get target for platform |
| PUT | `/api/updates/fleet/{platform}` | admin | Set target for platform |
| POST | `/api/updates/fleet/{platform}/refresh` | admin | Recalculate counts + auto-advance |

### Device Update Status
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/updates/devices/report` | user | Device reports installed version |
| GET | `/api/updates/devices` | admin | List all device statuses |
| GET | `/api/updates/devices/{device_id}` | user | Get device's update status |
| GET | `/api/updates/devices/{device_id}/pending` | user | Get ordered pending updates |

### Backup Snapshots
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/updates/backups` | admin | Record pre-update backup |
| GET | `/api/updates/backups` | admin | List backup snapshots |
| POST | `/api/updates/backups/{id}/restore` | admin | Mark backup as restored |

---

## 5. Strict Version Chain

Every update has:
- `version` — the new version (semver)
- `previous_version` — the ONLY version you can install from

**Device install rule:**
> Install only if `update.previous_version == device.current_version`

This guarantees: no skipping, no corruption, no out-of-order installs.

---

## 6. Per-Platform Validation

Before a version is published, the shop validates it on each platform:

| Check | Description |
|-------|-------------|
| Schema diff | No required fields removed, no breaking type changes |
| Migration test | All rows migrate on a DB copy, no data loss |
| Rollback test | Rollback scripts work cleanly |
| Backward compat | New version accepts old data, ignores unknown fields |

Each check stores a pass/fail flag. All must pass before publishing.

---

## 7. Fleet Rollout Strategy

- **Per-platform fleet targets:** `fleet_target_version_windows`, `_macos`, etc.
- **Staged advance:** Target only moves forward when ALL devices on that platform
  have caught up (or are retired/decommissioned)
- **Auto-advance:** When `auto_advance = true` and all devices are at target,
  fleet automatically steps to the next validated version in the chain

This means:
- Windows and Mac can advance at different paces
- A broken Mac version doesn't block Windows rollout
- No device jumps from v1.3 straight to v2.9

---

## 8. Handling Rapid Updates + Offline Scenarios

### 17 updates while shop is offline:
- Shop can't see them → they don't exist in your ecosystem
- When internet returns, shop pulls and validates one-by-one
- Devices install the chain in order

### Shop only runs Mondays:
- Monday: devices sync, receive any approved updates
- Tue–Sun: devices relay updates via Bluetooth mesh
- Next Monday: shop catches up from GitHub, publishes new approved versions

---

## 9. Backup & Rollback

Before ANY update is applied to the shop:
1. Freeze writes briefly
2. Create full backup (DB + config + binary)
3. Tag with version + timestamp + checksum
4. Only then install

If something breaks:
1. Stop updated app
2. Restore from backup
3. Mark failed update as blocked
4. Generate error report for maintainer

Devices: lightweight backup of previous binary + schema version.
Data is safe because shop holds canonical DB.

---

## 10. Remaining Work (Future)

- [ ] **GitHub release poller** — scheduler job that checks GitHub API for new releases
- [ ] **Sandbox runner** — automated migration test on DB copy
- [ ] **Error email pipeline** — send validation failure reports to maintainer
- [ ] **Frontend admin pages** — version management, fleet dashboard, device status
- [ ] **Mesh update relay** — include update packages in Bluetooth gossip payloads
- [ ] **Rollup update packaging** — combine N migrations into a single rollup for long offline gaps
- [ ] **Per-platform binary packaging** — platform-specific update bundles
