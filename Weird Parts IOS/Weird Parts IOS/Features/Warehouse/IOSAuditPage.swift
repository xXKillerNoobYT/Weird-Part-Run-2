import SwiftUI
import WiredPartCore
import os

private let auditLog = Logger(subsystem: "com.wiredpart", category: "warehouse.audit")

/// Warehouse audit page — confidence-based daily audit flow.
///
/// Smart card filters (Audit Now / Soon / Good / No Location),
/// warehouse score bar, audit queue grouped by shelf,
/// count flow with hidden system counts, speed mode, misplaced part handling.
struct IOSAuditPage: View {
    @EnvironmentObject private var appCore: AppCore
    private static let multiUserFixtureFlag = "-UITestingMultiUserVerificationFixture"
    private static let multiUserFixturePartCode = "UITEST-MUV-001"

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
    @State private var selectedItemForVerification: CountingItem?

    // Count flow
    @State private var activeSession: AuditSessionV2?
    @State private var countingPart: CountingItem?
    @State private var userCountInput = ""
    @State private var countResult: CountResult?

    // Speed mode
    @State private var speedModeActive = false
    @State private var speedQueue: [CountingItem] = []

    // Walking-path audit
    @State private var floorPlanId: Int64?
    @State private var walkingPathAreaIds: [Int64] = []
    @State private var walkingPathSourceHint: String?
    @State private var prunedStopsBanner: String?
    @State private var walkingPathActive = false
    @State private var currentPathStopIndex = 0

    private enum ActiveSheet: Identifiable {
        case auditSetup
        case misplacedPart(partId: Int64?, areaId: Int64?)
        case countDetail(CountResult)
        case sessionSummary(AuditSessionV2)
        case help

        var id: String {
            switch self {
            case .auditSetup: "setup"
            case .misplacedPart(let partId, let areaId): "misplaced-\(partId ?? 0)-\(areaId ?? 0)"
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
            } else if walkingPathActive {
                walkingPathStopView
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
        .sheet(item: $selectedItemForVerification) { item in
            QueueSendForVerificationSheet(item: item, sessionId: activeSession?.id) {
                selectedItemForVerification = nil
                loadData()
            }
            .environmentObject(appCore)
        }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .refreshable { loadData() }
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("wh-audit-view")
        }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseAuditPageInactive, object: nil)
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
        case .misplacedPart(let partId, let areaId):
            MisplacedPartSheet(
                candidates: buildQueue(),
                initialPartId: partId,
                initialAreaId: areaId
            ) { loadData() }
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

            if !walkingPathAreaIds.isEmpty || walkingPathSourceHint != nil || prunedStopsBanner != nil {
                Section("Walking Path") {
                    if let prunedStopsBanner {
                        Label(prunedStopsBanner, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let walkingPathSourceHint {
                        Label(walkingPathSourceHint, systemImage: "figure.walk")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if walkingPathAreaIds.isEmpty {
                        Text("No audit stops available yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            startWalkingPathAudit()
                        } label: {
                            Label("Walk \(walkingPathAreaIds.count) Stops", systemImage: "arrow.forward.circle")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
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
                            .accessibilityHidden(true)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        selectedItemForVerification = item
                                    } label: {
                                        Label("Verify", systemImage: "person.2.badge.gearshape")
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button {
                                        selectedItemForVerification = item
                                    } label: {
                                        Label("Verify", systemImage: "person.2.badge.gearshape")
                                    }
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
                                .accessibilityHidden(true)
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
                        activeSheet = .misplacedPart(partId: nil, areaId: nil)
                    } label: {
                        Label("+ Found Misplaced Part", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }

            if isMultiUserVerificationFixtureEnabled {
                Section("QA Fixture") {
                    if let fixtureItem = fixtureVerificationItem {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fixtureItem.partName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(fixtureItem.partCode ?? Self.multiUserFixturePartCode)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                selectedItemForVerification = fixtureItem
                            } label: {
                                Label("Verify Fixture Part", systemImage: "person.2.badge.gearshape")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .accessibilityIdentifier("qaFixtureVerifyButton")
                        }
                        .accessibilityIdentifier("qaFixturePartRow")
                    } else {
                        Text("Fixture part \(Self.multiUserFixturePartCode) is not available in this audit queue yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("qaFixturePartMissingMessage")
                    }
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
                            .accessibilityHidden(true)
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
        .scrollDismissesKeyboard(.interactively)
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
                        activeSheet = .misplacedPart(partId: item.partId, areaId: item.areaId)
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

    private var walkingPathStopView: some View {
        let areaId = currentWalkingPathAreaId
        let stopItems = areaId.map(itemsForArea) ?? []
        return VStack(spacing: 0) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stop \(min(currentPathStopIndex + 1, walkingPathAreaIds.count)) of \(walkingPathAreaIds.count)")
                            .font(.headline)
                        Text(areaId.map(locationCode(for:)) ?? "Unknown area")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(stopLabel(for: areaId))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if stopItems.isEmpty {
                    Section {
                        EmptyStateView(
                            icon: "tray",
                            title: "No parts here",
                            message: "Confirm empty or report count."
                        )

                        Button {
                            recordWalkingPathEvent(type: "empty_confirmed", notes: "Confirmed empty walking-path stop")
                            advanceWalkingPathStop()
                        } label: {
                            Label("Confirm Empty", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            recordWalkingPathEvent(type: "count_reported", notes: "Reported count issue at empty walking-path stop")
                            activeSheet = .misplacedPart(partId: nil, areaId: areaId)
                        } label: {
                            Label("Report Count", systemImage: "flag")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                } else {
                    Section("Parts") {
                        ForEach(stopItems, id: \.partId) { item in
                            auditQueueRow(item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    startCounting(item)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        selectedItemForVerification = item
                                    } label: {
                                        Label("Verify", systemImage: "person.2.badge.gearshape")
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button {
                                        selectedItemForVerification = item
                                    } label: {
                                        Label("Verify", systemImage: "person.2.badge.gearshape")
                                    }
                                }
                        }
                    }

                    Section {
                        Button {
                            recordWalkingPathEvent(type: "stop_completed", notes: "Completed walking-path stop")
                            advanceWalkingPathStop()
                        } label: {
                            Label("Next Stop", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            recordWalkingPathEvent(type: "deviation_reported", notes: "Reported issue during walking-path stop")
                            activeSheet = .misplacedPart(partId: nil, areaId: areaId)
                        } label: {
                            Label("Report Issue", systemImage: "flag")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }

            HStack {
                Button("Exit Walkthrough") {
                    walkingPathActive = false
                    currentPathStopIndex = 0
                }
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))
        }
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
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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

    private var isMultiUserVerificationFixtureEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(Self.multiUserFixtureFlag)
    }

    private var fixtureVerificationItem: CountingItem? {
        buildQueue().first {
            $0.partCode == Self.multiUserFixturePartCode ||
            $0.partName == "UITest Verification Part"
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

    private var currentWalkingPathAreaId: Int64? {
        guard walkingPathAreaIds.indices.contains(currentPathStopIndex) else { return nil }
        return walkingPathAreaIds[currentPathStopIndex]
    }

    private func itemsForArea(_ areaId: Int64) -> [CountingItem] {
        buildQueue()
            .filter { $0.areaId == areaId }
            .sorted { $0.partName < $1.partName }
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

    private func startWalkingPathAudit() {
        if activeSession == nil {
            startNewSession()
        }
        guard activeSession != nil else { return }
        currentPathStopIndex = 0
        walkingPathActive = true
        recordWalkingPathEvent(type: "walking_path_started", notes: walkingPathSourceHint)
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
        if activeSession == nil {
            // Auto-start a session, then immediately proceed to count if successful
            startNewSession()
            guard activeSession != nil else { return }
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

            // Update user rating — non-critical but log failures
            do {
                try service.updateUserRating(
                    userId: userId,
                    action: "audit",
                    result: auditCount.variance == 0 ? "accurate" : "inaccurate"
                )
            } catch {
                // Rating update failed — audit count is already saved; continue.
                // Fix #226: route through os.Logger for unified logging.
                auditLog.error("updateUserRating failed (non-critical): \(error.localizedDescription, privacy: .public)")
            }

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

    private func advanceWalkingPathStop() {
        if currentPathStopIndex + 1 < walkingPathAreaIds.count {
            currentPathStopIndex += 1
        } else {
            recordWalkingPathEvent(type: "walking_path_completed", notes: "Completed walking-path audit")
            walkingPathActive = false
            currentPathStopIndex = 0
            loadData()
        }
    }

    private func recordWalkingPathEvent(type: String, notes: String? = nil) {
        guard let service = appCore.warehouseService else {
            auditLog.error("recordAuditSessionEvent skipped: warehouse service unavailable")
            return
        }
        guard let sessionId = activeSession?.id else {
            auditLog.error("recordAuditSessionEvent skipped: no active audit session")
            return
        }
        do {
            try service.recordAuditSessionEvent(
                sessionId: sessionId,
                eventType: type,
                areaId: currentWalkingPathAreaId,
                walkingPathStopIndex: currentPathStopIndex,
                notes: notes,
                recordedBy: appCore.currentUser?.id
            )
        } catch {
            auditLog.error("recordAuditSessionEvent failed: \(error.localizedDescription, privacy: .public)")
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

    private func stopLabel(for areaId: Int64?) -> String {
        guard let areaId else { return "Unit · Shelf · Area" }
        let parts = locationCode(for: areaId).split(separator: "-").map(String.init)
        if parts.count >= 4 {
            return "\(parts[1]) · \(parts[2]) · \(parts[3])"
        }
        return "Unit · Shelf · Area"
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

            loadWalkingPath(service: service)
            postAIContext()

        } catch {
            loadError = userFriendlyError(error, context: "load audit data")
        }
        isLoading = false
    }

    private func postAIContext() {
        let context = """
        Warehouse Audit page. Read-only context.
        Confidence records loaded: \(confidenceRecords.count), recent sessions: \(recentSessions.count), active counts: \(activeCounts.count), warehouse score: \(String(format: "%.1f", warehouseScore)).
        Selected filter: \(filter.rawValue), visible search active: \(!searchText.isEmpty), active session: \(activeSession != nil), counting part: \(countingPart?.partName ?? "none"), speed mode: \(speedModeActive), walking path active: \(walkingPathActive).
        Filter counts: Audit Now \(countFor(.auditNow)), Soon \(countFor(.soon)), Good \(countFor(.good)), No Location \(countFor(.noLocation)).
        Available read-only guidance: explain confidence scores, filter cards, audit sessions, speed mode, walking path, and misplaced-part entry point. Do not start audits, submit counts, or log misplaced parts directly.
        """
        NotificationCenter.default.post(
            name: .warehouseAuditPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }

    private func loadNameCaches(service: WarehouseService) {
        for conf in confidenceRecords {
            if partNameCache[conf.partId] == nil {
                if let name = try? service.getPartName(partId: conf.partId) {
                    partNameCache[conf.partId] = name
                }
            }
            if partCodeCache[conf.partId] == nil {
                if let code = try? service.getPartCode(partId: conf.partId) {
                    partCodeCache[conf.partId] = code
                }
            }
            if locationCodeCache[conf.areaId] == nil {
                if let code = try? service.generateFullLocationCode(areaId: conf.areaId) {
                    locationCodeCache[conf.areaId] = code
                }
            }
        }
    }

    private func loadWalkingPath(service: WarehouseService) {
        do {
            guard let floorPlanId = try service.getOnboardingProgress()?.floorPlanId else {
                walkingPathAreaIds = []
                walkingPathSourceHint = nil
                prunedStopsBanner = nil
                self.floorPlanId = nil
                return
            }

            self.floorPlanId = floorPlanId
            let pruned = try service.pruneOrphanedStops(floorPlanId: floorPlanId)
            prunedStopsBanner = pruned > 0
                ? "\(pruned) saved walking-path stop was no longer available and was removed."
                : nil

            if let path = try service.getDefaultWalkingPath(floorPlanId: floorPlanId),
               !path.stops.isEmpty {
                walkingPathAreaIds = path.stops.map(\.areaId)
                walkingPathSourceHint = nil
            } else {
                walkingPathAreaIds = try service.suggestWalkingPath(floorPlanId: floorPlanId)
                walkingPathSourceHint = walkingPathAreaIds.isEmpty ? nil : "No walking path saved. Using suggested order for this audit."
            }

            for areaId in walkingPathAreaIds where locationCodeCache[areaId] == nil {
                locationCodeCache[areaId] = try? service.generateFullLocationCode(areaId: areaId)
            }
        } catch {
            auditLog.error("loadWalkingPath failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct QueueSendForVerificationSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let item: IOSAuditPage.CountingItem
    let sessionId: Int64?
    let onSent: () -> Void

    @State private var requiredCounts = 2
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    LabeledContent("Part", value: item.partName)
                    if let code = item.partCode, !code.isEmpty {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Location", value: item.locationCode)
                    LabeledContent("Expected", value: "\(item.systemCount)")
                }

                Section("Verification") {
                    Stepper("Required counters: \(requiredCounts)", value: $requiredCounts, in: 2...3)
                    Text("Counters are assigned automatically from eligible active users.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send for Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Send") { submit() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func submit() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Service or user unavailable."
            return
        }

        isSaving = true
        errorMessage = nil
        do {
            _ = try service.flagForMultiUserAudit(
                partId: item.partId,
                expectedQty: item.systemCount,
                sessionId: sessionId,
                flaggedBy: userId,
                requiredCounts: requiredCounts
            )
            onSent()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "send for multi-user verification")
        }
        isSaving = false
    }
}

// MARK: - Misplaced Part Sheet

private struct MisplacedPartSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let candidates: [IOSAuditPage.CountingItem]
    let initialPartId: Int64?
    let initialAreaId: Int64?
    let onSave: () -> Void

    @State private var partQuery = ""
    @State private var areaQuery = ""
    @State private var selectedPart: MisplacedLookupPart?
    @State private var selectedArea: MisplacedLookupArea?
    @State private var partResults: [MisplacedLookupPart] = []
    @State private var areaResults: [MisplacedLookupArea] = []
    @State private var homeOptions: [MisplacedLookupArea] = []
    @State private var homeAreaId: Int64?
    @State private var qtyFound = 1
    @State private var resolution: String = "sort_later"
    @State private var isSaving = false
    @State private var didConfigureInitialSelection = false
    @State private var partLookupMessage: LookupMessage?
    @State private var areaLookupMessage: LookupMessage?
    @State private var homeLookupMessage: LookupMessage?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if serviceUnavailable {
                    Section {
                        InlineStatusView(
                            systemImage: "wifi.slash",
                            title: "Service unavailable",
                            message: "Warehouse services must be available before logging misplaced parts.",
                            color: .orange
                        )
                    }
                }

                Section("Part found") {
                    selectedPartSummary

                    HStack {
                        TextField("Scan or search part", text: $partQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit(searchParts)
                        Button {
                            resolvePartQuery()
                        } label: {
                            Label("Scan", systemImage: "barcode.viewfinder")
                        }
                        .disabled(isSaving || partQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Button {
                        searchParts()
                    } label: {
                        Label("Search Parts", systemImage: "magnifyingglass")
                    }
                    .disabled(isSaving || partQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let partLookupMessage {
                        lookupMessageView(partLookupMessage)
                    }

                    partResultsView
                }

                Section("Found at") {
                    selectedAreaSummary

                    HStack {
                        TextField("Scan area QR or search location", text: $areaQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit(searchAreas)
                        Button {
                            resolveAreaQuery()
                        } label: {
                            Label("Scan", systemImage: "qrcode.viewfinder")
                        }
                        .disabled(isSaving || areaQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Button {
                        searchAreas()
                    } label: {
                        Label("Search Locations", systemImage: "magnifyingglass")
                    }
                    .disabled(isSaving || areaQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let areaLookupMessage {
                        lookupMessageView(areaLookupMessage)
                    }

                    areaResultsView
                }

                Section("Expected home") {
                    Button {
                        homeAreaId = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sort later")
                                Text("Log safely without guessing the home shelf.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if homeAreaId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }

                    ForEach(homeOptions) { area in
                        Button {
                            homeAreaId = area.id
                        } label: {
                            lookupAreaRow(area, selected: homeAreaId == area.id, showsHomeBadge: true)
                        }
                    }

                    if let homeLookupMessage {
                        lookupMessageView(homeLookupMessage)
                    }
                }

                Section("Quantity") {
                    Stepper("Quantity: \(qtyFound)", value: $qtyFound, in: 1...999)
                    TextField("Quantity", value: $qtyFound, format: .number)
                        .keyboardType(.numberPad)
                }

                Section("What to do?") {
                    Picker("Resolution", selection: $resolution) {
                        Text("Add to cart / sort later").tag("sort_later")
                        Text("Quick fix here").tag("quick_fix")
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
            .presentationDetents([.medium, .large])
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { saveMisplaced() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                            .accessibilityHint(saveDisabledReason ?? "Log misplaced part")
                    }
                }
            }
            .disabled(isSaving)
            .onAppear(perform: configureInitialSelection)
            .interactiveDismissDisabled(isSaving)
        }
    }

    @ViewBuilder
    private var selectedPartSummary: some View {
        if let selectedPart {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    lookupPartText(selectedPart)
                    Spacer()
                    Button("Change") {
                        self.selectedPart = nil
                        homeOptions = []
                        homeAreaId = nil
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isSelected)
            }
        } else {
            validationText("Select the part you found.")
        }
    }

    @ViewBuilder
    private var selectedAreaSummary: some View {
        if let selectedArea {
            HStack(alignment: .top) {
                lookupAreaText(selectedArea, showsHomeBadge: false)
                Spacer()
                Button("Change") {
                    self.selectedArea = nil
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isSelected)
        } else {
            validationText("Select where you found it.")
        }
    }

    @ViewBuilder
    private var partResultsView: some View {
        if partResults.isEmpty && selectedPart == nil && partLookupMessage == nil {
            ForEach(contextPartCandidates) { part in
                Button {
                    selectPart(part)
                } label: {
                    lookupPartRow(part, selected: false)
                }
            }
        } else {
            ForEach(partResults) { part in
                Button {
                    selectPart(part)
                } label: {
                    lookupPartRow(part, selected: selectedPart?.id == part.id)
                }
            }
        }
    }

    @ViewBuilder
    private var areaResultsView: some View {
        if areaResults.isEmpty && selectedArea == nil && areaLookupMessage == nil {
            ForEach(contextAreaCandidates) { area in
                Button {
                    selectedArea = area
                    areaLookupMessage = nil
                } label: {
                    lookupAreaRow(area, selected: false, showsHomeBadge: false)
                }
            }
        } else {
            ForEach(areaResults) { area in
                Button {
                    selectedArea = area
                    areaLookupMessage = nil
                } label: {
                    lookupAreaRow(area, selected: selectedArea?.id == area.id, showsHomeBadge: false)
                }
            }
        }
    }

    private var contextPartCandidates: [MisplacedLookupPart] {
        var seen: Set<Int64> = []
        return candidates.compactMap { item in
            guard !seen.contains(item.partId) else { return nil }
            seen.insert(item.partId)
            return MisplacedLookupPart(
                id: item.partId,
                name: item.partName,
                code: item.partCode,
                detail: "Audit queue candidate",
                totalStock: nil
            )
        }
    }

    private var contextAreaCandidates: [MisplacedLookupArea] {
        var seen: Set<Int64> = []
        return candidates.compactMap { item in
            guard !seen.contains(item.areaId) else { return nil }
            seen.insert(item.areaId)
            return MisplacedLookupArea(
                id: item.areaId,
                label: item.locationCode,
                detail: "Audit queue location",
                isHome: false
            )
        }
    }

    private var canSave: Bool {
        guard !serviceUnavailable, qtyFound >= 1, qtyFound <= 999 else { return false }
        guard let partId = selectedPart?.id, partId > 0 else { return false }
        guard let areaId = selectedArea?.id, areaId > 0 else { return false }
        return true
    }

    private var serviceUnavailable: Bool {
        appCore.warehouseService == nil || appCore.partsService == nil || appCore.currentUser?.id == nil
    }

    private var saveDisabledReason: String? {
        if serviceUnavailable { return "Warehouse services are unavailable." }
        if selectedPart?.id ?? 0 <= 0 { return "Select the part you found." }
        if selectedArea?.id ?? 0 <= 0 { return "Select where you found it." }
        if qtyFound < 1 { return "Quantity must be at least 1." }
        if qtyFound > 999 { return "Quantity must be 999 or less." }
        return nil
    }

    private func configureInitialSelection() {
        guard !didConfigureInitialSelection else { return }
        didConfigureInitialSelection = true

        if let initialPartId, initialPartId > 0 {
            resolvePart(id: initialPartId)
        } else if !contextPartCandidates.isEmpty {
            partResults = contextPartCandidates
            if initialPartId == nil {
                partLookupMessage = .info("Select the part you found.")
            }
        }

        if let initialAreaId, initialAreaId > 0 {
            resolveArea(id: initialAreaId)
        } else {
            areaResults = contextAreaCandidates
            if initialAreaId == nil {
                areaLookupMessage = .info("Select where you found it.")
            }
        }
    }

    private func searchParts() {
        guard let service = appCore.partsService else {
            partLookupMessage = .error("Part lookup failed. Try again or scan the label.")
            return
        }
        let query = partQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            partResults = contextPartCandidates
            partLookupMessage = .info("Search or scan a part label.")
            return
        }
        do {
            let parts = try service.searchParts(query: query, limit: 15)
            partResults = parts.compactMap { part in
                guard let id = part.id, id > 0, part.deletedAt == nil else { return nil }
                let stock = (try? service.getPartStockSummary(partId: id).total)
                return MisplacedLookupPart(
                    id: id,
                    name: part.name,
                    code: part.code,
                    detail: part.manufacturerPartNumber,
                    totalStock: stock
                )
            }
            partLookupMessage = partResults.isEmpty
                ? .empty("No matching parts", "Check the label or scan the part QR.")
                : nil
        } catch {
            partResults = []
            partLookupMessage = .error("Part lookup failed. Try again or scan the label.")
        }
    }

    private func resolvePartQuery() {
        let query = partQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int64(query), id > 0 {
            resolvePart(id: id)
        } else {
            searchParts()
        }
    }

    private func resolvePart(id: Int64) {
        guard let service = appCore.partsService else {
            partLookupMessage = .error("Part lookup failed. Try again or scan the label.")
            return
        }
        do {
            let detail = try service.getPart(id: id)
            guard let partId = detail.part.id, partId > 0, detail.part.deletedAt == nil else {
                selectedPart = nil
                partLookupMessage = .error("That part or location is no longer available. Search again.")
                return
            }
            selectPart(MisplacedLookupPart(
                id: partId,
                name: detail.part.name,
                code: detail.part.code,
                detail: [detail.brandName, detail.colorName].compactMap { $0 }.joined(separator: " / "),
                totalStock: detail.totalStock
            ))
        } catch {
            selectedPart = nil
            partLookupMessage = .error("That part or location is no longer available. Search again.")
        }
    }

    private func selectPart(_ part: MisplacedLookupPart) {
        guard part.id > 0 else {
            selectedPart = nil
            partLookupMessage = .error("That part or location is no longer available. Search again.")
            return
        }
        selectedPart = part
        partLookupMessage = nil
        loadHomeOptions(for: part.id)
    }

    private func searchAreas() {
        guard let service = appCore.warehouseService else {
            areaLookupMessage = .error("Location lookup failed. Try again or choose from the list.")
            return
        }
        let query = areaQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            areaResults = contextAreaCandidates
            areaLookupMessage = .info("Search or scan a location code.")
            return
        }
        do {
            areaResults = try service.searchActiveAreas(query: query, limit: 15).map(MisplacedLookupArea.init(info:))
            areaLookupMessage = areaResults.isEmpty
                ? .empty("No warehouse locations found", "Set up storage areas before logging misplaced parts.")
                : nil
        } catch {
            areaResults = []
            areaLookupMessage = .error("Location lookup failed. Try again or choose from the list.")
        }
    }

    private func resolveAreaQuery() {
        guard let service = appCore.warehouseService else {
            areaLookupMessage = .error("Location lookup failed. Try again or choose from the list.")
            return
        }
        let query = areaQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            areaLookupMessage = .info("Search or scan a location code.")
            return
        }
        do {
            if let scan = try service.getLocationByQR(qrCode: query) {
                selectedArea = MisplacedLookupArea(
                    id: scan.areaId,
                    label: scan.fullLocationCode,
                    detail: "\(scan.unitName) / \(scan.levelName) / \(scan.areaCode)",
                    isHome: false
                )
                areaLookupMessage = nil
            } else {
                searchAreas()
            }
        } catch {
            selectedArea = nil
            areaLookupMessage = .error("Location lookup failed. Try again or choose from the list.")
        }
    }

    private func resolveArea(id: Int64) {
        guard let service = appCore.warehouseService else {
            areaLookupMessage = .error("Location lookup failed. Try again or choose from the list.")
            return
        }
        do {
            selectedArea = MisplacedLookupArea(info: try service.getActiveArea(id: id))
            areaLookupMessage = nil
        } catch {
            selectedArea = nil
            areaLookupMessage = .error("That part or location is no longer available. Search again.")
        }
    }

    private func loadHomeOptions(for partId: Int64) {
        guard let service = appCore.warehouseService else {
            homeOptions = []
            homeAreaId = nil
            homeLookupMessage = .error("Location lookup failed. Try again or choose from the list.")
            return
        }
        do {
            let assignments = try service.getPartAssignments(partId: partId)
            homeOptions = assignments.map { assignment in
                MisplacedLookupArea(
                    id: assignment.areaId,
                    label: assignment.fullLocationCode ?? "\(assignment.unitName) \(assignment.levelCode) \(assignment.areaCode)",
                    detail: "\(assignment.unitName) / \(assignment.levelCode) / \(assignment.areaCode)",
                    isHome: assignment.isHome
                )
            }
            let homeAssignments = homeOptions.filter(\.isHome)
            homeAreaId = homeAssignments.count == 1 ? homeAssignments[0].id : nil
            homeLookupMessage = homeOptions.isEmpty
                ? .info("No home assignment found. Sort later is selected.")
                : nil
        } catch {
            homeOptions = []
            homeAreaId = nil
            homeLookupMessage = .error("Location lookup failed. Try again or choose from the list.")
        }
    }

    private func saveMisplaced() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Service or user unavailable."
            return
        }
        guard let partId = selectedPart?.id, partId > 0 else {
            errorMessage = "Select the part you found."
            return
        }
        guard let foundAtAreaId = selectedArea?.id, foundAtAreaId > 0 else {
            errorMessage = "Select where you found it."
            return
        }
        if qtyFound < 1 {
            errorMessage = "Quantity must be at least 1."
            return
        }
        if qtyFound > 999 {
            errorMessage = "Quantity must be 999 or less."
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            let log = try service.logMisplacedPart(
                partId: partId,
                foundAtAreaId: foundAtAreaId,
                homeAreaId: homeAreaId,
                qtyFound: qtyFound,
                foundBy: userId
            )
            if resolution != "sort_later" {
                guard let logId = log.id else {
                    errorMessage = "Misplaced-part log was saved without an ID. Refresh and try again."
                    isSaving = false
                    return
                }
                try service.resolveMisplacedPart(
                    logId: logId,
                    resolution: resolution,
                    resolvedBy: userId
                )
            }
            try service.updateUserRating(userId: userId, action: "misplacement_find")
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "log misplaced part")
        }
        isSaving = false
    }

    @ViewBuilder
    private func lookupMessageView(_ message: LookupMessage) -> some View {
        switch message {
        case .info(let text):
            validationText(text)
        case .error(let text):
            InlineStatusView(systemImage: "exclamationmark.triangle", title: text, message: nil, color: .red)
        case .empty(let title, let detail):
            InlineStatusView(systemImage: "magnifyingglass", title: title, message: detail, color: .secondary)
        }
    }

    private func validationText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func lookupPartRow(_ part: MisplacedLookupPart, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            lookupPartText(part)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
    }

    private func lookupPartText(_ part: MisplacedLookupPart) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(part.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let code = part.code, !code.isEmpty {
                Text(code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let detail = part.detail, !detail.isEmpty {
                    Text(detail)
                }
                if let totalStock = part.totalStock {
                    Text("Stock \(totalStock)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func lookupAreaRow(_ area: MisplacedLookupArea, selected: Bool, showsHomeBadge: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            lookupAreaText(area, showsHomeBadge: showsHomeBadge)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
    }

    private func lookupAreaText(_ area: MisplacedLookupArea, showsHomeBadge: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(area.label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if showsHomeBadge && area.isHome {
                    Text("Home")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            if !area.detail.isEmpty {
                Text(area.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct MisplacedLookupPart: Identifiable, Equatable {
    let id: Int64
    let name: String
    let code: String?
    let detail: String?
    let totalStock: Int?
}

private struct MisplacedLookupArea: Identifiable, Equatable {
    let id: Int64
    let label: String
    let detail: String
    let isHome: Bool

    init(id: Int64, label: String, detail: String, isHome: Bool) {
        self.id = id
        self.label = label
        self.detail = detail
        self.isHome = isHome
    }

    init(info: WarehouseService.ActiveAreaInfo) {
        self.id = info.id
        self.label = info.displayLabel
        self.detail = info.detailLabel
        self.isHome = false
    }
}

private enum LookupMessage: Equatable {
    case info(String)
    case error(String)
    case empty(String, String)
}

private struct InlineStatusView: View {
    let systemImage: String
    let title: String
    let message: String?
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                if let message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
