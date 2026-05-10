# iOS Tools Pages — Design Plan

## What This Does

The Tools area manages physical tools and tool kits — checkout/return tracking, condition verification, kit content verification (counting items in pre-defined kits), maintenance scheduling, lost/stolen tracking, tool trades between users, and edit-with-verification (changes to tool records require photo + condition verification). Backed by `ToolsService.swift` (30 public methods, 1767 lines, 115 tests = **3.83× breadth — second-highest in project after scheduling's 4.28×**) + 8 iOS pages. Per memory: "First area with 0 dismiss-safety gaps" first rotation; documented `allowedToolEditFields` allowlist pattern for safe field-level UPDATE.

## Why

Tools are physical assets with high theft/loss risk and ongoing maintenance costs. A misplaced $2k impact wrench is real money walking off; an un-maintained $10k vehicle lift is a liability waiting to fail. The checkout/return flow with condition verification creates an explicit chain-of-custody: every tool's location/condition is the latest auditable transaction. Kit verification supports the "pre-staged kits for jobs" workflow — Tech grabs Kit A on the way to a job, the verification step ensures all items are present before they leave the shop. Maintenance scheduling surfaces upcoming-due work before it becomes failure. Tool trades support cross-shop transfers in multi-shop networks. The 3.83× test breadth ratio reflects that tool-state correctness is operational ground truth — getting "tool X is at job Y" wrong means a Tech shows up to a job missing the tool they need.

## Navigation
Tools: Dashboard, All Tools (renamed from Registry), Checkouts, Kits, Maintenance, Management (renamed from Admin)

## Key Design Decisions

### Dashboard Quick Actions with QR
- Checkout Tool, Return Tool, Report Issue
- Each action: tap → camera pops up for QR scan OR type tool ID number
- Difference from Dashboard QR: you pick the action FIRST, then scan

### Tool Detail — Full View
- All parts attached shown for verification
- Checkout/return at shop AND at job
- Full checkout history + maintenance log
- Version history (2 years) showing who changed what
- "Edit without permission" pattern: ANY user can edit, but without hat permission → changes are PENDING → manager gets notification + chat → manager must scan QR or type tool ID to verify before approving

### Edit Verification Flow
- Worker edits → changes saved as PENDING (yellow badge)
- Manager notified via notification + Chat with action buttons
- Manager MUST scan QR or type tool ID before approve/reject buttons unlock
- Forces physical verification — can't rubber-stamp remotely

### Four Kit Types
1. CONSUMABLE-ONLY (Grease Kit): no tools, just supplies
2. TOOL + CONSUMABLE (Crimp Kit): main tool + consumable accessories
3. MIXED (Packout Kit): hand tools + consumable parts
4. TOOLS ONLY (Meter Kit): multiple tools, no consumables

### Kit Features
- Missing tools status
- Checkout + return + full inspection checklist (tools AND consumable parts)
- Restock consumable parts
- Version history (2 years)
- Condition check required on checkout AND return

### Tool Trade Between Users
- Initiator does condition check → sends trade request to receiver
- Receiver does their own condition check → accepts/declines
- If receiver doesn't respond in 7 DAYS: auto-completes using initiator's check, flagged as "unconfirmed"
- Both parties can initiate, system reconciles

### Checkout Actions
- Report Lost/Stolen: company tool → manager decides. Personal tool → owner decides.
- Report Damaged
- Trade to another user

### Maintenance Types
1. Time-based (every 90 days)
2. Usage-based (every 500 uses)
3. Schedule-based (first Monday of every month)
4. Decreasing-based (confidence decay math — same as audit system)
5. Condition-triggered (return condition check flags it)

### Management Page (renamed from Admin)
- Bulk tool management (checkout/return/restock)
- Tool categories/types configuration
- Company tool policies (max checkout duration, overdue notification, auto-maintenance thresholds)
- Location assignment (home location for tools/kits)
- Records & history (full audit trail, filterable, exportable)

---

## Current State (as of 2026-04-19 — AUTO GO C1 audit)

### iOS Files (8)
| File | Purpose |
|---|---|
| `IOSToolsDashboardPage.swift` | Dashboard with smart cards, quick-action QR buttons |
| `IOSToolRegistryPage.swift` | All tools list with search/filter |
| `IOSToolDetailPage.swift` | Full tool detail: parts, checkout history, maintenance log, version history |
| `IOSToolCheckoutsPage.swift` | Active + history checkouts list |
| `IOSToolKitsPage.swift` | Kit list with contents and inspection |
| `IOSToolMaintenancePage.swift` | Maintenance configs, schedules, history |
| `IOSToolAdminPage.swift` | Bulk management, categories, policies |
| `IOSToolsRouter.swift` | NavigationStack routing |

### ToolsService API Surface (30 public methods)

| Section | Methods |
|---|---|
| 1. Tools List | `listTools(search:status:)` |
| 2. Kits | `listKits()`, `listToolKits()` |
| 3. Checkouts | `listCheckouts(toolId:active:)`, `checkoutTool(toolId:userId:notes:)`, `returnTool(toolId:userId:notes:)`, `markToolMaintenance(toolId:)` |
| 4. Stats | `getToolsStats()` |
| 5. Detail | `getToolDetail(toolId:)` |
| 6. Kit Contents | `getKitContents(toolId:)` |
| 7. Version History | `getToolVersionHistory(toolId:months:)`, `getPendingEdits(toolId:)` |
| 8. Condition Checkout | `checkoutToolWithCondition(...)`, `returnToolWithCondition(...)` |
| 9. Edit w/ Verification | `editToolWithVerification(...)`, `approveToolEdit(...)`, `listPendingToolEdits()`, `rejectToolEdit(...)` |
| 10. Trades | `initiateTrade(...)`, `respondToTrade(...)`, `expireOldTrades()`, `getPendingTradesForUser(userId:)` |
| 11. Lost/Stolen | `reportToolLostOrStolen(...)` |
| 12. Maintenance | `createMaintenanceConfig(...)`, `getMaintenanceConfigs(toolId:)`, `toggleMaintenanceConfig(...)`, `recordMaintenance(...)`, `calculateNextMaintenanceDate(toolId:)`, `updateConfidenceScores()`, `getMaintenanceHistory(toolId:)` |

### Database Foundation
- Migration `006_fleet_tools_scheduling` — core tools + checkouts tables
- Migration `013_tools_supplier_extras` — tool extras
- Migration `048_tool_detail_tables` — detail, version history, pending edits
- Migration `049_tool_trades` — tool trade workflow
- Migration `050_tool_maintenance_configs` — maintenance config + scheduling + confidence

### Implementation Status
Phase 9 (Tools & Kits) is complete per CLAUDE.md. All 8 iOS pages are present and ToolsService has 31 public methods across all 12 feature areas. The edit-verification flow, trade workflow, and maintenance confidence decay are all implemented.
