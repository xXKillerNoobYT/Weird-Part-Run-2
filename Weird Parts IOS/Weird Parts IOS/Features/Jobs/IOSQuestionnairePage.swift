import SwiftUI
import WiredPartCore

/// Clock-out questionnaire page for iOS.
///
/// Presents the list of active questions from the `clock_out_questions` table.
/// Each question has a text answer field. When the user submits, all responses
/// are saved via `JobsService.saveClockOutResponses(laborEntryId:responses:)`.
///
/// Designed to be presented as a sheet after the user taps "Clock Out".
struct IOSQuestionnairePage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    /// The labor entry being clocked out.
    let laborEntryId: Int64

    /// Optional callback invoked after successful submission.
    var onComplete: (() -> Void)?

    // MARK: - State

    @State private var questions: [JobsService.QuestionnaireItem] = []
    @State private var answers: [Int64: String] = [:]
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // Companion poll questions
    @State private var companionPolls: [(pollId: Int64, questionText: String, hasVoted: Bool)] = []
    @State private var companionVotes: [Int64: Bool] = [:]  // pollId -> true=accept, false=reject

    // Break verification
    @State private var breakVerification: BreakAnswer = .allTaken
    @State private var missedBreaks: Set<String> = []
    @State private var hadBreakButtons = false  // Did the user use break buttons today?

    private enum BreakAnswer: String, CaseIterable {
        case allTaken = "Yes, all"
        case forgot = "I forgot / didn't"
        case partial = "Partial"
    }

    var body: some View {
        NavigationStack {
            questionnaireContent
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Clock-Out Questions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Hide Skip when required questions remain unanswered
                        if !hasUnansweredRequired {
                            Button("Skip") { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { submitResponses() }
                            .disabled(isSubmitting || !allRequiredAnswered)
                    }
                }
                .task { loadQuestions() }
                .onDisappear {
                    NotificationCenter.default.post(name: .questionnairePageInactive, object: nil)
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var questionnaireContent: some View {
        if isLoading {
            ProgressView("Loading questions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if questions.isEmpty && companionPolls.isEmpty {
            ContentUnavailableView {
                Label("No Questions", systemImage: "questionmark.circle")
            } description: {
                Text("No clock-out questions are configured. You can close this screen.")
            }
        } else {
            List {
                // Error banner
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // Instructions
                Section {
                    Text("Please answer the following questions before clocking out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Question list
                ForEach(questions, id: \.questionId) { question in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 6) {
                                Text(question.questionText)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                if question.isRequired {
                                    Text("*")
                                        .foregroundStyle(.red)
                                        .fontWeight(.bold)
                                }
                            }

                            answerField(for: question)

                            // Per-question validation error for unanswered required fields
                            if question.isRequired &&
                               (answers[question.questionId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label("This question is required", systemImage: "exclamationmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Break verification
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Did you take your breaks today?")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("Breaks", selection: $breakVerification) {
                            ForEach(BreakAnswer.allCases, id: \.self) { answer in
                                Text(answer.rawValue).tag(answer)
                            }
                        }
                        .pickerStyle(.segmented)

                        if breakVerification == .partial || breakVerification == .forgot {
                            if breakVerification == .partial {
                                Text("Which breaks did you miss?")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                breakCheckToggle("Morning break", key: "morning_break")
                                breakCheckToggle("Lunch", key: "lunch")
                                breakCheckToggle("Afternoon break", key: "afternoon_break")
                            }

                            Label("Missed breaks will be reported to the office.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Image(systemName: "cup.and.saucer")
                            .foregroundStyle(.purple)
                            .accessibilityHidden(true)
                        Text("Break Verification")
                    }
                }

                // Companion poll questions (always optional)
                if !companionPolls.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "link.badge.plus")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text("Companion Rule Votes")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("Recommended")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }

                    ForEach(companionPolls, id: \.pollId) { poll in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(poll.questionText)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Toggle("Yes, link these", isOn: Binding<Bool>(
                                    get: { companionVotes[poll.pollId] ?? false },
                                    set: { companionVotes[poll.pollId] = $0 }
                                ))
                                .font(.subheadline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Submission info
                if !allRequiredAnswered {
                    Section {
                        Label(
                            "Fill in all required fields (marked with *) to submit.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { loadQuestions() }
        }
    }

    // MARK: - Break Check Toggle

    private func breakCheckToggle(_ label: String, key: String) -> some View {
        Toggle(label, isOn: Binding<Bool>(
            get: { missedBreaks.contains(key) },
            set: { selected in
                if selected {
                    missedBreaks.insert(key)
                } else {
                    missedBreaks.remove(key)
                }
            }
        ))
        .font(.subheadline)
    }

    // MARK: - Answer Field

    @ViewBuilder
    private func answerField(for question: JobsService.QuestionnaireItem) -> some View {
        let binding = Binding<String>(
            get: { answers[question.questionId] ?? "" },
            set: { answers[question.questionId] = $0 }
        )

        switch question.answerType {
        case "boolean":
            Toggle("Yes / No", isOn: Binding<Bool>(
                get: { answers[question.questionId]?.lowercased() == "yes" },
                set: { answers[question.questionId] = $0 ? "Yes" : "No" }
            ))
            .font(.subheadline)

        case "number":
            TextField("Enter a number...", text: binding)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

        default:
            // Default to text input (covers "text" and any other types)
            TextField("Enter your answer...", text: binding, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
    }

    // MARK: - Validation

    /// True when at least one required question has no answer yet.
    private var hasUnansweredRequired: Bool {
        questions.contains { question in
            question.isRequired &&
            (answers[question.questionId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var allRequiredAnswered: Bool {
        !hasUnansweredRequired
    }

    // MARK: - Actions

    private func submitResponses() {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }
        isSubmitting = true
        errorMessage = nil

        let responses: [(questionId: Int64, answer: String)] = questions.map { q in
            (questionId: q.questionId, answer: answers[q.questionId] ?? "")
        }

        do {
            try service.saveClockOutResponses(
                laborEntryId: laborEntryId,
                responses: responses
            )

            // Handle break verification
            handleBreakVerification()

            // Save companion poll votes (separate from clock-out responses)
            if let partsService = appCore.partsService,
               let userId = appCore.currentUser?.id {
                for (pollId, answeredYes) in companionVotes {
                    try partsService.castVote(
                        pollId: pollId,
                        userId: userId,
                        vote: answeredYes ? "accept" : "reject"
                    )
                }
            }

            onComplete?()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "save responses")
        }
        isSubmitting = false
    }

    /// Handle break verification logic:
    /// - "Yes, all taken" + no break buttons used → auto-fill at defaults
    /// - "Forgot" or "Partial" → report missed breaks to office
    private func handleBreakVerification() {
        guard let breakSvc = appCore.breakService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Break service not available"
            return
        }

        switch breakVerification {
        case .allTaken:
            // If user said "yes, all taken" but didn't actually use break buttons,
            // auto-fill break records at default times for compliance
            if !hadBreakButtons {
                try? breakSvc.autoFillBreaksForDay(
                    userId: userId,
                    laborEntryId: laborEntryId
                )
            }
            // Note: if hadBreakButtons == true, bonus is eligible (handled by compliance calc)

        case .forgot:
            // All breaks missed — mark all as missed, auto-fill for compliance
            try? breakSvc.autoFillBreaksForDay(
                userId: userId,
                laborEntryId: laborEntryId
            )
            // Bonus NOT eligible since questionnaire had to ask

        case .partial:
            // Some breaks missed — auto-fill the ones that were missed
            if !missedBreaks.isEmpty {
                try? breakSvc.autoFillBreaksForDay(
                    userId: userId,
                    laborEntryId: laborEntryId
                )
            }
            // Bonus NOT eligible since questionnaire had to ask
        }
    }

    // MARK: - Data Loading

    private func loadQuestions() {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            isLoading = false
            return
        }
        isLoading = true
        do {
            questions = try service.getActiveQuestions()
            // Pre-populate answers dictionary with empty strings
            for q in questions {
                answers[q.questionId] = ""
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                errorMessage = userFriendlyError(error, context: "load questions")
            }
        }

        // Check if user used break buttons today
        if let breakSvc = appCore.breakService,
           let userId = appCore.currentUser?.id {
            do {
                let records = try breakSvc.getBreakRecordsForDay(userId: userId)
                hadBreakButtons = records.contains { !$0.autoFilled }
                // Pre-select "forgot" if no break records at all
                if records.isEmpty {
                    breakVerification = .forgot
                    missedBreaks = ["morning_break", "lunch", "afternoon_break"]
                }
            } catch {
                // Non-critical
            }
        }

        // Load companion poll questions (7+ days active, not yet voted)
        if let partsService = appCore.partsService,
           let userId = appCore.currentUser?.id {
            do {
                let pollQuestions = try partsService.getActivePollsForClockOut(userId: userId)
                companionPolls = pollQuestions.filter { !$0.hasVoted }
            } catch {
                // Non-critical — don't block questionnaire
            }
        }

        isLoading = false
        postAIContext()
    }

    private func postAIContext() {
        let requiredCount = questions.filter { $0.isRequired }.count
        let answeredCount = answers.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let answerTypes = Dictionary(grouping: questions, by: \.answerType)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let context = """
        Clock-Out Questionnaire page. Read-only context.
        Labor entry id: \(laborEntryId), questions loaded: \(questions.count), required questions: \(requiredCount), answered fields: \(answeredCount), unanswered required: \(hasUnansweredRequired).
        Answer types: \(answerTypes.isEmpty ? "none" : answerTypes), companion polls: \(companionPolls.count), break verification: \(breakVerification.rawValue), missed break selections: \(missedBreaks.count), submitting: \(isSubmitting).
        Available read-only guidance: explain required questions, answer types, break verification, companion poll section, and submit/skip availability. Do not submit or change answers directly.
        """
        NotificationCenter.default.post(
            name: .questionnairePageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}
