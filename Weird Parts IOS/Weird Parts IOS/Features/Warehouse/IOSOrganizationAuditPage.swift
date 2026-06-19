import SwiftUI
import WiredPartCore

/// Organization audit tab — focuses on warehouse organization quality.
///
/// Shows per-area organization ratings, consolidation voting,
/// and a checklist for area org audits.
struct IOSOrganizationAuditPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var searchText = ""

    // Data
    @State private var orgRatings: [OrganizationRating] = []
    @State private var consolidationVotes: [ConsolidationVote] = []
    @State private var warehouseScore: Double = 5.0

    // Tab filter
    @State private var tab: OrgTab = .ratings

    private enum ActiveSheet: Identifiable {
        case orgChecklist(Int64) // areaId
        case consolidationDetail(ConsolidationVote)
        case managerOverride(ConsolidationVote)
        case help

        var id: String {
            switch self {
            case .orgChecklist(let id): "org-\(id)"
            case .consolidationDetail(let v): "consol-\(v.id ?? 0)"
            case .managerOverride(let v): "override-\(v.id ?? 0)"
            case .help: "help"
            }
        }
    }

    enum OrgTab: String, CaseIterable {
        case ratings = "Ratings"
        case consolidation = "Consolidation"

        var icon: String {
            switch self {
            case .ratings: "chart.bar.fill"
            case .consolidation: "arrow.triangle.merge"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading organization data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                orgContent
            }
        }
        .navigationTitle("Organization Audit")
        .searchable(text: $searchText, prompt: "Search areas...")
        .onChange(of: searchText) { _, _ in postAIContext() }
        .onChange(of: tab) { _, _ in postAIContext() }
        .toolbar {
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
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseOrganizationAuditPageInactive, object: nil)
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .orgChecklist(let areaId):
            OrgChecklistSheet(areaId: areaId) { loadData() }
                .environmentObject(appCore)
        case .consolidationDetail(let vote):
            ConsolidationDetailSheet(vote: vote) { loadData() }
                .environmentObject(appCore)
        case .managerOverride(let vote):
            ManagerOverrideSheet(vote: vote) { loadData() }
                .environmentObject(appCore)
        case .help:
            PageHelpSheet(
                title: "Organization Audit Help",
                sections: [
                    ("Organization Ratings", "Each area gets a 0-10 rating based on labels, part placement, overcrowding, and bin assignment."),
                    ("Consolidation", "When the same part is in 3+ areas, the system suggests consolidating to one. Users vote on the best location."),
                    ("Org Checklist", "Tap any area to run an org checklist: labels accurate, parts in right spots, bins assigned, etc.")
                ]
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var orgContent: some View {
        List {
            // Tab picker
            Section {
                Picker("Tab", selection: $tab) {
                    ForEach(OrgTab.allCases, id: \.self) { t in
                        Label(t.rawValue, systemImage: t.icon).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Warehouse overall score
            Section("Warehouse Organization") {
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
                        Text(scoreLabel(warehouseScore))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(scoreColor(warehouseScore))
                    }
                    ProgressView(value: warehouseScore, total: 10)
                        .tint(scoreColor(warehouseScore))
                }
                .padding(.vertical, 4)
            }

            switch tab {
            case .ratings:
                ratingsSection
            case .consolidation:
                consolidationSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Ratings Section

    @ViewBuilder
    private var ratingsSection: some View {
        if filteredRatings.isEmpty {
            Section("Area Ratings") {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No organization ratings yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Run an org checklist on any area to start tracking.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } else {
            Section("Area Ratings (\(filteredRatings.count))") {
                ForEach(filteredRatings, id: \.id) { rating in
                    orgRatingRow(rating)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activeSheet = .orgChecklist(rating.areaId)
                        }
                }
            }
        }
    }

    private func orgRatingRow(_ rating: OrganizationRating) -> some View {
        HStack(spacing: 12) {
            // Score circle
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: rating.overallRating / 10.0)
                    .stroke(scoreColor(rating.overallRating), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f", rating.overallRating))
                    .font(.footnote).bold()
            }
            .frame(width: 36, height: 36)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Area #\(rating.areaId)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Checklist summary
                HStack(spacing: 8) {
                    checkIcon(rating.labelsAccurate, label: "Labels")
                    checkIcon(rating.partsInHome, label: "Home")
                    checkIcon(rating.noDuplicates, label: "No Dups")
                    checkIcon(rating.notOvercrowded, label: "Space")
                    checkIcon(rating.binsAssigned, label: "Bins")
                }
            }

            Spacer()

            if let lastCheck = rating.lastOrgCheck {
                Text(formatDate(lastCheck))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    private func checkIcon(_ passed: Bool, label: String) -> some View {
        VStack(spacing: 1) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption)
                .foregroundStyle(passed ? .green : .red)
                .accessibilityLabel(passed ? "\(label): Passed" : "\(label): Failed")
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Consolidation Section

    @ViewBuilder
    private var consolidationSection: some View {
        if consolidationVotes.isEmpty {
            Section("Consolidation Suggestions") {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.title)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("No consolidation needed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("All parts are stored in optimal locations.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } else {
            Section("Consolidation Suggestions (\(consolidationVotes.count))") {
                ForEach(consolidationVotes, id: \.id) { vote in
                    consolidationRow(vote)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activeSheet = .consolidationDetail(vote)
                        }
                }
            }
        }
    }

    private func consolidationRow(_ vote: ConsolidationVote) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.merge")
                .foregroundStyle(.orange)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Part #\(vote.partId)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("In \(parseAreaCount(vote.currentAreas)) areas — pick best home")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if vote.ignoreCount >= 3 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("Escalated — ignored \(vote.ignoreCount) times")
                            .font(.caption2)
                    }
                    .foregroundStyle(.red)
                }
            }

            Spacer()

            Text(vote.status.capitalized)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        vote.status == "voting" ? Color.blue.opacity(0.15) :
                        vote.status == "decided" ? Color.green.opacity(0.15) :
                        Color.gray.opacity(0.15)
                    )
                )
                .foregroundStyle(
                    vote.status == "voting" ? .blue :
                    vote.status == "decided" ? .green : .gray
                )

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Computed

    private var filteredRatings: [OrganizationRating] {
        guard !searchText.isEmpty else { return orgRatings }
        let query = searchText.lowercased()
        return orgRatings.filter {
            "area #\($0.areaId)".contains(query)
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Double) -> Color {
        if score >= 8 { return .green }
        if score >= 5 { return .orange }
        return .red
    }

    private func scoreLabel(_ score: Double) -> String {
        if score >= 8 { return "Well Organized" }
        if score >= 5 { return "Needs Attention" }
        return "Disorganized"
    }

    private func formatDate(_ str: String) -> String {
        if str.count >= 10 { return String(str.prefix(10)) }
        return str
    }

    private func parseAreaCount(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Int64].self, from: data) else { return 0 }
        return arr.count
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service unavailable"
            isLoading = false
            return
        }
        isLoading = orgRatings.isEmpty
        loadError = nil
        do {
            // Load all org ratings by querying directly
            orgRatings = try loadAllOrgRatings(service: service)
            consolidationVotes = try service.getActiveConsolidationVotes()
            warehouseScore = try service.getWarehouseOverallScore()
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load organization audit")
        }
        isLoading = false
    }

    private func postAIContext() {
        let context = """
        Warehouse Organization Audit page. Read-only context.
        Active tab: \(tab.rawValue), organization ratings: \(orgRatings.count), visible ratings: \(filteredRatings.count), consolidation votes: \(consolidationVotes.count).
        Warehouse organization score: \(String(format: "%.1f", warehouseScore)), search active: \(!searchText.isEmpty).
        Available read-only guidance: explain ratings, consolidation voting, checklist entry point, score meaning, and manager override entry point. Do not submit checklists, votes, or overrides directly.
        """
        NotificationCenter.default.post(
            name: .warehouseOrganizationAuditPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }

    private func loadAllOrgRatings(service: WarehouseService) throws -> [OrganizationRating] {
        // Load via the warehouse score — get all ratings that exist
        // This uses a raw query since there's no "list all" method yet
        // The service will handle this gracefully
        var ratings: [OrganizationRating] = []
        // Get areas from floor plans to seed org ratings
        let plans = try service.listFloorPlans()
        for plan in plans {
            guard let planId = plan.id else { continue }
            let units = try service.listStorageUnits(floorPlanId: planId)
            for unit in units {
                guard let unitId = unit.id else { continue }
                let levels = try service.listLevelsForUnit(unitId: unitId)
                for level in levels {
                    guard let levelId = level.id else { continue }
                    let areas = try service.listAreasForLevel(levelId: levelId)
                    for area in areas {
                        guard let areaId = area.id else { continue }
                        let rating = try service.getOrganizationRating(areaId: areaId)
                        ratings.append(rating)
                    }
                }
            }
        }
        return ratings
    }
}

// MARK: - Organization Checklist Sheet

private struct OrgChecklistSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let areaId: Int64
    let onSave: () -> Void

    @State private var labelsAccurate = false
    @State private var partsInHome = false
    @State private var noDuplicates = false
    @State private var notOvercrowded = false
    @State private var binsAssigned = false
    @State private var similarPartsNearby = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Area #\(areaId) — Organization Check") {
                    Toggle("Labels accurate?", isOn: $labelsAccurate)
                    Toggle("Parts in right spots?", isOn: $partsInHome)
                    Toggle("No duplicate storage?", isOn: $noDuplicates)
                    Toggle("Not overcrowded?", isOn: $notOvercrowded)
                    Toggle("Bins properly assigned?", isOn: $binsAssigned)
                    Toggle("Similar parts nearby?", isOn: $similarPartsNearby)
                }

                Section {
                    // Score preview
                    let checks = [labelsAccurate, partsInHome, noDuplicates, notOvercrowded, binsAssigned, similarPartsNearby]
                    let passed = checks.filter { $0 }.count
                    let score = (Double(passed) / Double(checks.count)) * 10.0

                    HStack {
                        Text("Organization Score")
                        Spacer()
                        Text(String(format: "%.1f / 10", score))
                            .fontWeight(.bold)
                            .foregroundStyle(score >= 8 ? .green : score >= 5 ? .orange : .red)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Org Checklist")
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
                        Button("Save") { saveChecklist() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let service = appCore.warehouseService else {
            errorMessage = "Service not available"
            return
        }
        if let rating = try? service.getOrganizationRating(areaId: areaId) {
            labelsAccurate = rating.labelsAccurate
            partsInHome = rating.partsInHome
            noDuplicates = rating.noDuplicates
            notOvercrowded = rating.notOvercrowded
            binsAssigned = rating.binsAssigned
            similarPartsNearby = rating.similarPartsNearby
        }
    }

    private func saveChecklist() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Service unavailable"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try service.recordOrgCheck(
                areaId: areaId,
                checkedBy: userId,
                labelsAccurate: labelsAccurate,
                partsInHome: partsInHome,
                noDuplicates: noDuplicates,
                notOvercrowded: notOvercrowded,
                binsAssigned: binsAssigned,
                similarPartsNearby: similarPartsNearby
            )
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load audit")
        }
        isSaving = false
    }
}

// MARK: - Consolidation Detail Sheet

private struct ConsolidationDetailSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let vote: ConsolidationVote
    let onSave: () -> Void

    @State private var selectedAreaId: Int64?
    @State private var areaIds: [Int64] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Consolidation Vote") {
                    LabeledContent("Part", value: "Part #\(vote.partId)")
                    LabeledContent("Status", value: vote.status.capitalized)
                    if vote.ignoreCount > 0 {
                        LabeledContent("Times Ignored", value: "\(vote.ignoreCount)")
                    }
                }

                Section("Current Locations") {
                    if areaIds.isEmpty {
                        Text("Loading areas...").foregroundStyle(.secondary)
                    } else {
                        ForEach(areaIds, id: \.self) { areaId in
                            Button {
                                selectedAreaId = areaId
                            } label: {
                                HStack {
                                    Text("Area #\(areaId)")
                                    Spacer()
                                    if selectedAreaId == areaId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                            .accessibilityLabel("Selected")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if vote.ignoreCount >= 3 {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                            Text("This consolidation has been ignored \(vote.ignoreCount) times. A decision is required.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Vote to Consolidate")
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
                        Button("Vote") { castVote() }
                            .fontWeight(.semibold)
                            .disabled(selectedAreaId == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { parseAreas() }
        }
    }

    private func parseAreas() {
        guard let data = vote.currentAreas.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data) else { return }
        areaIds = ids
    }

    private func castVote() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id,
              let voteId = vote.id,
              let chosenArea = selectedAreaId else {
            errorMessage = "Missing data"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try service.castConsolidationVote(voteId: voteId, userId: userId, chosenAreaId: chosenArea)
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load audit")
        }
        isSaving = false
    }
}

// MARK: - Manager Override Sheet

private struct ManagerOverrideSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let vote: ConsolidationVote
    let onSave: () -> Void

    @State private var selectedAreaId: Int64?
    @State private var areaIds: [Int64] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Manager Override") {
                    LabeledContent("Part", value: "Part #\(vote.partId)")
                    Text("As a manager, you can directly choose the consolidation target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Choose Area") {
                    ForEach(areaIds, id: \.self) { areaId in
                        Button {
                            selectedAreaId = areaId
                        } label: {
                            HStack {
                                Text("Area #\(areaId)")
                                Spacer()
                                if selectedAreaId == areaId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                        .accessibilityLabel("Selected")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Manager Override")
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
                        Button("Override") { applyOverride() }
                            .fontWeight(.semibold)
                            .disabled(selectedAreaId == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { parseAreas() }
        }
    }

    private func parseAreas() {
        guard let data = vote.currentAreas.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data) else { return }
        areaIds = ids
    }

    private func applyOverride() {
        guard let service = appCore.warehouseService,
              let voteId = vote.id,
              let chosenArea = selectedAreaId else {
            errorMessage = "Missing data"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try service.managerOverrideConsolidation(voteId: voteId, chosenAreaId: chosenArea)
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load audit")
        }
        isSaving = false
    }
}
