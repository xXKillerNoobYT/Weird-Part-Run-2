import SwiftUI
import WiredPartCore

/// Clock-out questions management page.
///
/// Displays the list of questions that workers answer when clocking
/// out of a job. Allows reordering and toggling active status.
/// Reads directly from the database since there is no dedicated
/// service yet for clock-out questions.
struct ClockOutQuestionsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var questions: [ClockOutQuestion] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if questions.isEmpty {
                Section {
                    Text("No clock-out questions configured. Questions asked to workers when they clock out of a job.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Active Questions") {
                    ForEach(questions.filter { $0.isActive == 1 }, id: \.id) { q in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(q.questionText)
                                .font(.body)
                            HStack {
                                Text("Type: \(q.answerType)")
                                if q.isRequired == 1 {
                                    Text("Required")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                let inactive = questions.filter { $0.isActive == 0 }
                if !inactive.isEmpty {
                    Section("Inactive Questions") {
                        ForEach(inactive, id: \.id) { q in
                            Text(q.questionText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            Section {
                Text("Clock-out questions are answered by workers when they end their shift. Responses are stored with the labor entry for reporting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadQuestions() }
    }

    private func loadQuestions() {
        do {
            questions = try appCore.db.writer.read { dbConnection in
                try ClockOutQuestion.fetchAll(
                    dbConnection,
                    sql: "SELECT * FROM clock_out_questions WHERE deleted_at IS NULL ORDER BY sort_order ASC"
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
