import SwiftUI
import GRDB
import WiredPartCore

/// Clock-out questionnaire management page for iOS.
///
/// Lists the questions that employees answer when clocking out.
/// Supports viewing, adding, editing, and deleting questions.
/// Questions are stored in the `clock_out_questions` table.
struct IOSClockOutQuestionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var questions: [ClockOutQuestion] = []
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var editingQuestion: ClockOutQuestion?
    @State private var newQuestionText = ""
    @State private var newQuestionType = "text"
    @State private var newQuestionRequired = true
    @State private var showDeleteConfirm = false
    @State private var questionToDelete: ClockOutQuestion?

    private let questionTypes = ["text", "yes_no", "rating", "multiple_choice"]

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading questions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if questions.isEmpty {
                        Section {
                            Text("No clock-out questions configured. Tap + to add one.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    } else {
                        Section("Questions (\(questions.count))") {
                            ForEach(questions) { question in
                                questionRow(question)
                            }
                            .onDelete(perform: deleteQuestions)
                        }
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle("Clock-Out Questions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    resetForm()
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { loadData() }
        .sheet(isPresented: $showAddSheet) {
            questionFormSheet
        }
        .sheet(item: $editingQuestion) { question in
            questionEditSheet(question)
        }
        .alert("Delete Question", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { questionToDelete = nil }
            Button("Delete", role: .destructive) { confirmDelete() }
        } message: {
            Text("Are you sure you want to delete this question? This cannot be undone.")
        }
    }

    // MARK: - Question Row

    private func questionRow(_ question: ClockOutQuestion) -> some View {
        Button {
            newQuestionText = question.text
            newQuestionType = question.type
            newQuestionRequired = question.isRequired
            editingQuestion = question
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 12) {
                    Label(question.type.replacingOccurrences(of: "_", with: " ").capitalized,
                          systemImage: iconForType(question.type))
                    if question.isRequired {
                        Label("Required", systemImage: "asterisk")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Optional", systemImage: "circle.dashed")
                    }
                    Text("#\(question.sortOrder)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                questionToDelete = question
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "yes_no":           return "hand.thumbsup"
        case "rating":           return "star"
        case "multiple_choice":  return "list.bullet"
        default:                 return "text.alignleft"
        }
    }

    // MARK: - Add Sheet

    private var questionFormSheet: some View {
        NavigationStack {
            Form {
                Section("Question Text") {
                    TextField("Enter question...", text: $newQuestionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Response Type") {
                    Picker("Type", selection: $newQuestionType) {
                        ForEach(questionTypes, id: \.self) { type in
                            Text(type.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                        }
                    }
                }

                Section {
                    Toggle("Required", isOn: $newQuestionRequired)
                }
            }
            .navigationTitle("Add Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNewQuestion() }
                        .disabled(newQuestionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Edit Sheet

    private func questionEditSheet(_ question: ClockOutQuestion) -> some View {
        NavigationStack {
            Form {
                Section("Question Text") {
                    TextField("Enter question...", text: $newQuestionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Response Type") {
                    Picker("Type", selection: $newQuestionType) {
                        ForEach(questionTypes, id: \.self) { type in
                            Text(type.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                        }
                    }
                }

                Section {
                    Toggle("Required", isOn: $newQuestionRequired)
                }
            }
            .navigationTitle("Edit Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingQuestion = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEditedQuestion(question) }
                        .disabled(newQuestionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func resetForm() {
        newQuestionText = ""
        newQuestionType = "text"
        newQuestionRequired = true
    }

    private func loadData() {
        guard let db = appCore.db else {
            errorMessage = "Database not available."
            isLoading = false
            return
        }
        do {
            questions = try db.writer.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, question_text, question_type, is_required, sort_order
                    FROM clock_out_questions
                    ORDER BY sort_order ASC, id ASC
                """)
                return rows.map { row in
                    ClockOutQuestion(
                        id: "\(row["id"] as Int64? ?? 0)",
                        text: row["question_text"] as? String ?? "",
                        type: row["question_type"] as? String ?? "text",
                        isRequired: (row["is_required"] as? Int64 ?? 1) == 1,
                        sortOrder: Int(row["sort_order"] as? Int64 ?? 0)
                    )
                }
            }
        } catch {
            if !error.localizedDescription.contains("no such table") {
                errorMessage = "Failed to load questions: \(error.localizedDescription)"
            }
            questions = []
        }
        isLoading = false
    }

    private func saveNewQuestion() {
        guard let db = appCore.db else { return }
        let nextOrder = (questions.last?.sortOrder ?? 0) + 1
        do {
            try db.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO clock_out_questions (question_text, question_type, is_required, sort_order)
                    VALUES (?, ?, ?, ?)
                """, arguments: [newQuestionText.trimmingCharacters(in: .whitespaces), newQuestionType, newQuestionRequired ? 1 : 0, nextOrder])
            }
            showAddSheet = false
            Task { loadData() }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func saveEditedQuestion(_ question: ClockOutQuestion) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { db in
                try db.execute(sql: """
                    UPDATE clock_out_questions
                    SET question_text = ?, question_type = ?, is_required = ?
                    WHERE id = ?
                """, arguments: [newQuestionText.trimmingCharacters(in: .whitespaces), newQuestionType, newQuestionRequired ? 1 : 0, question.id])
            }
            editingQuestion = nil
            Task { loadData() }
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    private func deleteQuestions(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        questionToDelete = questions[index]
        showDeleteConfirm = true
    }

    private func confirmDelete() {
        guard let db = appCore.db, let question = questionToDelete else { return }
        do {
            try db.writer.write { db in
                try db.execute(sql: "DELETE FROM clock_out_questions WHERE id = ?", arguments: [question.id])
            }
            questionToDelete = nil
            Task { loadData() }
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }

    // MARK: - Model

    private struct ClockOutQuestion: Identifiable {
        let id: String
        let text: String
        let type: String
        let isRequired: Bool
        let sortOrder: Int
    }
}
