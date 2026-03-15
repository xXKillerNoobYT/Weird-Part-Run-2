import SwiftUI
import WiredPartCore

/// Q&A threads page showing all questions with status filtering.
///
/// Displays a table of Q&A threads with subject, asked by, status badge,
/// priority, answer status, and creation date columns. Supports filtering
/// by thread status (open, answered, closed).
struct QuestionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var threads: [ChatService.QAThreadRow] = []
    @State private var isLoading = true
    @State private var statusFilter = "all"

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ChatService.QAThreadRow.question)]

    private let statusOptions = ["all", "open", "answered", "closed"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Questions & Answers")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(threads.count) thread\(threads.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Status", selection: $statusFilter) {
                ForEach(statusOptions, id: \.self) { status in
                    Text(status == "all" ? "All Statuses" : status.capitalized)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .onChange(of: statusFilter) { loadData() }

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading questions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if threads.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No questions")
                    .font(.headline)
                Text("No Q&A threads found matching your filter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedThreads, sortOrder: $sortOrder) {
                TableColumn("Question", value: \.question) { thread in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.question)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        if let answer = thread.answer, !answer.isEmpty {
                            Text(answer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .width(min: 200, ideal: 350)

                TableColumn("Asked By", value: \.askedByName) { thread in
                    Text(thread.askedByName)
                        .font(.callout)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Status", value: \.status) { thread in
                    statusBadge(thread.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Priority", value: \.priority) { thread in
                    priorityBadge(thread.priority)
                }
                .width(min: 70, ideal: 80)

                TableColumn("Level", value: \.currentLevel) { thread in
                    Text(thread.currentLevel.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 80)

                TableColumn("Answered By") { (thread: ChatService.QAThreadRow) in
                    Text(thread.answeredByName ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedThreads: [ChatService.QAThreadRow] {
        threads.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "open": .orange
        case "answered": .green
        case "closed": .gray
        case "escalated": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
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
            .font(.caption)
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            let service = ChatService(db: db)
            threads = try service.listQAThreads(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            print("[QuestionsPage] Load error: \(error)")
        }

        isLoading = false
    }
}
