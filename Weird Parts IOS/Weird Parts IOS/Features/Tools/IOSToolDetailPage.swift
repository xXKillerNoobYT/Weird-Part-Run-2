import SwiftUI
import WiredPartCore

/// Full tool detail page with contents checklist, checkout/return,
/// version history, and edit-with-verification.
struct IOSToolDetailPage: View {
    let toolId: Int64
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var tool: ToolsService.ToolDetail?
    @State private var kitContents: [ToolsService.KitContentItem] = []
    @State private var versionHistory: [ToolsService.ToolChangeRecord] = []
    @State private var pendingEdits: [ToolsService.ToolChangeRecord] = []
    @State private var pendingTrades: [ToolsService.ToolTradeInfo] = []
    @State private var maintenanceConfigs: [ToolsService.MaintenanceConfigInfo] = []
    @State private var nextMaintenanceDue: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var actionMessage: String?

    private enum ActiveSheet: Identifiable {
        case checkout
        case returnTool
        case reportIssue
        case editTool
        case versionHistory
        case pendingVerification(editId: Int64)
        case trade
        case tradeResponse(ToolsService.ToolTradeInfo)
        case lostStolen
        case addMaintenance
        case help

        var id: String {
            switch self {
            case .checkout: "checkout"
            case .returnTool: "returnTool"
            case .reportIssue: "reportIssue"
            case .editTool: "editTool"
            case .versionHistory: "versionHistory"
            case .pendingVerification(let eid): "pending_\(eid)"
            case .trade: "trade"
            case .tradeResponse(let t): "tradeResp_\(t.id)"
            case .lostStolen: "lostStolen"
            case .addMaintenance: "addMaintenance"
            case .help: "help"
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading tool...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadAllData() }
            } else if let tool {
                toolContent(tool)
            } else {
                ErrorStateView(message: "Tool not found") { }
            }
        }
        .navigationTitle(tool?.name ?? "Tool Detail")
        .toolbar {
            if let tool {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        if tool.status == "available" {
                            Button { activeSheet = .checkout } label: {
                                Label("Checkout", systemImage: "arrow.up.right.square")
                            }
                        }
                        if tool.status == "checked_out" {
                            Button { activeSheet = .returnTool } label: {
                                Label("Return", systemImage: "arrow.down.left.square")
                            }
                            Button { activeSheet = .trade } label: {
                                Label("Trade", systemImage: "arrow.triangle.swap")
                            }
                        }
                        Button { activeSheet = .editTool } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button { activeSheet = .reportIssue } label: {
                            Label("Report Issue", systemImage: "exclamationmark.triangle")
                        }
                        Divider()
                        Button(role: .destructive) { activeSheet = .lostStolen } label: {
                            Label("Report Lost/Stolen", systemImage: "exclamationmark.shield")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Actions")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .refreshable { loadAllData() }
        .task { loadAllData() }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Main Content

    @ViewBuilder
    private func toolContent(_ tool: ToolsService.ToolDetail) -> some View {
        List {
            // Action message banner
            if let msg = actionMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text(msg).font(.subheadline)
                        Spacer()
                        Button { actionMessage = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss message")
                    }
                }
            }

            // Pending verification banner
            if !pendingEdits.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "clock.badge.questionmark")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pendingEdits.count) edit(s) pending verification")
                                .font(.subheadline).fontWeight(.medium)
                            Text("A manager must scan this tool's QR code to approve.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            toolInfoSection(tool)
            statusSection(tool)

            if tool.hasKit {
                kitContentsSection
            }

            if !pendingTrades.isEmpty {
                pendingTradesSection
            }

            // Confidence gauge for tools with decreasing-based maintenance
            if let confidence = tool.confidenceScore,
               maintenanceConfigs.contains(where: { $0.maintenanceType == "decreasing_based" }) {
                confidenceSection(confidence)
            }

            if !maintenanceConfigs.isEmpty {
                maintenanceConfigsSection
            }

            recentChangesSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Tool Info Section

    private func toolInfoSection(_ tool: ToolsService.ToolDetail) -> some View {
        Section {
            detailRow("Tool #", tool.toolNumber, icon: "number")
            detailRow("Category", tool.category.replacingOccurrences(of: "_", with: " ").capitalized, icon: "tag")
            if let brand = tool.brand {
                detailRow("Brand", brand, icon: "building.2")
            }
            if let model = tool.modelNumber {
                detailRow("Model", model, icon: "doc.text")
            }
            if let serial = tool.serialNumber {
                detailRow("Serial #", serial, icon: "barcode")
            }
            if let cost = tool.purchaseCost, cost > 0 {
                detailRow("Purchase Cost", formatCurrency(cost), icon: "dollarsign.circle")
            }
            if let date = tool.purchaseDate {
                detailRow("Purchase Date", date, icon: "calendar")
            }
            if let warranty = tool.warrantyExpiry {
                detailRow("Warranty Until", warranty, icon: "shield.checkered")
            }
            if let cal = tool.calibrationDueDate {
                detailRow("Calibration Due", cal, icon: "gauge.with.dots.needle.33percent")
            }
            if let notes = tool.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Notes", systemImage: "note.text")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(notes).font(.subheadline)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Tool Information")
        }
    }

    // MARK: - Status Section

    private func statusSection(_ tool: ToolsService.ToolDetail) -> some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                statusBadge(tool.status)
            }

            HStack {
                Text("Condition")
                Spacer()
                let condStr = ToolsService.ratingToCondition(tool.conditionRating)
                Text(condStr)
                    .foregroundStyle(conditionColor(condStr))
                    .fontWeight(.medium)
            }

            if let assignee = tool.assignedToName {
                HStack {
                    Text("Assigned To")
                    Spacer()
                    Label(assignee, systemImage: "person.fill")
                        .font(.subheadline)
                }
            }

            detailRow("Location", tool.locationType.replacingOccurrences(of: "_", with: " ").capitalized, icon: "mappin")

            // Quick actions
            if tool.status == "available" {
                Button {
                    activeSheet = .checkout
                } label: {
                    Label("Checkout This Tool", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, 4)
            } else if tool.status == "checked_out" {
                Button {
                    activeSheet = .returnTool
                } label: {
                    Label("Return This Tool", systemImage: "arrow.down.left.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.vertical, 4)
            }
        } header: {
            Text("Status & Assignment")
        }
    }

    // MARK: - Kit Contents Section

    @ViewBuilder
    private var kitContentsSection: some View {
        Section {
            if kitContents.isEmpty {
                Text("No kit components defined")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(kitContents) { item in
                    HStack {
                        Image(systemName: kitStatusIcon(item.status))
                            .foregroundStyle(kitStatusColor(item.status))
                            .accessibilityLabel("Status: \(item.status.capitalized)")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline)
                            Text(item.itemType.capitalized)
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        Spacer()

                        if item.itemType == "consumable" {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(item.currentQty)/\(item.requiredQty)")
                                    .font(.caption).monospacedDigit()
                                ProgressView(
                                    value: Double(item.currentQty),
                                    total: Double(max(item.requiredQty, 1))
                                )
                                .tint(item.currentQty < item.requiredQty ? .orange : .green)
                                .frame(width: 60)
                            }
                        } else {
                            Text(item.status.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(kitStatusColor(item.status).opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Contents")
                Spacer()
                let missing = kitContents.filter { $0.status == "missing" }.count
                if missing > 0 {
                    Text("\(missing) missing").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Confidence Section

    private func confidenceSection(_ confidence: Double) -> some View {
        Section {
            VStack(spacing: 8) {
                Gauge(value: confidence, in: 0...1) {
                    Text("Confidence")
                } currentValueLabel: {
                    Text("\(Int(confidence * 100))%")
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(confidenceScoreColor(confidence))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.red, .orange, .green]))

                if let nextDue = nextMaintenanceDue {
                    Text("Next maintenance: \(nextDue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } header: {
            Text("Reliability")
        }
    }

    private func confidenceScoreColor(_ score: Double) -> Color {
        if score > 0.7 { return .green }
        if score > 0.4 { return .orange }
        return .red
    }

    // MARK: - Maintenance Configs Section

    @ViewBuilder
    private var maintenanceConfigsSection: some View {
        Section {
            ForEach(maintenanceConfigs) { config in
                HStack {
                    Image(systemName: maintenanceTypeIcon(config.maintenanceType))
                        .foregroundStyle(config.isActive ? .blue : .secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(maintenanceTypeDisplayName(config.maintenanceType))
                            .font(.subheadline).fontWeight(.medium)
                        if let desc = config.description, !desc.isEmpty {
                            Text(desc).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(maintenanceConfigDetail(config))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if !config.isActive {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                activeSheet = .addMaintenance
            } label: {
                Label("Add Maintenance Rule", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } header: {
            Text("Maintenance Rules")
        }
    }

    private func maintenanceTypeIcon(_ type: String) -> String {
        switch type {
        case "time_based": "clock.fill"
        case "usage_based": "gauge.with.dots.needle.50percent"
        case "schedule_based": "calendar"
        case "decreasing_based": "chart.line.downtrend.xyaxis"
        case "condition_triggered": "exclamationmark.triangle.fill"
        default: "wrench.fill"
        }
    }

    private func maintenanceTypeDisplayName(_ type: String) -> String {
        switch type {
        case "time_based": "Time-Based"
        case "usage_based": "Usage-Based"
        case "schedule_based": "Schedule-Based"
        case "decreasing_based": "Confidence Decay"
        case "condition_triggered": "Condition-Triggered"
        default: type.capitalized
        }
    }

    private func maintenanceConfigDetail(_ config: ToolsService.MaintenanceConfigInfo) -> String {
        switch config.maintenanceType {
        case "time_based":
            return "Every \(config.intervalDays ?? 0) days"
        case "usage_based":
            return "After \(Int(config.usageThreshold ?? 0)) hours"
        case "schedule_based":
            return "Every \(config.intervalDays ?? 0) days (fixed)"
        case "decreasing_based":
            let rate = config.decayRate ?? 0
            let floor = config.decayFloor ?? 0
            return "Decay \(String(format: "%.1f", rate * 100))%/day, floor \(Int(floor * 100))%"
        case "condition_triggered":
            return "Triggers: \(config.conditionTriggers ?? "poor, damaged")"
        default:
            return ""
        }
    }

    // MARK: - Pending Trades Section

    @ViewBuilder
    private var pendingTradesSection: some View {
        Section {
            ForEach(pendingTrades) { trade in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        Text("\(trade.fromName) → \(trade.toName)")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    HStack {
                        Text("Condition: \(trade.conditionAtSend)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("Expires: \(trade.expiresAt)")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if let userId = appCore.currentUser?.id, trade.toUserId == userId {
                        Button("Respond to Trade") {
                            activeSheet = .tradeResponse(trade)
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text("Pending Trades")
                Spacer()
                Text("\(pendingTrades.count)")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Recent Changes Section

    @ViewBuilder
    private var recentChangesSection: some View {
        Section {
            if versionHistory.isEmpty {
                Text("No changes recorded")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(versionHistory.prefix(5)) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(record.changedByName ?? "Unknown")
                                .font(.subheadline).fontWeight(.medium)
                            Spacer()
                            Text(record.changedAt)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            changeTypeBadge(record.changeType)
                            if let field = record.fieldName {
                                Text("\(field): \(record.oldValue ?? "—") → \(record.newValue ?? "—")")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if record.verificationStatus == "pending_verification" {
                            Text("Pending Verification")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if versionHistory.count > 5 {
                    Button("View All History (\(versionHistory.count))") {
                        activeSheet = .versionHistory
                    }
                }
            }
        } header: {
            Text("Recent Changes")
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .checkout:
            if let tool {
                ToolCheckoutSheet(tool: tool) {
                    activeSheet = nil
                    actionMessage = "Tool checked out successfully"
                    loadAllData()
                }
                .environmentObject(appCore)
            }
        case .returnTool:
            if let tool {
                ToolReturnSheet(tool: tool) {
                    activeSheet = nil
                    actionMessage = "Tool returned successfully"
                    loadAllData()
                }
                .environmentObject(appCore)
            }
        case .editTool:
            if let tool {
                ToolEditSheet(tool: tool) { result in
                    activeSheet = nil
                    if result.requiresVerification {
                        actionMessage = "Edit submitted for verification. A manager must scan this tool's QR code to approve."
                    } else {
                        actionMessage = "Tool updated successfully"
                    }
                    loadAllData()
                }
                .environmentObject(appCore)
            }
        case .reportIssue:
            if let tool {
                ToolReportIssueSheet(tool: tool) {
                    activeSheet = nil
                    actionMessage = "Issue reported"
                    loadAllData()
                }
                .environmentObject(appCore)
            }
        case .versionHistory:
            NavigationStack {
                ToolVersionHistorySheet(history: versionHistory)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
            }
        case .pendingVerification(let editId):
            ToolApproveEditSheet(editId: editId) {
                activeSheet = nil
                actionMessage = "Edit approved"
                loadAllData()
            }
            .environmentObject(appCore)
        case .trade:
            if let tool {
                ToolTradeSheet(tool: tool) {
                    activeSheet = nil
                    actionMessage = "Trade request sent"
                    loadAllData()
                }
                .environmentObject(appCore)
            }
        case .tradeResponse(let tradeInfo):
            TradeResponseSheet(trade: tradeInfo) {
                activeSheet = nil
                actionMessage = "Trade response recorded"
                loadAllData()
            }
            .environmentObject(appCore)
        case .lostStolen:
            if let tool {
                LostStolenReportSheet(tool: tool) {
                    activeSheet = nil
                    actionMessage = "Report submitted"
                    loadAllData()
                }
                .environmentObject(appCore)
            }
        case .addMaintenance:
            if let tool {
                MaintenanceConfigSheet(tool: tool) {
                    activeSheet = nil
                    actionMessage = "Maintenance rule added"
                    loadAllData()
                }
                .environmentObject(appCore)
            }
        case .help:
            PageHelpSheet(
                title: "Tool Detail Help",
                sections: [
                    ("What This Page Does", "This is the complete profile for a single tool. It shows everything about the tool: identification info, current status, kit contents (if it is a kit), maintenance rules, pending trades, and a full change history."),
                    ("Tool Information", "The top section shows the tool number, category, brand, model, serial number, purchase cost, purchase date, warranty expiration, calibration due date, and any notes. This is the tool's identity card."),
                    ("Status & Assignment", "Shows the current status (Available, Checked Out, Maintenance, Lost), condition rating, who the tool is assigned to, and its location. If the tool is available, a blue 'Checkout' button appears. If checked out, a green 'Return' button appears."),
                    ("Actions Menu", "Tap the three-dot menu in the top right for actions: Checkout, Return, Trade (swap with another person), Edit (change tool details), Report Issue (flag a problem), and Report Lost/Stolen."),
                    ("Edit Verification", "Some edits require manager verification. If you change critical fields, the edit will show as 'Pending Verification' until a manager scans the tool's QR code to approve it."),
                    ("Kit Contents", "If the tool is a kit, you will see a Contents section listing every item in the kit with its status (Present, Missing, Damaged) and quantity levels for consumables."),
                    ("Maintenance Rules", "Shows any scheduled maintenance rules: time-based (every N days), usage-based (after N hours), confidence decay, or condition-triggered. Tap 'Add Maintenance Rule' to create new rules."),
                    ("Tips", "Before checking out a tool, check its condition rating. If it is 'Poor' or 'Damaged', report an issue instead. Always return tools promptly to keep records accurate for the whole team.")
                ]
            )
        }
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "available": .green
        case "checked_out": .blue
        case "maintenance": .orange
        case "lost": .red
        case "retired": .secondary
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func conditionColor(_ condition: String) -> Color {
        switch condition {
        case "Excellent": .green
        case "Good": .blue
        case "Fair": .orange
        case "Poor": .red
        case "Damaged": .red
        default: .secondary
        }
    }

    private func kitStatusIcon(_ status: String) -> String {
        switch status {
        case "present": "checkmark.circle.fill"
        case "missing": "xmark.circle.fill"
        case "damaged": "exclamationmark.triangle.fill"
        case "low": "exclamationmark.circle.fill"
        default: "questionmark.circle"
        }
    }

    private func kitStatusColor(_ status: String) -> Color {
        switch status {
        case "present": .green
        case "missing": .red
        case "damaged": .orange
        case "low": .orange
        default: .secondary
        }
    }

    private func changeTypeBadge(_ type: String) -> some View {
        let (label, color): (String, Color) = switch type {
        case "checkout": ("Checkout", .blue)
        case "return": ("Return", .green)
        case "edit": ("Edit", .purple)
        case "maintenance": ("Maintenance", .orange)
        default: (type.capitalized, .secondary)
        }
        return Text(label)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrencyWhole(value)
    }

    // MARK: - Data Loading

    private func loadAllData() {
        guard let service = appCore.toolsService else {
            isLoading = false
            loadError = "Tools service unavailable"
            return
        }
        isLoading = tool == nil
        loadError = nil
        do {
            tool = try service.getToolDetail(toolId: toolId)
            if tool?.hasKit == true {
                kitContents = try service.getKitContents(toolId: toolId)
            }
            versionHistory = try service.getToolVersionHistory(toolId: toolId)
            pendingEdits = try service.getPendingEdits(toolId: toolId)
            // Expire old trades then load pending ones
            _ = try? service.expireOldTrades()
            if let userId = appCore.currentUser?.id {
                pendingTrades = (try? service.getPendingTradesForUser(userId: userId)
                    .filter { $0.toolId == toolId }) ?? []
            }
            // Load maintenance configs and next due
            maintenanceConfigs = (try? service.getMaintenanceConfigs(toolId: toolId)) ?? []
            nextMaintenanceDue = try? service.calculateNextMaintenanceDate(toolId: toolId)
        } catch {
            loadError = userFriendlyError(error, context: "load tool details")
        }
        isLoading = false
    }
}

// MARK: - Checkout Sheet

struct ToolCheckoutSheet: View {
    let tool: ToolsService.ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var condition: ToolCondition = .good
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tool.name).font(.headline)
                    if let serial = tool.serialNumber {
                        Text("S/N: \(serial)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Condition", selection: $condition) {
                        ForEach(ToolCondition.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Condition Check (Required)")
                } footer: {
                    Text("You must record the tool's condition before checkout.")
                }

                if let error = saveError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Checkout Tool")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Checkout") {
                        Task { await performCheckout() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    func performCheckout() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            isSaving = false
            return
        }
        do {
            try service.checkoutToolWithCondition(
                toolId: tool.id,
                userId: userId,
                condition: condition.rawValue,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Return Sheet

struct ToolReturnSheet: View {
    let tool: ToolsService.ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var condition: ToolCondition = .good
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tool.name).font(.headline)
                }

                Section {
                    Picker("Return Condition", selection: $condition) {
                        ForEach(ToolCondition.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Return notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Return Condition Check (Required)")
                }

                // Show condition change warning
                if let lastCondition = tool.lastKnownCondition,
                   condition.rawValue != lastCondition {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text("Condition changed from \(lastCondition) to \(condition.rawValue)")
                                .font(.caption)
                        }
                    }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Return Tool")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Return") {
                        Task { await performReturn() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    func performReturn() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            isSaving = false
            return
        }
        do {
            try service.returnToolWithCondition(
                toolId: tool.id,
                userId: userId,
                condition: condition.rawValue,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Edit Sheet

struct ToolEditSheet: View {
    let tool: ToolsService.ToolDetail
    let onComplete: (ToolsService.ToolEditResult) -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: String = ""
    @State private var brand: String = ""
    @State private var modelNumber: String = ""
    @State private var serialNumber: String = ""
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false
    @State private var isInitialized = false

    private var hasManagePermission: Bool {
        appCore.hasPermission("manage_tools")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, _ in if isInitialized { isDirty = true } }
                    TextField("Category", text: $category)
                        .onChange(of: category) { _, _ in if isInitialized { isDirty = true } }
                    TextField("Brand", text: $brand)
                        .onChange(of: brand) { _, _ in if isInitialized { isDirty = true } }
                    TextField("Model Number", text: $modelNumber)
                        .onChange(of: modelNumber) { _, _ in if isInitialized { isDirty = true } }
                    TextField("Serial Number", text: $serialNumber)
                        .onChange(of: serialNumber) { _, _ in if isInitialized { isDirty = true } }
                } header: {
                    Text("Tool Details")
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: notes) { _, _ in if isInitialized { isDirty = true } }
                } header: {
                    Text("Notes")
                }

                if !hasManagePermission {
                    Section {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text("Your edits will be submitted for manager verification.")
                                .font(.caption)
                        }
                    }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Tool")
            .interactiveDismissDisabled(isDirty || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasManagePermission ? "Save" : "Submit for Verification") {
                        Task { await saveEdit() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
            .onAppear {
                name = tool.name
                category = tool.category
                brand = tool.brand ?? ""
                modelNumber = tool.modelNumber ?? ""
                serialNumber = tool.serialNumber ?? ""
                notes = tool.notes ?? ""
                Task { @MainActor in isInitialized = true }
            }
        }
    }

    @MainActor
    func saveEdit() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            isSaving = false
            return
        }

        // Build changes dict — only include fields that changed
        var changes: [String: String] = [:]
        if name != tool.name { changes["name"] = name }
        if category != tool.category { changes["category"] = category }
        if brand != (tool.brand ?? "") { changes["brand"] = brand }
        if modelNumber != (tool.modelNumber ?? "") { changes["model_number"] = modelNumber }
        if serialNumber != (tool.serialNumber ?? "") { changes["serial_number"] = serialNumber }
        if notes != (tool.notes ?? "") { changes["notes"] = notes }

        guard !changes.isEmpty else {
            isDirty = false
            dismiss()
            return
        }

        do {
            let result = try service.editToolWithVerification(
                toolId: tool.id,
                userId: userId,
                changes: changes,
                hasPermission: hasManagePermission
            )
            isDirty = false
            onComplete(result)
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Report Issue Sheet

struct ToolReportIssueSheet: View {
    let tool: ToolsService.ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var issueDescription: String = ""
    @State private var severity: String = "minor"
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tool.name).font(.headline)
                }

                Section {
                    Picker("Severity", selection: $severity) {
                        Text("Minor").tag("minor")
                        Text("Major").tag("major")
                        Text("Critical").tag("critical")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: severity) { _, _ in isDirty = true }

                    TextField("Describe the issue...", text: $issueDescription, axis: .vertical)
                        .lineLimit(4...8)
                        .onChange(of: issueDescription) { _, _ in isDirty = true }
                } header: {
                    Text("Issue Details")
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Report Issue")
            .interactiveDismissDisabled(isDirty || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submitIssue() }
                    }
                    .disabled(isSaving || issueDescription.isEmpty)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
    }

    @MainActor
    func submitIssue() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            isSaving = false
            return
        }
        do {
            // Log as a change record with type "issue"
            var changes: [String: String] = [:]
            changes["notes"] = "[\(severity.uppercased())] \(issueDescription)"
            _ = try service.editToolWithVerification(
                toolId: tool.id,
                userId: userId,
                changes: changes,
                hasPermission: true
            )
            if severity == "critical" {
                try service.markToolMaintenance(toolId: tool.id, performedBy: userId)
            }
            isDirty = false
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Version History Sheet

struct ToolVersionHistorySheet: View {
    let history: [ToolsService.ToolChangeRecord]

    var body: some View {
        List(history) { record in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.changedByName ?? "Unknown")
                        .font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text(record.changedAt)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    changeTypeBadge(record.changeType)
                    if let field = record.fieldName {
                        Text("\(field): \(record.oldValue ?? "—") → \(record.newValue ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if record.verificationStatus == "pending_verification" {
                    Text("Pending Verification")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("Version History")
    }

    private func changeTypeBadge(_ type: String) -> some View {
        let (label, color): (String, Color) = switch type {
        case "checkout": ("Checkout", .blue)
        case "return": ("Return", .green)
        case "edit": ("Edit", .purple)
        case "maintenance": ("Maintenance", .orange)
        default: (type.capitalized, .secondary)
        }
        return Text(label)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

// MARK: - Approve Edit Sheet

struct ToolApproveEditSheet: View {
    let editId: Int64
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Approve this pending edit?")
                        .font(.headline)
                    Text("This action will apply the change to the tool record.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Approve Edit")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") {
                        Task { await approve() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    func approve() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            isSaving = false
            return
        }
        do {
            try service.approveToolEdit(editId: editId, approverId: userId)
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Tool Trade Sheet

struct ToolTradeSheet: View {
    let tool: ToolsService.ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUser: Int64?
    @State private var condition: ToolCondition = .good
    @State private var notes: String = ""
    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    Text(tool.name).font(.headline)
                    if let serial = tool.serialNumber {
                        Text("S/N: \(serial)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Current Condition", selection: $condition) {
                        ForEach(ToolCondition.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: condition) { _, _ in isDirty = true }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: notes) { _, _ in isDirty = true }
                } header: {
                    Text("Condition Check (Required)")
                }

                Section("Send To") {
                    if employees.isEmpty {
                        Text("No other employees found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(employees) { emp in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(emp.displayName).font(.subheadline)
                                    if let role = emp.hatNames {
                                        Text(role).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedUser == emp.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                        .accessibilityLabel("Selected")
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedUser = emp.id }
                        }
                    }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Trade Tool")
            .interactiveDismissDisabled(isDirty || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Request") {
                        Task { await sendTradeRequest() }
                    }
                    .disabled(selectedUser == nil || isSaving)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
            .task { loadEmployees() }
        }
    }

    @MainActor
    func sendTradeRequest() async {
        guard let toUserId = selectedUser else { return }
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            isSaving = false
            return
        }
        do {
            _ = try service.initiateTrade(
                toolId: tool.id,
                fromUserId: userId,
                toUserId: toUserId,
                condition: condition.rawValue,
                notes: notes.isEmpty ? nil : notes
            )
            isDirty = false
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }

    private func loadEmployees() {
        guard let service = appCore.peopleService else {
            saveError = "Service not available"
            return
        }
        let currentId = appCore.currentUser?.id
        do {
            employees = try service.listEmployees(status: "active")
                .filter { $0.id != currentId }
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
    }
}

// MARK: - Trade Response Sheet

struct TradeResponseSheet: View {
    let trade: ToolsService.ToolTradeInfo
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var condition: ToolCondition = .good
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Trade Request") {
                    LabeledContent("Tool", value: trade.toolName)
                    LabeledContent("From", value: trade.fromName)
                    LabeledContent("Sender Condition", value: trade.conditionAtSend)
                    LabeledContent("Expires", value: trade.expiresAt)
                    if let sendNotes = trade.sendNotes, !sendNotes.isEmpty {
                        LabeledContent("Notes", value: sendNotes)
                    }
                }

                Section {
                    Picker("Condition", selection: $condition) {
                        ForEach(ToolCondition.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Your Condition Check (Required)")
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
                        .disabled(isSaving)

                        Spacer()

                        Button("Accept") {
                            Task { await respond(accepted: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle("Respond to Trade")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    func respond(accepted: Bool) async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "You must be signed in to respond to a trade."
            isSaving = false
            return
        }
        do {
            try service.respondToTrade(
                tradeId: trade.id,
                responderId: userId,
                accepted: accepted,
                condition: accepted ? condition.rawValue : nil,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Lost/Stolen Report Sheet

struct LostStolenReportSheet: View {
    let tool: ToolsService.ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var reportType: String = "lost"
    @State private var description: String = ""
    @State private var lastLocation: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    Text(tool.name).font(.headline)
                    if let serial = tool.serialNumber {
                        Text("S/N: \(serial)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Report Type") {
                    Picker("Type", selection: $reportType) {
                        Text("Lost").tag("lost")
                        Text("Stolen").tag("stolen")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: reportType) { _, _ in isDirty = true }
                }

                Section("Details") {
                    TextField("What happened?", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: description) { _, _ in isDirty = true }
                    TextField("Last known location", text: $lastLocation)
                        .onChange(of: lastLocation) { _, _ in isDirty = true }
                }

                Section {
                    Label {
                        Text("A manager will review this report and decide next steps.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundStyle(.orange)
                    }
                    .foregroundStyle(.secondary)
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Report \(reportType.capitalized)")
            .interactiveDismissDisabled(isDirty || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit Report") {
                        Task { await submitReport() }
                    }
                    .disabled(description.isEmpty || isSaving)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
    }

    @MainActor
    func submitReport() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            isSaving = false
            return
        }
        do {
            try service.reportToolLostOrStolen(
                toolId: tool.id,
                reportedBy: userId,
                reportType: reportType,
                description: description,
                lastKnownLocation: lastLocation.isEmpty ? nil : lastLocation
            )
            isDirty = false
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Maintenance Config Sheet

struct MaintenanceConfigSheet: View {
    let tool: ToolsService.ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: String = "time_based"
    @State private var intervalDays: Int = 90
    @State private var usageThreshold: Double = 500
    @State private var decayRate: Double = 0.02
    @State private var decayFloor: Double = 0.3
    @State private var conditionTriggers: Set<String> = ["poor", "damaged"]
    @State private var description: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    private let maintenanceTypes = [
        ("time_based", "Time-Based", "clock.fill"),
        ("usage_based", "Usage-Based", "gauge.with.dots.needle.50percent"),
        ("schedule_based", "Schedule-Based", "calendar"),
        ("decreasing_based", "Confidence Decay", "chart.line.downtrend.xyaxis"),
        ("condition_triggered", "Condition-Triggered", "exclamationmark.triangle.fill"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Maintenance Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(maintenanceTypes, id: \.0) { (value, label, icon) in
                            Label(label, systemImage: icon).tag(value)
                        }
                    }
                    .onChange(of: selectedType) { _, _ in isDirty = true }
                }

                typeSpecificSection

                Section("Description") {
                    TextField("What maintenance is needed?", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: description) { _, _ in isDirty = true }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Maintenance Rule")
            .interactiveDismissDisabled(isDirty || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveConfig() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch selectedType {
        case "time_based":
            Section("Interval") {
                Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...365)
                    .onChange(of: intervalDays) { _, _ in isDirty = true }
            }
        case "usage_based":
            Section("Usage Threshold") {
                HStack {
                    Text("After")
                    TextField("Hours", value: $usageThreshold, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: usageThreshold) { _, _ in isDirty = true }
                    Text("hours of use")
                }
            }
        case "schedule_based":
            Section("Schedule") {
                Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...730)
                    .onChange(of: intervalDays) { _, _ in isDirty = true }
                Text("Maintenance on a fixed calendar schedule")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case "decreasing_based":
            Section("Confidence Decay") {
                HStack {
                    Text("Decay rate:")
                    Slider(value: $decayRate, in: 0.001...0.1, step: 0.001)
                        .onChange(of: decayRate) { _, _ in isDirty = true }
                    Text("\(String(format: "%.1f", decayRate * 100))%/day")
                        .font(.caption).monospacedDigit()
                }
                HStack {
                    Text("Maintenance floor:")
                    Slider(value: $decayFloor, in: 0.1...0.9, step: 0.05)
                        .onChange(of: decayFloor) { _, _ in isDirty = true }
                    Text("\(Int(decayFloor * 100))%")
                        .font(.caption).monospacedDigit()
                }
                let daysUntil = decayRate > 0
                    ? Int(ceil(log(decayFloor) / log(1.0 - decayRate)))
                    : 999
                Text("At current rate, maintenance due in ~\(daysUntil) days")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case "condition_triggered":
            Section("Trigger Conditions") {
                ForEach(["fair", "poor", "damaged"], id: \.self) { cond in
                    Toggle(cond.capitalized, isOn: Binding(
                        get: { conditionTriggers.contains(cond) },
                        set: { isOn in
                            if isOn { conditionTriggers.insert(cond) }
                            else { conditionTriggers.remove(cond) }
                        }
                    ))
                }
                .onChange(of: conditionTriggers) { _, _ in isDirty = true }
                Text("Maintenance flagged when condition check returns any selected level")
                    .font(.caption).foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    @MainActor
    func saveConfig() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            _ = try service.createMaintenanceConfig(
                toolId: tool.id,
                type: selectedType,
                intervalDays: ["time_based", "schedule_based"].contains(selectedType) ? intervalDays : nil,
                usageThreshold: selectedType == "usage_based" ? usageThreshold : nil,
                decayRate: selectedType == "decreasing_based" ? decayRate : nil,
                decayFloor: selectedType == "decreasing_based" ? decayFloor : nil,
                conditionTriggers: selectedType == "condition_triggered" ? Array(conditionTriggers) : nil,
                description: description.isEmpty ? nil : description
            )
            isDirty = false
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

// MARK: - Tool Condition Enum (shared)

enum ToolCondition: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case damaged = "Damaged"
}
