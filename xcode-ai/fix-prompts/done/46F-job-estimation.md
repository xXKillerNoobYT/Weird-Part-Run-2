# 46F — Job Estimation Questionnaire System

> **Chain position:** **46F** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `JobsService.swift` and review the Office section in `OfficeRouter.swift`. Create a job estimation questionnaire system with grouped questions, stage-aware prompts, AI learning, and capacity calculation.

## Context

Estimating job duration is one of the hardest parts of construction management. The questionnaire system asks targeted questions at each stage of a job's lifecycle (bid, pre-start, during, before-trim, punch list). Questions are configurable by Office users. "?" marks unknowns (instead of forcing guesses). After 15+ completed jobs, AI learns which questions actually predict duration and suggests improvements. Historical averages give work-day capacity calculations. Weekly reviews mid-job and end-of-job reviews improve future estimates.

## Task

### Step 1: Migration — Estimation Tables

```sql
CREATE TABLE estimation_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_text TEXT NOT NULL,
    question_group TEXT NOT NULL,  -- 'scope', 'complexity', 'access', 'materials', 'labor'
    stage TEXT NOT NULL,  -- 'bid', 'pre_start', 'during', 'before_trim', 'punch_list'
    answer_type TEXT NOT NULL DEFAULT 'number',  -- 'number', 'choice', 'boolean', 'text'
    choices TEXT,  -- JSON array for choice type
    weight REAL NOT NULL DEFAULT 1.0,  -- how much this affects estimate
    is_active INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);

CREATE TABLE estimation_responses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    question_id INTEGER NOT NULL REFERENCES estimation_questions(id),
    stage TEXT NOT NULL,
    response_value TEXT,  -- the answer (number, choice, or text)
    is_unknown INTEGER NOT NULL DEFAULT 0,  -- "?" response
    answered_by INTEGER REFERENCES users(id),
    answered_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE estimation_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    stage TEXT NOT NULL,
    estimated_days REAL,
    estimated_hours REAL,
    confidence_percent REAL,  -- 0-100, lower if many "?" answers
    ai_suggested INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE estimation_reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    review_type TEXT NOT NULL,  -- 'weekly', 'end_of_job'
    actual_days REAL,
    actual_hours REAL,
    estimate_at_start REAL,
    variance_percent REAL,
    lessons_learned TEXT,
    reviewed_by INTEGER REFERENCES users(id),
    reviewed_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE estimation_question_rejections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES estimation_questions(id),
    rejected_by INTEGER REFERENCES users(id),
    reason TEXT,
    rejected_at TEXT DEFAULT (datetime('now'))
);
```

### Step 2: Create JobEstimationService

Create `core/Sources/WiredPartCore/Services/JobEstimationService.swift`:

```swift
import Foundation

actor JobEstimationService {
    private let db: AppDatabase

    // MARK: - Questions

    func getQuestionsForStage(stage: String) async throws -> [EstimationQuestion]
    func createQuestion(text: String, group: String, stage: String, answerType: String, choices: [String]?) async throws -> EstimationQuestion
    func updateQuestion(questionId: Int64, text: String?, weight: Double?, isActive: Bool?) async throws
    func rejectQuestion(questionId: Int64, rejectedBy: Int64, reason: String?) async throws

    // MARK: - Responses

    func submitResponse(jobId: Int64, questionId: Int64, stage: String, value: String?, isUnknown: Bool, answeredBy: Int64) async throws
    func getResponsesForJob(jobId: Int64, stage: String?) async throws -> [EstimationResponse]

    // MARK: - Estimation Calculation

    /// Calculate estimated duration based on responses
    func calculateEstimate(jobId: Int64, stage: String) async throws -> EstimationResult {
        // 1. Get all responses for this job+stage
        // 2. Apply question weights
        // 3. Calculate confidence (lower if many unknowns)
        // 4. Compare with historical jobs (same GC, area, type)
        // 5. Return estimated days/hours
    }

    /// Get historical average for similar jobs
    func getHistoricalAverage(gcId: Int64?, jobType: String?, area: String?) async throws -> HistoricalAverage?

    struct HistoricalAverage: Sendable {
        let jobCount: Int
        let avgDays: Double
        let avgHours: Double
        let minDays: Double
        let maxDays: Double
    }

    // MARK: - Reviews

    func submitWeeklyReview(jobId: Int64, reviewedBy: Int64, notes: String?) async throws
    func submitEndOfJobReview(jobId: Int64, actualDays: Double, actualHours: Double, lessonsLearned: String?, reviewedBy: Int64) async throws
    func getJobReviews(jobId: Int64) async throws -> [EstimationReview]

    // MARK: - AI Learning (after 15+ completed jobs)

    /// Analyze which questions best predict actual duration
    func analyzeQuestionEffectiveness() async throws -> [QuestionEffectiveness] {
        // Correlate question responses with actual job duration
        // Rank questions by predictive value
        // Flag questions that never correlate (candidates for rejection)
    }

    struct QuestionEffectiveness: Identifiable, Sendable {
        let id: Int64
        let questionText: String
        let correlationScore: Double  // 0-1, how well it predicts duration
        let timesAsked: Int
        let timesUnknown: Int
        let recommendation: String  // "keep", "modify", "remove", "needs_more_data"
    }

    /// AI suggestions based on GC/area/type history
    func getJobSpecificSuggestions(jobId: Int64) async throws -> [String]

    // MARK: - Capacity Calculation

    /// Calculate work-day capacity from historical averages
    func calculateMonthlyCapacity() async throws -> Double {
        // Average productive hours per worker per day (from last 6 months of clock data)
        // × number of active workers
        // × working days in month
        // = available work-days
    }
}
```

### Step 3: Estimation Questionnaire UI

```swift
// Questionnaire view for a job at a specific stage
struct EstimationQuestionnaireView: View {
    let jobId: Int64
    let stage: String
    @State private var questions: [EstimationQuestion] = []
    @State private var responses: [Int64: ResponseValue] = [:]

    enum ResponseValue {
        case value(String)
        case unknown
    }

    var body: some View {
        List {
            // Questions grouped by category
            ForEach(groupedQuestions.keys.sorted(), id: \.self) { group in
                Section {
                    ForEach(groupedQuestions[group] ?? []) { question in
                        questionRow(question)
                    }
                } header: {
                    Text(group.capitalized)
                }
            }

            // Estimate result
            Section {
                Button("Calculate Estimate") {
                    Task { await calculateEstimate() }
                }
                .buttonStyle(.borderedProminent)

                if let result = estimateResult {
                    LabeledContent("Estimated Days", value: String(format: "%.1f", result.estimatedDays ?? 0))
                    LabeledContent("Confidence", value: "\(Int(result.confidencePercent ?? 0))%")

                    // Historical comparison
                    if let historical = historicalAvg {
                        LabeledContent("Similar Jobs Avg", value: String(format: "%.1f days", historical.avgDays))
                        LabeledContent("Range", value: "\(Int(historical.minDays))-\(Int(historical.maxDays)) days")
                    }
                }
            } header: {
                Text("Estimate")
            }
        }
        .navigationTitle("Estimation — \(stage.capitalized)")
    }

    func questionRow(_ question: EstimationQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question.questionText).font(.subheadline)

            HStack {
                switch question.answerType {
                case "number":
                    TextField("Value", text: responseBinding(question.id!))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)

                case "boolean":
                    Picker("", selection: responseBinding(question.id!)) {
                        Text("Yes").tag("yes")
                        Text("No").tag("no")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)

                case "choice":
                    if let choices = question.decodedChoices {
                        Picker("", selection: responseBinding(question.id!)) {
                            ForEach(choices, id: \.self) { choice in
                                Text(choice).tag(choice)
                            }
                        }
                    }

                default:
                    TextField("Response", text: responseBinding(question.id!))
                        .textFieldStyle(.roundedBorder)
                }

                Spacer()

                // "?" button for unknowns
                Button {
                    responses[question.id!] = .unknown
                } label: {
                    Text("?")
                        .font(.headline)
                        .foregroundStyle(responses[question.id!] == .unknown ? .white : .orange)
                        .frame(width: 32, height: 32)
                        .background(responses[question.id!] == .unknown ? Color.orange : Color.orange.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
    }
}
```

### Step 4: Office Settings — Question Management

```swift
// Office page for managing estimation questions
struct EstimationQuestionsSettingsPage: View {
    // List all questions grouped by stage
    // Add/edit/deactivate questions
    // Set weights
    // View rejected questions log
    // AI effectiveness analysis (after 15+ jobs)
}

// Add to OfficeRouter
```

### Step 5: Weekly + End-of-Job Reviews

```swift
// Weekly review prompt (triggered by scheduler or manual)
struct WeeklyEstimationReview: View {
    let jobId: Int64
    // Shows: original estimate vs actual progress
    // Asks: "Is the job on track?"
    // Records notes and any revised estimate
}

// End-of-job review (triggered when job status → complete)
struct EndOfJobReview: View {
    let jobId: Int64
    // Shows: original estimate vs actual
    // Variance percentage
    // "Lessons learned" text field
    // Feeds into AI learning
}
```

### Step 6: Update ConflictResolver

Add all new tables to the whitelist.

## Important Notes
- "?" option is critical — it prevents bad data from forced guesses
- Confidence score decreases with more "?" answers
- AI learning only activates after 15+ completed jobs with reviews
- Questions are stage-specific: bid questions != punch list questions
- Historical averages filter by GC, area, and job type for relevance
- Rejected questions are logged — AI can reconsider them later
- Weekly reviews are optional but recommended
- End-of-job reviews are prompted but not required
- Work-day capacity = actual productive hours, not calendar days

## Success Criteria
- [ ] 5 estimation tables created (questions, responses, results, reviews, rejections)
- [ ] JobEstimationService with 15+ methods
- [ ] Questionnaire UI with grouped questions and "?" option
- [ ] Estimate calculation with confidence score
- [ ] Historical average comparison
- [ ] Office settings for question management
- [ ] Weekly review and end-of-job review
- [ ] AI effectiveness analysis (after 15+ jobs)
- [ ] ConflictResolver updated
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 46F Results (YYYY-MM-DD)
- Migration: 5 estimation tables
- JobEstimationService: X methods
- Questionnaire UI with "?" unknowns
- Office settings for questions
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
