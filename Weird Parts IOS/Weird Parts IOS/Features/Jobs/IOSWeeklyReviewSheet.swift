import SwiftUI
import WiredPartCore

/// Weekly work review sheet for a job.
///
/// Gathers a summary of the week's work: labor hours, todo progress,
/// delay factors, on-track status, and notes. Submits a weekly review
/// record via `JobEstimationService.submitWeeklyReview(...)`.
struct IOSWeeklyReviewSheet: View {
    @EnvironmentObject private var appCore: AppCore
    let jobId: Int64
    let jobName: String

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var workDays: Int = 5
    @State private var weekHours: Double = 0
    @State private var todosCompleted: Int = 0
    @State private var todosTotal: Int = 0
    @State private var isOnTrack = true
    @State private var notes = ""
    @State private var selectedDelayFactors: Set<String> = []
    @State private var isSubmitting = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var submitError: String?
    @State private var showingSuccess = false

    private let delayFactors = [
        "Weather", "Material delays", "Subcontractor no-show",
        "Design changes", "Inspection failed", "Equipment breakdown",
        "Permit issues", "Labor shortage", "Customer changes", "Other"
    ]

    // MARK: - Computed

    /// Monday-Sunday date range for the current week.
    private var weekRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        let daysFromMonday = (weekday + 5) % 7 // Monday = 0
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        return (monday, sunday)
    }

    private var weekRangeFormatted: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let (start, end) = weekRange
        let endFmt = DateFormatter()
        endFmt.dateFormat = "MMM d, yyyy"
        return "\(fmt.string(from: start)) \u{2013} \(endFmt.string(from: end))"
    }

    private var todoProgress: Double {
        guard todosTotal > 0 else { return 0 }
        return Double(todosCompleted) / Double(todosTotal)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading week data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    formContent
                }
            }
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitReview() }
                        .fontWeight(.semibold)
                        .disabled(isSubmitting || isLoading || loadError != nil)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .task { loadWeekData() }
            .alert("Review Submitted", isPresented: $showingSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your weekly review for \(jobName) has been saved.")
            }
        }
    }

    // MARK: - Form

    @ViewBuilder
    private var formContent: some View {
        Form {
            // Week summary header
            Section("Week Summary") {
                HStack {
                    Label("Week", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    Text(weekRangeFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                HStack {
                    Label("Job", systemImage: "hammer")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    Text(jobName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Stepper(value: $workDays, in: 1...7) {
                    HStack {
                        Label("Work Days", systemImage: "clock.badge.checkmark")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        Spacer()
                        Text("\(workDays)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                }

                HStack {
                    Label("Hours Logged", systemImage: "clock")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f hrs", weekHours))
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                }
            }

            // Progress
            Section("Todo Progress") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(todosCompleted) of \(todosTotal) completed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(todosTotal > 0 ? "\(Int(todoProgress * 100))%" : "N/A")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(progressColor)
                    }

                    if todosTotal > 0 {
                        ProgressView(value: todoProgress)
                            .tint(progressColor)
                    } else {
                        Text("No todos found for this job.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // On Track
            Section {
                Toggle(isOn: $isOnTrack) {
                    Label(
                        "Job is on track",
                        systemImage: isOnTrack
                            ? "checkmark.seal.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isOnTrack ? .green : .orange)
                    .font(.subheadline)
                }
            }

            // Delay Factors
            Section("Delay Factors") {
                if isOnTrack {
                    Text("No delays \u{2014} looking good!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(delayFactors, id: \.self) { factor in
                        Button {
                            toggleFactor(factor)
                        } label: {
                            HStack {
                                Image(
                                    systemName: selectedDelayFactors.contains(factor)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    selectedDelayFactors.contains(factor) ? .red : .secondary
                                )
                                Text(factor)
                                    .foregroundStyle(.primary)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }

            // Notes
            Section("Notes & Observations") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
                    .font(.subheadline)
            }

            // Errors
            if let error = submitError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Helpers

    private var progressColor: Color {
        if todosTotal == 0 { return .secondary }
        if todoProgress >= 0.75 { return .green }
        if todoProgress >= 0.4 { return .orange }
        return .red
    }

    private func toggleFactor(_ factor: String) {
        if selectedDelayFactors.contains(factor) {
            selectedDelayFactors.remove(factor)
        } else {
            selectedDelayFactors.insert(factor)
        }
    }

    // MARK: - Data Loading

    private func loadWeekData() {
        guard let jobsService = appCore.jobsService else {
            loadError = "Jobs service unavailable"
            isLoading = false
            return
        }

        let (start, end) = weekRange
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: start)
        let endStr = fmt.string(from: end)

        do {
            // Get all labor entries for this job and filter to this week's date range
            let allEntries = try jobsService.listLaborEntries(jobId: jobId, limit: 500)
            weekHours = allEntries
                .filter { entry in
                    // clock_in is ISO datetime; compare the date prefix (yyyy-MM-dd)
                    let datePrefix = String(entry.clockIn.prefix(10))
                    return datePrefix >= startStr && datePrefix <= endStr
                }
                .reduce(0.0) { $0 + $1.regularHours + $1.overtimeHours }

            // Get todo summary (completed and total counts)
            let todoSummary = try jobsService.getJobTodoSummary(jobId: jobId)
            todosCompleted = todoSummary.completedTodos
            todosTotal = todoSummary.totalTodos
        } catch {
            loadError = userFriendlyError(error, context: "load weekly review")
        }
        isLoading = false
    }

    // MARK: - Submit

    private func submitReview() {
        guard let estimationService = appCore.jobEstimationService else {
            submitError = "Estimation service unavailable"
            return
        }

        isSubmitting = true
        submitError = nil

        // Build structured notes payload
        var reviewNotes = ""

        if !isOnTrack {
            let factors = selectedDelayFactors.sorted().joined(separator: ", ")
            reviewNotes += "Status: OFF TRACK\n"
            if !factors.isEmpty {
                reviewNotes += "Delay factors: \(factors)\n"
            }
        } else {
            reviewNotes += "Status: ON TRACK\n"
        }

        reviewNotes += "Work days: \(workDays)\n"
        reviewNotes += "Week hours: \(String(format: "%.1f", weekHours))\n"
        reviewNotes += "Todos: \(todosCompleted)/\(todosTotal)\n"

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            reviewNotes += "\n\(trimmedNotes)"
        }

        let userId = appCore.currentUser?.id ?? 0

        do {
            try estimationService.submitWeeklyReview(
                jobId: jobId,
                reviewedBy: userId,
                notes: reviewNotes
            )
            showingSuccess = true
        } catch {
            submitError = userFriendlyError(error, context: "submit review")
        }

        isSubmitting = false
    }
}
