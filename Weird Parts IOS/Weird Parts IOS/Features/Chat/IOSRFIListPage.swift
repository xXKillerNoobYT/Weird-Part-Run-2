import SwiftUI
import WiredPartCore

/// RFI (Request for Information) list page — Office-only.
///
/// Shows all RFIs across jobs for office/management review.
/// RFIs are Q&A threads that have been escalated to the office level.
/// Uses smart card filters and provides navigation to escalation timeline.
struct IOSRFIListPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var threads: [ChatService.QAThreadRow] = []
    @State private var supplierQuestions: [ChatService.SupplierQuestionRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter: RFIFilter = .all
    @State private var loadError: String?
    @State private var actionError: String?
    private enum ActiveSheet: String, Identifiable {
        case createRFI
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    enum RFIFilter: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case pendingResponse = "Pending Response"
        case closed = "Closed"
    }

    var body: some View {
        VStack(spacing: 0) {
            smartCardBar

            if let error = actionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            threadList
        }
        .navigationTitle("RFIs")
        .searchable(text: $searchText, prompt: "Search RFIs...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .createRFI } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new RFI")
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
            case .createRFI:
                // RFIs live at the office level — create the thread there so it
                // appears in this page's office-level list right away instead of
                // dead-ending at the worker level (#1200 follow-up).
                IOSQAQuestionForm(escalationLevel: "office", onSubmitted: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "RFI Help",
                    sections: [
                        ("What This Page Does", "RFIs (Requests for Information) are questions that have been escalated to the office level. This page gives office and management a single view of all open RFIs across every job, plus supplier questions that need responses."),
                        ("How to Use It", "Use the filter cards to view All RFIs, just Open ones, those Pending Response from suppliers, or Closed items. Tap any RFI to see the full escalation timeline -- who asked it, what level it came from, and any answers provided so far."),
                        ("Supplier Questions", "The Supplier Questions section shows inquiries sent to or from suppliers. These might be about pricing, availability, lead times, or technical specs. They appear separately so office staff can track vendor communications."),
                        ("Creating an RFI", "Tap the + button to create a new RFI. Select the job, type the question, and set the priority. The RFI enters the escalation chain and notifies the appropriate people."),
                        ("Tips", "Color-coded status badges (Open, Answered, Escalated, Closed) and priority badges (Low, Normal, High, Urgent) help you quickly triage which RFIs need attention first. Pull down to refresh the list at any time.")
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
                ForEach(RFIFilter.allCases, id: \.self) { filter in
                    smartCard(filter.rawValue, count: countFor(filter),
                              icon: iconFor(filter), isActive: statusFilter == filter,
                              color: colorFor(filter)) {
                        statusFilter = filter
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countFor(_ filter: RFIFilter) -> Int {
        let allItems = threads
        switch filter {
        case .all: return allItems.count + supplierQuestions.count
        case .open: return allItems.filter { $0.status == "open" || $0.status == "escalated" }.count
        case .pendingResponse: return supplierQuestions.filter { $0.status == "open" }.count
        case .closed: return allItems.filter { $0.status == "answered" || $0.status == "closed" }.count
        }
    }

    private func iconFor(_ filter: RFIFilter) -> String {
        switch filter {
        case .all: return "doc.text"
        case .open: return "exclamationmark.circle"
        case .pendingResponse: return "clock"
        case .closed: return "checkmark.circle"
        }
    }

    private func colorFor(_ filter: RFIFilter) -> Color {
        switch filter {
        case .all: return .blue
        case .open: return .orange
        case .pendingResponse: return .purple
        case .closed: return .green
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

    // MARK: - Thread List

    @ViewBuilder
    private var threadList: some View {
        if isLoading {
            ProgressView("Loading RFIs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredThreads.isEmpty && filteredSupplierQuestions.isEmpty {
            if threads.isEmpty && supplierQuestions.isEmpty {
                EmptyStateView(
                    icon: "doc.questionmark",
                    title: "No RFIs",
                    message: "No questions have been escalated to the office level and no supplier questions are waiting."
                )
            } else {
                EmptyStateView(
                    icon: "doc.questionmark",
                    title: "No Matching RFIs",
                    message: "No RFIs match your current filter or search."
                )
            }
        } else {
            List {
                if !filteredSupplierQuestions.isEmpty {
                    Section("Supplier Questions") {
                        ForEach(filteredSupplierQuestions) { question in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "building.2")
                                        .foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                    Text(question.subject)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                HStack {
                                    Text(question.supplierName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(question.status.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(statusColor(question.status).opacity(0.1))
                                        .foregroundStyle(statusColor(question.status))
                                        .clipShape(Capsule())
                                }
                                Text("Asked by \(question.askedByName)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !filteredThreads.isEmpty {
                    Section("RFIs") {
                        ForEach(filteredThreads) { thread in
                            NavigationLink {
                                IOSEscalationTimeline(thread: thread)
                                    .environmentObject(appCore)
                                    .navigationTitle("RFI Detail")
                            } label: {
                                rfiRow(thread)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredThreads: [ChatService.QAThreadRow] {
        var items = threads

        switch statusFilter {
        case .all: break
        case .open: items = items.filter { $0.status == "open" || $0.status == "escalated" }
        case .pendingResponse: items = [] // Supplier questions only
        case .closed: items = items.filter { $0.status == "answered" || $0.status == "closed" }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.question.lowercased().contains(query) ||
                $0.askedByName.lowercased().contains(query)
            }
        }

        return items
    }

    private var filteredSupplierQuestions: [ChatService.SupplierQuestionRow] {
        switch statusFilter {
        case .pendingResponse, .all:
            if searchText.isEmpty { return supplierQuestions }
            let query = searchText.lowercased()
            return supplierQuestions.filter {
                $0.subject.lowercased().contains(query) ||
                $0.supplierName.lowercased().contains(query)
            }
        default:
            return []
        }
    }

    private func rfiRow(_ thread: ChatService.QAThreadRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusBadge(
                    text: thread.status.capitalized,
                    color: statusColor(thread.status)
                )
                StatusBadge(
                    text: thread.priority.capitalized,
                    color: priorityColor(thread.priority, dueDate: thread.dueDate)
                )
                Spacer()
                Text("Level: \(thread.currentLevel.capitalized)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(thread.question)
                .font(.subheadline)
                .lineLimit(2)

            Text("Asked by \(thread.askedByName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let answer = thread.answer {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(answer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open": return .orange
        case "answered": return .green
        case "escalated": return .red
        default: return .secondary
        }
    }
    private func priorityColor(_ priority: String, dueDate: String?) -> Color {
        if dueDate != nil {
            return TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)
        }
        return TimelinePriorityColor.fallbackColor(priority: priority)
    }

    // MARK: - Data

    private func loadData() {
        guard let service = appCore.chatService else {
            loadError = "Chat service unavailable"
            isLoading = false
            return
        }
        isLoading = threads.isEmpty && supplierQuestions.isEmpty
        loadError = nil
        do {
            // RFIs are Q&A threads escalated to the office level — load only those,
            // not every open Q&A thread (#1200). Status filtering stays client-side
            // via the smart cards.
            threads = try service.listQAThreads(levels: ["office"])
            supplierQuestions = try service.listSupplierQuestions()
        } catch {
            loadError = userFriendlyError(error, context: "load RFIs")
        }
        isLoading = false
    }
}
