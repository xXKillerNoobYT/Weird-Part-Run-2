# MCP-Native Architecture Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task after Stage 10 is promoted, or earlier only for a specific MCP tool explicitly promoted by Paperclip/Isaac.

**Goal:** Design WiredPart as an MCP-native local-first app so attached LLMs can safely read and, when explicitly enabled, write real app data.

**Architecture:** Keep the primary data authority inside the Swift core and expose MCP through a sidecar process that talks to a narrow, local-only bridge API. The app owns authentication, user/session context, tool enablement, audit logging, and all business-rule validation. The sidecar only adapts MCP JSON-RPC calls into typed bridge requests and never bypasses service-layer permissions.

**Tech Stack:** SwiftUI iOS app, WiredPartCore Swift Package, GRDB/SQLite, Apple Multipeer/local-first sync, MCP JSON-RPC over stdio or loopback HTTP, per-tool settings stored in the existing `settings` table.

---

## Executive decision

Use an **in-app-owned sidecar MCP server** rather than embedding MCP transport directly in the iOS UI process.

The iOS app and `WiredPartCore` remain the source of truth. A small local sidecar handles MCP protocol concerns and forwards every call to a Swift bridge exposed by the running app/core. This keeps MCP optional, runtime-configurable, and sandboxable while preserving the local-first data model.

## ADR: MCP server placement

### Context

WiredPart is a local-first iOS shop-management app. The active beta path is SwiftUI + shared Swift core. Existing AI work already includes Apple Foundation Models tools in `core/Sources/WiredPartCore/AI/AITools.swift`, but those are Foundation Models-specific and not a general MCP surface.

The MCP feature must support external agents such as Claude, Codex, and Hermes while preserving:

- Offline-first operation.
- Local device data ownership.
- Per-user app permissions.
- Per-tool read/write enablement.
- Safe defaults with write tools off.
- Runtime changes without restarting the app.

### Options considered

1. **MCP transport embedded directly in the iOS app**
   - Pros: fewer moving parts, direct access to Swift services.
   - Cons: iOS backgrounding/sandboxing constraints, awkward stdio support, harder to expose to desktop agents, more risk of protocol code polluting the UI process.

2. **Sidecar MCP server with a narrow app/core bridge**
   - Pros: isolates MCP protocol/runtime, works with desktop LLM clients, allows stdio and loopback HTTP transports, keeps Swift core as authority, easier to disable/remove.
   - Cons: requires a bridge contract and packaging story.

3. **Remote/cloud MCP server**
   - Pros: easiest for remote agents.
   - Cons: violates local-first/offline assumptions and increases data exposure.

### Decision

Adopt **Option 2: sidecar MCP server with an app/core-owned bridge**.

The sidecar may be implemented as a small Swift executable, Node/TypeScript executable, or Python executable, but it must not own business logic. The bridge boundary should be typed and minimal:

- `listTools(context)`
- `callTool(toolName, arguments, context)`
- `getToolPolicySnapshot()`
- `appendToolAuditEvent(event)`

All domain reads/writes go through `WiredPartCore` services and existing permission checks.

### Consequences

- The app can ship with MCP disabled by default.
- Users can toggle individual tools at runtime from Settings.
- The sidecar can be replaced without changing domain services.
- The bridge can reuse the same registry for Apple Foundation Models tools later, avoiding two inconsistent AI permission systems.

---

## Tool naming and permission model

### Tool namespace

Use snake_case names grouped by domain and access level:

| Tool | Access | Default | Stage | Notes |
|---|---:|---:|---:|---|
| `parts_catalog_read` | read | on | Stage 2 design, implementation when promoted | Search/list parts, categories, brands, suppliers, prices. |
| `parts_catalog_write` | write | off | Stage 2+ only if promoted | Add/update parts, category metadata, supplier links, prices. |
| `inventory_read` | read | on | Stage 3+ | Stock levels, locations, movement history, low-stock queries. |
| `inventory_write` | write | off | Stage 3+ | Stock adjustments/movements via existing movement rules. |
| `jobs_read` | read | on | Stage 4+ | Job lookup, stages, labor/material summaries. |
| `jobs_write` | write | off | Stage 4+ | Job status/stage updates and notes through service APIs. |
| `time_entries_read` | read | on | Stage 5/7+ | Timesheets and clock history. No write tool in initial MCP set. |
| `purchase_orders_read` | read | on | Stage 6/7+ | JPO/PO lookup, receiving state, supplier context. |
| `purchase_orders_write` | write | off | Stage 6/7+ | Create/update JPOs/POs, confirm receiving only through order service rules. |
| `receipt_scan_ingest` | write | off | Stage 6/7+ | Ingest OCR/receipt scan results into a review queue, not direct inventory mutation. |

### Tool IDs vs display names

Store a stable `toolId` such as `parts_catalog_read`. UI labels can change, but stored policy and audit rows must use stable IDs.

### Access rules

Every MCP call must pass all of these checks:

1. **Transport trust:** request originates from local stdio/session or a loopback address explicitly allowed by the app.
2. **Session binding:** request is bound to a current WiredPart user/device session.
3. **Tool policy:** tool exists, is enabled, and write access is explicitly allowed when needed.
4. **User permission:** the current app user has the corresponding app permission, such as `view_parts_catalog` or a future `manage_inventory` permission.
5. **Business validation:** the target service validates invariants exactly as it does for UI-initiated actions.
6. **Audit:** every write request and every denied request writes an audit event before returning.

---

## MCP tool registry schema design

Use existing settings infrastructure for the first version so the registry can be changed at runtime and synced according to current settings policy. Add a typed service wrapper over the raw settings rows rather than scattering key strings across the UI and sidecar.

### Swift model types

Create these types in a future implementation file such as `core/Sources/WiredPartCore/AI/MCPToolRegistry.swift`:

```swift
public enum MCPToolAccess: String, Codable, Sendable, CaseIterable {
    case read
    case write
}

public struct MCPToolDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let domain: String
    public let access: MCPToolAccess
    public let description: String
    public let requiredPermissions: [String]
    public let defaultEnabled: Bool
    public let stage: String
}

public struct MCPToolPolicy: Codable, Sendable, Equatable {
    public let toolId: String
    public var enabled: Bool
    public var allowWrites: Bool
    public var requireConfirmation: Bool
    public var updatedAt: String
    public var updatedByUserId: Int64?
}

public struct MCPToolAuditEvent: Codable, Sendable, Equatable {
    public let id: String
    public let toolId: String
    public let access: MCPToolAccess
    public let actorUserId: Int64?
    public let actorDeviceId: Int64?
    public let outcome: String   // allowed, denied, failed
    public let reason: String?
    public let requestSummary: String
    public let createdAt: String
}
```

### Initial registry constants

The static registry should be source-controlled and reviewed like code:

```swift
public enum MCPToolRegistry {
    public static let definitions: [MCPToolDefinition] = [
        MCPToolDefinition(
            id: "parts_catalog_read",
            displayName: "Parts catalog read",
            domain: "Parts",
            access: .read,
            description: "Search and inspect parts, categories, brands, suppliers, and pricing.",
            requiredPermissions: ["view_parts_catalog"],
            defaultEnabled: true,
            stage: "Stage 2"
        ),
        MCPToolDefinition(
            id: "parts_catalog_write",
            displayName: "Parts catalog write",
            domain: "Parts",
            access: .write,
            description: "Create and update parts catalog records through PartsService validation.",
            requiredPermissions: ["manage_parts_catalog"],
            defaultEnabled: false,
            stage: "Stage 2+"
        )
        // Add the remaining definitions from the table above.
    ]
}
```

### Settings storage

For the first implementation, store one JSON policy row per tool:

- `settings.key`: `mcp.tool.<toolId>`
- `settings.category`: `mcp_tools`
- `settings.value`: JSON-encoded `MCPToolPolicy`
- `syncScope`: company-level unless the security review decides MCP policy should be device-only.

Default policy generation:

- Read tools: `enabled = defaultEnabled`, `allowWrites = false`, `requireConfirmation = false`.
- Write tools: `enabled = false`, `allowWrites = false`, `requireConfirmation = true`.
- Unknown tools: disabled, no writes.

### Future normalized tables

If MCP audit volume grows, promote storage to tables:

```sql
CREATE TABLE mcp_tool_policies (
    tool_id TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 0,
    allow_writes INTEGER NOT NULL DEFAULT 0,
    require_confirmation INTEGER NOT NULL DEFAULT 1,
    updated_by_user_id INTEGER,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE mcp_tool_audit_events (
    id TEXT PRIMARY KEY,
    tool_id TEXT NOT NULL,
    access TEXT NOT NULL,
    actor_user_id INTEGER,
    actor_device_id INTEGER,
    outcome TEXT NOT NULL,
    reason TEXT,
    request_summary TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Do not add these tables until implementation starts; the current issue is design-only.

---

## Bridge and call flow

### Read call flow

1. MCP client calls sidecar tool, e.g. `parts_catalog_read`.
2. Sidecar validates JSON shape and forwards to bridge as `callTool`.
3. Bridge loads current tool policy from `SettingsService`.
4. Bridge checks the user permission snapshot.
5. Bridge calls `PartsService` read methods.
6. Bridge returns small, structured JSON suitable for LLM consumption.

### Write call flow

1. MCP client calls a write tool, e.g. `inventory_write`.
2. Sidecar forwards to bridge.
3. Bridge verifies tool is enabled, `allowWrites == true`, and user has required permission.
4. If `requireConfirmation == true`, bridge returns `confirmation_required` with a plain-language diff instead of mutating data.
5. UI shows the confirmation to an authorized user.
6. On approval, the bridge calls the service-layer write method.
7. Bridge writes audit event and returns the resulting entity/change summary.

### Error shape

Every tool should return deterministic errors:

```json
{
  "ok": false,
  "errorCode": "tool_disabled",
  "message": "parts_catalog_write is disabled in Settings > AI & MCP > MCP Tools.",
  "retryable": false
}
```

Recommended error codes:

- `tool_not_found`
- `tool_disabled`
- `write_not_allowed`
- `confirmation_required`
- `permission_denied`
- `validation_failed`
- `not_available_offline`
- `internal_error`

---

## App settings UI wireframe/plan

Add an MCP Tools panel under the existing Settings area. If the app keeps a separate AI configuration page, place it at:

`Settings → AI & MCP → MCP Tools`

### Screen sections

```text
AI & MCP
┌────────────────────────────────────────────┐
│ MCP Tools                                  │
│ Local agents can use enabled tools to      │
│ inspect or change WiredPart data. Write    │
│ tools are off by default.                  │
├────────────────────────────────────────────┤
│ Global MCP access              [ Off/On ]  │
│ Sidecar status: Not running / Running      │
│ Connection mode: Local only                │
├────────────────────────────────────────────┤
│ Parts                                      │
│  [On ] Parts catalog read                  │
│       Search/list parts, categories...     │
│  [Off] Parts catalog write                 │
│       Add/update parts and prices          │
│       [ ] Allow writes                     │
│       [x] Require in-app confirmation      │
├────────────────────────────────────────────┤
│ Inventory                                  │
│  [On ] Inventory read                      │
│  [Off] Inventory write                     │
├────────────────────────────────────────────┤
│ Jobs                                       │
│  [On ] Jobs read                           │
│  [Off] Jobs write                          │
├────────────────────────────────────────────┤
│ Procurement                                │
│  [On ] Purchase orders read                │
│  [Off] Purchase orders write               │
│  [Off] Receipt scan ingest                 │
├────────────────────────────────────────────┤
│ Recent MCP activity                         │
│  10:42 parts_catalog_read allowed          │
│  10:40 inventory_write denied: disabled    │
└────────────────────────────────────────────┘
```

### UI behavior

- Global MCP access defaults off until the user intentionally enables it.
- Individual read tools may default on only after global MCP is enabled.
- Write tools always default off.
- Enabling `allowWrites` should require admin permission and an explicit confirmation dialog.
- If a write tool is enabled, show a visible warning badge.
- Runtime changes save through `SettingsService` and should affect the next tool call without app restart.
- The panel should expose copyable connection instructions for local agents only after global MCP is enabled.

### Accessibility

- Every toggle label must include the tool display name and access level.
- Warning badges must not rely on color alone.
- The Recent MCP activity list should be readable by VoiceOver as event time, tool, outcome, and reason.

---

## Implementation plan

### Task 1: Add registry design types behind no-op service

**Objective:** Create typed MCP registry and policy helpers without exposing any transport.

**Files:**
- Create: `core/Sources/WiredPartCore/AI/MCPToolRegistry.swift`
- Test: `core/Tests/WiredPartCoreTests/MCPToolRegistryTests.swift`

**Steps:**
1. Write tests proving all minimum tool IDs exist.
2. Write tests proving write tools default to disabled and require confirmation.
3. Implement `MCPToolAccess`, `MCPToolDefinition`, `MCPToolPolicy`, and static definitions.
4. Add helper `defaultPolicy(for:)`.
5. Run `cd core && swift test --filter MCPToolRegistryTests`.

### Task 2: Add SettingsService policy persistence

**Objective:** Persist and read MCP tool policies using existing settings storage.

**Files:**
- Modify: `core/Sources/WiredPartCore/Services/SettingsService.swift`
- Test: `core/Tests/WiredPartCoreTests/SettingsServiceTests.swift`

**Steps:**
1. Add failing tests for `getMCPToolPolicies()` returning defaults when no rows exist.
2. Add failing tests for `upsertMCPToolPolicy()` round-tripping one read and one write policy.
3. Implement JSON encode/decode with `settings.category = "mcp_tools"`.
4. Ensure corrupt/unknown tool rows are ignored or surfaced as safe disabled policies.
5. Run `cd core && swift test --filter SettingsServiceTests`.

### Task 3: Add bridge authorization contract

**Objective:** Centralize allow/deny decisions before any MCP transport exists.

**Files:**
- Create: `core/Sources/WiredPartCore/AI/MCPToolAuthorization.swift`
- Test: `core/Tests/WiredPartCoreTests/MCPToolAuthorizationTests.swift`

**Steps:**
1. Test disabled tool denies reads and writes.
2. Test write tool denies when `allowWrites == false`.
3. Test missing app permission denies even when tool policy is enabled.
4. Test enabled read tool with required permission allows.
5. Implement pure Swift authorization function returning allow/deny result and reason.
6. Run focused tests.

### Task 4: Plan the Settings UI page

**Objective:** Add the UI shell only when MCP implementation is promoted.

**Files:**
- Future create/modify: `Weird Parts IOS/Weird Parts IOS/Features/Settings/.../IOSMCPToolsPage.swift`
- Future tests: Settings save-button validation tests and source-level toggle checks.

**Steps:**
1. Create an `ActiveSheet` enum for write-warning confirmation dialogs.
2. Render grouped tool definitions by domain.
3. Save policy changes through `SettingsService`.
4. Add disabled/save validation guards matching existing settings-page expectations.
5. Verify with iOS build only when UI implementation starts.

### Task 5: Add sidecar transport after the registry is stable

**Objective:** Implement MCP JSON-RPC/stdio adapter without domain business logic.

**Files:**
- Future create: `mcp-sidecar/` or `tools/mcp-sidecar/`
- Future docs: `docs/runbooks/mcp-sidecar.md`

**Steps:**
1. Sidecar lists tools from bridge snapshot.
2. Sidecar calls bridge and relays structured JSON.
3. Sidecar refuses non-local network bindings by default.
4. Sidecar integration tests cover disabled write attempts and allowed read attempts.

---

## Safety and local-first constraints

- No cloud MCP endpoint in beta scope.
- No write tool should mutate data without service-layer validation.
- Receipt scan ingest should create a review queue item first, not directly alter stock/prices.
- MCP settings must be visible and reversible in-app.
- Audit logs must survive app restart.
- Sidecar launch should be opt-in and local-only.
- The app should keep working normally when the sidecar is missing, stopped, or crashed.

## Acceptance criteria for this design issue

- ADR decision is documented: sidecar MCP server with app/core-owned bridge.
- Minimum MCP tool list covers read/write split for parts, inventory, jobs, time entries, POs, and receipt scan ingest.
- Registry schema includes stable tool IDs, access type, default enablement, required permissions, policy, and audit event fields.
- Settings UI wireframe includes global enablement, per-tool toggles, write warnings, and recent activity.
- Implementation is explicitly gated by current Paperclip stage rules: design now, implementation Stage 10 unless specifically promoted earlier.

## Verification commands

For this design-only issue:

```bash
test -f docs/plans/mcp-native-architecture.md
python3 - <<'PY'
from pathlib import Path
p = Path('docs/plans/mcp-native-architecture.md')
text = p.read_text()
required = [
    'ADR: MCP server placement',
    'MCP tool registry schema design',
    'App settings UI wireframe/plan',
    'parts_catalog_read',
    'parts_catalog_write',
    'inventory_read',
    'inventory_write',
    'jobs_read',
    'jobs_write',
    'time_entries_read',
    'purchase_orders_read',
    'purchase_orders_write',
    'receipt_scan_ingest',
]
missing = [s for s in required if s not in text]
if missing:
    raise SystemExit(f'Missing required content: {missing}')
print(f'OK: {p} contains all required MCP design sections ({len(text)} chars)')
PY
```
