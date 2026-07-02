import SwiftUI
import WiredPartCore

/// Combined page for weekly and end-of-job estimation reviews.
/// Shows original estimate vs actual progress, variance, and lessons learned.
struct IOSEstimationReviewPage: View {
    let jobId: Int64

    @EnvironmentObject private var appCore: AppCore
    @State private var reviews: [EstimationReview] = []
    @State private var latestEstimate: EstimationResult?
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

                    // Current estimate summary
                    if let est = latestEstimate {
                        Section {
                            LabeledContent("Estimated Days", value: String(format: "%.1f", est.estimatedDays ?? 0))
                            LabeledContent("Estimated Hours", value: String(format: "%.0f", est.estimatedHours ?? 0))
                            LabeledContent("Confidence", value: "\(Int(est.confidencePercent ?? 0))%")
                            LabeledContent("Stage", value: est.stage.replacingOccurrences(of: "_", with: " ").capitalized)
                        } header: {
                            Text("Current Estimate")
                        }
                    }

                    // Action buttons
                    Section {
                        Button {
                            activeSheet = .weekly
                        } label: {
                            Label("Submit Weekly Review", systemImage: "calendar.badge.clock")
                        }

                        Button {
                            activeSheet = .endOfJob
                        } label: {
                            Label("Submit End-of-Job Review", systemImage: "checkmark.seal")
                        }
                    } header: {
                        Text("New Review")
                    }

                    // Past reviews
                    if !reviews.isEmpty {
                        Section {
                            ForEach(reviews) { review in
                                reviewRow(review)
                            }
                        } header: {
                            Text("Review History (\(reviews.count))")
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Estimation Reviews")
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
                WeeklyReviewSheet(jobId: jobId) { await loadData() }
            case .endOfJob:
                EndOfJobReviewSheet(jobId: jobId) { await loadData() }
            case .help:
                PageHelpSheet(
                    title: "Estimation Reviews Help",
                    sections: [
                        ("Purpose", "Track how accurate your estimates were over the life of a job. Reviews capture actual hours and days vs the original estimate so future bids improve."),
                        ("Weekly Review", "Submit a progress check at the end of each week. Notes any surprises, scope changes, or scheduling issues. Actual hours are calculated automatically from clock data."),
                        ("End-of-Job Review", "Submit final actuals when the job closes. Provide actual days and hours worked. Lessons Learned feeds the AI to improve question selection for similar future jobs."),
                        ("Variance", "The variance percentage shows how far off the estimate was. ±10% is good, ±25% is acceptable, anything beyond that is flagged red for follow-up."),
                    ]
                )
            }
        }
        .task { await loadData() }
        .onDisappear {
            NotificationCenter.default.post(name: .estimationReviewPageInactive, object: nil)
        }
    }

    // MARK: - Review Row

    private func reviewRow(_ review: EstimationReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.reviewType == "weekly" ? "Weekly Review" : "End-of-Job Review")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let date = review.reviewedAt {
                    Text(date.prefix(10))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                if let actual = review.actualDays {
                    VStack(alignment: .leading) {
                        Text("Actual")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f days", actual))
                            .font(.caption)
                    }
                }

                if let est = review.estimateAtStart {
                    VStack(alignment: .leading) {
                        Text("Estimate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f days", est))
                            .font(.caption)
                    }
                }

                if let variance = review.variancePercent {
                    VStack(alignment: .leading) {
                        Text("Variance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%+.0f%%", variance))
                            .font(.caption)
                            .foregroundStyle(abs(variance) <= 10 ? .green : abs(variance) <= 25 ? .orange : .red)
                    }
                }
            }

            if let lessons = review.lessonsLearned, !lessons.isEmpty {
                Text(lessons)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
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
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load estimation review")
        }
        isLoading = false
    }

    private func postAIContext() {
        let reviewTypes = Dictionary(grouping: reviews, by: \.reviewType)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let averageVariance = reviews.compactMap(\.variancePercent).isEmpty
            ? nil
            : reviews.compactMap(\.variancePercent).reduce(0, +) / Double(reviews.compactMap(\.variancePercent).count)
        let context = """
        Estimation Reviews page. Read-only context.
        Job id: \(jobId), reviews loaded: \(reviews.count), review types: \(reviewTypes.isEmpty ? "none" : reviewTypes).
        Latest estimate stage: \(latestEstimate?.stage ?? "none"), estimated hours: \(String(format: "%.0f", latestEstimate?.estimatedHours ?? 0)), confidence: \(String(format: "%.0f", latestEstimate?.confidencePercent ?? 0))%.
        Average variance across reviews: \(averageVariance.map { String(format: "%+.0f%%", $0) } ?? "not available"), active sheet: \(activeSheet?.id ?? "none").
        Available read-only guidance: explain estimate vs actual review history, variance, weekly/end-of-job review entry points, and visible sections. Do not submit reviews directly.
        """
        NotificationCenter.default.post(
            name: .estimationReviewPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}

// MARK: - Weekly Review Sheet

private struct WeeklyReviewSheet: View {
    let jobId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var notes = ""
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }

                Section {
                    Text("This weekly review captures your current progress against the original estimate. Actual hours are calculated automatically from clock data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Notes or observations", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Is the job on track? Any surprises or changes?")
                        .font(.caption2)
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
            saveError = "Estimation service not available"
            return
        }
        isSaving = true
        do {
            try svc.submitWeeklyReview(
                jobId: jobId,
                reviewedBy: userId,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save settings")
        }
        isSaving = false
    }
}

// MARK: - End-of-Job Review Sheet

private struct EndOfJobReviewSheet: View {
    let jobId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var actualDays = ""
    @State private var actualHours = ""
    @State private var lessonsLearned = ""
    @State private var saveError: String?
    @State private var isSaving = false

    /// Live validation: actuals feed variance % and the AI estimation-learning
    /// pipeline, so zero/negative values must never be submitted.
    private var actualDaysValidationMessage: String? {
        positiveNumberValidationMessage(for: actualDays, label: "Actual Days")
    }

    private var actualHoursValidationMessage: String? {
        positiveNumberValidationMessage(for: actualHours, label: "Actual Hours")
    }

    private func positiveNumberValidationMessage(for value: String, label: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let number = Double(trimmed), number.isFinite else {
            return "\(label) must be a plain number, like 3 or 3.5."
        }
        guard number > 0 else {
            return "\(label) must be greater than zero."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }

                Section {
                    Text("Record the final actuals for this job. This data improves future estimates through AI learning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    if let message = actualDaysValidationMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    HStack {
                        Text("Actual Hours")
                        Spacer()
                        TextField("Hours", text: $actualHours)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    if let message = actualHoursValidationMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } header: {
                    Text("Final Actuals")
                }

                Section {
                    TextField("What would you do differently?", text: $lessonsLearned, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Lessons Learned")
                } footer: {
                    Text("This feeds into AI analysis to improve question selection for future jobs.")
                        .font(.caption2)
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
                        .disabled(
                            isSaving || actualDays.isEmpty || actualHours.isEmpty
                                || actualDaysValidationMessage != nil
                                || actualHoursValidationMessage != nil
                        )
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        guard let svc = appCore.jobEstimationService,
              let userId = appCore.currentUser?.id else {
            saveError = "Estimation service not available"
            return
        }
        // Zero/negative actuals corrupt variance % and AI estimation learning,
        // so require strictly positive values (backstop for the disabled button).
        guard let days = Double(actualDays.trimmingCharacters(in: .whitespacesAndNewlines)),
              days.isFinite, days > 0,
              let hours = Double(actualHours.trimmingCharacters(in: .whitespacesAndNewlines)),
              hours.isFinite, hours > 0 else {
            saveError = "Actual days and hours must be numbers greater than zero"
            return
        }
        isSaving = true
        do {
            try svc.submitEndOfJobReview(
                jobId: jobId,
                actualDays: days,
                actualHours: hours,
                lessonsLearned: lessonsLearned.isEmpty ? nil : lessonsLearned,
                reviewedBy: userId
            )
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save settings")
        }
        isSaving = false
    }
}
