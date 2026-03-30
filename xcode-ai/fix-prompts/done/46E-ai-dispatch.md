# 46E — AI Dispatch Suggestion System

> **Chain position:** 46B → **46E**
> **Prerequisite:** 46B (dispatch board)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSDispatchPage.swift`, `FoundationModelsService.swift`, and `SchedulingService.swift`. Build an AI dispatch suggestion system with points-based reasoning, a dedicated AI chat, and learning from dispatcher picks.

## Context

Dispatching is complex: match workers to jobs based on skills, availability, travel distance, team chemistry, job history, and crew specialties. AI generates 3 options with points-based scoring. A dedicated AI chat (separate from general AI) lets dispatchers ask "what if" questions. The system learns from dispatcher choices to improve future suggestions. Daily rolling suggestions: confirm today, generate tomorrow.

## Task

### Step 1: Create AIDispatchService

Create `core/Sources/WiredPartCore/Services/AIDispatchService.swift`:

```swift
import Foundation

struct DispatchSuggestion: Identifiable, Sendable {
    let id = UUID()
    let rank: Int  // 1, 2, 3
    let assignments: [SuggestedAssignment]
    let totalPoints: Int
    let reasoning: [ScoringFactor]
}

struct SuggestedAssignment: Identifiable, Sendable {
    let id = UUID()
    let employeeId: Int64
    let employeeName: String
    let jobId: Int64
    let jobName: String
    let timeSlot: String  // "full", "am", "pm"
    let matchScore: Int   // points for this specific assignment
}

struct ScoringFactor: Identifiable, Sendable {
    let id = UUID()
    let category: String  // "skills", "availability", "travel", "team", "history", "specialty"
    let description: String
    let points: Int
    let isPositive: Bool
}

actor AIDispatchService {
    private let db: AppDatabase
    private let aiService: FoundationModelsService?
    private let schedulingService: SchedulingService

    init(db: AppDatabase, aiService: FoundationModelsService?, schedulingService: SchedulingService) {
        self.db = db
        self.aiService = aiService
        self.schedulingService = schedulingService
    }

    /// Generate 3 dispatch options for a given date
    func generateSuggestions(date: Date) async throws -> [DispatchSuggestion] {
        // 1. Get available workers for date (not on time-off)
        // 2. Get jobs needing workers (from pipeline + schedule)
        // 3. Calculate points for each worker-job combination
        // 4. Generate 3 different optimal arrangements
        // 5. Return sorted by total points

        // Scoring weights:
        // +10 Skill match (worker has certs/experience for job type)
        // +8  Team continuity (same crew as yesterday)
        // +6  Specialty match (worker's primary specialty)
        // +5  Travel distance (closer = more points)
        // +4  History (has worked this job before)
        // +3  Worker preference (favors this type of work)
        // -5  Overtime risk (would exceed 40hr week)
        // -10 Qualification gap (missing required cert)
    }

    /// Record dispatcher's choice (for learning)
    func recordDispatcherChoice(
        date: Date,
        chosenSuggestion: Int,  // rank 1, 2, or 3
        modifications: [DispatchModification]
    ) async throws {
        // Log which suggestion was chosen
        // Log any modifications made
        // Use for future weight adjustments
    }

    /// Adjust scoring weights based on historical choices
    func recalibrateWeights() async throws {
        // Analyze past choices
        // If dispatchers consistently override skill matches for team continuity,
        // increase team continuity weight
    }

    /// Get AI chat context for dispatch questions
    func getDispatchContext(date: Date) async throws -> String {
        // Return structured context about:
        // - Available workers and their status
        // - Jobs needing workers
        // - Time-off conflicts
        // - Yesterday's assignments
        // - Early finish predictions
    }
}
```

### Step 2: Suggestion Display on Dispatch Page

```swift
// In IOSDispatchPage.swift:
@State private var suggestions: [DispatchSuggestion] = []
@State private var showSuggestions = false
@State private var showAIChat = false

// AI Suggestions section
if !suggestions.isEmpty {
    Section {
        ForEach(suggestions) { suggestion in
            DisclosureGroup {
                // Assignment details
                ForEach(suggestion.assignments) { assignment in
                    HStack {
                        Text(assignment.employeeName).font(.subheadline)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(assignment.jobName).font(.subheadline)
                        Spacer()
                        Text("\(assignment.matchScore) pts")
                            .font(.caption).foregroundStyle(.blue)
                    }
                }

                // Scoring breakdown
                ForEach(suggestion.reasoning) { factor in
                    HStack {
                        Image(systemName: factor.isPositive ? "plus.circle.fill" : "minus.circle.fill")
                            .foregroundStyle(factor.isPositive ? .green : .red)
                            .font(.caption)
                        Text(factor.description)
                            .font(.caption)
                        Spacer()
                        Text("\(factor.isPositive ? "+" : "")\(factor.points)")
                            .font(.caption).monospacedDigit()
                    }
                }

                // Apply button
                Button("Apply This Option") {
                    Task { await applySuggestion(suggestion) }
                }
                .buttonStyle(.borderedProminent)
            } label: {
                HStack {
                    Text("Option \(suggestion.rank)")
                        .font(.headline)
                    Spacer()
                    Text("\(suggestion.totalPoints) points")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
        }

        // Generate button
        Button {
            Task { await generateSuggestions() }
        } label: {
            Label("Generate New Suggestions", systemImage: "sparkles")
        }
    } header: {
        Text("AI Suggestions")
    }
}
```

### Step 3: Dedicated AI Chat for Dispatch

```swift
// Separate AI chat for dispatch modifications
Button { showAIChat = true } label: {
    Label("Ask AI", systemImage: "bubble.left.and.bubble.right")
}
.sheet(isPresented: $showAIChat) {
    DispatchAIChatView(
        date: selectedDate,
        currentAssignments: currentAssignments,
        onModify: { modification in
            // Apply AI-suggested modification to the board
        }
    )
}

// DispatchAIChatView is a chat interface specifically for dispatch questions:
// "What if I move John to Job A instead?"
// "Who's available for afternoon work?"
// "What happens if Team B finishes early?"
```

### Step 4: Learning from Choices

```swift
// After dispatcher applies or modifies a suggestion:
func applySuggestion(_ suggestion: DispatchSuggestion) async {
    do {
        // 1. Create the assignments
        for assignment in suggestion.assignments {
            try await schedulingService.createDispatchAssignment(/*...*/)
        }
        // 2. Record the choice for learning
        try await aiDispatchService.recordDispatcherChoice(
            date: selectedDate,
            chosenSuggestion: suggestion.rank,
            modifications: []
        )
        await loadData()
    } catch {
        actionError = error.localizedDescription
    }
}
```

### Step 5: Early Finish Suggestions

```swift
// When a crew finishes early (detected from clock-out before scheduled end):
func checkForEarlyFinish() async {
    // 1. Find crews that finished today before 3 PM
    // 2. Check if any urgent jobs could use them
    // 3. Generate suggestion: "Team A finished at 2 PM. Suggest: send to [Job B] for afternoon."
}
```

### Step 6: Daily Rolling Flow

```swift
// Confirm today → generate tomorrow
// "Today's dispatch is confirmed. Here are 3 options for tomorrow."
func confirmTodayAndSuggestTomorrow() async {
    do {
        // Lock today's assignments
        try await schedulingService.confirmDayDispatch(date: Date())
        // Generate tomorrow's suggestions
        suggestions = try await aiDispatchService.generateSuggestions(
            date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
    } catch {
        actionError = error.localizedDescription
    }
}
```

## Important Notes
- AI generates exactly 3 options — not more, not less
- Points are transparent — dispatcher sees WHY each option scored as it did
- The AI dispatch chat is SEPARATE from the general AI assistant
- Learning happens automatically — no manual training required
- Scoring weights are adjustable over time based on dispatcher patterns
- Early finish detection triggers push notification (if available)
- "Confirm today" locks assignments — no more changes without override

## Success Criteria
- [ ] AIDispatchService.swift created
- [ ] 3 ranked suggestions with points-based scoring
- [ ] Scoring breakdown visible (skills, team, travel, history, specialty)
- [ ] Apply suggestion creates assignments on dispatch board
- [ ] Dedicated AI chat for dispatch questions (separate from general AI)
- [ ] Learning from dispatcher choices (record + recalibrate)
- [ ] Early finish detection + suggestions
- [ ] Daily rolling: confirm today, suggest tomorrow
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 46E Results (YYYY-MM-DD)
- AIDispatchService: 3-option suggestions with points
- Scoring: skills, team, travel, history, specialty
- AI chat for dispatch, learning system
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 46F.**
