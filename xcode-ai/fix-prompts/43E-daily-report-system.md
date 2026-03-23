# 43E — System-Generated Daily Report

> **Chain position:** 43A → ... → **43E**
> **Prerequisite:** 43A (notebook structure), 40A (clock + to-do integration)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `DashboardDailyReportPage.swift` and the clock/to-do integration from 40A. Then build a daily report generator that compiles system data and uses AI for multi-step self-verification.

## Context

Daily reports are currently manual. The system already tracks clock events, to-do completions, breaks, parts used (via JPOs), and Q&A — it should compile this data automatically. AI reviews the compiled report for completeness and accuracy (self-verification). Workers add their own notes below the system section. Office users configure report templates.

## Task

### Step 1: Create DailyReportGenerator

Create `core/Sources/WiredPartCore/Services/DailyReportGenerator.swift`:

```swift
import Foundation

struct DailyReportData: Codable, Sendable {
    let date: String
    let userId: Int64
    let userName: String
    let jobId: Int64
    let jobName: String

    // Clock data
    let clockIn: String?
    let clockOut: String?
    let totalHours: Double
    let breaksTaken: [BreakEntry]

    // To-do progress
    let todosCompleted: [TodoSummary]
    let todosInProgress: [TodoSummary]
    let todosStarted: [TodoSummary]

    // Parts & orders
    let jposCreated: [JPOSummary]
    let partsUsed: [PartUsageSummary]

    // Communication
    let qaQuestions: [QASummary]
    let messagesCount: Int

    // User notes (added manually)
    var userNotes: String?

    // AI summary
    var aiSummary: String?
    var aiVerificationNotes: String?
}

struct TodoSummary: Codable, Sendable {
    let name: String
    let workType: String  // "new_work" or "warranty"
    let timeSpent: Double  // hours
}

struct BreakEntry: Codable, Sendable {
    let type: String  // "break", "lunch", "supply_run"
    let startTime: String
    let endTime: String?
    let duration: Double  // minutes
}

struct JPOSummary: Codable, Sendable {
    let jpoNumber: String
    let lineCount: Int
}

struct PartUsageSummary: Codable, Sendable {
    let partName: String
    let qty: Int
}

struct QASummary: Codable, Sendable {
    let question: String
    let status: String
}

actor DailyReportGenerator {
    private let db: AppDatabase
    private let aiService: FoundationModelsService?

    init(db: AppDatabase, aiService: FoundationModelsService?) {
        self.db = db
        self.aiService = aiService
    }

    /// Generate daily report data from system records
    func generateReport(userId: Int64, jobId: Int64, date: Date) async throws -> DailyReportData {
        // 1. Fetch clock entries for user+job+date
        // 2. Fetch to-do changes (completed, started, in-progress)
        // 3. Fetch JPOs created today for this job
        // 4. Fetch parts movements for this job today
        // 5. Fetch Q&A activity
        // 6. Fetch break/lunch records
        // 7. Compile into DailyReportData
        // 8. If AI available, run verification
    }

    /// AI self-verification: check report for completeness
    func verifyReport(_ report: DailyReportData) async throws -> DailyReportData {
        guard let ai = aiService else { return report }

        // Multi-step verification:
        // Step 1: Check hours match clock data
        // Step 2: Check to-do progress is consistent
        // Step 3: Generate 1-2 sentence summary
        // Step 4: Flag any anomalies (e.g., 12+ hour day, no breaks)

        var verified = report
        // AI generates summary and verification notes
        verified.aiSummary = "Completed X to-dos, Y hours on site..."
        verified.aiVerificationNotes = "Hours verified. No anomalies detected."
        return verified
    }
}
```

### Step 2: Update DashboardDailyReportPage.swift

```swift
// Report layout
List {
    // System-generated section
    Section {
        // Hours summary
        HStack {
            Label("Hours", systemImage: "clock")
            Spacer()
            Text(String(format: "%.1fh", report.totalHours))
                .font(.headline)
        }

        // To-do summary
        if !report.todosCompleted.isEmpty {
            ForEach(report.todosCompleted, id: \.name) { todo in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(todo.name)
                    Spacer()
                    if todo.workType == "warranty" {
                        Text("Warranty")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(String(format: "%.1fh", todo.timeSpent))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        // Breaks
        if !report.breaksTaken.isEmpty {
            ForEach(report.breaksTaken, id: \.startTime) { brk in
                HStack {
                    Image(systemName: "cup.and.saucer")
                    Text(brk.type.capitalized)
                    Spacer()
                    Text("\(Int(brk.duration))m")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        // Parts/JPOs
        if !report.jposCreated.isEmpty {
            ForEach(report.jposCreated, id: \.jpoNumber) { jpo in
                HStack {
                    Image(systemName: "doc.plaintext")
                    Text(jpo.jpoNumber)
                    Spacer()
                    Text("\(jpo.lineCount) items")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        // Q&A
        if !report.qaQuestions.isEmpty {
            ForEach(report.qaQuestions, id: \.question) { qa in
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text(qa.question).lineLimit(1)
                    Spacer()
                    Text(qa.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    } header: {
        Text("System-Generated")
    } footer: {
        if let aiNotes = report.aiVerificationNotes {
            Text("AI: \(aiNotes)")
        }
    }

    // AI Summary
    if let summary = report.aiSummary {
        Section {
            Text(summary)
                .font(.callout)
                .italic()
        } header: {
            Text("AI Summary")
        }
    }

    // User notes section
    Section {
        TextEditor(text: $userNotes)
            .frame(minHeight: 100)
    } header: {
        Text("Your Notes")
    } footer: {
        Text("Add anything the system missed")
    }

    // Submit button
    Section {
        Button {
            Task { await submitReport() }
        } label: {
            Label("Submit Daily Report", systemImage: "paperplane.fill")
        }
        .buttonStyle(.borderedProminent)
    }
}
```

### Step 3: Report Template Configuration (Office)

Office users configure what appears in daily reports:

```swift
// Settings: which sections to include
// - Clock events: always on
// - To-do changes: toggle
// - Parts/JPOs: toggle
// - Q&A: toggle
// - Breaks: toggle
// - AI summary: toggle (requires AI availability)
// - Required user notes: toggle
```

### Step 4: Auto-Population Flow

```swift
// On DashboardDailyReportPage appear:
.task {
    guard let service = appCore.jobsService else {
        loadError = "Service unavailable"
        return
    }
    do {
        // Auto-detect: which job was the user on today?
        let todaysClock = try await service.getTodaysClockEntries(userId: currentUserId)
        if let primaryJob = todaysClock.first {
            report = try await reportGenerator.generateReport(
                userId: currentUserId,
                jobId: primaryJob.jobId,
                date: Date()
            )
            // Run AI verification if available
            if appCore.aiService != nil {
                report = try await reportGenerator.verifyReport(report!)
            }
        }
        isLoading = false
    } catch {
        loadError = error.localizedDescription
        isLoading = false
    }
}
```

## Important Notes
- System-generated data is READ-ONLY — users can't edit clock entries or to-do records here
- User notes are the only editable section
- AI verification is optional (requires Foundation Models availability)
- AI summary should be 1-3 sentences max
- Reports are saved to the job's notebook automatically (daily log section)
- If the user worked on multiple jobs today, show a job picker
- Submit saves the report and marks it as submitted (can't be edited after)

## Success Criteria
- [ ] DailyReportGenerator.swift created
- [ ] Auto-populates: clock events, to-do changes, breaks, JPOs, Q&A
- [ ] AI summary + self-verification (when AI available)
- [ ] User notes section below system data
- [ ] Submit button saves report
- [ ] Report template configurable in Office
- [ ] Auto-detects primary job from today's clock data
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 43E Results (YYYY-MM-DD)
- DailyReportGenerator: auto-populates X data types
- AI: summary + verification
- DashboardDailyReportPage rebuilt
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
