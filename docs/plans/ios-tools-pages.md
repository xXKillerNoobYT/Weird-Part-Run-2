# iOS Tools Pages — Design Plan

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
