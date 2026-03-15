import SwiftUI
import GRDB
import WiredPartCore

/// Clock-out questions management page.
///
/// Lists global clock-out questions with add, edit, reorder, and delete.
/// Reads from and writes to the `global_questions` table via GRDB.
struct ClockOutQuestionsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var questions: [ClockOutQuestion] = []
    @State private var newQuestionText: String = ""
    @State private var editingId: Int64? = nil
    @State private var editText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Clock-Out Questions")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("These questions are presented to workers when they clock out of a job.")
                    .foregroundStyle(.secondary)

                // Add new question
                GroupBox("Add Question") {
                    HStack {
                        TextField("Enter question text...", text: $newQuestionText)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            addQuestion()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newQuestionText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.vertical, 4)
                }

                // Question list
                if questions.isEmpty {
                    Text("No clock-out questions configured yet.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    GroupBox("Questions (\(questions.count))") {
                        VStack(spacing: 0) {
                            ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                                questionRow(question, index: index)
                                if index < questions.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadQuestions() }
    }

    private func questionRow(_ question: ClockOutQuestion, index: Int) -> some View {
        HStack {
            Text("\(index + 1).")
                .foregroundStyle(.secondary)
                .frame(width: 28)

            if editingId == question.id {
                TextField("Question", text: $editText)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    saveEdit(question)
                }
                .buttonStyle(.bordered)
                Button("Cancel") {
                    editingId = nil
                }
                .buttonStyle(.plain)
            } else {
                Text(question.questionText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Reorder buttons
                Button {
                    moveQuestion(question, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .buttonStyle(.plain)

                Button {
                    moveQuestion(question, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == questions.count - 1)
                .buttonStyle(.plain)

                Button {
                    editingId = question.id
                    editText = question.questionText
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)

                Button {
                    deleteQuestion(question)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Data Operations

    private func loadQuestions() {
        guard let db = appCore.db else { return }
        do {
            questions = try db.writer.read { dbConnection in
                try ClockOutQuestion.fetchAll(
                    dbConnection,
                    sql: "SELECT * FROM global_questions WHERE deleted_at IS NULL ORDER BY sort_order ASC, id ASC"
                )
            }
        } catch {
            // Table may not exist yet
            questions = []
        }
    }

    private func addQuestion() {
        guard let db = appCore.db else { return }
        let text = newQuestionText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let nextOrder = (questions.last?.sortOrder ?? 0) + 1

        do {
            try db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: """
                        INSERT INTO global_questions (question_text, question_type, sort_order, is_required, created_at)
                        VALUES (?, 'text', ?, 0, datetime('now'))
                        """,
                    arguments: [text, nextOrder]
                )
            }
            newQuestionText = ""
            loadQuestions()
        } catch {
            print("[ClockOutQuestions] Add error: \(error)")
        }
    }

    private func saveEdit(_ question: ClockOutQuestion) {
        guard let db = appCore.db, let id = question.id else { return }
        let text = editText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        do {
            try db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: "UPDATE global_questions SET question_text = ? WHERE id = ?",
                    arguments: [text, id]
                )
            }
            editingId = nil
            loadQuestions()
        } catch {
            print("[ClockOutQuestions] Edit error: \(error)")
        }
    }

    private func deleteQuestion(_ question: ClockOutQuestion) {
        guard let db = appCore.db, let id = question.id else { return }
        do {
            try db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: "UPDATE global_questions SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [id]
                )
            }
            loadQuestions()
        } catch {
            print("[ClockOutQuestions] Delete error: \(error)")
        }
    }

    private func moveQuestion(_ question: ClockOutQuestion, direction: Int) {
        guard let idx = questions.firstIndex(where: { $0.id == question.id }) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0 && newIdx < questions.count else { return }
        guard let db = appCore.db else { return }

        let other = questions[newIdx]
        do {
            try db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: "UPDATE global_questions SET sort_order = ? WHERE id = ?",
                    arguments: [other.sortOrder, question.id]
                )
                try dbConnection.execute(
                    sql: "UPDATE global_questions SET sort_order = ? WHERE id = ?",
                    arguments: [question.sortOrder, other.id]
                )
            }
            loadQuestions()
        } catch {
            print("[ClockOutQuestions] Reorder error: \(error)")
        }
    }
}

// MARK: - Model

private struct ClockOutQuestion: Codable, FetchableRecord, Identifiable {
    var id: Int64?
    var questionText: String
    var questionType: String
    var sortOrder: Int
    var isRequired: Int
    var deletedAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case questionType = "question_type"
        case sortOrder = "sort_order"
        case isRequired = "is_required"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }
}
