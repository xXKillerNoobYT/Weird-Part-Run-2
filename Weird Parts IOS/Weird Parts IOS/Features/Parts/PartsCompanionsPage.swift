import SwiftUI
import WiredPartCore

/// Companion rules and alternatives management page.
///
/// Shows companion rules (parts that should be ordered together) and
/// part alternatives (substitute parts). Supports creating new rules
/// and managing existing relationships.
struct PartsCompanionsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var companionRules: [PartsService.CompanionRuleHierarchyRow] = []
    @State private var alternatives: [PartsService.PartAlternativeWithName] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeTab = CompanionTab.rules

    // Delete confirmation
    @State private var ruleToDelete: PartsService.CompanionRuleHierarchyRow?
    @State private var showDeleteRuleConfirm = false
    @State private var altToDelete: PartsService.PartAlternativeWithName?
    @State private var showDeleteAltConfirm = false

    // Action errors
    @State private var actionError: String?

    // Polls state
    @State private var activePolls: [PartsService.CompanionPollDisplayRow] = []
    @State private var lastWeekResults: [(pollName: String, passed: Bool, myVote: String?, matchedWinner: Bool)] = []
    @State private var trainingQuestion: (sourceName: String, targetName: String, points: Int, isTraining: Bool)?
    @State private var nextPollPreview: (pairId: Int64, catAName: String, catBName: String, points: Int, confidence: Double)?
    @State private var showLockConfirm = false
    @State private var lockAction: String = "accept"
    @State private var pollToLock: Int64?
    @State private var showSkipConfirm = false
    @State private var pollToSkip: Int64?

    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addRule
        case editRule(PartsService.CompanionRuleHierarchyRow)
        case addAlternative
        case testSandbox
        case adminDashboard

        var id: String {
            switch self {
            case .addRule: return "addRule"
            case .editRule(let rule): return "editRule-\(rule.id)"
            case .addAlternative: return "addAlternative"
            case .testSandbox: return "testSandbox"
            case .adminDashboard: return "adminDashboard"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 0) {
            // Action error banner
            if let error = actionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { actionError = nil }
                        .font(.caption)
                }
                .padding(8)
                .background(.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Tabs
            Picker("View", selection: $activeTab) {
                Text("Rules").tag(CompanionTab.rules)
                Text("Alternatives").tag(CompanionTab.alternatives)
                Text("Polls").tag(CompanionTab.polls)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else {
                switch activeTab {
                case .rules:
                    rulesView
                case .alternatives:
                    alternativesView
                case .polls:
                    pollsView
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search companions...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 12) {
                    if appCore.hasPermission("manage_people") {
                        Button { activeSheet = .adminDashboard } label: {
                            Image(systemName: "chart.bar.xaxis")
                        }
                    }

                    Button { activeSheet = .testSandbox } label: {
                        Image(systemName: "flask")
                    }

                    if activeTab != .polls {
                        Button {
                            switch activeTab {
                            case .rules: activeSheet = .addRule
                            case .alternatives: activeSheet = .addAlternative
                            case .polls: break
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .alert("Delete Rule?", isPresented: $showDeleteRuleConfirm, presenting: ruleToDelete) { rule in
            Button("Delete", role: .destructive) {
                Task { await confirmDeleteRule(rule) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { rule in
            if rule.childCount > 0 {
                Text("This will also schedule \(rule.childCount) child rule\(rule.childCount == 1 ? "" : "s") for deletion in 30 days.")
            } else {
                Text("\"" + rule.name + "\" will be scheduled for deletion.")
            }
        }
        .alert("Delete Alternative?", isPresented: $showDeleteAltConfirm, presenting: altToDelete) { alt in
            Button("Delete", role: .destructive) {
                Task { await confirmDeleteAlternative(alt) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { alt in
            Text("Remove the link between \"\(alt.partName ?? "Part")\" and \"\(alt.alternativePartName ?? "Alternative")\"?")
        }
        .alert("Lock Poll Result?", isPresented: $showLockConfirm) {
            Button("Lock as \(lockAction == "accept" ? "Pass" : "Reject")", role: .destructive) {
                Task {
                    guard let pollId = pollToLock, let service = appCore.partsService,
                          let userId = appCore.currentUser?.id else { return }
                    do {
                        try service.adminLockPoll(pollId: pollId, result: lockAction, lockedBy: userId)
                        await loadData()
                    } catch { actionError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The poll will continue running but the outcome is already decided. Only admin users will see the lock.")
        }
        .alert("Skip This Poll?", isPresented: $showSkipConfirm) {
            Button("Skip (-50 points)", role: .destructive) {
                Task {
                    guard let pollId = pollToSkip, let service = appCore.partsService else { return }
                    do {
                        _ = try service.adminSkipPoll(pollId: pollId)
                        await loadData()
                    } catch { actionError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This poll will be closed and a -50 point penalty applied. A replacement poll will be created from the next-best suggestion.")
        }
        .background(DS.Background.page)
        .task { await loadData() }
        .onAppear { postCompanionsContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .companionsPageInactive, object: nil)
        }
    }

    // MARK: - Rules View

    @ViewBuilder
    private var rulesView: some View {
        if filteredRules.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Companion Rules")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Create rules to automatically suggest companion parts when ordering.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    activeSheet = .addRule
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Text("\(filteredRules.count) rule\(filteredRules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredRules, id: \.id) { rule in
                    ruleRowView(rule)
                        .contentShape(Rectangle())
                        .onTapGesture { activeSheet = .editRule(rule) }
                        .swipeActions(edge: .trailing) {
                            if rule.deletedAt != nil || rule.autoDeleteAt != nil {
                                // Already pending deletion — offer restore
                                Button {
                                    Task { await restoreRule(rule) }
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            } else {
                                Button(role: .destructive) {
                                    ruleToDelete = rule
                                    showDeleteRuleConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Task { await toggleRuleActive(rule) }
                                } label: {
                                    Label(rule.isActive == 1 ? "Deactivate" : "Activate",
                                          systemImage: rule.isActive == 1 ? "xmark.circle" : "checkmark.circle")
                                }
                                .tint(rule.isActive == 1 ? .orange : .green)
                            }
                        }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func ruleRowView(_ rule: PartsService.CompanionRuleHierarchyRow) -> some View {
        let isDeleting = rule.deletedAt != nil || rule.autoDeleteAt != nil || rule.isOrphaned
        HStack(spacing: 12) {
            Image(systemName: isDeleting ? "trash.circle" : "link")
                .foregroundStyle(isDeleting ? .red : (rule.isActive == 1 ? Color.accentColor : .secondary))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                // Source → Target names from sources/targets arrays
                Text(sourceDisplayName(rule))
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(targetDisplayName(rule))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    // Match level badge
                    Text(rule.matchLevel.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(matchLevelColor(rule.matchLevel).opacity(0.15))
                        .foregroundStyle(matchLevelColor(rule.matchLevel))
                        .clipShape(Capsule())

                    // Brand match indicator
                    if rule.tryMatchBrand == 1 {
                        Text("Brand")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }

                    // Qty info
                    Text("Qty: \(rule.qtyMode) ×\(String(format: "%.0f", rule.qtyRatio))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Child count
                    if rule.childCount > 0 {
                        Text("(\(rule.childCount) sub-rule\(rule.childCount == 1 ? "" : "s"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Orphan / deletion indicator
                if isDeleting {
                    if let autoDelete = rule.autoDeleteAt {
                        Text("Deleting: \(autoDelete)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if rule.isOrphaned {
                        Text("Orphaned — parent deleted")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            if !isDeleting && rule.isActive != 1 {
                Text("Inactive")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(minHeight: 56)
        .opacity(isDeleting ? 0.6 : 1.0)
    }

    // MARK: - Alternatives View

    @ViewBuilder
    private var alternativesView: some View {
        if filteredAlternatives.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Part Alternatives")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Define substitute parts for when primary parts are unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    activeSheet = .addAlternative
                } label: {
                    Label("Add Alternative", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Text("\(filteredAlternatives.count) alternative\(filteredAlternatives.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredAlternatives, id: \.id) { alt in
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundStyle(.purple)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(alt.partName ?? "Unknown Part")
                                .font(.body)
                                .fontWeight(.medium)

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(alt.alternativePartName ?? "Unknown")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text(alt.relationship.capitalized)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.1))
                                    .clipShape(Capsule())
                                Text("Priority: \(alt.preference)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .frame(minHeight: 56)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            altToDelete = alt
                            showDeleteAltConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Polls View

    @ViewBuilder
    private var pollsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Last Week's Results
                if !lastWeekResults.isEmpty {
                    lastWeekResultsSection
                }

                // Active Polls
                if activePolls.isEmpty {
                    if let training = trainingQuestion {
                        trainingQuestionCard(training)
                    } else {
                        emptyPollsState
                    }
                } else {
                    ForEach(activePolls, id: \.pollId) { poll in
                        pollCard(poll)
                    }
                }

                // Admin: Preview Next Week
                if appCore.hasPermission("vote_veto"), let preview = nextPollPreview {
                    adminPreviewSection(preview)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var lastWeekResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Week's Results")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(Array(lastWeekResults.enumerated()), id: \.offset) { _, result in
                HStack(spacing: 12) {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.passed ? .green : .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.pollName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(spacing: 4) {
                            Text(result.passed ? "Passed" : "Didn't Pass")
                                .font(.caption)
                                .foregroundStyle(result.passed ? .green : .red)

                            if let myVote = result.myVote {
                                Text("·")
                                Text("You voted: \(myVote == "accept" ? "Yes" : "No")")
                                    .font(.caption)
                                    .foregroundStyle(result.matchedWinner ? .green : .orange)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
        }
    }

    @ViewBuilder
    private func pollCard(_ poll: PartsService.CompanionPollDisplayRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(poll.matchLevel.capitalized)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                Text("\(poll.daysRemaining) days left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Question: Source → Target
            HStack(spacing: 8) {
                Text(poll.sourceName)
                    .font(.body)
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(poll.targetName)
                    .font(.body)
                    .fontWeight(.semibold)
            }

            if let desc = poll.proposedRuleDescription, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Vote buttons
            HStack(spacing: 12) {
                Button {
                    Task { await vote(pollId: poll.pollId, vote: "accept") }
                } label: {
                    HStack {
                        Image(systemName: poll.myVote == "accept" ? "hand.thumbsup.fill" : "hand.thumbsup")
                        Text("Yes, link these")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(poll.myVote == "accept" ? Color.green.opacity(0.2) : Color(.systemGray5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await vote(pollId: poll.pollId, vote: "reject") }
                } label: {
                    HStack {
                        Image(systemName: poll.myVote == "reject" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        Text("No")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(poll.myVote == "reject" ? Color.red.opacity(0.2) : Color(.systemGray5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Admin controls
            if appCore.hasPermission("vote_veto") {
                adminControlsSection(poll)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private func adminControlsSection(_ poll: PartsService.CompanionPollDisplayRow) -> some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Powered votes: \(poll.poweredAcceptCount) accept / \(poll.poweredRejectCount) reject")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Total: \(poll.totalVotes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if poll.isAdminLocked, let lockedResult = poll.adminLockedResult {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                    Text("Locked: \(lockedResult == "accept" ? "Will Pass" : "Will Reject")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                if !poll.isAdminLocked {
                    Menu {
                        Button("Lock as Pass") {
                            pollToLock = poll.pollId
                            lockAction = "accept"
                            showLockConfirm = true
                        }
                        Button("Lock as Reject") {
                            pollToLock = poll.pollId
                            lockAction = "reject"
                            showLockConfirm = true
                        }
                    } label: {
                        Label("Lock Result", systemImage: "lock.fill")
                            .font(.caption)
                    }
                }

                Button {
                    pollToSkip = poll.pollId
                    showSkipConfirm = true
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.caption)
                }
                .tint(.orange)
            }
        }
    }

    @ViewBuilder
    private func trainingQuestionCard(_ question: (sourceName: String, targetName: String, points: Int, isTraining: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(.blue)
                Text("Training Question")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                Text("Practice")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text("Should these categories be linked as companions?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(question.sourceName)
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(question.targetName)
                    .fontWeight(.semibold)
            }

            Text("This is a practice question — your answer won't create any rules.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2)))
    }

    @ViewBuilder
    private func adminPreviewSection(_ preview: (pairId: Int64, catAName: String, catBName: String, points: Int, confidence: Double)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.purple)
                Text("Next Week's Poll (Preview)")
                    .font(.headline)
                    .foregroundStyle(.purple)
            }

            HStack(spacing: 8) {
                Text(preview.catAName)
                    .fontWeight(.medium)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(preview.catBName)
                    .fontWeight(.medium)
            }

            HStack {
                Text("\(preview.points) points")
                    .font(.caption)
                Text("·")
                Text("\(Int(preview.confidence * 100))% confidence")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.2)))
    }

    @ViewBuilder
    private var emptyPollsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Active Polls")
                .font(.title3)
                .fontWeight(.semibold)
            Text("The system needs at least 3 months of ordering data before it can suggest companion rules.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtered

    private var filteredRules: [PartsService.CompanionRuleHierarchyRow] {
        if searchText.isEmpty { return companionRules }
        let query = searchText.lowercased()
        return companionRules.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    private var filteredAlternatives: [PartsService.PartAlternativeWithName] {
        if searchText.isEmpty { return alternatives }
        let query = searchText.lowercased()
        return alternatives.filter {
            ($0.partName?.lowercased().contains(query) ?? false) ||
            ($0.alternativePartName?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Display Helpers

    private func sourceDisplayName(_ rule: PartsService.CompanionRuleHierarchyRow) -> String {
        if !rule.sources.isEmpty {
            return rule.sources.map { buildEntryName($0.categoryId, $0.styleId, $0.typeId) }.joined(separator: ", ")
        }
        return rule.name
    }

    private func targetDisplayName(_ rule: PartsService.CompanionRuleHierarchyRow) -> String {
        if !rule.targets.isEmpty {
            return rule.targets.map { buildEntryName($0.categoryId, $0.styleId, $0.typeId) }.joined(separator: ", ")
        }
        return rule.description ?? ""
    }

    private func buildEntryName(_ categoryId: Int64, _ styleId: Int64?, _ typeId: Int64?) -> String {
        // Build "Category > Style > Type" from the cached names
        // Use the names loaded from the hierarchy query
        var parts: [String] = ["Cat:\(categoryId)"]
        if let sid = styleId { parts.append("Style:\(sid)") }
        if let tid = typeId { parts.append("Type:\(tid)") }
        return parts.joined(separator: " > ")
    }

    private func matchLevelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "type": return .green
        case "style": return .blue
        case "category": return .orange
        default: return .secondary
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .addRule:
            CompanionRuleFormSheet(editingRule: nil) { await loadData() }
        case .editRule(let rule):
            CompanionRuleFormSheet(editingRule: rule) { await loadData() }
        case .addAlternative:
            AlternativeFormSheet { await loadData() }
        case .testSandbox:
            CompanionSandboxSheet()
        case .adminDashboard:
            CompanionAdminDashboardSheet()
        }
    }

    // MARK: - Data Loading

    private func postCompanionsContext() {
        var context = "Page: Companion Rules\n"
        context += "Rules: \(companionRules.count), Alternatives: \(alternatives.count)\n"
        context += "Active Polls: \(activePolls.count)\n"
        if !companionRules.isEmpty {
            context += "Rule levels: " + Set(companionRules.map { $0.matchLevel }).sorted().joined(separator: ", ") + "\n"
        }
        context += "\nCapabilities:\n"
        context += "- List and explain companion rules\n"
        context += "- Show active polls and voting status\n"
        context += "- Explain why category pairings were suggested\n"
        context += "- Summarize recent voting results\n"
        NotificationCenter.default.post(
            name: .companionsPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }

    private func loadData() async {
        isLoading = true
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                isLoading = false
                return
            }
            let rules = try service.listCompanionRulesHierarchy()
            let alts = try service.listAllAlternatives()

            // Poll data
            let userId = appCore.currentUser?.id ?? 0
            let isAdmin = appCore.hasPermission("vote_veto")
            let polls = try service.getActivePolls(userId: userId, isAdmin: isAdmin)
            let results = try service.getLastWeekResults(userId: userId)
            let training = try service.getTrainingQuestion()
            let preview = isAdmin ? try service.getNextPollPreview() : nil

            // Housekeeping
            try service.closeExpiredPolls()
            try service.purgeExpiredRules()

            await MainActor.run {
                companionRules = rules
                alternatives = alts
                activePolls = polls
                lastWeekResults = results
                trainingQuestion = training
                nextPollPreview = preview
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Actions

    private func confirmDeleteRule(_ rule: PartsService.CompanionRuleHierarchyRow) async {
        do {
            guard let service = appCore.partsService else { return }
            try service.deleteCompanionRuleSoft(id: rule.id)
            await loadData()
        } catch {
            await MainActor.run {
                actionError = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    private func toggleRuleActive(_ rule: PartsService.CompanionRuleHierarchyRow) async {
        do {
            guard let service = appCore.partsService else { return }
            let newActive = rule.isActive == 1 ? 0 : 1
            try service.updateCompanionRule(id: rule.id, isActive: newActive)
            await loadData()
        } catch {
            await MainActor.run {
                actionError = "Toggle failed: \(error.localizedDescription)"
            }
        }
    }

    private func restoreRule(_ rule: PartsService.CompanionRuleHierarchyRow) async {
        do {
            guard let service = appCore.partsService else { return }
            try service.restoreCompanionRule(id: rule.id)
            await loadData()
        } catch {
            await MainActor.run {
                actionError = "Restore failed: \(error.localizedDescription)"
            }
        }
    }

    private func vote(pollId: Int64, vote: String) async {
        do {
            guard let service = appCore.partsService, let userId = appCore.currentUser?.id else { return }
            try service.castVote(pollId: pollId, userId: userId, vote: vote)
            await loadData()
        } catch {
            await MainActor.run {
                actionError = "Vote failed: \(error.localizedDescription)"
            }
        }
    }

    private func confirmDeleteAlternative(_ alt: PartsService.PartAlternativeWithName) async {
        do {
            guard let service = appCore.partsService else { return }
            try service.unlinkPartAlternative(linkId: alt.id)
            await loadData()
        } catch {
            await MainActor.run {
                actionError = "Delete failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Types

private enum CompanionTab {
    case rules, alternatives, polls
}

// MARK: - Companion Rule Form Sheet

private struct CompanionRuleFormSheet: View {
    let editingRule: PartsService.CompanionRuleHierarchyRow?  // nil = create mode
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var ruleName = ""
    @State private var ruleDescription = ""
    @State private var matchLevel = "category"  // "category", "style", "type"
    @State private var tryMatchBrand = false
    @State private var autoColorMatch = true
    @State private var qtyMode = "sum"          // "sum", "ratio", "fixed"
    @State private var qtyRatio: Double = 1.0

    // Source picker state
    @State private var sourceCategoryId: Int64 = 0
    @State private var sourceStyleId: Int64 = 0
    @State private var sourceTypeId: Int64 = 0

    // Target picker state
    @State private var targetCategoryId: Int64 = 0
    @State private var targetStyleId: Int64 = 0
    @State private var targetTypeId: Int64 = 0

    // Picker data
    @State private var categories: [PartCategory] = []
    @State private var sourceStyles: [PartStyle] = []
    @State private var sourceTypes: [PartType] = []
    @State private var targetStyles: [PartStyle] = []
    @State private var targetTypes: [PartType] = []

    // Error + loading
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                // Error display
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // Section 1: Rule Info
                Section("Rule Name") {
                    TextField("e.g., Wire → Wire Nuts", text: $ruleName)
                    TextField("Description (optional)", text: $ruleDescription)
                }

                // Section 2: Match Level
                Section("Match Level") {
                    Picker("Level", selection: $matchLevel) {
                        Text("Category").tag("category")
                        Text("Style").tag("style")
                        Text("Type").tag("type")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: matchLevel) {
                        // Reset lower-level selections when level changes
                        if matchLevel == "category" {
                            sourceStyleId = 0; sourceTypeId = 0
                            targetStyleId = 0; targetTypeId = 0
                        } else if matchLevel == "style" {
                            sourceTypeId = 0; targetTypeId = 0
                        }
                    }
                }

                // Section 3: Source — "When ordering..."
                Section("Source — When ordering from...") {
                    Picker("Category", selection: $sourceCategoryId) {
                        Text("Select category...").tag(Int64(0))
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id ?? Int64(0))
                        }
                    }
                    .onChange(of: sourceCategoryId) {
                        sourceStyleId = 0; sourceTypeId = 0
                        Task { await loadSourceStyles() }
                    }

                    if matchLevel != "category" {
                        Picker("Style", selection: $sourceStyleId) {
                            Text("Select style...").tag(Int64(0))
                            ForEach(sourceStyles, id: \.id) { style in
                                Text(style.name).tag(style.id ?? Int64(0))
                            }
                        }
                        .onChange(of: sourceStyleId) {
                            sourceTypeId = 0
                            Task { await loadSourceTypes() }
                        }
                    }

                    if matchLevel == "type" {
                        Picker("Type", selection: $sourceTypeId) {
                            Text("Select type...").tag(Int64(0))
                            ForEach(sourceTypes, id: \.id) { type in
                                Text(type.name).tag(type.id ?? Int64(0))
                            }
                        }
                    }
                }

                // Section 4: Target — "Also suggest..."
                Section("Target — Also suggest from...") {
                    Picker("Category", selection: $targetCategoryId) {
                        Text("Select category...").tag(Int64(0))
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id ?? Int64(0))
                        }
                    }
                    .onChange(of: targetCategoryId) {
                        targetStyleId = 0; targetTypeId = 0
                        Task { await loadTargetStyles() }
                    }

                    if matchLevel != "category" {
                        Picker("Style", selection: $targetStyleId) {
                            Text("Select style...").tag(Int64(0))
                            ForEach(targetStyles, id: \.id) { style in
                                Text(style.name).tag(style.id ?? Int64(0))
                            }
                        }
                        .onChange(of: targetStyleId) {
                            targetTypeId = 0
                            Task { await loadTargetTypes() }
                        }
                    }

                    if matchLevel == "type" {
                        Picker("Type", selection: $targetTypeId) {
                            Text("Select type...").tag(Int64(0))
                            ForEach(targetTypes, id: \.id) { type in
                                Text(type.name).tag(type.id ?? Int64(0))
                            }
                        }
                    }
                }

                // Section 5: Options
                Section("Options") {
                    Toggle("Try to Match Brand", isOn: $tryMatchBrand)
                    Toggle("Auto-Match Color", isOn: $autoColorMatch)

                    Picker("Quantity Mode", selection: $qtyMode) {
                        Text("Sum").tag("sum")
                        Text("Ratio").tag("ratio")
                        Text("Fixed").tag("fixed")
                    }

                    if qtyMode != "sum" {
                        HStack {
                            Text("Qty Ratio")
                            Spacer()
                            TextField("1.0", value: $qtyRatio, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .navigationTitle(editingRule == nil ? "New Companion Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!isValid)
                    }
                }
            }
            .task { await loadCategories() }
            .onAppear { populateFromEditingRule() }
        }
    }

    // Validation: source and target must be selected at the correct level
    private var isValid: Bool {
        guard !ruleName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard sourceCategoryId != 0 && targetCategoryId != 0 else { return false }
        if matchLevel != "category" {
            guard sourceStyleId != 0 && targetStyleId != 0 else { return false }
        }
        if matchLevel == "type" {
            guard sourceTypeId != 0 && targetTypeId != 0 else { return false }
        }
        // Source and target can't be identical at the selected level
        if matchLevel == "category" { return sourceCategoryId != targetCategoryId }
        if matchLevel == "style" { return sourceStyleId != targetStyleId }
        if matchLevel == "type" { return sourceTypeId != targetTypeId }
        return true
    }

    // Populate form from editing rule (if in edit mode)
    private func populateFromEditingRule() {
        guard let rule = editingRule else { return }
        ruleName = rule.name
        ruleDescription = rule.description ?? ""
        matchLevel = rule.matchLevel
        tryMatchBrand = rule.tryMatchBrand == 1
        autoColorMatch = rule.autoColorMatch == 1
        qtyMode = rule.qtyMode
        qtyRatio = rule.qtyRatio
        if let src = rule.sources.first {
            sourceCategoryId = src.categoryId
            sourceStyleId = src.styleId ?? 0
            sourceTypeId = src.typeId ?? 0
        }
        if let tgt = rule.targets.first {
            targetCategoryId = tgt.categoryId
            targetStyleId = tgt.styleId ?? 0
            targetTypeId = tgt.typeId ?? 0
        }
    }

    // Load categories
    private func loadCategories() async {
        do {
            guard let service = appCore.partsService else { return }
            categories = try service.listCategories()
            // If editing, load dependent styles/types
            if editingRule != nil {
                await loadSourceStyles()
                await loadTargetStyles()
                await loadSourceTypes()
                await loadTargetTypes()
            }
        } catch {
            saveError = "Failed to load categories"
        }
    }

    private func loadSourceStyles() async {
        guard sourceCategoryId != 0, let service = appCore.partsService else { sourceStyles = []; return }
        do { sourceStyles = try service.listStyles(categoryId: sourceCategoryId) }
        catch { saveError = "Failed to load styles" }
    }

    private func loadSourceTypes() async {
        guard sourceStyleId != 0, let service = appCore.partsService else { sourceTypes = []; return }
        do { sourceTypes = try service.listTypes(styleId: sourceStyleId) }
        catch { saveError = "Failed to load types" }
    }

    private func loadTargetStyles() async {
        guard targetCategoryId != 0, let service = appCore.partsService else { targetStyles = []; return }
        do { targetStyles = try service.listStyles(categoryId: targetCategoryId) }
        catch { saveError = "Failed to load styles" }
    }

    private func loadTargetTypes() async {
        guard targetStyleId != 0, let service = appCore.partsService else { targetTypes = []; return }
        do { targetTypes = try service.listTypes(styleId: targetStyleId) }
        catch { saveError = "Failed to load types" }
    }

    // Save
    private func save() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                saveError = "Service unavailable"
                isSaving = false
                return
            }

            let sources: [(categoryId: Int64, styleId: Int64?, typeId: Int64?)] = [
                (categoryId: sourceCategoryId,
                 styleId: matchLevel != "category" ? sourceStyleId : nil,
                 typeId: matchLevel == "type" ? sourceTypeId : nil)
            ]
            let targets: [(categoryId: Int64, styleId: Int64?, typeId: Int64?)] = [
                (categoryId: targetCategoryId,
                 styleId: matchLevel != "category" ? targetStyleId : nil,
                 typeId: matchLevel == "type" ? targetTypeId : nil)
            ]

            if let existing = editingRule {
                // Update existing rule fields
                try service.updateCompanionRule(
                    id: existing.id,
                    name: ruleName,
                    description: ruleDescription.isEmpty ? nil : ruleDescription,
                    qtyMode: qtyMode,
                    qtyRatio: qtyRatio
                )
            } else {
                _ = try service.createCompanionRuleAtLevel(
                    name: ruleName,
                    description: ruleDescription.isEmpty ? nil : ruleDescription,
                    qtyMode: qtyMode,
                    qtyRatio: qtyRatio,
                    tryMatchBrand: tryMatchBrand,
                    autoColorMatch: autoColorMatch,
                    sources: sources,
                    targets: targets
                )
            }

            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Alternative Form Sheet

private struct AlternativeFormSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var parts: [PartPickerItem] = []
    @State private var partId: Int64 = 0
    @State private var alternativePartId: Int64 = 0
    @State private var relationship = "substitute"
    @State private var priority = 1
    @State private var saveError: String?
    @State private var isSaving = false

    private let relationships = ["substitute", "equivalent", "upgrade", "downgrade"]

    var body: some View {
        NavigationStack {
            Form {
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Primary Part") {
                    Picker("Part", selection: $partId) {
                        Text("Select...").tag(Int64(0))
                        ForEach(parts, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }

                Section("Alternative Part") {
                    Picker("Can be replaced with", selection: $alternativePartId) {
                        Text("Select...").tag(Int64(0))
                        ForEach(parts, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }

                Section("Details") {
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { r in
                            Text(r.capitalized).tag(r)
                        }
                    }
                    Stepper("Priority: \(priority)", value: $priority, in: 1...10)
                }
            }
            .navigationTitle("New Alternative")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            await save()
                            if saveError == nil {
                                await onSave()
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(partId == 0 || alternativePartId == 0 || partId == alternativePartId || isSaving)
                }
            }
            .task { await loadParts() }
        }
    }

    private func loadParts() async {
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                return
            }
            let all = try service.listParts()
            parts = all.compactMap { item in
                guard let id = item.part.id else { return nil }
                return PartPickerItem(id: id, name: item.part.name)
            }
        } catch {
            saveError = "Failed to load parts: \(error.localizedDescription)"
        }
    }

    private func save() async {
        saveError = nil
        let capturedPartId = partId
        let capturedAlternativePartId = alternativePartId
        let capturedRelationship = relationship
        let capturedPriority = priority
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                return
            }
            try service.linkPartAlternative(
                partId: capturedPartId,
                alternativePartId: capturedAlternativePartId,
                relationship: capturedRelationship,
                preference: capturedPriority,
                notes: nil
            )
        } catch {
            await MainActor.run {
                saveError = "Save failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Part Picker Item

struct PartPickerItem: Identifiable, Sendable {
    let id: Int64
    let name: String
}
