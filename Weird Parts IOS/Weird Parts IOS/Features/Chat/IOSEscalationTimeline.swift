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
    @State private var pushBackReason = ""
    @State private var activeSheet: ActiveSheet?
    @State private var showEscalateConfirm = false

    // Single enum for all sheets — avoids SwiftUI multiple-.sheet() bug
    private enum ActiveSheet: Identifiable {
        case help
        case pushBack
        var id: String {
            switch self {
            case .help: return "help"
            case .pushBack: return "pushBack"
            }
        }
    }

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
                } else if steps.isEmpty {
                    EmptyStateView(
                        icon: "arrow.up.arrow.down.circle",
                        title: "No Escalation History",
                        message: "This question has not been escalated yet. Use the buttons below to escalate or push back."
                    )
                } else {
                    timelineView
                }

                // Action buttons
                actionButtons
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Escalation Timeline Help",
                    sections: [
                        ("What This Page Does", "This page shows the full escalation history of a Q&A question or RFI. You can see every level the question has passed through -- Worker, Lead, Manager, Office -- who reviewed it, when, and any notes they left."),
                        ("How to Read the Timeline", "The vertical timeline shows each escalation level as a node. Green nodes are completed levels, the blue node is the current level, and gray nodes have not been reached yet. Reviewer names and timestamps appear next to each completed step."),
                        ("Escalating a Question", "If you cannot answer the question at your level, tap the Escalate button to send it up to the next level. The question moves from Worker to Lead, Lead to Manager, or Manager to Office."),
                        ("Pushing Back", "If a question was escalated to your level but should be handled at a lower level, tap Push Back. You will need to provide a reason explaining why it is being sent back down. This feedback helps the team learn the right routing."),
                        ("Tips", "Check the status and priority badges at the top for a quick summary. The question text, who asked it, and any existing answer are all shown in the header. Only open questions can be escalated; closed questions cannot be changed.")
                    ]
                )
            case .pushBack:
                PushBackSheet(
                    reason: $pushBackReason,
                    onSubmit: { doPushBack() }
                )
            }
        }
        .refreshable { loadSteps() }
        .task { loadSteps() }
    }

    // MARK: - Thread Info Header

    private var threadInfoHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StatusBadge(text: thread.status.capitalized, color: statusColor(thread.status))
                StatusBadge(text: thread.priority.capitalized, color: priorityColor(thread.priority, dueDate: thread.dueDate))
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
                        .accessibilityHidden(true)
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
                            .accessibilityLabel(step.isCurrent ? "Status: Current level" : step.isComplete ? "Status: Completed" : "Status: Not yet reached")
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.isComplete ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 2, height: 40)
                                .accessibilityHidden(true)
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
                        showEscalateConfirm = true
                    } label: {
                        Label("Escalate", systemImage: "arrow.up.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .confirmationDialog(
                        "Escalate this question?",
                        isPresented: $showEscalateConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Escalate", role: .destructive) { doEscalate() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("The question will be sent to the next level. This notifies the reviewer above you.")
                    }
                }
                if canPushBack {
                    Button {
                        activeSheet = .pushBack
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
            loadError = userFriendlyError(error, context: "load escalation timeline")
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
            actionError = userFriendlyError(error, context: "process escalation")
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
            activeSheet = nil
            loadSteps()
        } catch {
            actionError = userFriendlyError(error, context: "process escalation")
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
    private func priorityColor(_ priority: String, dueDate: String?) -> Color {
        TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)
    }
}

// MARK: - Push Back Sheet

/// Sheet for entering a reason when pushing back a Q&A thread.
private struct PushBackSheet: View {
    @Binding var reason: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false

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
            .interactiveDismissDisabled(!reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        isSubmitting = true
                        onSubmit()
                        isSubmitting = false
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }
}
