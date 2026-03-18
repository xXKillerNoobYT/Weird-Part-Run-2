import SwiftUI
import WiredPartCore

/// RFI (Request for Information) list page — Office-only.
///
/// Shows all RFIs across jobs for office/management review.
/// RFIs are Q&A threads that have been escalated to the office level.
struct IOSRFIListPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var threads: [ChatService.QAThreadRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var loadError: String?

    private let statusOptions = ["all", "open", "answered", "escalated"]

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            threadList
        }
        .navigationTitle("RFIs")
        .searchable(text: $searchText, prompt: "Search RFIs...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status.capitalized)
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Thread List

    @ViewBuilder
    private var threadList: some View {
        if isLoading {
            ProgressView("Loading RFIs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredThreads.isEmpty {
            EmptyStateView(
                icon: "doc.questionmark",
                title: "No RFIs",
                message: "No requests for information at this time."
            )
        } else {
            List(filteredThreads) { thread in
                NavigationLink {
                    IOSEscalationTimeline(thread: thread)
                        .navigationTitle("RFI Detail")
                } label: {
                    rfiRow(thread)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredThreads: [ChatService.QAThreadRow] {
        // Status filter is already applied in loadData() via the service call,
        // so only apply search text filtering here
        guard !searchText.isEmpty else { return threads }
        let query = searchText.lowercased()
        return threads.filter {
            $0.question.lowercased().contains(query) ||
            $0.askedByName.lowercased().contains(query)
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
                    color: priorityColor(thread.priority)
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
        case "open": .orange
        case "answered": .green
        case "escalated": .red
        default: .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        case "low": .secondary
        default: .secondary
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let service = appCore.chatService else { return }
        isLoading = threads.isEmpty
        loadError = nil
        do {
            threads = try service.listQAThreads(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
