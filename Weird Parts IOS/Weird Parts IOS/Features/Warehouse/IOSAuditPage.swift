import SwiftUI
import WiredPartCore

/// Warehouse audit page — confidence-based daily audit flow.
///
/// Smart card filters (Audit Now / Soon / Good / No Location),
/// warehouse score bar, audit queue grouped by shelf,
/// count flow with hidden system counts, speed mode, misplaced part handling.
struct IOSAuditPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var searchText = ""

    // Smart card filter
    @State private var filter: AuditFilter = .auditNow

    // Data
    @State private var confidenceRecords: [PartConfidence] = []
    @State private var recentSessions: [AuditSessionV2] = []
    @State private var warehouseScore: Double = 5.0
    @State private var activeCounts: [AuditCount] = []

    // Count flow
    @State private var activeSession: AuditSessionV2?
    @State private var countingPart: CountingItem?
    @State private var userCountInput = ""
    @State private var countResult: CountResult?

    // Speed mode
    @State private var speedModeActive = false
    @State private var speedQueue: [CountingItem] = []

    private enum ActiveSheet: Identifiable {
        case auditSetup
        case misplacedPart
        case countDetail(CountResult)
        case sessionSummary(AuditSessionV2)
        case help

        var id: String {
            switch self {
            case .auditSetup: "setup"
            case .misplacedPart: "misplaced"
            case .countDetail: "countDetail"
            case .sessionSummary(let s): "summary-\(s.id ?? 0)"
            case .help: "help"
            }
        }
    }

    enum AuditFilter: String, CaseIterable {
        case auditNow = "Audit Now"
        case soon = "Soon"
        case good = "Good"
        case noLocation = "No Location"

        var icon: String {
            switch self {
            case .auditNow: "exclamationmark.triangle.fill"
            case .soon: "clock.fill"
            case .good: "checkmark.seal.fill"
            case .noLocation: "mappin.slash"
            }
        }

        var color: Color {
            switch self {
            case .auditNow: .red
            case .soon: .orange
            case .good: .green
            case .noLocation: .gray
            }
        }
    }

    struct CountingItem: Identifiable {
        let id = UUID()
        let partId: Int64
        let areaId: Int64
        let partName: String
        let partCode: String?
        let locationCode: String
        let systemCount: Int
        let confidence: Double
    }

    struct CountResult: Identifiable {
        let id = UUID()
        let partName: String
        let systemCount: Int
        let userCount: Int
        let variance: Int
        let resultType: String // "exact", "neutral", "over", "under"
        let varianceDollars: Double
    }

    var body: some View {
        VStack(spacing: 0) {
            FirstVisitHint(pageId: "audit", message: "Tap 'Audit This Shelf' to count parts. The system hides expected counts so you count fresh.")

            OnboardingBanner(pageId: "warehouse-audit")

            if isLoading {
                ProgressView("Loading audit data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let counting = countingPart {
                countFlowView(counting)
            } else {
                auditContent
            }
        }
        .navigationTitle("Warehouse Audit")
        .searchable(text: $searchText, prompt: "Search parts...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    startNewSession()
                } label: {
                    Label("Start Audit", systemImage: "plus")
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
            sheetContent(for: sheet)
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .refreshable { loadData() }
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("wh-audit-view")
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .auditSetup:
            IOSAuditSetupView(onAuditCreated: { _ in
                loadData()
            })
            .environmentObject(appCore)
        case .misplacedPart:
            MisplacedPartSheet { loadData() }
                .environmentObject(appCore)
        case .countDetail(let result):
            CountResultSheet(result: result) {
                countResult = nil
                countingPart = nil
                advanceSpeedMode()
                loadData()
            } onRecount: {
                countResult = nil
                userCountInput = ""
            }
        case .sessionSummary(let session):
            SessionSummarySheet(session: session)
                .environmentObject(appCore)
        case .help:
            PageHelpSheet(
                title: "Warehouse Audit Help",
                sections: [
                    ("Confidence System", "Each part has a confidence score (0-100%) that decays daily. Auditing resets it. Parts below 80% need auditing."),
                    ("Count Flow", "System count is hidden while you count. After submitting, variance is shown with bonus/penalty."),
                    ("Speed Mode", "When areas have QR codes, speed mode auto-advances through the shelf queue."),
                    ("Misplaced Parts", "Found a part in the wrong spot? Tap '+ Misplaced' to log it for resolution.")
                ]
            )
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var auditContent: some View {
        List {
            // Smart card filters
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(AuditFilter.allCases, id: \.self) { f in
                            smartCard(
                                title: f.rawValue,
                                count: countFor(f),
                                icon: f.icon,
                                color: f.color,
                                isActive: filter == f
                            ) {
                                filter = f
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))

            // Warehouse score bar
            Section("Warehouse Score") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(format: "%.1f", warehouseScore))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(scoreColor(warehouseScore))
                        Text("/ 10")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        scoreLabel(warehouseScore)
                    }
                    ProgressView(value: warehouseScore, total: 10)
                        .tint(scoreColor(warehouseScore))
                }
                .padding(.vertical, 4)
            }

            // Active session banner
            if let session = activeSession {
                Section {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Audit Session")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("\(session.partsCounted) counted · \(session.discrepanciesFound) discrepancies")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("End") {
                            endActiveSession()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }

            // Audit queue
            if filteredQueue.isEmpty {
                Section("Audit Queue") {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.title)
                            .foregroundStyle(.green)
                        Text(filter == .good ? "All parts are in good standing!" : "No parts match this filter")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                // Group by area/shelf
                let grouped = Dictionary(grouping: filteredQueue, by: { $0.locationCode.components(separatedBy: "-").prefix(2).joined(separator: "-") })
                let sortedKeys = grouped.keys.sorted()

                ForEach(sortedKeys, id: \.self) { shelfKey in
                    let items = grouped[shelfKey] ?? []
                    Section {
                        ForEach(items, id: \.partId) { item in
                            auditQueueRow(item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    startCounting(item)
                                }
                        }

                        if activeSession != nil {
                            Button {
                                startShelfAudit(items)
                            } label: {
                                Label("Audit This Shelf", systemImage: "arrow.right.circle")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "cabinet.fill")
                                .font(.caption)
                            Text("Shelf \(shelfKey)")
                                .font(.subheadline)
                            Spacer()
                            Text("\(items.count) parts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Misplaced parts shortcut
            if activeSession != nil {
                Section {
                    Button {
                        activeSheet = .misplacedPart
                    } label: {
                        Label("+ Found Misplaced Part", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }

            // Organization Audit link
            Section("Organization") {
                NavigationLink {
                    IOSOrganizationAuditPage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.purple)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Organization Audit")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Area ratings, consolidation voting, org checklists")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Recent sessions
            if !recentSessions.isEmpty {
                Section("Recent Audits") {
                    ForEach(recentSessions, id: \.id) { session in
                        Button {
                            activeSheet = .sessionSummary(session)
                        } label: {
                            recentSessionRow(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Smart Card

    private func smartCard(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? color : .clear, lineWidth: 2)
            )
            .foregroundStyle(isActive ? color : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Count Flow View

    @ViewBuilder
    private func countFlowView(_ item: CountingItem) -> some View {
        VStack(spacing: 0) {
            if let result = countResult {
                // Show result after submission
                countResultView(item, result: result)
            } else {
                // Count entry — system count HIDDEN
                countEntryView(item)
            }
        }
    }

    private func countEntryView(_ item: CountingItem) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Part info
            VStack(spacing: 8) {
                Text(item.partName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                if let code = item.partCode {
                    Text(code)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text(item.locationCode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Confidence indicator
            HStack(spacing: 8) {
                Image(systemName: "gauge.low")
                    .foregroundStyle(confidenceColor(item.confidence))
                    .accessibilityHidden(true)
                Text("Confidence: \(Int(item.confidence))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Hidden system count indicator
            HStack {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("System count hidden — count independently")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))

            // Count input
            VStack(spacing: 12) {
                Text("How many?")
                    .font(.headline)

                TextField("0", text: $userCountInput)
                    .font(.system(.largeTitle, design: .rounded)).bold()
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .frame(width: 150)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            }

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button {
                    submitCount(item)
                } label: {
                    Text("Submit Count")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(userCountInput.isEmpty)

                Button("Cancel") {
                    countingPart = nil
                    countResult = nil
                    userCountInput = ""
                    speedModeActive = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding()
    }

    private func countResultView(_ item: CountingItem, result: CountResult) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Result icon
            Image(systemName: resultIcon(result.resultType))
                .decorativeIconFont(60)
                .foregroundStyle(resultColor(result.resultType))

            Text(resultLabel(result.resultType))
                .font(.title2)
                .fontWeight(.bold)

            // Revealed counts
            VStack(spacing: 16) {
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("System")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(result.systemCount)")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    VStack(spacing: 4) {
                        Text("Your Count")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(result.userCount)")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    VStack(spacing: 4) {
                        Text("Variance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.variance >= 0 ? "+\(result.variance)" : "\(result.variance)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(resultColor(result.resultType))
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

            if result.varianceDollars > 0 {
                Text(String(format: "Variance: $%.2f", result.varianceDollars))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    countResult = nil
                    countingPart = nil
                    advanceSpeedMode()
                    loadData()
                } label: {
                    Text("Accept Count")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 16) {
                    Button {
                        countResult = nil
                        userCountInput = ""
                    } label: {
                        Label("Count Again", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        activeSheet = .misplacedPart
                    } label: {
                        Label("Report Issue", systemImage: "flag")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding()
    }

    // MARK: - Queue Row

    private func auditQueueRow(_ item: CountingItem) -> some View {
        HStack(spacing: 12) {
            // Confidence gauge
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: item.confidence / 100)
                    .stroke(confidenceColor(item.confidence), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(item.confidence))%")
                    .font(.caption).bold()
            }
            .frame(width: 36, height: 36)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Confidence: \(Int(item.confidence))%")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.partName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let code = item.partCode, !code.isEmpty {
                    Text(code)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(item.locationCode)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Recent Session Row

    private func recentSessionRow(_ session: AuditSessionV2) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.status == "completed" ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(session.status == "completed" ? .green : .orange)
                .accessibilityLabel(session.status == "completed" ? "Status: Completed" : "Status: In progress")

            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.sessionType.capitalized) Audit")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let started = session.startedAt {
                    Text(formatDate(started))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.partsCounted) counted")
                    .font(.caption)
                if session.discrepanciesFound > 0 {
                    Text("\(session.discrepanciesFound) discrepancies")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredQueue: [CountingItem] {
        var items = buildQueue()

        // Apply filter
        switch filter {
        case .auditNow:
            items = items.filter { $0.confidence < 80 }
        case .soon:
            items = items.filter { $0.confidence >= 80 && $0.confidence < 90 }
        case .good:
            items = items.filter { $0.confidence >= 90 }
        case .noLocation:
            items = items.filter { $0.locationCode.isEmpty || $0.locationCode == "—" }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.partName.lowercased().contains(query) ||
                ($0.partCode?.lowercased().contains(query) ?? false) ||
                $0.locationCode.lowercased().contains(query)
            }
        }

        // Sort by confidence ascending (most urgent first)
        return items.sorted { $0.confidence < $1.confidence }
    }

    private func countFor(_ f: AuditFilter) -> Int {
        let all = buildQueue()
        switch f {
        case .auditNow: return all.filter { $0.confidence < 80 }.count
        case .soon: return all.filter { $0.confidence >= 80 && $0.confidence < 90 }.count
        case .good: return all.filter { $0.confidence >= 90 }.count
        case .noLocation: return all.filter { $0.locationCode.isEmpty || $0.locationCode == "—" }.count
        }
    }

    private func buildQueue() -> [CountingItem] {
        confidenceRecords.map { conf in
            CountingItem(
                partId: conf.partId,
                areaId: conf.areaId,
                partName: partName(for: conf.partId),
                partCode: partCode(for: conf.partId),
                locationCode: locationCode(for: conf.areaId),
                systemCount: conf.systemCount,
                confidence: conf.confidencePercent
            )
        }
    }

    // MARK: - Actions

    private func startNewSession() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            actionError = "Service or user unavailable"
            return
        }
        do {
            activeSession = try service.startAuditSession(startedBy: userId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func endActiveSession() {
        guard let service = appCore.warehouseService,
              let session = activeSession,
              let sessionId = session.id else {
            loadError = "Warehouse service not available"
            return
        }
        do {
            try service.completeAuditSession(sessionId: sessionId)
            activeSession = nil
            activeSheet = .sessionSummary(session)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func startCounting(_ item: CountingItem) {
        guard activeSession != nil else {
            // Auto-start a session
            startNewSession()
            return
        }
        countingPart = item
        countResult = nil
        userCountInput = ""
    }

    private func startShelfAudit(_ items: [CountingItem]) {
        speedQueue = items
        speedModeActive = true
        if let first = speedQueue.first {
            startCounting(first)
        }
    }

    private func submitCount(_ item: CountingItem) {
        guard let service = appCore.warehouseService,
              let sessionId = activeSession?.id,
              let userId = appCore.currentUser?.id,
              let userCount = Int(userCountInput) else {
            actionError = "Invalid count value"
            return
        }

        do {
            let auditCount = try service.recordAuditCount(
                sessionId: sessionId,
                partId: item.partId,
                areaId: item.areaId,
                systemCount: item.systemCount,
                userCount: userCount,
                countedBy: userId
            )

            // Update user rating
            try? service.updateUserRating(
                userId: userId,
                action: "audit",
                result: auditCount.variance == 0 ? "accurate" : "inaccurate"
            )

            countResult = CountResult(
                partName: item.partName,
                systemCount: item.systemCount,
                userCount: userCount,
                variance: auditCount.variance,
                resultType: auditCount.result,
                varianceDollars: auditCount.varianceDollars
            )
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func advanceSpeedMode() {
        guard speedModeActive, !speedQueue.isEmpty else {
            speedModeActive = false
            return
        }
        speedQueue.removeFirst()
        if let next = speedQueue.first {
            countingPart = next
            countResult = nil
            userCountInput = ""
        } else {
            speedModeActive = false
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Double) -> Color {
        if score >= 8 { return .green }
        if score >= 5 { return .orange }
        return .red
    }

    private func scoreLabel(_ score: Double) -> some View {
        let text: String
        if score >= 8 { text = "Great" }
        else if score >= 5 { text = "Fair" }
        else { text = "Needs Work" }
        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(scoreColor(score))
    }

    private func confidenceColor(_ percent: Double) -> Color {
        if percent >= 90 { return .green }
        if percent >= 80 { return .orange }
        return .red
    }

    private func resultIcon(_ type: String) -> String {
        switch type {
        case "exact": return "checkmark.circle.fill"
        case "neutral": return "equal.circle.fill"
        case "over": return "arrow.up.circle.fill"
        case "under": return "arrow.down.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private func resultColor(_ type: String) -> Color {
        switch type {
        case "exact": return .green
        case "neutral": return .blue
        case "over": return .orange
        case "under": return .red
        default: return .gray
        }
    }

    private func resultLabel(_ type: String) -> String {
        switch type {
        case "exact": return "Exact Match! +Bonus"
        case "neutral": return "Within Tolerance"
        case "over": return "Over Count"
        case "under": return "Under Count — Penalty"
        default: return "Result"
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    // Part/location name lookups — uses cached data or fallback
    @State private var partNameCache: [Int64: String] = [:]
    @State private var partCodeCache: [Int64: String] = [:]
    @State private var locationCodeCache: [Int64: String] = [:]

    private func partName(for partId: Int64) -> String {
        partNameCache[partId] ?? "Part #\(partId)"
    }

    private func partCode(for partId: Int64) -> String? {
        partCodeCache[partId]
    }

    private func locationCode(for areaId: Int64) -> String {
        locationCodeCache[areaId] ?? "—"
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service unavailable"
            isLoading = false
            return
        }
        isLoading = confidenceRecords.isEmpty
        loadError = nil
        do {
            // Load confidence records
            confidenceRecords = try service.getPartsAtLevel(level: 0)
            // Also load higher levels up to 10
            for level in 1...10 {
                let levelRecords = try service.getPartsAtLevel(level: level)
                confidenceRecords.append(contentsOf: levelRecords)
            }

            // Load warehouse score
            warehouseScore = try service.getWarehouseOverallScore()

            // Load recent sessions
            recentSessions = try service.listAuditSessions(limit: 5)

            // Check for active session
            let activeSessions = try service.listAuditSessions(status: "active", limit: 1)
            activeSession = activeSessions.first

            // Build lookup caches from confidence records
            loadNameCaches(service: service)

        } catch {
            loadError = userFriendlyError(error, context: "load audit data")
        }
        isLoading = false
    }

    private func loadNameCaches(service: WarehouseService) {
        for conf in confidenceRecords {
            if partNameCache[conf.partId] == nil {
                if let name = try? service.getPartName(partId: conf.partId) {
                    partNameCache[conf.partId] = name
                }
            }
            if locationCodeCache[conf.areaId] == nil {
                if let code = try? service.generateFullLocationCode(areaId: conf.areaId) {
                    locationCodeCache[conf.areaId] = code
                }
            }
        }
    }
}

// MARK: - Misplaced Part Sheet

private struct MisplacedPartSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var partName = ""
    @State private var qtyFound = 1
    @State private var resolution: String = "carted"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Misplaced Part") {
                    TextField("Part name or scan", text: $partName)
                    Stepper("Quantity: \(qtyFound)", value: $qtyFound, in: 1...999)
                }

                Section("What to do?") {
                    Picker("Resolution", selection: $resolution) {
                        Text("Cart (sort later)").tag("carted")
                        Text("Leave here").tag("left_here")
                        Text("Move to home").tag("moved_to_home")
                    }
                    .pickerStyle(.inline)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Misplaced Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { saveMisplaced() }
                            .fontWeight(.semibold)
                            .disabled(partName.isEmpty)
                    }
                }
            }
        }
    }

    private func saveMisplaced() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Service unavailable"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            // Log with placeholder IDs — in production would resolve from search
            try service.logMisplacedPart(
                partId: 0,
                foundAtAreaId: 0,
                homeAreaId: nil,
                qtyFound: qtyFound,
                foundBy: userId
            )
            try service.updateUserRating(userId: userId, action: "misplacement_find")
            onSave()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "load audit")
        }
        isSaving = false
    }
}

// MARK: - Count Result Sheet

private struct CountResultSheet: View {
    let result: IOSAuditPage.CountResult
    let onAccept: () -> Void
    let onRecount: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(result.partName)
                    .font(.title3)
                    .fontWeight(.bold)

                HStack(spacing: 24) {
                    VStack {
                        Text("System").font(.caption).foregroundStyle(.secondary)
                        Text("\(result.systemCount)").font(.title2).fontWeight(.bold)
                    }
                    VStack {
                        Text("Yours").font(.caption).foregroundStyle(.secondary)
                        Text("\(result.userCount)").font(.title2).fontWeight(.bold)
                    }
                    VStack {
                        Text("Variance").font(.caption).foregroundStyle(.secondary)
                        Text(result.variance >= 0 ? "+\(result.variance)" : "\(result.variance)")
                            .font(.title2).fontWeight(.bold)
                    }
                }

                Spacer()

                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                Button("Count Again", action: onRecount)
                    .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Result")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Session Summary Sheet

private struct SessionSummarySheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let session: AuditSessionV2

    @State private var counts: [AuditCount] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Session Info") {
                    LabeledContent("Type", value: session.sessionType.capitalized)
                    LabeledContent("Status", value: session.status.capitalized)
                    LabeledContent("Parts Counted", value: "\(session.partsCounted)")
                    LabeledContent("Discrepancies", value: "\(session.discrepanciesFound)")
                    LabeledContent("Misplaced", value: "\(session.misplacedFound)")
                }

                if !counts.isEmpty {
                    Section("Counts (\(counts.count))") {
                        ForEach(counts, id: \.id) { count in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Part #\(count.partId)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Sys: \(count.systemCount) → You: \(count.userCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(count.result.capitalized)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(
                                            count.result == "exact" ? Color.green.opacity(0.15) :
                                            count.result == "neutral" ? Color.blue.opacity(0.15) :
                                            Color.red.opacity(0.15)
                                        )
                                    )
                                    .foregroundStyle(
                                        count.result == "exact" ? .green :
                                        count.result == "neutral" ? .blue : .red
                                    )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audit Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let service = appCore.warehouseService,
                   let sessionId = session.id {
                    counts = (try? service.getAuditCounts(sessionId: sessionId)) ?? []
                }
            }
        }
    }
}
