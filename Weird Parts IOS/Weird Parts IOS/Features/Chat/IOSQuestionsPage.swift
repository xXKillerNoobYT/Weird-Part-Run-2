import SwiftUI
import WiredPartCore

/// Q&A threads list page for iOS.
///
/// Displays a searchable list of Q&A threads with question text,
/// asked by name, status badge, priority, and answer status.
/// Supports pull-to-refresh and status-based filtering.
struct IOSQuestionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var threads: [ChatService.QAThreadRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    private let statusOptions = ["all", "open", "answered", "escalated", "closed"]

    var body: some View {
        VStack(spacing: 0) {
            statusPicker
            questionsList
        }
        .navigationTitle("Q&A")
        .searchable(text: $searchText, prompt: "Search questions...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status == "all" ? "All" : status.capitalized)
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
            .padding(.vertical, 8)
        }
    }

    // MARK: - Questions List

    @ViewBuilder
    private var questionsList: some View {
        if isLoading {
            ProgressView("Loading questions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredThreads.isEmpty {
            ContentUnavailableView {
                Label("No Questions", systemImage: "questionmark.circle")
            } description: {
                Text("No Q&A threads match your criteria.")
            }
        } else {
            List(filteredThreads, id: \.id) { thread in
                threadRow(thread)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredThreads: [ChatService.QAThreadRow] {
        guard !searchText.isEmpty else { return threads }
        let query = searchText.lowercased()
        return threads.filter {
            $0.question.lowercased().contains(query) ||
            $0.askedByName.lowercased().contains(query) ||
            ($0.answeredByName?.lowercased().contains(query) ?? false)
        }
    }

    private func threadRow(_ thread: ChatService.QAThreadRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    priorityBadge(thread.priority)
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
        case "answered": .green
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

    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        case "low": .secondary
        default: .secondary
        }
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
        guard let service = appCore.chatService else { return }
        isLoading = threads.isEmpty
        do {
            threads = try service.listQAThreads(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            print("[IOSQuestionsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
