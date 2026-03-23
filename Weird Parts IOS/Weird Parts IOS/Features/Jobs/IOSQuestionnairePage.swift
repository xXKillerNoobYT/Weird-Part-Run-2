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

    var body: some View {
        NavigationStack {
            questionnaireContent
                .navigationTitle("Clock-Out Questions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { submitResponses() }
                            .disabled(isSubmitting || !allRequiredAnswered)
                    }
                }
                .task { loadQuestions() }
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
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Companion poll questions (always optional)
                if !companionPolls.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "link.badge.plus")
                                .foregroundStyle(.blue)
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
        }
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

    private var allRequiredAnswered: Bool {
        for question in questions where question.isRequired {
            let answer = answers[question.questionId] ?? ""
            if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    // MARK: - Actions

    private func submitResponses() {
        guard let service = appCore.jobsService else { return }
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
            errorMessage = "Failed to save responses: \(error.localizedDescription)"
        }
        isSubmitting = false
    }

    // MARK: - Data Loading

    private func loadQuestions() {
        guard let service = appCore.jobsService else { return }
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
                errorMessage = "Failed to load questions: \(error.localizedDescription)"
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
    }
}
