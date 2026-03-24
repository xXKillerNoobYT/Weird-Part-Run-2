import SwiftUI
import WiredPartCore

/// Visual escalation timeline showing the bidirectional escalation chain for Q&A threads.
///
/// Displays: Worker → Lead → Manager → Office with review info at each step.
/// Supports escalate (up) and push back (down) actions.
struct IOSEscalationTimeline: View {
    @EnvironmentObject private var appCore: AppCore

    let thread: ChatService.QAThreadRow

    @State private var steps: [ChatService.EscalationStep] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var showPushBackSheet = false
    @State private var pushBackReason = ""

    private var canEscalate: Bool {
        thread.currentLevel != "office" && thread.status == "open"
    }

    private var canPushBack: Bool {
        thread.currentLevel != "worker" && thread.status != "closed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Thread info header
                threadInfoHeader

                // Error banner
                if let error = actionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Timeline
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { Task { loadSteps() } }
                } else {
                    timelineView
                }

                // Action buttons
                actionButtons
            }
            .padding()
        }
        .task { loadSteps() }
        .sheet(isPresented: $showPushBackSheet) {
            PushBackSheet(
                reason: $pushBackReason,
                onSubmit: { doPushBack() }
            )
        }
    }

    // MARK: - Thread Info Header

    private var threadInfoHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StatusBadge(text: thread.status.capitalized, color: statusColor(thread.status))
                StatusBadge(text: thread.priority.capitalized, color: priorityColor(thread.priority))
            }

            Text(thread.question)
                .font(.headline)

            Text("Asked by \(thread.askedByName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let answer = thread.answer, !answer.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(answer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Timeline View

    private var timelineView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Escalation Timeline")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.bottom, 8)

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline node
                    VStack(spacing: 0) {
                        Circle()
                            .fill(step.isCurrent ? Color.blue : step.isComplete ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.isComplete ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 2, height: 40)
                        }
                    }

                    // Step content
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(step.levelLabel)
                                .font(.subheadline)
                                .fontWeight(step.isCurrent ? .bold : .regular)
                            if step.isCurrent {
                                Text("Current")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        if let reviewer = step.reviewedBy, let date = step.reviewedAt {
                            Text("\(reviewer) — \(date, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let notes = step.notes {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if canEscalate || canPushBack {
            HStack(spacing: 12) {
                if canEscalate {
                    Button {
                        doEscalate()
                    } label: {
                        Label("Escalate", systemImage: "arrow.up.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if canPushBack {
                    Button {
                        showPushBackSheet = true
                    } label: {
                        Label("Push Back", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func loadSteps() {
        guard let service = appCore.chatService else {
            loadError = "Chat service unavailable"
            isLoading = false
            return
        }
        isLoading = steps.isEmpty
        loadError = nil
        do {
            steps = try service.getEscalationHistory(threadId: thread.id)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func doEscalate() {
        guard let service = appCore.chatService,
              let userId = appCore.currentUser?.id else {
            actionError = "Service unavailable"
            return
        }
        do {
            try service.escalateThread(threadId: thread.id, escalatedBy: userId, notes: nil)
            loadSteps()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func doPushBack() {
        guard let service = appCore.chatService,
              let userId = appCore.currentUser?.id else {
            actionError = "Service unavailable"
            return
        }
        let reason = pushBackReason.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else {
            actionError = "Push back requires a reason"
            return
        }
        do {
            try service.pushBackThread(threadId: thread.id, pushedBackBy: userId, reason: reason)
            pushBackReason = ""
            showPushBackSheet = false
            loadSteps()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open": return .orange
        case "answered": return .green
        case "escalated": return .red
        case "closed": return .secondary
        default: return .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": return .red
        case "high": return .orange
        case "normal": return .blue
        case "low": return .secondary
        default: return .secondary
        }
    }
}

// MARK: - Push Back Sheet

/// Sheet for entering a reason when pushing back a Q&A thread.
private struct PushBackSheet: View {
    @Binding var reason: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reason for pushing back...", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Provide feedback explaining why the question is being sent back.")
                }
            }
            .navigationTitle("Push Back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        onSubmit()
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
