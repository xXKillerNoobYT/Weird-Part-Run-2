import SwiftUI
import WiredPartCore

/// Q&A threads list page for iOS.
///
/// Displays a searchable list of Q&A threads with smart card filters,
/// escalation level display, and navigation to thread detail/escalation timeline.
struct IOSQuestionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var threads: [ChatService.QAThreadRow] = []
    /// IDs of threads the current user (or their role) must act on — drives "Needs My Review".
    @State private var reviewThreadIds: Set<Int64> = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter: QAFilter = .all
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case askQuestion
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    enum QAFilter: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case myQuestions = "My Questions"
        case needsMyReview = "Needs My Review"
        case resolved = "Resolved"
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "chat-questions")
            smartCardBar
            questionsList
        }
        .task { appCore.onboardingManager?.markCompleted("qa-view") }
        .navigationTitle("Q&A")
        .searchable(text: $searchText, prompt: "Search questions...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .askQuestion } label: {
                    Label("Ask", systemImage: "plus")
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
            switch sheet {
            case .askQuestion:
                IOSQAQuestionForm(onSubmitted: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Q&A Help",
                    sections: [
                        ("What This Page Does", "The Q&A page is where field workers ask questions and get answers through the escalation chain. Questions start at the worker level and can be escalated up to lead, manager, or office if the person at the current level cannot answer."),
                        ("How to Use It", "Use the filter cards to see All questions, Open ones, your own questions (My Questions), ones awaiting your input (Needs My Review), or Resolved threads. Tap any question to see its full escalation timeline and add your response."),
                        ("Asking a Question", "Tap the + button to submit a new question. Pick the job it relates to, type your question, and set the priority (low, normal, high, urgent). Your question enters the escalation chain and the right people get notified."),
                        ("Escalation Levels", "Questions flow through Worker, Lead, Manager, and Office levels. If someone at your level cannot answer, they escalate it up. If it was sent to the wrong level, it can be pushed back down with feedback."),
                        ("Tips", "Urgent and high-priority questions are flagged with colored badges so they stand out. Check the status badges to see which questions are open, answered, escalated, or closed. Pull down to refresh the list.")
                    ]
                )
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Smart Card Filters

    private var smartCardBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(QAFilter.allCases, id: \.self) { filter in
                    smartCard(filter.rawValue, count: countFor(filter),
                              icon: iconFor(filter), isActive: statusFilter == filter,
                              color: colorFor(filter)) {
                        statusFilter = filter
                        loadData()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countFor(_ filter: QAFilter) -> Int {
        switch filter {
        case .all: return threads.count
        case .open: return threads.filter { QAThreadStatusBuckets.isOpen($0.status) }.count
        case .myQuestions:
            guard let currentUserId = appCore.currentUser?.id else { return 0 }
            return threads.filter { $0.askedById == currentUserId }.count
        case .needsMyReview: return threads.filter { reviewThreadIds.contains($0.id) }.count
        case .resolved: return threads.filter { QAThreadStatusBuckets.isResolved($0.status) }.count
        }
    }

    private func iconFor(_ filter: QAFilter) -> String {
        switch filter {
        case .all: return "list.bullet"
        case .open: return "exclamationmark.circle"
        case .myQuestions: return "person.circle"
        case .needsMyReview: return "eye.circle"
        case .resolved: return "checkmark.circle"
        }
    }

    private func colorFor(_ filter: QAFilter) -> Color {
        switch filter {
        case .all: return .blue
        case .open: return .orange
        case .myQuestions: return .purple
        case .needsMyReview: return .red
        case .resolved: return .green
        }
    }

    private func smartCard(_ label: String, count: Int, icon: String, isActive: Bool,
                           color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text("\(count)")
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                }
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? .white : color)
            .frame(minWidth: 70)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color : color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Questions List

    @ViewBuilder
    private var questionsList: some View {
        if isLoading {
            ProgressView("Loading questions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredThreads.isEmpty {
            if threads.isEmpty {
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "No Questions",
                    message: "No Q&A threads exist yet. Tap + to ask the first question."
                )
            } else if statusFilter == .needsMyReview {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Nothing Needs Your Review",
                    message: "No open questions are waiting on you or your role right now."
                )
            } else {
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "No Matching Questions",
                    message: "No Q&A threads match your current filter or search."
                )
            }
        } else {
            List(filteredThreads, id: \.id) { thread in
                NavigationLink {
                    IOSEscalationTimeline(thread: thread)
                        .environmentObject(appCore)
                        .navigationTitle("Q&A Detail")
                } label: {
                    threadRow(thread)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredThreads: [ChatService.QAThreadRow] {
        var items = threads

        // Apply smart card filter
        switch statusFilter {
        case .all: break
        case .open: items = items.filter { QAThreadStatusBuckets.isOpen($0.status) }
        case .myQuestions:
            guard let currentUserId = appCore.currentUser?.id else {
                items = []
                break
            }
            items = items.filter { $0.askedById == currentUserId }
        case .needsMyReview: items = items.filter { reviewThreadIds.contains($0.id) }
        case .resolved: items = items.filter { QAThreadStatusBuckets.isResolved($0.status) }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.question.lowercased().contains(query) ||
                $0.askedByName.lowercased().contains(query) ||
                ($0.answeredByName?.lowercased().contains(query) ?? false)
            }
        }

        return items
    }

    private func threadRow(_ thread: ChatService.QAThreadRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    priorityBadge(thread.priority, dueDate: thread.dueDate)
                    levelBadge(thread.currentLevel)
                }
                Text(thread.question)
                    .fontWeight(.medium)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("Asked by \(thread.askedByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let answer = thread.answer, !answer.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text(answer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(thread.status)
                if let answerer = thread.answeredByName {
                    Text(answerer)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "open": .orange
        case "answered", "resolved": .green
        case "escalated": .red
        case "closed": .secondary
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func priorityBadge(_ priority: String, dueDate: String?) -> some View {
        let color: Color = dueDate != nil
            ? TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)
            : TimelinePriorityColor.fallbackColor(priority: priority)
        return Text(priority.capitalized)
            .font(.caption2)
            .foregroundStyle(color)
    }

    private func levelBadge(_ level: String) -> some View {
        Text(level.capitalized)
            .font(.system(.caption2, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.indigo.opacity(0.12)))
            .foregroundStyle(.indigo)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.chatService else {
            loadError = "Chat service unavailable"
            isLoading = false
            return
        }
        isLoading = threads.isEmpty
        loadError = nil
        do {
            // Load all threads — filtering is done client-side via smart cards
            threads = try service.listQAThreads()
            // "Needs My Review" is ownership-aware: only threads at an escalation
            // level the current user's role responds to (excluding their own
            // questions unless pushed back to them). See ChatService (#1200).
            if let currentUserId = appCore.currentUser?.id {
                reviewThreadIds = Set(try service.listQAThreadsNeedingReview(userId: currentUserId).map(\.id))
            } else {
                reviewThreadIds = []
            }
        } catch {
            loadError = userFriendlyError(error, context: "load questions")
        }
        isLoading = false
    }
}

enum QAThreadStatusBuckets {
    static func isOpen(_ status: String) -> Bool {
        status == "open" || status == "escalated"
    }

    static func isResolved(_ status: String) -> Bool {
        status == "answered" || status == "closed" || status == "resolved"
    }
}
