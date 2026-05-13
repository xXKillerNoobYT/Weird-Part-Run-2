import SwiftUI
import WiredPartCore

/// Combined page for weekly and end-of-job estimation reviews.
/// Shows original estimate vs actual progress, variance, and lessons learned.
struct IOSEstimationReviewPage: View {
    let jobId: Int64

    @EnvironmentObject private var appCore: AppCore
    @State private var reviews: [EstimationReview] = []
    @State private var latestEstimate: EstimationResult?
    @State private var unresolvedQuestionCount = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?

    private enum ActiveSheet: Identifiable {
        case weekly
        case endOfJob
        case help
        var id: String {
            switch self {
            case .weekly: return "weekly"
            case .endOfJob: return "endOfJob"
            case .help: return "help"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading reviews...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let loadError {
                        Section { ErrorStateView(message: loadError) { Task { await loadData() } } }
                    }
                    if let actionError {
                        Section { Text(actionError).foregroundStyle(.red) }
                    }

                    Section {
                        if let est = latestEstimate {
                            LabeledContent("Estimated Days", value: est.estimatedDays.map { String(format: "%.1f", $0) } ?? "Not available")
                            LabeledContent("Estimated Hours", value: est.estimatedHours.map { String(format: "%.0f", $0) } ?? "Not available")
                            LabeledContent("Confidence", value: est.confidencePercent.map { "\(Int($0))%" } ?? "Not available")
                            LabeledContent("Stage", value: displayText(for: est.stage))
                            LabeledContent("Unresolved Questions", value: "\(unresolvedQuestionCount)")
                            if let createdAt = est.createdAt {
                                LabeledContent("Last Calculated", value: String(createdAt.prefix(10)))
                            }
                        } else {
                            ContentUnavailableView(
                                "No estimate yet",
                                systemImage: "doc.text.magnifyingglass",
                                description: Text("Complete an estimation questionnaire before reviewing accuracy.")
                            )
                        }
                    } header: {
                        Text("Estimate Snapshot")
                    }

                    Section {
                        if reviews.isEmpty {
                            ContentUnavailableView(
                                "No reviews yet",
                                systemImage: "clock.badge.questionmark",
                                description: Text("Add a weekly review to start tracking estimate accuracy.")
                            )
                        } else {
                            reviewHistorySummary
                            ForEach(reviews) { review in
                                reviewRow(review)
                            }
                        }
                    } header: {
                        Text("Review History")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Estimation Reviews")
        .safeAreaInset(edge: .bottom) {
            if !isLoading {
                reviewActionBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .refreshable {
            await loadData()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .weekly:
                WeeklyReviewSheet(jobId: jobId, unresolvedQuestionCount: unresolvedQuestionCount) { await loadData() }
            case .endOfJob:
                EndOfJobReviewSheet(jobId: jobId, unresolvedQuestionCount: unresolvedQuestionCount) { await loadData() }
            case .help:
                PageHelpSheet(
                    title: "Estimation Reviews Help",
                    sections: [
                        ("Purpose", "Track how accurate your estimates were over the life of a job. Reviews capture actual hours and days vs the original estimate so future bids improve."),
                        ("Weekly Review", "Submit a progress check at the end of each week. Structured status, delay factors, crew feedback, and GC coordination stay separate from freeform notes."),
                        ("End-of-Job Review", "Submit final actuals when the job closes. Lessons learned and per-question accuracy feedback improve future estimates."),
                        ("Variance", "The variance percentage shows how far off the estimate was. ±10% is good, ±25% is acceptable, anything beyond that is flagged red for follow-up."),
                    ]
                )
            }
        }
        .task { await loadData() }
    }

    private var reviewActionBar: some View {
        HStack(spacing: 12) {
            Button {
                activeSheet = .weekly
            } label: {
                Label("Add Weekly Review", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                activeSheet = .endOfJob
            } label: {
                Label("Add End-of-Job Review", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Review Row

    private func reviewRow(_ review: EstimationReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.reviewType == "weekly" ? "Weekly" : "End-of-job")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(review.reviewedAt.map { String($0.prefix(10)) } ?? "Date not recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                statusBadge(review.onTrackStatus)
                varianceBadge(review.variancePercent)
                Spacer()
            }

            if let actual = review.actualDays, let estimate = review.estimateAtStart {
                Text(String(format: "Actual %.1f days / Estimate %.1f days", actual, estimate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Variance unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !review.decodedDelayFactors.isEmpty {
                Text(review.decodedDelayFactors.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let count = review.unresolvedQuestionCount {
                Text("Unresolved questions: \(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let rating = review.gcRating {
                Text("GC coordination: \(rating)/5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let feedback = review.crewFeedback, !feedback.isEmpty {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let notes = review.lessonsLearned, !notes.isEmpty {
                Text(review.reviewType == "weekly" ? "Notes: \(notes)" : "Lessons learned: \(notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var reviewHistorySummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(reviewHistoryHighlights, id: \.self) { highlight in
                Text(highlight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var reviewHistoryHighlights: [String] {
        var highlights: [String] = []
        var seen = Set<String>()
        for review in reviews {
            for factor in review.decodedDelayFactors where seen.insert(factor).inserted {
                highlights.append(factor)
            }
            if let feedback = review.crewFeedback, !feedback.isEmpty {
                if seen.insert(feedback).inserted {
                    highlights.append(feedback)
                }
            }
            if let notes = review.lessonsLearned, !notes.isEmpty {
                let summary = review.reviewType == "weekly" ? "Notes: \(notes)" : "Lessons learned: \(notes)"
                if seen.insert(summary).inserted {
                    highlights.append(summary)
                }
            }
        }
        return highlights
    }

    @ViewBuilder
    private func statusBadge(_ status: String?) -> some View {
        Text(statusLabel(status))
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    @ViewBuilder
    private func varianceBadge(_ variance: Double?) -> some View {
        if let variance {
            Text(String(format: "%+.0f%%", variance))
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(varianceColor(variance).opacity(0.15), in: Capsule())
                .foregroundStyle(varianceColor(variance))
        } else {
            Text("Variance unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusLabel(_ status: String?) -> String {
        switch status {
        case "on_track": return "On track"
        case "at_risk": return "At risk"
        case "off_track": return "Off track"
        default: return "Status not recorded"
        }
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "on_track": return .green
        case "at_risk": return .orange
        case "off_track": return .red
        default: return .secondary
        }
    }

    private func varianceColor(_ variance: Double) -> Color {
        if abs(variance) <= 10 { return .green }
        if abs(variance) <= 25 { return .orange }
        return .red
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = reviews.isEmpty
        loadError = nil
        guard let svc = appCore.jobEstimationService else {
            isLoading = false
            loadError = "Estimation service not available"
            return
        }
        do {
            reviews = try svc.getJobReviews(jobId: jobId)
            latestEstimate = try svc.getLatestResult(jobId: jobId, stage: "bid")
                ?? svc.getLatestResult(jobId: jobId, stage: "pre_start")
                ?? svc.getLatestResult(jobId: jobId, stage: "during")
            unresolvedQuestionCount = try svc.getResponsesForJob(jobId: jobId).filter { $0.isUnknown == 1 }.count
        } catch {
            loadError = userFriendlyError(error, context: "load estimation review")
        }
        isLoading = false
    }

    private func displayText(for value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Weekly Review Sheet

private struct WeeklyReviewSheet: View {
    let jobId: Int64
    let unresolvedQuestionCount: Int
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var workDays = 5
    @State private var onTrackStatus = "on_track"
    @State private var selectedDelayFactors: Set<String> = []
    @State private var crewFeedback = ""
    @State private var gcRating = 0
    @State private var notes = ""
    @State private var saveError: String?
    @State private var isSaving = false

    private let delayFactors = ReviewFormOptions.delayFactors

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }

                Section("Week") {
                    LabeledContent("Week", value: weekRangeFormatted)
                    Stepper(value: $workDays, in: 1...7) {
                        LabeledContent("Work Days", value: "\(workDays)")
                    }
                    LabeledContent("Unresolved estimate questions", value: "\(unresolvedQuestionCount)")
                    if unresolvedQuestionCount > 0 {
                        Text("Review unknown answers from the estimation questionnaire before submitting final accuracy feedback.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $onTrackStatus) {
                        Text("On track").tag("on_track")
                        Text("At risk").tag("at_risk")
                        Text("Off track").tag("off_track")
                    }
                    .pickerStyle(.segmented)

                    if onTrackStatus == "on_track" {
                        Text("No delay factors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(delayFactors, id: \.self) { factor in
                            Button { toggleFactor(factor) } label: {
                                Label(
                                    factor,
                                    systemImage: selectedDelayFactors.contains(factor) ? "checkmark.circle.fill" : "circle"
                                )
                            }
                            .foregroundStyle(.primary)
                            .accessibilityValue(selectedDelayFactors.contains(factor) ? "Selected" : "Not selected")
                        }
                    }
                }

                Section("Crew and GC") {
                    TextField("What did the crew learn this week?", text: $crewFeedback, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("GC coordination", selection: $gcRating) {
                        Text("Not rated").tag(0)
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value) \(ReviewFormOptions.gcRatingLabel(value))").tag(value)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Observations that do not fit the structured fields", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        guard let svc = appCore.jobEstimationService,
              let userId = appCore.currentUser?.id else {
            saveError = "Estimation service is unavailable. Try again after sync finishes."
            return
        }
        isSaving = true
        saveError = nil
        do {
            try svc.submitWeeklyReview(
                jobId: jobId,
                reviewedBy: userId,
                notes: trimmed(notes),
                delayFactors: onTrackStatus == "on_track" ? [] : selectedDelayFactors.sorted(),
                onTrackStatus: onTrackStatus,
                unresolvedQuestionCount: unresolvedQuestionCount,
                crewFeedback: trimmed(crewFeedback),
                gcRating: gcRating == 0 ? nil : gcRating
            )
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save settings")
        }
        isSaving = false
    }

    private var weekRangeFormatted: String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        return "\(Formatters.monthDayFormatter.string(from: monday)) - \(Formatters.monthDayYearFormatter.string(from: sunday))"
    }

    private func toggleFactor(_ factor: String) {
        if selectedDelayFactors.contains(factor) {
            selectedDelayFactors.remove(factor)
        } else {
            selectedDelayFactors.insert(factor)
        }
    }
}

// MARK: - End-of-Job Review Sheet

private struct EndOfJobReviewSheet: View {
    let jobId: Int64
    let unresolvedQuestionCount: Int
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var actualDays = ""
    @State private var actualHours = ""
    @State private var onTrackStatus = "on_track"
    @State private var selectedDelayFactors: Set<String> = []
    @State private var crewFeedback = ""
    @State private var gcRating = 0
    @State private var lessonsLearned = ""
    @State private var questionRows: [QuestionAccuracyRow] = []
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isLoadingQuestions = true

    private let delayFactors = ReviewFormOptions.delayFactors

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }

                Section {
                    HStack {
                        Text("Actual Days")
                        Spacer()
                        TextField("Days", text: $actualDays)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Actual Hours")
                        Spacer()
                        TextField("Hours", text: $actualHours)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } header: {
                    Text("Final Actuals")
                }

                Section("Final Status") {
                    Picker("Final Status", selection: $onTrackStatus) {
                        Text("On track").tag("on_track")
                        Text("At risk").tag("at_risk")
                        Text("Off track").tag("off_track")
                    }
                    .pickerStyle(.segmented)

                    if onTrackStatus == "on_track" {
                        Text("No delay factors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(delayFactors, id: \.self) { factor in
                            Button { toggleFactor(factor) } label: {
                                Label(
                                    factor,
                                    systemImage: selectedDelayFactors.contains(factor) ? "checkmark.circle.fill" : "circle"
                                )
                            }
                            .foregroundStyle(.primary)
                            .accessibilityValue(selectedDelayFactors.contains(factor) ? "Selected" : "Not selected")
                        }
                    }
                }

                Section("Crew and GC") {
                    LabeledContent("Unresolved estimate questions", value: "\(unresolvedQuestionCount)")
                    TextField("What should the crew know for similar jobs?", text: $crewFeedback, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("GC coordination", selection: $gcRating) {
                        Text("Not rated").tag(0)
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value) \(ReviewFormOptions.gcRatingLabel(value))").tag(value)
                        }
                    }
                }

                Section("Lessons learned") {
                    TextField("What would you do differently?", text: $lessonsLearned, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Question accuracy") {
                    if isLoadingQuestions {
                        ProgressView("Loading question accuracy...")
                    } else if questionRows.isEmpty {
                        Text("No answered estimation questions found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($questionRows) { $row in
                            DisclosureGroup {
                                Picker("Accuracy", selection: $row.accuracyRating) {
                                    Text("Accurate").tag(5)
                                    Text("Somewhat").tag(3)
                                    Text("Missed").tag(1)
                                }
                                .pickerStyle(.segmented)
                                TextField("Predicted impact", text: $row.predictedImpact, axis: .vertical)
                                    .lineLimit(2...4)
                                TextField("Actual impact", text: $row.actualImpact, axis: .vertical)
                                    .lineLimit(2...4)
                                TextField("Notes", text: $row.notes, axis: .vertical)
                                    .lineLimit(2...4)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.questionText)
                                        .font(.subheadline)
                                    Text(row.answerSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("End-of-Job Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await save() } }
                        .disabled(isSaving || actualDays.isEmpty || actualHours.isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadQuestions() }
        }
    }

    private func save() async {
        guard let svc = appCore.jobEstimationService,
              let userId = appCore.currentUser?.id,
              let days = Double(actualDays),
              let hours = Double(actualHours) else {
            saveError = "Please enter valid numbers for days and hours"
            return
        }
        isSaving = true
        saveError = nil
        do {
            try svc.submitEndOfJobReview(
                jobId: jobId,
                actualDays: days,
                actualHours: hours,
                lessonsLearned: trimmed(lessonsLearned),
                reviewedBy: userId,
                delayFactors: onTrackStatus == "on_track" ? [] : selectedDelayFactors.sorted(),
                onTrackStatus: onTrackStatus,
                unresolvedQuestionCount: unresolvedQuestionCount,
                crewFeedback: trimmed(crewFeedback),
                gcRating: gcRating == 0 ? nil : gcRating,
                questionAccuracy: questionRows.map(\.input)
            )
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save settings")
        }
        isSaving = false
    }

    private func loadQuestions() {
        guard let svc = appCore.jobEstimationService else {
            isLoadingQuestions = false
            return
        }
        do {
            let responses = try svc.getResponsesForJob(jobId: jobId)
            var questionMap: [Int64: EstimationQuestion] = [:]
            for question in try svc.getAllQuestions() {
                if let id = question.id {
                    questionMap[id] = question
                }
            }
            questionRows = responses.compactMap { response in
                guard let question = questionMap[response.questionId] else { return nil }
                return QuestionAccuracyRow(response: response, question: question)
            }
        } catch {
            saveError = userFriendlyError(error, context: "load question accuracy")
        }
        isLoadingQuestions = false
    }

    private func toggleFactor(_ factor: String) {
        if selectedDelayFactors.contains(factor) {
            selectedDelayFactors.remove(factor)
        } else {
            selectedDelayFactors.insert(factor)
        }
    }
}

private enum ReviewFormOptions {
    static let delayFactors = [
        "Weather", "Materials", "Subcontractor", "Design changes",
        "Inspection", "Equipment", "Permits", "Labor",
        "Customer changes", "GC decision", "Other",
    ]

    static func gcRatingLabel(_ rating: Int) -> String {
        switch rating {
        case 1: "Poor"
        case 2: "Fair"
        case 3: "Good"
        case 4: "Very good"
        case 5: "Excellent"
        default: "Not rated"
        }
    }
}

private struct QuestionAccuracyRow: Identifiable {
    let id: Int64
    let questionId: Int64
    let questionText: String
    let answerSummary: String
    var accuracyRating = 5
    var predictedImpact = ""
    var actualImpact = ""
    var notes = ""

    init(response: EstimationResponse, question: EstimationQuestion) {
        id = response.id ?? response.questionId
        questionId = response.questionId
        questionText = question.questionText
        answerSummary = response.isUnknown == 1 ? "Unknown answer" : "Answer: \(response.responseValue ?? "Not recorded")"
    }

    var input: QuestionAccuracyFeedbackInput {
        QuestionAccuracyFeedbackInput(
            questionId: questionId,
            predictedImpact: trimmed(predictedImpact),
            actualImpact: trimmed(actualImpact),
            accuracyRating: accuracyRating,
            notes: trimmed(notes)
        )
    }
}

private func trimmed(_ value: String) -> String? {
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
}
