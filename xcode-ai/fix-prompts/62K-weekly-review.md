# 62K — Create IOSWeeklyReviewSheet
> Chain position: Standalone

## Task

Create a new `IOSWeeklyReviewSheet` that provides a weekly review summary for workers. It shows work-days used, to-dos completed, delay factors, unanswered estimation questions, and a "still on track?" question.

### Step 1: Create the sheet view

Create a new file: `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSWeeklyReviewSheet.swift`

```swift
import SwiftUI
import WiredPartCore

struct IOSWeeklyReviewSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let jobId: Int64

    // Data
    @State private var weekSummary: WeekSummary?
    @State private var isLoading = true

    // User inputs
    @State private var delayFactors: Set<String> = []
    @State private var onTrack: Bool? = nil
    @State private var notes = ""
    @State private var isSaving = false
    @State private var saveError: String?

    struct WeekSummary {
        let jobName: String
        let workDaysThisWeek: Int
        let totalHoursThisWeek: Double
        let todosCompleted: Int
        let todosTotal: Int
        let unansweredQuestions: Int
        let weekStart: String
        let weekEnd: String
    }

    private let possibleDelays = [
        "Waiting on parts",
        "Waiting on customer decision",
        "Weather",
        "Manpower shortage",
        "Change order",
        "Inspection delay",
        "Subcontractor delay",
        "Equipment issue",
        "Material defect/return",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("Loading week summary...")
                } else if let summary = weekSummary {
                    // Week overview section
                    Section("This Week: \(summary.weekStart) — \(summary.weekEnd)") {
                        LabeledContent("Job", value: summary.jobName)
                        LabeledContent("Work Days", value: "\(summary.workDaysThisWeek)")
                        LabeledContent("Total Hours", value: String(format: "%.1f", summary.totalHoursThisWeek))
                    }

                    // To-dos section
                    Section("To-Dos") {
                        LabeledContent("Completed", value: "\(summary.todosCompleted) / \(summary.todosTotal)")

                        if summary.todosTotal > 0 {
                            ProgressView(value: Double(summary.todosCompleted),
                                        total: Double(summary.todosTotal))
                                .tint(summary.todosCompleted == summary.todosTotal ? .green : .orange)
                        }
                    }

                    // Unanswered questions
                    if summary.unansweredQuestions > 0 {
                        Section {
                            Label("\(summary.unansweredQuestions) estimation question\(summary.unansweredQuestions == 1 ? "" : "s") unanswered",
                                  systemImage: "questionmark.circle.fill")
                                .foregroundStyle(.orange)
                        } header: {
                            Text("Attention Needed")
                        }
                    }

                    // Delay factors checklist
                    Section("Any Delays This Week?") {
                        ForEach(possibleDelays, id: \.self) { factor in
                            Button {
                                if delayFactors.contains(factor) {
                                    delayFactors.remove(factor)
                                } else {
                                    delayFactors.insert(factor)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: delayFactors.contains(factor)
                                          ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(delayFactors.contains(factor) ? .blue : .secondary)
                                    Text(factor)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }

                    // On track question
                    Section("Still On Track?") {
                        HStack(spacing: 16) {
                            Button {
                                onTrack = true
                            } label: {
                                Label("Yes", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(onTrack == true ? .green : .gray.opacity(0.3))

                            Button {
                                onTrack = false
                            } label: {
                                Label("No", systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(onTrack == false ? .red : .gray.opacity(0.3))
                        }
                    }

                    // Notes
                    Section("Notes (optional)") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }

                    // Save error
                    if let error = saveError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submitReview() }
                    }
                    .disabled(onTrack == nil || isSaving)
                }
            }
            .task {
                await loadWeekSummary()
            }
        }
    }

    private func loadWeekSummary() async {
        guard let jobsService = appCore.jobsService else { return }
        isLoading = true

        // Calculate current week boundaries (Monday-Sunday)
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7  // Monday = 0
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startStr = dateFormatter.string(from: monday)
        let endStr = dateFormatter.string(from: sunday)

        dateFormatter.dateFormat = "MMM d"
        let displayStart = dateFormatter.string(from: monday)
        let displayEnd = dateFormatter.string(from: sunday)

        // Get job name
        let jobName = (try? jobsService.getJobDetail(jobId: jobId))?.jobName ?? "Job #\(jobId)"

        // Count work days (labor entries this week)
        // Count to-dos
        // Count unanswered questions
        // These would come from service calls — use placeholder values if service methods don't exist yet

        weekSummary = WeekSummary(
            jobName: jobName,
            workDaysThisWeek: 0,  // TODO: count from labor_entries
            totalHoursThisWeek: 0,  // TODO: sum from labor_entries
            todosCompleted: 0,  // TODO: count from notebook_blocks
            todosTotal: 0,  // TODO: count from notebook_blocks
            unansweredQuestions: 0,  // TODO: count from estimation_responses
            weekStart: displayStart,
            weekEnd: displayEnd
        )

        isLoading = false
    }

    private func submitReview() async {
        isSaving = true
        saveError = nil

        // Save the review as a daily report note or notebook entry
        // For now, create a notebook block with the review data
        guard let service = appCore.notebooksService else {
            saveError = "Service unavailable"
            isSaving = false
            return
        }

        let reviewContent = """
        ## Weekly Review — \(weekSummary?.weekStart ?? "") to \(weekSummary?.weekEnd ?? "")
        **On Track:** \(onTrack == true ? "Yes" : "No")
        **Delay Factors:** \(delayFactors.isEmpty ? "None" : delayFactors.joined(separator: ", "))
        **Notes:** \(notes.isEmpty ? "None" : notes)
        """

        // Save as a report annotation or similar — adapt to actual available service methods
        _ = reviewContent
        _ = service

        isSaving = false
        dismiss()
    }
}
```

### Step 2: Add trigger from IOSJobDetailPage

In `IOSJobDetailPage.swift`, add a button to open the weekly review:

```swift
@State private var showWeeklyReview = false

// In the toolbar or action menu:
Button {
    showWeeklyReview = true
} label: {
    Label("Weekly Review", systemImage: "calendar.badge.checkmark")
}

// Sheet:
.sheet(isPresented: $showWeeklyReview) {
    IOSWeeklyReviewSheet(jobId: jobId)
}
```

## Files to Modify

- **Create:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSWeeklyReviewSheet.swift`
- **Modify:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailPage.swift` — add button to open the sheet

## Success Criteria
- [ ] New IOSWeeklyReviewSheet shows week summary with work days, hours, to-dos
- [ ] Delay factor checklist with 10 common delay reasons
- [ ] "Still on track?" Yes/No toggle (required before submit)
- [ ] Optional notes field
- [ ] Sheet accessible from Job Detail page via toolbar button
- [ ] Submit saves the review data
- [ ] No compile errors
