# 46C — Short-Term Pipeline Page

> **Chain position:** **46C** → 46D
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `SchedulingService.swift` and the scheduling router. Create a new IOSShortTermPipelinePage for managing near-term job pipeline with callback tracking and AI crew suggestions.

## Context

The short-term pipeline shows jobs that are ready or almost ready to schedule. Dispatchers need to see: jobs ready to start anytime (target: keep 3+ in queue), jobs needing scheduling (target: keep 2+ scheduled), favorite GC jobs (target: keep 1+ ready), and small jobs that can fill gaps. Callback tracking with snooze helps manage follow-ups. AI suggests crew assignments when teams finish early.

## Task

### Step 1: Create IOSShortTermPipelinePage.swift

Create `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSShortTermPipelinePage.swift`:

```swift
import SwiftUI

struct IOSShortTermPipelinePage: View {
    @EnvironmentObject var appCore: AppCore
    @State private var pipelineItems: [PipelineItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case scheduleJob(PipelineItem)
        case callback(PipelineItem)
        case aiSuggestion

        var id: String {
            switch self {
            case .scheduleJob(let item): return "schedule-\(item.id)"
            case .callback(let item): return "callback-\(item.id)"
            case .aiSuggestion: return "ai"
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pipeline...")
            } else if let error = loadError {
                ErrorStateView(message: error, retryAction: { Task { await loadData() } })
            } else {
                pipelineContent
            }
        }
        .navigationTitle("Short-Term Pipeline")
        .task { await loadData() }
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .aiSuggestion } label: {
                    Label("AI Suggest", systemImage: "sparkles")
                }
            }
        }
    }

    var pipelineContent: some View {
        List {
            // Smart cards with targets
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        TargetCard(title: "Start Anytime", count: startAnytimeCount,
                                   target: 3, color: .green)
                        TargetCard(title: "Schedule Needed", count: scheduleNeededCount,
                                   target: 2, color: .blue)
                        TargetCard(title: "Favorite GC", count: favoriteGCCount,
                                   target: 1, color: .purple)
                        SmartCard(title: "Small Jobs", count: smallJobsCount, color: .orange)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Start Anytime (ready to go)
            pipelineSection(title: "Start Anytime", target: 3,
                          items: startAnytimeItems, icon: "bolt.fill", color: .green)

            // Schedule Needed
            pipelineSection(title: "Schedule Needed", target: 2,
                          items: scheduleNeededItems, icon: "calendar.badge.exclamationmark", color: .blue)

            // Favorite GC
            pipelineSection(title: "Favorite GC", target: 1,
                          items: favoriteGCItems, icon: "star.fill", color: .purple)

            // Small Jobs (gap fillers)
            pipelineSection(title: "Small Jobs", target: nil,
                          items: smallJobItems, icon: "rectangle.compress.vertical", color: .orange)

            // Callbacks Due
            if !callbacksDue.isEmpty {
                Section {
                    ForEach(callbacksDue) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.jobName).font(.headline)
                                Text(item.customerName).font(.caption).foregroundStyle(.secondary)
                                Text("Callback: \(item.callbackDate!, style: .relative)")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Spacer()
                            Button { activeSheet = .callback(item) } label: {
                                Image(systemName: "phone.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Callbacks Due (\(callbacksDue.count))")
                }
            }
        }
    }

    func pipelineSection(title: String, target: Int?, items: [PipelineItem],
                         icon: String, color: Color) -> some View {
        Section {
            if items.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Below target — need more jobs here")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            ForEach(items) { item in
                PipelineRow(item: item) {
                    activeSheet = .scheduleJob(item)
                }
            }
        } header: {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title)
                Spacer()
                if let target = target {
                    Text("\(items.count)/\(target) target")
                        .font(.caption)
                        .foregroundStyle(items.count >= target ? .green : .red)
                }
            }
        }
    }
}
```

### Step 2: Models and Service Methods

```swift
struct PipelineItem: Identifiable, Sendable {
    let id: Int64
    let jobId: Int64
    let jobName: String
    let customerName: String
    let estimatedDays: Int?
    let pipelineCategory: String  // "start_anytime", "schedule_needed", "favorite_gc", "small_job"
    let callbackDate: Date?
    let callbackSnoozedUntil: Date?
    let gcIsFavorite: Bool
    let notes: String?
}

// In SchedulingService:
func getShortTermPipeline() async throws -> [PipelineItem]
func snoozeCallback(jobId: Int64, until: Date) async throws
func markCallbackComplete(jobId: Int64, notes: String?) async throws
func getAICrewSuggestion(jobId: Int64) async throws -> [CrewSuggestion]

struct CrewSuggestion: Identifiable, Sendable {
    let id = UUID()
    let teamName: String?
    let workers: [EmployeeSummary]
    let reason: String
    let availableDate: Date
}
```

### Step 3: Callback Tracking with Snooze

```swift
// Callback sheet
struct CallbackSheet: View {
    let item: PipelineItem
    let onComplete: (String?) -> Void
    let onSnooze: (Date) -> Void
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Callback for \(item.jobName)") {
                    Text(item.customerName)
                    if let date = item.callbackDate {
                        LabeledContent("Scheduled", value: date, format: .dateTime)
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
                Section {
                    Button("Mark Complete") {
                        onComplete(notes.isEmpty ? nil : notes)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Snooze 1 Day") { onSnooze(Date().addingTimeInterval(86400)) }
                    Button("Snooze 3 Days") { onSnooze(Date().addingTimeInterval(86400 * 3)) }
                    Button("Snooze 1 Week") { onSnooze(Date().addingTimeInterval(86400 * 7)) }
                }
            }
            .navigationTitle("Callback")
        }
    }
}
```

### Step 4: Target Card Component

```swift
struct TargetCard: View {
    let title: String
    let count: Int
    let target: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count)").font(.title2).bold()
                Text("/\(target)").font(.caption).foregroundStyle(.secondary)
            }
            // Status indicator
            if count >= target {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
        }
        .padding(10)
        .frame(minWidth: 100)
        .background(color.opacity(count >= target ? 0.1 : 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

### Step 5: Update SchedulingRouter

Add pipeline to the scheduling module navigation:

```swift
// In SchedulingRouter or NavigationConfig, add tab for "Pipeline"
```

## Important Notes
- Target counts (3, 2, 1) are guideline targets, not hard rules
- Below-target sections show orange warning
- Callback snooze pushes the date forward, doesn't remove it
- AI crew suggestions consider: skills, availability, travel distance, team history
- "Small Jobs" are jobs estimated at 1-2 days (gap fillers)
- "Favorite GC" jobs come from GCs marked as favorites in the customer record
- The pipeline auto-updates — jobs move categories as they're scheduled

## Success Criteria
- [ ] IOSShortTermPipelinePage.swift created
- [ ] Smart cards with target indicators (Start Anytime, Schedule Needed, Favorite GC, Small Jobs)
- [ ] Pipeline sections with items and below-target warnings
- [ ] Callback tracking with snooze (1 day, 3 days, 1 week)
- [ ] AI crew suggestion (toolbar button)
- [ ] Schedule job action from pipeline
- [ ] Added to scheduling router
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 46C Results (YYYY-MM-DD)
- IOSShortTermPipelinePage created
- TargetCard component
- Callback tracking with snooze
- Added to router
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 46D.**
