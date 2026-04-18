import Foundation
import GRDB

/// Service for job estimation: questions, responses, calculation, reviews, and AI learning.
public final class JobEstimationService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Questions
    // =========================================================================

    /// Get active questions for a specific stage, ordered by group then sort_order.
    public func getQuestionsForStage(stage: String) throws -> [EstimationQuestion] {
        do {
            return try db.writer.read { dbConn in
                try EstimationQuestion
                    .filter(Column("stage") == stage &&
                            Column("is_active") == 1 &&
                            Column("deleted_at") == nil)
                    .order(Column("question_group").asc, Column("sort_order").asc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get all questions (active and inactive) for settings management.
    public func getAllQuestions() throws -> [EstimationQuestion] {
        do {
            return try db.writer.read { dbConn in
                try EstimationQuestion
                    .filter(Column("deleted_at") == nil)
                    .order(Column("stage").asc, Column("question_group").asc, Column("sort_order").asc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new estimation question.
    @discardableResult
    public func createQuestion(
        text: String,
        group: String,
        stage: String,
        answerType: String = "number",
        choices: [String]? = nil,
        weight: Double = 1.0
    ) throws -> EstimationQuestion {
        let choicesJSON: String? = if let choices {
            (try? JSONEncoder().encode(choices)).flatMap { String(data: $0, encoding: .utf8) }
        } else {
            nil
        }

        do {
            // Get next sort order
            let maxSort: Int = try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(MAX(sort_order), 0) FROM estimation_questions
                    WHERE stage = ? AND question_group = ? AND deleted_at IS NULL
                    """, arguments: [stage, group]) ?? 0
            }

            return try db.writer.write { dbConn in
                var question = EstimationQuestion(
                    id: nil, questionText: text, questionGroup: group,
                    stage: stage, answerType: answerType, choices: choicesJSON,
                    weight: weight, isActive: 1, sortOrder: maxSort + 1,
                    createdAt: nil, updatedAt: nil, deletedAt: nil
                )
                try question.insert(dbConn)
                return question
            }
        } catch {
            if isTableNotFoundError(error) {
                return EstimationQuestion(
                    id: nil, questionText: text, questionGroup: group,
                    stage: stage, answerType: answerType, choices: choicesJSON,
                    weight: weight, isActive: 1, sortOrder: 1,
                    createdAt: nil, updatedAt: nil, deletedAt: nil
                )
            }
            throw error
        }
    }

    /// Update a question's text, weight, or active status.
    public func updateQuestion(
        questionId: Int64,
        text: String? = nil,
        weight: Double? = nil,
        isActive: Bool? = nil
    ) throws {
        do {
            try db.writer.write { dbConn in
                guard var question = try EstimationQuestion.fetchOne(dbConn, key: questionId) else { return }
                if let text { question.questionText = text }
                if let weight { question.weight = weight }
                if let isActive { question.isActive = isActive ? 1 : 0 }
                question.updatedAt = Self.nowString()
                try question.update(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    /// Reject/deactivate a question with a reason.
    public func rejectQuestion(questionId: Int64, rejectedBy: Int64, reason: String?) throws {
        do {
            try db.writer.write { dbConn in
                // Deactivate the question
                try dbConn.execute(sql: """
                    UPDATE estimation_questions SET is_active = 0, updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [questionId])

                // Log the rejection
                var rejection = EstimationQuestionRejection(
                    id: nil, questionId: questionId, rejectedBy: rejectedBy,
                    reason: reason, rejectedAt: nil
                )
                try rejection.insert(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    /// Get rejection history for a question.
    public func getQuestionRejections(questionId: Int64) throws -> [EstimationQuestionRejection] {
        do {
            return try db.writer.read { dbConn in
                try EstimationQuestionRejection
                    .filter(Column("question_id") == questionId)
                    .order(Column("rejected_at").desc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Responses
    // =========================================================================

    /// Submit or update a response to an estimation question.
    @discardableResult
    public func submitResponse(
        jobId: Int64,
        questionId: Int64,
        stage: String,
        value: String?,
        isUnknown: Bool = false,
        answeredBy: Int64
    ) throws -> EstimationResponse {
        do {
            return try db.writer.write { dbConn in
                // Delete any existing response for this job+question+stage
                try dbConn.execute(sql: """
                    DELETE FROM estimation_responses
                    WHERE job_id = ? AND question_id = ? AND stage = ?
                    """, arguments: [jobId, questionId, stage])

                var response = EstimationResponse(
                    id: nil, jobId: jobId, questionId: questionId,
                    stage: stage, responseValue: isUnknown ? nil : value,
                    isUnknown: isUnknown ? 1 : 0,
                    answeredBy: answeredBy, answeredAt: nil
                )
                try response.insert(dbConn)
                return response
            }
        } catch {
            if isTableNotFoundError(error) {
                return EstimationResponse(
                    id: nil, jobId: jobId, questionId: questionId,
                    stage: stage, responseValue: isUnknown ? nil : value,
                    isUnknown: isUnknown ? 1 : 0,
                    answeredBy: answeredBy, answeredAt: nil
                )
            }
            throw error
        }
    }

    /// Get all responses for a job, optionally filtered by stage.
    public func getResponsesForJob(jobId: Int64, stage: String? = nil) throws -> [EstimationResponse] {
        do {
            return try db.writer.read { dbConn in
                var request = EstimationResponse
                    .filter(Column("job_id") == jobId)

                if let stage {
                    request = request.filter(Column("stage") == stage)
                }

                return try request
                    .order(Column("question_id").asc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Estimation Calculation
    // =========================================================================

    /// Calculate estimated duration based on question responses and weights.
    @discardableResult
    public func calculateEstimate(jobId: Int64, stage: String) throws -> EstimationResult {
        let responses = try getResponsesForJob(jobId: jobId, stage: stage)
        let questions = try getQuestionsForStage(stage: stage)

        // Build a lookup of question ID → question
        var questionMap: [Int64: EstimationQuestion] = [:]
        for q in questions {
            if let qid = q.id { questionMap[qid] = q }
        }

        var totalWeightedScore: Double = 0
        var totalWeight: Double = 0
        var unknownCount = 0
        var answeredCount = 0

        for response in responses {
            guard let question = questionMap[response.questionId] else { continue }

            if response.isUnknown == 1 {
                unknownCount += 1
                continue
            }

            answeredCount += 1
            let score = scoreResponse(response: response, question: question)
            totalWeightedScore += score * question.weight
            totalWeight += question.weight
        }

        // Base estimate: weighted score maps to days
        // Higher score = more days (complexity, size, difficulty increase duration)
        let baseDays: Double = if totalWeight > 0 {
            (totalWeightedScore / totalWeight) * 5.0 // scale factor
        } else {
            0
        }

        // Confidence: decreases with more unknowns
        let totalQuestions = unknownCount + answeredCount
        let confidence: Double = if totalQuestions > 0 {
            Double(answeredCount) / Double(totalQuestions) * 100.0
        } else {
            0
        }

        let estimatedHours = baseDays * 8.0

        // Save the result
        do {
            return try db.writer.write { dbConn in
                var result = EstimationResult(
                    id: nil, jobId: jobId, stage: stage,
                    estimatedDays: baseDays, estimatedHours: estimatedHours,
                    confidencePercent: confidence, aiSuggested: 0,
                    notes: nil, createdAt: nil
                )
                try result.insert(dbConn)
                return result
            }
        } catch {
            if isTableNotFoundError(error) {
                return EstimationResult(
                    id: nil, jobId: jobId, stage: stage,
                    estimatedDays: baseDays, estimatedHours: estimatedHours,
                    confidencePercent: confidence, aiSuggested: 0,
                    notes: nil, createdAt: nil
                )
            }
            throw error
        }
    }

    /// Score a single response on a 0-10 scale based on answer type and value.
    private func scoreResponse(response: EstimationResponse, question: EstimationQuestion) -> Double {
        guard let value = response.responseValue else { return 0 }

        switch question.answerType {
        case "number":
            // Normalize: treat as a direct numeric factor
            return min(Double(value) ?? 0, 10.0)
        case "boolean":
            return value.lowercased() == "yes" ? 1.0 : 0.0
        case "choice":
            // Score based on position in choices list (later = more complex)
            if let choices = question.decodedChoices,
               let idx = choices.firstIndex(of: value) {
                return Double(idx + 1) / Double(choices.count) * 5.0
            }
            return 1.0
        default:
            return 1.0 // text answers get a neutral score
        }
    }

    /// Get the most recent estimation result for a job and stage.
    public func getLatestResult(jobId: Int64, stage: String) throws -> EstimationResult? {
        do {
            return try db.writer.read { dbConn in
                try EstimationResult
                    .filter(Column("job_id") == jobId && Column("stage") == stage)
                    .order(Column("created_at").desc)
                    .fetchOne(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Get all estimation results for a job across all stages.
    public func getAllResults(jobId: Int64) throws -> [EstimationResult] {
        do {
            return try db.writer.read { dbConn in
                try EstimationResult
                    .filter(Column("job_id") == jobId)
                    .order(Column("created_at").desc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Historical Averages
    // =========================================================================

    /// Get historical average durations for similar jobs (same GC, type, or area).
    public func getHistoricalAverage(gcId: Int64? = nil, jobType: String? = nil, area: String? = nil) throws -> HistoricalAverage? {
        do { return try db.writer.read { dbConn in
            // Build filter conditions for completed jobs with reviews
            var conditions: [String] = ["j.status = 'completed'", "j.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible] = []

            if let gcId {
                conditions.append("jgc.gc_id = ?")
                args.append(gcId)
            }
            if let jobType {
                conditions.append("j.job_type = ?")
                args.append(jobType)
            }
            if let area {
                conditions.append("j.city = ?")
                args.append(area)
            }

            let whereClause = conditions.joined(separator: " AND ")
            let gcJoin = gcId != nil ? "LEFT JOIN job_general_contractors jgc ON jgc.job_id = j.id" : ""

            let row = try Row.fetchOne(dbConn, sql: """
                SELECT
                    COUNT(*) as job_count,
                    COALESCE(AVG(er.actual_days), 0) as avg_days,
                    COALESCE(AVG(er.actual_hours), 0) as avg_hours,
                    COALESCE(MIN(er.actual_days), 0) as min_days,
                    COALESCE(MAX(er.actual_days), 0) as max_days
                FROM jobs j
                \(gcJoin)
                LEFT JOIN estimation_reviews er ON er.job_id = j.id AND er.review_type = 'end_of_job'
                WHERE \(whereClause) AND er.actual_days IS NOT NULL
                """, arguments: StatementArguments(args))

            guard let row, row["job_count"] as Int? ?? 0 > 0 else { return nil }

            return HistoricalAverage(
                jobCount: row["job_count"],
                avgDays: row["avg_days"],
                avgHours: row["avg_hours"],
                minDays: row["min_days"],
                maxDays: row["max_days"]
            )
        }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Reviews
    // =========================================================================

    /// Submit a weekly review for a job.
    @discardableResult
    public func submitWeeklyReview(
        jobId: Int64,
        reviewedBy: Int64,
        notes: String?
    ) throws -> EstimationReview {
        // Get the original estimate for variance calculation
        let originalEstimate = try getLatestResult(jobId: jobId, stage: "bid")

        do {
            return try db.writer.write { dbConn in
                // Calculate actual hours worked so far from labor entries
                let actualHours = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(regular_hours + overtime_hours), 0) FROM labor_entries
                    WHERE job_id = ? AND deleted_at IS NULL
                    """, arguments: [jobId]) ?? 0

                let actualDays = actualHours / 8.0
                let estimateAtStart = originalEstimate?.estimatedDays
                let variance: Double? = if let est = estimateAtStart, est > 0 {
                    ((actualDays - est) / est) * 100.0
                } else {
                    nil
                }

                var review = EstimationReview(
                    id: nil, jobId: jobId, reviewType: "weekly",
                    actualDays: actualDays, actualHours: actualHours,
                    estimateAtStart: estimateAtStart, variancePercent: variance,
                    lessonsLearned: notes, reviewedBy: reviewedBy, reviewedAt: nil
                )
                try review.insert(dbConn)
                return review
            }
        } catch {
            if isTableNotFoundError(error) {
                return EstimationReview(
                    id: nil, jobId: jobId, reviewType: "weekly",
                    actualDays: 0, actualHours: 0,
                    estimateAtStart: originalEstimate?.estimatedDays, variancePercent: nil,
                    lessonsLearned: notes, reviewedBy: reviewedBy, reviewedAt: nil
                )
            }
            throw error
        }
    }

    /// Submit an end-of-job review with final actuals.
    @discardableResult
    public func submitEndOfJobReview(
        jobId: Int64,
        actualDays: Double,
        actualHours: Double,
        lessonsLearned: String?,
        reviewedBy: Int64
    ) throws -> EstimationReview {
        let originalEstimate = try getLatestResult(jobId: jobId, stage: "bid")

        do {
            return try db.writer.write { dbConn in
                let estimateAtStart = originalEstimate?.estimatedDays
                let variance: Double? = if let est = estimateAtStart, est > 0 {
                    ((actualDays - est) / est) * 100.0
                } else {
                    nil
                }

                var review = EstimationReview(
                    id: nil, jobId: jobId, reviewType: "end_of_job",
                    actualDays: actualDays, actualHours: actualHours,
                    estimateAtStart: estimateAtStart, variancePercent: variance,
                    lessonsLearned: lessonsLearned, reviewedBy: reviewedBy, reviewedAt: nil
                )
                try review.insert(dbConn)
                return review
            }
        } catch {
            if isTableNotFoundError(error) {
                let estimateAtStart = originalEstimate?.estimatedDays
                let variance: Double? = if let est = estimateAtStart, est > 0 {
                    ((actualDays - est) / est) * 100.0
                } else {
                    nil
                }
                return EstimationReview(
                    id: nil, jobId: jobId, reviewType: "end_of_job",
                    actualDays: actualDays, actualHours: actualHours,
                    estimateAtStart: estimateAtStart, variancePercent: variance,
                    lessonsLearned: lessonsLearned, reviewedBy: reviewedBy, reviewedAt: nil
                )
            }
            throw error
        }
    }

    /// Get all reviews for a job.
    public func getJobReviews(jobId: Int64) throws -> [EstimationReview] {
        do {
            return try db.writer.read { dbConn in
                try EstimationReview
                    .filter(Column("job_id") == jobId)
                    .order(Column("reviewed_at").desc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - AI Learning (after 15+ completed jobs)
    // =========================================================================

    /// Analyze which questions best predict actual duration.
    /// Only meaningful after 15+ completed jobs with end-of-job reviews.
    public func analyzeQuestionEffectiveness() throws -> [QuestionEffectiveness] {
        do { return try db.writer.read { dbConn in
            // Count completed jobs with reviews
            let completedCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(DISTINCT job_id) FROM estimation_reviews WHERE review_type = 'end_of_job'
                """) ?? 0

            guard completedCount >= 15 else {
                // Not enough data — return all questions as "needs_more_data"
                let questions = try EstimationQuestion
                    .filter(Column("deleted_at") == nil)
                    .fetchAll(dbConn)
                return questions.compactMap { q -> QuestionEffectiveness? in
                    guard let qid = q.id else { return nil }
                    return QuestionEffectiveness(
                        id: qid, questionText: q.questionText,
                        correlationScore: 0, timesAsked: 0, timesUnknown: 0,
                        recommendation: "needs_more_data"
                    )
                }
            }

            // For each question, calculate correlation with actual duration
            let questions = try EstimationQuestion
                .filter(Column("deleted_at") == nil)
                .fetchAll(dbConn)

            var results: [QuestionEffectiveness] = []

            for question in questions {
                guard let qid = question.id else { continue }

                // Get response stats
                let row = try Row.fetchOne(dbConn, sql: """
                    SELECT
                        COUNT(*) as times_asked,
                        SUM(CASE WHEN er.is_unknown = 1 THEN 1 ELSE 0 END) as times_unknown
                    FROM estimation_responses er
                    WHERE er.question_id = ?
                    """, arguments: [qid])

                let timesAsked: Int = row?["times_asked"] ?? 0
                let timesUnknown: Int = row?["times_unknown"] ?? 0

                // Calculate variance correlation:
                // Questions whose responses correlate with lower variance = better predictors
                let varianceRow = try Row.fetchOne(dbConn, sql: """
                    SELECT
                        AVG(ABS(rev.variance_percent)) as avg_variance
                    FROM estimation_responses er
                    JOIN estimation_reviews rev ON rev.job_id = er.job_id AND rev.review_type = 'end_of_job'
                    WHERE er.question_id = ? AND er.is_unknown = 0
                    """, arguments: [qid])

                let avgVariance: Double = varianceRow?["avg_variance"] ?? 100.0

                // Lower variance = higher correlation score (inverted)
                let correlationScore = max(0, min(1.0, 1.0 - (avgVariance / 100.0)))

                let recommendation: String
                if timesAsked < 5 {
                    recommendation = "needs_more_data"
                } else if correlationScore > 0.6 {
                    recommendation = "keep"
                } else if correlationScore > 0.3 {
                    recommendation = "modify"
                } else {
                    recommendation = "remove"
                }

                results.append(QuestionEffectiveness(
                    id: qid, questionText: question.questionText,
                    correlationScore: correlationScore,
                    timesAsked: timesAsked, timesUnknown: timesUnknown,
                    recommendation: recommendation
                ))
            }

            return results.sorted { $0.correlationScore > $1.correlationScore }
        }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get AI suggestions based on job history (GC, area, type).
    public func getJobSpecificSuggestions(jobId: Int64) throws -> [String] {
        do { return try db.writer.read { dbConn in
            guard let job = try Row.fetchOne(dbConn, sql: """
                SELECT j.job_type, j.city, jgc.gc_id
                FROM jobs j
                LEFT JOIN job_general_contractors jgc ON jgc.job_id = j.id
                WHERE j.id = ?
                """, arguments: [jobId]) else { return [] }

            let jobType: String? = job["job_type"]
            let city: String? = job["city"]
            let gcId: Int64? = job["gc_id"]

            var suggestions: [String] = []

            // Check similar past jobs
            let similarCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM jobs
                WHERE job_type = ? AND status = 'completed' AND deleted_at IS NULL
                """, arguments: [jobType ?? ""]) ?? 0

            if similarCount >= 3 {
                let avgHours = try Double.fetchOne(dbConn, sql: """
                    SELECT AVG(er.actual_hours) FROM estimation_reviews er
                    JOIN jobs j ON j.id = er.job_id
                    WHERE j.job_type = ? AND er.review_type = 'end_of_job'
                    """, arguments: [jobType ?? ""]) ?? 0

                if avgHours > 0 {
                    suggestions.append("Similar \(jobType ?? "type") jobs averaged \(String(format: "%.0f", avgHours)) hours")
                }
            }

            // GC-specific insight
            if let gcId {
                let gcAvg = try Double.fetchOne(dbConn, sql: """
                    SELECT AVG(er.variance_percent) FROM estimation_reviews er
                    JOIN job_general_contractors jgc ON jgc.job_id = er.job_id
                    WHERE jgc.gc_id = ? AND er.review_type = 'end_of_job'
                    """, arguments: [gcId])

                if let gcAvg, abs(gcAvg) > 10 {
                    let direction = gcAvg > 0 ? "over" : "under"
                    suggestions.append("Jobs with this GC tend to run \(Int(abs(gcAvg)))% \(direction) estimate")
                }
            }

            // Area-specific insight
            if let city, !city.isEmpty {
                let areaCount = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM jobs WHERE city = ? AND status = 'completed' AND deleted_at IS NULL
                    """, arguments: [city]) ?? 0

                if areaCount >= 2 {
                    suggestions.append("\(areaCount) completed jobs in \(city) area")
                }
            }

            return suggestions
        }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Capacity Calculation
    // =========================================================================

    /// Calculate work-day capacity from historical averages.
    /// Returns available work-days for the current month.
    public func calculateMonthlyCapacity() throws -> Double {
        do { return try db.writer.read { dbConn in
            // Get active worker count
            let workerCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE deleted_at IS NULL
                """) ?? 1

            // Average productive hours per worker per day from last 6 months
            let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            let sinceDate = f.string(from: sixMonthsAgo)

            let avgHoursPerDay = try Double.fetchOne(dbConn, sql: """
                SELECT AVG(daily_hours) FROM (
                    SELECT date(clock_in) as work_date, SUM(regular_hours + overtime_hours) as daily_hours
                    FROM labor_entries
                    WHERE clock_in >= ? AND deleted_at IS NULL AND (regular_hours + overtime_hours) > 0
                    GROUP BY user_id, date(clock_in)
                )
                """, arguments: [sinceDate]) ?? 8.0

            // Working days in current month (approx 22)
            let calendar = Calendar.current
            let now = Date()
            let range = calendar.range(of: .day, in: .month, for: now) ?? 1..<31
            let weekdays = (range).reduce(0) { count, day in
                var comps = calendar.dateComponents([.year, .month], from: now)
                comps.day = day
                guard let date = calendar.date(from: comps) else { return count }
                let weekday = calendar.component(.weekday, from: date)
                return count + (weekday >= 2 && weekday <= 6 ? 1 : 0)
            }

            return (avgHoursPerDay / 8.0) * Double(workerCount) * Double(weekdays)
        }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    private static func nowString() -> String { CoreFormatters.nowISO() }

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
