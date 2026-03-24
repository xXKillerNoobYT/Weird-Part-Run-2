# 47D — Tool Trade

> **Chain position:** 47A → 47B → 47C → **47D** → 47E
> **Prerequisite:** 47B (condition check pattern)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `ToolsService.swift` and any existing trade/transfer pages. Add tool trade flow with condition checks on both sides, 7-day timeout, and lost/stolen reporting with ownership-based decision rules.

## Context

Workers trade tools between each other. The flow: initiator checks the tool's condition and sends a trade request → receiver gets a notification → receiver checks condition on their end and accepts/declines. If no response in 7 days, the trade auto-expires. Lost/stolen reporting follows ownership rules: company tools are decided by a manager, personal tools by the owner.

## Task

### Step 1: Migration + Model

```swift
// Migration: tool_trades table
try db.create(table: "tool_trades") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("tool_id", .integer).notNull().references("tools")
    t.column("from_user_id", .integer).notNull().references("users")
    t.column("to_user_id", .integer).notNull().references("users")
    t.column("condition_at_send", .text).notNull()  // condition check by sender
    t.column("condition_at_receive", .text)           // condition check by receiver
    t.column("send_notes", .text)
    t.column("receive_notes", .text)
    t.column("status", .text).notNull().defaults(to: "pending")
        // "pending", "accepted", "declined", "expired", "cancelled"
    t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    t.column("responded_at", .datetime)
    t.column("expires_at", .datetime).notNull()  // created_at + 7 days
}

struct ToolTrade: Identifiable, Sendable {
    let id: Int64
    let toolId: Int64
    let fromUserId: Int64
    let toUserId: Int64
    let conditionAtSend: String
    let conditionAtReceive: String?
    let sendNotes: String?
    let receiveNotes: String?
    let status: String
    let createdAt: Date
    let respondedAt: Date?
    let expiresAt: Date
}
```

### Step 2: Trade Flow Service Methods

```swift
// MARK: - Tool Trades

func initiateTrade(
    toolId: Int64, fromUserId: Int64, toUserId: Int64,
    condition: String, notes: String?
) async throws -> ToolTrade {
    try await db.write { db in
        // Verify tool is checked out to the sender
        let currentCheckout = try Row.fetchOne(db, sql: """
            SELECT id FROM tool_checkouts
            WHERE tool_id = ? AND checked_out_by = ? AND returned_at IS NULL
            """, arguments: [toolId, fromUserId])

        guard currentCheckout != nil else {
            throw ToolsServiceError.toolNotCheckedOutToUser
        }

        // Check no pending trades for this tool
        let pendingTrade = try Row.fetchOne(db, sql: """
            SELECT id FROM tool_trades
            WHERE tool_id = ? AND status = 'pending'
            """, arguments: [toolId])

        guard pendingTrade == nil else {
            throw ToolsServiceError.tradePending
        }

        let expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

        try db.execute(sql: """
            INSERT INTO tool_trades
            (tool_id, from_user_id, to_user_id, condition_at_send, send_notes, status, expires_at)
            VALUES (?, ?, ?, ?, ?, 'pending', ?)
            """, arguments: [toolId, fromUserId, toUserId, condition, notes,
                            expiresAt.ISO8601Format()])

        let tradeId = db.lastInsertedRowID

        return ToolTrade(
            id: tradeId, toolId: toolId,
            fromUserId: fromUserId, toUserId: toUserId,
            conditionAtSend: condition, conditionAtReceive: nil,
            sendNotes: notes, receiveNotes: nil,
            status: "pending", createdAt: Date(),
            respondedAt: nil, expiresAt: expiresAt
        )
    }
}

func respondToTrade(
    tradeId: Int64, accepted: Bool, condition: String?, notes: String?
) async throws {
    try await db.write { db in
        let trade = try Row.fetchOne(db, sql: """
            SELECT * FROM tool_trades WHERE id = ? AND status = 'pending'
            """, arguments: [tradeId])

        guard let trade = trade else {
            throw ToolsServiceError.tradeNotFound
        }

        let toolId: Int64 = trade["tool_id"]
        let fromUserId: Int64 = trade["from_user_id"]
        let toUserId: Int64 = trade["to_user_id"]

        let newStatus = accepted ? "accepted" : "declined"

        try db.execute(sql: """
            UPDATE tool_trades SET status = ?, condition_at_receive = ?,
            receive_notes = ?, responded_at = datetime('now')
            WHERE id = ?
            """, arguments: [newStatus, condition, notes, tradeId])

        if accepted {
            // Close sender's checkout
            try db.execute(sql: """
                UPDATE tool_checkouts SET returned_at = datetime('now'),
                condition_at_return = ?
                WHERE tool_id = ? AND checked_out_by = ? AND returned_at IS NULL
                """, arguments: [trade["condition_at_send"], toolId, fromUserId])

            // Create new checkout for receiver
            try db.execute(sql: """
                INSERT INTO tool_checkouts
                (tool_id, checked_out_by, checked_out_at, condition_at_checkout)
                VALUES (?, ?, datetime('now'), ?)
                """, arguments: [toolId, toUserId, condition ?? trade["condition_at_send"]])
        }
    }
}

func expireOldTrades() async throws -> Int {
    try await db.write { db in
        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM tool_trades
            WHERE status = 'pending' AND expires_at < datetime('now')
            """) ?? 0

        try db.execute(sql: """
            UPDATE tool_trades SET status = 'expired', responded_at = datetime('now')
            WHERE status = 'pending' AND expires_at < datetime('now')
            """)

        return count
    }
}

func getPendingTradesForUser(userId: Int64) async throws -> [ToolTradeInfo] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT tt.*, t.name as tool_name, t.serial_number,
                   fu.first_name || ' ' || fu.last_name as from_name,
                   tu.first_name || ' ' || tu.last_name as to_name
            FROM tool_trades tt
            JOIN tools t ON tt.tool_id = t.id
            JOIN users fu ON tt.from_user_id = fu.id
            JOIN users tu ON tt.to_user_id = tu.id
            WHERE (tt.to_user_id = ? OR tt.from_user_id = ?)
            AND tt.status = 'pending'
            ORDER BY tt.created_at DESC
            """, arguments: [userId, userId])
        .map { row in
            ToolTradeInfo(row: row)
        }
    }
}
```

### Step 3: Trade UI

```swift
struct ToolTradeSheet: View {
    let tool: ToolDetail
    @EnvironmentObject var appCore: AppCore
    @State private var selectedUser: Int64?
    @State private var condition: String = "good"
    @State private var notes: String = ""
    @State private var employees: [EmployeeBasic] = []
    @State private var isSaving = false
    @State private var saveError: String?
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    Text(tool.name).font(.headline)
                }

                Section("Condition Check (Required)") {
                    Picker("Current Condition", selection: $condition) {
                        Text("Excellent").tag("excellent")
                        Text("Good").tag("good")
                        Text("Fair").tag("fair")
                        Text("Poor").tag("poor")
                        Text("Damaged").tag("damaged")
                    }
                    .pickerStyle(.segmented)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Send To") {
                    ForEach(employees, id: \.id) { emp in
                        HStack {
                            Text(emp.fullName)
                            Spacer()
                            if selectedUser == emp.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedUser = emp.id }
                    }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Trade Tool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Request") {
                        Task { await sendTradeRequest() }
                    }
                    .disabled(selectedUser == nil || isSaving)
                }
            }
            .task { await loadEmployees() }
        }
    }

    func sendTradeRequest() async {
        guard let toUserId = selectedUser else { return }
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            _ = try await service.initiateTrade(
                toolId: tool.id,
                fromUserId: appCore.currentUserId,
                toUserId: toUserId,
                condition: condition,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    func loadEmployees() async {
        guard let service = appCore.peopleService else { return }
        do {
            employees = try await service.getActiveEmployees()
                .filter { $0.id != appCore.currentUserId }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
```

### Step 4: Trade Response View (Receiver)

```swift
struct TradeResponseView: View {
    let trade: ToolTradeInfo
    @EnvironmentObject var appCore: AppCore
    @State private var condition: String = "good"
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section("Trade Request") {
                LabeledContent("Tool", value: trade.toolName)
                LabeledContent("From", value: trade.fromName)
                LabeledContent("Condition (Sender)", value: trade.conditionAtSend.capitalized)
                LabeledContent("Expires", value: trade.expiresAt, format: .dateTime.month().day().hour().minute())
            }

            Section("Your Condition Check (Required)") {
                Picker("Condition", selection: $condition) {
                    Text("Excellent").tag("excellent")
                    Text("Good").tag("good")
                    Text("Fair").tag("fair")
                    Text("Poor").tag("poor")
                    Text("Damaged").tag("damaged")
                }
                .pickerStyle(.segmented)

                TextField("Notes", text: $notes, axis: .vertical)
            }

            if let error = saveError {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                HStack(spacing: 16) {
                    Button("Decline") {
                        Task { await respond(accepted: false) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("Accept") {
                        Task { await respond(accepted: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    func respond(accepted: Bool) async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            try await service.respondToTrade(
                tradeId: trade.id,
                accepted: accepted,
                condition: accepted ? condition : nil,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

### Step 5: Lost/Stolen Reporting

```swift
// Service
func reportToolLostOrStolen(
    toolId: Int64, reportedBy: Int64, reportType: String,  // "lost" or "stolen"
    description: String, lastKnownLocation: String?
) async throws {
    try await db.write { db in
        // Update tool status
        try db.execute(sql: """
            UPDATE tools SET status = ?, updated_at = datetime('now')
            WHERE id = ?
            """, arguments: [reportType, toolId])

        // Log the report
        try db.execute(sql: """
            INSERT INTO part_change_log
            (entity_type, entity_id, field_name, old_value, new_value,
             changed_by, changed_at, change_type)
            VALUES ('tool', ?, 'status', 'active', ?, ?, datetime('now'), ?)
            """, arguments: [toolId, reportType, reportedBy, "report_\(reportType)"])

        // Close active checkout if any
        try db.execute(sql: """
            UPDATE tool_checkouts SET returned_at = datetime('now'),
            condition_at_return = ?, return_notes = ?
            WHERE tool_id = ? AND returned_at IS NULL
            """, arguments: [reportType, description, toolId])
    }
}

// UI: ownership determines who decides
// Company tool → manager must approve resolution
// Personal tool → owner decides
struct LostStolenReportSheet: View {
    let tool: ToolDetail
    @EnvironmentObject var appCore: AppCore
    @State private var reportType: String = "lost"
    @State private var description: String = ""
    @State private var lastLocation: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    Text(tool.name).font(.headline)
                    LabeledContent("Owner", value: tool.ownershipType == "company" ? "Company" : "Personal")
                }

                Section("Report Type") {
                    Picker("Type", selection: $reportType) {
                        Text("Lost").tag("lost")
                        Text("Stolen").tag("stolen")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    TextField("What happened?", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Last known location", text: $lastLocation)
                }

                // Ownership-based decision info
                Section {
                    if tool.ownershipType == "company" {
                        Label("A manager will review this report and decide next steps.",
                              systemImage: "person.badge.shield.checkmark.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("As the owner, you control what happens next.",
                              systemImage: "person.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Report \(reportType.capitalized)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit Report") {
                        Task { await submitReport() }
                    }
                    .disabled(description.isEmpty || isSaving)
                }
            }
        }
    }

    func submitReport() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            try await service.reportToolLostOrStolen(
                toolId: tool.id,
                reportedBy: appCore.currentUserId,
                reportType: reportType,
                description: description,
                lastKnownLocation: lastLocation.isEmpty ? nil : lastLocation
            )
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

## Important Notes
- Trade requires condition check from BOTH sender and receiver
- 7-day timeout: after 7 days, pending trades auto-expire (call expireOldTrades on app launch)
- Accepting a trade: closes sender's checkout, creates receiver's checkout
- Lost/stolen: company tool → manager decides resolution; personal tool → owner decides
- Cannot initiate a trade if the tool already has a pending trade
- Tool must be currently checked out to the sender to initiate a trade

## Success Criteria
- [ ] Trade flow: initiator condition check → send request
- [ ] Receiver condition check → accept/decline
- [ ] 7-day timeout for unconfirmed trades
- [ ] Lost/stolen reporting with description + last location
- [ ] Company tool: manager reviews; Personal tool: owner decides
- [ ] Migration for tool_trades table
- [ ] Service: initiateTrade, respondToTrade, expireOldTrades, reportToolLostOrStolen
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 47D Results (YYYY-MM-DD)
- Trade flow: condition checks on both sides
- 7-day expiration
- Lost/stolen reporting with ownership rules
- Migration: tool_trades
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 47E.**
