import SwiftUI
import WiredPartCore

/// Office page for managing estimation questions: add, edit, deactivate, view AI effectiveness.
struct IOSEstimationSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var questions: [EstimationQuestion] = []
    @State private var effectiveness: [QuestionEffectiveness] = []
    @State private var rejections: [Int64: [EstimationQuestionRejection]] = [:]
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var showEffectiveness = false

    private enum ActiveSheet: Identifiable {
        case add
        case edit(EstimationQuestion)
        case help
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let q): return "edit_\(q.id ?? 0)"
            case .help: return "help"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    private let stages = ["bid", "pre_start", "during", "before_trim", "punch_list"]

    private var groupedByStage: [String: [EstimationQuestion]] {
        Dictionary(grouping: questions, by: { $0.stage })
    }

    var body: some View {
        List {
            if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            }
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red) }
            }

            // Questions by stage
            ForEach(stages, id: \.self) { stage in
                if let stageQuestions = groupedByStage[stage], !stageQuestions.isEmpty {
                    Section {
                        ForEach(stageQuestions) { question in
                            questionSettingsRow(question)
                        }
                    } header: {
                        HStack {
                            Text(stageLabel(stage))
                            Spacer()
                            Text("\(stageQuestions.count) questions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // AI Effectiveness analysis
            Section {
                Button {
                    Task { await loadEffectiveness() }
                } label: {
                    Label("Analyze Question Effectiveness", systemImage: "sparkles")
                }

                if showEffectiveness {
                    ForEach(effectiveness) { item in
                        effectivenessRow(item)
                    }
                }
            } header: {
                Text("AI Analysis")
            } footer: {
                Text("Requires 15+ completed jobs with end-of-job reviews.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Estimation Questions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add question")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                AddEstimationQuestionSheet { await loadData() }
            case .edit(let question):
                EditEstimationQuestionSheet(question: question) { await loadData() }
            case .help:
                PageHelpSheet(
                    title: "Estimation Questions Help",
                    sections: [
                        ("What This Page Does", "Manage the questions asked during job estimation. Questions are grouped by stage (Bid, Pre-Start, During, Before Trim, Punch List) and used to build accurate job estimates based on real project data."),
                        ("How to Use It", "Tap + to add a new question. Swipe left on any question to edit or deactivate it. Swipe right on an inactive question to reactivate it. Each question has a group, stage, answer type, and weight that affects how much it influences the estimate."),
                        ("AI Analysis", "Tap 'Analyze Question Effectiveness' to see which questions actually correlate with accurate estimates. Questions are rated Keep, Modify, or Remove based on historical data. Requires at least 15 completed jobs with end-of-job reviews."),
                        ("Question Weight", "Weight controls how much a question's answer impacts the final estimate. Higher weight (up to 5.0) means the answer has more influence. Default is 1.0.")
                    ]
                )
            }
        }
        .refreshable { await loadData() }
        .task { await loadData() }
    }

    // MARK: - Question Row

    private func questionSettingsRow(_ question: EstimationQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(question.questionText)
                    .font(.subheadline)
                    .foregroundStyle(question.isActive == 1 ? .primary : .secondary)

                Spacer()

                if question.isActive == 0 {
                    Text("Inactive")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            HStack(spacing: 12) {
                Label(question.questionGroup, systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Group: \(question.questionGroup)")

                Label(question.answerType, systemImage: "textformat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Answer type: \(question.answerType)")

                Label(String(format: "%.1fx", question.weight), systemImage: "scalemass")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Weight: \(String(format: "%.1f", question.weight))")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await deactivateQuestion(question) }
            } label: {
                Label("Deactivate", systemImage: "xmark.circle")
            }

            Button {
                activeSheet = .edit(question)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            if question.isActive == 0 {
                Button {
                    Task { await reactivateQuestion(question) }
                } label: {
                    Label("Activate", systemImage: "checkmark.circle")
                }
                .tint(.green)
            }
        }
    }

    // MARK: - Effectiveness Row

    private func effectivenessRow(_ item: QuestionEffectiveness) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.questionText)
                    .font(.subheadline)
                Spacer()
                recommendationBadge(item.recommendation)
            }

            HStack(spacing: 12) {
                Label(String(format: "%.0f%%", item.correlationScore * 100), systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(item.correlationScore > 0.6 ? .green : item.correlationScore > 0.3 ? .orange : .red)

                Text("Asked \(item.timesAsked)×")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.timesUnknown > 0 {
                    Text("Unknown \(item.timesUnknown)×")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func recommendationBadge(_ recommendation: String) -> some View {
        let (label, color): (String, Color) = switch recommendation {
        case "keep": ("Keep", .green)
        case "modify": ("Modify", .orange)
        case "remove": ("Remove", .red)
        default: ("Need Data", .gray)
        }

        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let svc = appCore.jobEstimationService else {
            loadError = "Estimation service not available"
            return
        }
        do {
            questions = try svc.getAllQuestions()
        } catch {
            loadError = userFriendlyError(error, context: "load estimation settings")
        }
    }

    private func loadEffectiveness() async {
        guard let svc = appCore.jobEstimationService else {
            actionError = "Service not available"
            return
        }
        do {
            effectiveness = try svc.analyzeQuestionEffectiveness()
            showEffectiveness = true
        } catch {
            actionError = userFriendlyError(error, context: "save settings")
        }
    }

    private func deactivateQuestion(_ question: EstimationQuestion) async {
        guard let svc = appCore.jobEstimationService,
              let qid = question.id,
              let userId = appCore.currentUser?.id else {
            loadError = "Estimation service not available"
            return
        }
        do {
            try svc.rejectQuestion(questionId: qid, rejectedBy: userId, reason: "Deactivated from settings")
            await loadData()
        } catch {
            actionError = userFriendlyError(error, context: "save settings")
        }
    }

    private func reactivateQuestion(_ question: EstimationQuestion) async {
        guard let svc = appCore.jobEstimationService,
              let qid = question.id else {
            loadError = "Estimation service not available"
            return
        }
        do {
            try svc.updateQuestion(questionId: qid, isActive: true)
            await loadData()
        } catch {
            actionError = userFriendlyError(error, context: "save settings")
        }
    }

    // MARK: - Helpers

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "bid": return "Bid Stage"
        case "pre_start": return "Pre-Start"
        case "during": return "During Job"
        case "before_trim": return "Before Trim"
        case "punch_list": return "Punch List"
        default: return stage.capitalized
        }
    }
}

// MARK: - Add Question Sheet

private struct AddEstimationQuestionSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var questionText = ""
    @State private var group = "scope"
    @State private var stage = "bid"
    @State private var answerType = "number"
    @State private var choicesText = ""
    @State private var weight = 1.0
    @State private var saveError: String?

    private let groups = ["scope", "complexity", "access", "materials", "labor"]
    private let stages = ["bid", "pre_start", "during", "before_trim", "punch_list"]
    private let answerTypes = ["number", "choice", "boolean", "text"]

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }

                Section {
                    TextField("Question text", text: $questionText, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Question")
                }

                Section {
                    Picker("Group", selection: $group) {
                        ForEach(groups, id: \.self) { Text($0.capitalized).tag($0) }
                    }

                    Picker("Stage", selection: $stage) {
                        ForEach(stages, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                    }

                    Picker("Answer Type", selection: $answerType) {
                        ForEach(answerTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                if answerType == "choice" {
                    Section {
                        TextField("Comma-separated choices", text: $choicesText)
                    } header: {
                        Text("Choices")
                    } footer: {
                        Text("Enter options separated by commas, e.g.: \"Low, Medium, High\"")
                            .font(.caption2)
                    }
                }

                Section {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(String(format: "%.1f", weight))
                            .monospacedDigit()
                    }
                    Slider(value: $weight, in: 0.5...5.0, step: 0.5)
                } footer: {
                    Text("Higher weight = more impact on the estimate.")
                        .font(.caption2)
                }
            }
            .navigationTitle("Add Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(questionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        guard let svc = appCore.jobEstimationService else {
            saveError = "Service not available"
            return
        }
        do {
            let choices: [String]? = if answerType == "choice" && !choicesText.isEmpty {
                choicesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                nil
            }

            try svc.createQuestion(
                text: questionText.trimmingCharacters(in: .whitespaces),
                group: group, stage: stage, answerType: answerType,
                choices: choices, weight: weight
            )
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save settings")
        }
    }
}

// MARK: - Edit Question Sheet

private struct EditEstimationQuestionSheet: View {
    let question: EstimationQuestion
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var questionText: String
    @State private var weight: Double
    @State private var saveError: String?

    init(question: EstimationQuestion, onSave: @escaping () async -> Void) {
        self.question = question
        self.onSave = onSave
        _questionText = State(initialValue: question.questionText)
        _weight = State(initialValue: question.weight)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }

                Section {
                    TextField("Question text", text: $questionText, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Question")
                }

                Section {
                    LabeledContent("Group", value: question.questionGroup.capitalized)
                    LabeledContent("Stage", value: question.stage.replacingOccurrences(of: "_", with: " ").capitalized)
                    LabeledContent("Answer Type", value: question.answerType.capitalized)
                }

                Section {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(String(format: "%.1f", weight))
                            .monospacedDigit()
                    }
                    Slider(value: $weight, in: 0.5...5.0, step: 0.5)
                }
            }
            .navigationTitle("Edit Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
        }
    }

    private func save() async {
        guard let svc = appCore.jobEstimationService,
              let qid = question.id else {
            saveError = "Estimation service not available"
            return
        }
        do {
            try svc.updateQuestion(
                questionId: qid,
                text: questionText.trimmingCharacters(in: .whitespaces),
                weight: weight
            )
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save settings")
        }
    }
}
