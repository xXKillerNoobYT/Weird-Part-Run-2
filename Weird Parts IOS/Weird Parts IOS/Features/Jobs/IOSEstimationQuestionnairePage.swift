import SwiftUI
import WiredPartCore

/// Questionnaire view for a job at a specific estimation stage.
/// Shows grouped questions with "?" unknown option, calculates estimate with confidence.
struct IOSEstimationQuestionnairePage: View {
    let jobId: Int64
    let stage: String

    @EnvironmentObject private var appCore: AppCore
    @State private var questions: [EstimationQuestion] = []
    @State private var responseValues: [Int64: String] = [:]
    @State private var unknowns: Set<Int64> = []
    @State private var estimateResult: EstimationResult?
    @State private var historicalAvg: HistoricalAverage?
    @State private var suggestions: [String] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var isSaving = false

    private var groupedQuestions: [String: [EstimationQuestion]] {
        Dictionary(grouping: questions, by: { $0.questionGroup })
    }

    private let groupOrder = ["scope", "complexity", "access", "materials", "labor"]

    var body: some View {
        List {
            if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            }

            if let actionError {
                Section { Text(actionError).foregroundStyle(.red) }
            }

            // Questions grouped by category
            ForEach(groupOrder, id: \.self) { group in
                if let groupQuestions = groupedQuestions[group], !groupQuestions.isEmpty {
                    Section {
                        ForEach(groupQuestions) { question in
                            questionRow(question)
                        }
                    } header: {
                        Text(group.capitalized)
                    }
                }
            }

            // Estimate result section
            Section {
                Button {
                    Task { await calculateEstimate() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        }
                        Text("Calculate Estimate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)

                if let result = estimateResult {
                    LabeledContent("Estimated Days", value: String(format: "%.1f", result.estimatedDays ?? 0))
                    LabeledContent("Estimated Hours", value: String(format: "%.0f", result.estimatedHours ?? 0))

                    HStack {
                        Text("Confidence")
                        Spacer()
                        let pct = Int(result.confidencePercent ?? 0)
                        Text("\(pct)%")
                            .foregroundStyle(pct >= 80 ? .green : pct >= 50 ? .orange : .red)
                            .fontWeight(.semibold)
                    }

                    if let historical = historicalAvg {
                        LabeledContent("Similar Jobs (\(historical.jobCount))",
                                       value: String(format: "%.1f days avg", historical.avgDays))
                        LabeledContent("Range",
                                       value: "\(String(format: "%.0f", historical.minDays))–\(String(format: "%.0f", historical.maxDays)) days")
                    }
                }
            } header: {
                Text("Estimate")
            }

            // AI suggestions
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.self) { suggestion in
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                                .font(.caption)
                            Text(suggestion)
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("AI Insights")
                }
            }
        }
        .navigationTitle("Estimation — \(stageLabel)")
        .task { await loadData() }
    }

    // MARK: - Question Row

    @ViewBuilder
    private func questionRow(_ question: EstimationQuestion) -> some View {
        let qid = question.id ?? 0
        let isUnknown = unknowns.contains(qid)

        VStack(alignment: .leading, spacing: 6) {
            Text(question.questionText)
                .font(.subheadline)
                .foregroundStyle(isUnknown ? .secondary : .primary)

            HStack {
                if isUnknown {
                    Text("Unknown")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    answerInput(question)
                }

                Spacer()

                // "?" button for unknowns
                Button {
                    if isUnknown {
                        unknowns.remove(qid)
                    } else {
                        unknowns.insert(qid)
                        responseValues.removeValue(forKey: qid)
                    }
                } label: {
                    Text("?")
                        .font(.headline)
                        .foregroundStyle(isUnknown ? .white : .orange)
                        .frame(width: 32, height: 32)
                        .background(isUnknown ? Color.orange : Color.orange.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func answerInput(_ question: EstimationQuestion) -> some View {
        let qid = question.id ?? 0
        let binding = Binding<String>(
            get: { responseValues[qid] ?? "" },
            set: { responseValues[qid] = $0 }
        )

        switch question.answerType {
        case "number":
            TextField("Value", text: binding)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)

        case "boolean":
            Picker("", selection: binding) {
                Text("—").tag("")
                Text("Yes").tag("yes")
                Text("No").tag("no")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

        case "choice":
            if let choices = question.decodedChoices {
                Picker("", selection: binding) {
                    Text("Select...").tag("")
                    ForEach(choices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .tint(.primary)
            }

        default:
            TextField("Response", text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let svc = appCore.jobEstimationService else {
            loadError = "Estimation service not available"
            return
        }

        do {
            questions = try svc.getQuestionsForStage(stage: stage)

            // Load existing responses
            let existing = try svc.getResponsesForJob(jobId: jobId, stage: stage)
            for response in existing {
                if response.isUnknown == 1 {
                    unknowns.insert(response.questionId)
                } else if let val = response.responseValue {
                    responseValues[response.questionId] = val
                }
            }

            // Load latest result if any
            estimateResult = try svc.getLatestResult(jobId: jobId, stage: stage)

            // Load historical averages
            historicalAvg = try svc.getHistoricalAverage()

            // Load AI suggestions
            suggestions = try svc.getJobSpecificSuggestions(jobId: jobId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Calculate Estimate

    private func calculateEstimate() async {
        guard let svc = appCore.jobEstimationService,
              let userId = appCore.currentUser?.id else {
            actionError = "Service or user not available"
            return
        }

        isSaving = true
        actionError = nil

        do {
            // Save all responses first
            for question in questions {
                guard let qid = question.id else { continue }

                if unknowns.contains(qid) {
                    try svc.submitResponse(jobId: jobId, questionId: qid, stage: stage,
                                           value: nil, isUnknown: true, answeredBy: userId)
                } else if let value = responseValues[qid], !value.isEmpty {
                    try svc.submitResponse(jobId: jobId, questionId: qid, stage: stage,
                                           value: value, isUnknown: false, answeredBy: userId)
                }
            }

            // Calculate the estimate
            estimateResult = try svc.calculateEstimate(jobId: jobId, stage: stage)

            // Refresh historical averages
            historicalAvg = try svc.getHistoricalAverage()
        } catch {
            actionError = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Helpers

    private var stageLabel: String {
        switch stage {
        case "bid": return "Bid"
        case "pre_start": return "Pre-Start"
        case "during": return "During"
        case "before_trim": return "Before Trim"
        case "punch_list": return "Punch List"
        default: return stage.capitalized
        }
    }
}
