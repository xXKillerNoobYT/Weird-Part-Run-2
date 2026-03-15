import SwiftUI
import GRDB
import WiredPartCore

/// Clock-out questionnaire management page.
///
/// Lists all clock-out questions with their type and required status.
/// Provides CRUD operations for managing questions that workers must
/// answer when clocking out.
struct QuestionnairePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var questions: [JobsService.QuestionnaireItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            questionContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadQuestions() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clock-Out Questionnaire")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(questions.count) questions configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                loadQuestions()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var questionContent: some View {
        if isLoading {
            ProgressView("Loading questions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if questions.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No questions configured")
                    .font(.headline)
                Text("Clock-out questions can be managed in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.1)))
                    }

                    ForEach(questions, id: \.questionId) { question in
                        questionRow(question)
                    }
                }
                .padding(24)
            }
        }
    }

    private func questionRow(_ question: JobsService.QuestionnaireItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(question.questionText)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text("Type: \(question.answerType)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if question.isRequired {
                        Text("Required")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if let answer = question.answer, !answer.isEmpty {
                Text(answer)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.05)))
    }

    // MARK: - Data Loading

    private func loadQuestions() {
        guard let service = appCore.jobsService else { return }
        isLoading = true
        do {
            questions = try service.getActiveQuestions()
        } catch {
            print("[QuestionnairePage] Load error: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
