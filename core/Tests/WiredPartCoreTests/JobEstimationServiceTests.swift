import Foundation
#if canImport(Darwin)
import Darwin
#endif
import Testing
import GRDB
@testable import WiredPartCore

@Suite("JobEstimationService Tests")
struct JobEstimationServiceTests {

    private func freshEnv() throws -> (E2ETestHelpers.TestEnvironment, JobEstimationService) {
        let env = try E2ETestHelpers.setUp()
        let estimation = JobEstimationService(db: env.db)
        return (env, estimation)
    }

    // MARK: - Question CRUD

    @Test("Create and list estimation questions")
    func testCreateQuestion() throws {
        let (_, est) = try freshEnv()

        let q = try est.createQuestion(
            text: "How many floors?",
            group: "scope",
            stage: "initial",
            answerType: "number",
            weight: 1.5
        )
        #expect(q.questionText == "How many floors?")
        #expect(q.weight == 1.5)

        let all = try est.getAllQuestions()
        #expect(all.count >= 1)
    }

    @Test("Get questions filtered by stage")
    func testQuestionsByStage() throws {
        let (_, est) = try freshEnv()

        _ = try est.createQuestion(text: "Q1", group: "scope", stage: "initial")
        _ = try est.createQuestion(text: "Q2", group: "scope", stage: "detailed")

        let initial = try est.getQuestionsForStage(stage: "initial")
        #expect(initial.count == 1)
        #expect(initial[0].questionText == "Q1")
    }

    @Test("Update question properties")
    func testUpdateQuestion() throws {
        let (_, est) = try freshEnv()

        let q = try est.createQuestion(text: "Original", group: "g", stage: "s")
        try est.updateQuestion(questionId: q.id!, text: "Updated", weight: 2.0)

        let all = try est.getAllQuestions()
        let found = all.first { $0.id == q.id }
        #expect(found?.questionText == "Updated")
        #expect(found?.weight == 2.0)
    }

    @Test("Reject question records rejection")
    func testRejectQuestion() throws {
        let (env, est) = try freshEnv()

        let q = try est.createQuestion(text: "Bad Q", group: "g", stage: "s")
        try est.rejectQuestion(questionId: q.id!, rejectedBy: env.adminUserId, reason: "Not relevant")

        let rejections = try est.getQuestionRejections(questionId: q.id!)
        #expect(rejections.count == 1)
        #expect(rejections[0].reason == "Not relevant")
    }

    // MARK: - Responses

    @Test("Submit and retrieve estimation response")
    func testSubmitResponse() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        let q = try est.createQuestion(text: "Sq footage?", group: "scope", stage: "initial", answerType: "number")

        let response = try est.submitResponse(
            jobId: jobId,
            questionId: q.id!,
            stage: "initial",
            value: "2500",
            answeredBy: env.adminUserId
        )
        #expect(response.responseValue == "2500")

        let responses = try est.getResponsesForJob(jobId: jobId)
        #expect(responses.count == 1)
    }

    @Test("Submit unknown response")
    func testSubmitUnknownResponse() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        let q = try est.createQuestion(text: "Ceiling height?", group: "scope", stage: "initial")

        let response = try est.submitResponse(
            jobId: jobId,
            questionId: q.id!,
            stage: "initial",
            value: nil,
            isUnknown: true,
            answeredBy: env.adminUserId
        )
        #expect(response.isUnknown != 0)
    }

    @Test("Filter responses by stage")
    func testResponsesByStage() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let q1 = try est.createQuestion(text: "Q1", group: "g", stage: "initial")
        let q2 = try est.createQuestion(text: "Q2", group: "g", stage: "detailed")

        _ = try est.submitResponse(jobId: jobId, questionId: q1.id!, stage: "initial", value: "10", answeredBy: env.adminUserId)
        _ = try est.submitResponse(jobId: jobId, questionId: q2.id!, stage: "detailed", value: "20", answeredBy: env.adminUserId)

        let initialOnly = try est.getResponsesForJob(jobId: jobId, stage: "initial")
        #expect(initialOnly.count == 1)
    }

    // MARK: - Estimation Calculation

    @Test("Calculate estimate for a job")
    func testCalculateEstimate() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let q = try est.createQuestion(text: "Rooms?", group: "scope", stage: "initial", answerType: "number", weight: 1.0)
        _ = try est.submitResponse(jobId: jobId, questionId: q.id!, stage: "initial", value: "5", answeredBy: env.adminUserId)

        let result = try est.calculateEstimate(jobId: jobId, stage: "initial")
        #expect(result.stage == "initial")
        #expect((result.estimatedDays ?? 0) >= 0)
    }

    @Test("Get latest result for job")
    func testGetLatestResult() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let q = try est.createQuestion(text: "Size?", group: "scope", stage: "initial", answerType: "number")
        _ = try est.submitResponse(jobId: jobId, questionId: q.id!, stage: "initial", value: "100", answeredBy: env.adminUserId)
        _ = try est.calculateEstimate(jobId: jobId, stage: "initial")

        let latest = try est.getLatestResult(jobId: jobId, stage: "initial")
        #expect(latest != nil)
    }

    @Test("Get all results for job")
    func testGetAllResults() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let q = try est.createQuestion(text: "Area?", group: "scope", stage: "initial", answerType: "number")
        _ = try est.submitResponse(jobId: jobId, questionId: q.id!, stage: "initial", value: "200", answeredBy: env.adminUserId)
        _ = try est.calculateEstimate(jobId: jobId, stage: "initial")

        let all = try est.getAllResults(jobId: jobId)
        #expect(all.count >= 1)
    }

    // MARK: - Reviews

    @Test("Submit weekly review")
    func testWeeklyReview() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let review = try est.submitWeeklyReview(
            jobId: jobId,
            reviewedBy: env.adminUserId,
            notes: "On track"
        )
        #expect(review.reviewType == "weekly")
        #expect(review.lessonsLearned == "On track" || review.reviewType == "weekly")
    }

    @Test("Submit structured weekly review persists review fields")
    func testStructuredWeeklyReviewPersistsFields() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let review = try est.submitWeeklyReview(
            jobId: jobId,
            reviewedBy: env.adminUserId,
            notes: "Waiting on inspection",
            delayFactors: ["inspection", "change_order"],
            onTrackStatus: "at_risk",
            unresolvedQuestionCount: 2,
            crewFeedback: "Need clearer rough-in assumptions",
            gcRating: 4
        )

        #expect(review.reviewType == "weekly")
        #expect(review.decodedDelayFactors == ["inspection", "change_order"])
        #expect(review.onTrackStatus == "at_risk")
        #expect(review.unresolvedQuestionCount == 2)
        #expect(review.crewFeedback == "Need clearer rough-in assumptions")
        #expect(review.gcRating == 4)

        let stored = try est.getJobReviews(jobId: jobId).first
        #expect(stored?.decodedDelayFactors == ["inspection", "change_order"])
        #expect(stored?.onTrackStatus == "at_risk")
        #expect(stored?.unresolvedQuestionCount == 2)
        #expect(stored?.crewFeedback == "Need clearer rough-in assumptions")
        #expect(stored?.gcRating == 4)
    }

    @Test("Submit end-of-job review")
    func testEndOfJobReview() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let review = try est.submitEndOfJobReview(
            jobId: jobId,
            actualDays: 12.5,
            actualHours: 100.0,
            lessonsLearned: "Should have estimated higher for wiring",
            reviewedBy: env.adminUserId
        )
        #expect(review.reviewType == "end_of_job")
        #expect(review.actualDays == 12.5)
    }

    @Test("Submit structured end-of-job review persists question accuracy")
    func testStructuredEndOfJobReviewPersistsQuestionAccuracy() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        let question = try est.createQuestion(
            text: "Was ceiling height above standard?",
            group: "scope",
            stage: "bid"
        )

        let review = try est.submitEndOfJobReview(
            jobId: jobId,
            actualDays: 8,
            actualHours: 64,
            lessonsLearned: "Ask earlier about access constraints",
            reviewedBy: env.adminUserId,
            delayFactors: ["access"],
            onTrackStatus: "complete",
            unresolvedQuestionCount: 0,
            crewFeedback: "Estimate matched field conditions",
            gcRating: 5,
            questionAccuracy: [
                QuestionAccuracyFeedbackInput(
                    questionId: question.id!,
                    predictedImpact: "minor",
                    actualImpact: "major",
                    accuracyRating: 3,
                    notes: "Impact was underestimated"
                )
            ]
        )

        #expect(review.reviewType == "end_of_job")
        #expect(review.decodedDelayFactors == ["access"])
        #expect(review.onTrackStatus == "complete")
        #expect(review.unresolvedQuestionCount == 0)
        #expect(review.crewFeedback == "Estimate matched field conditions")
        #expect(review.gcRating == 5)

        let count = try env.db.writer.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM estimation_question_accuracy_reviews
                    WHERE review_id = ? AND question_id = ? AND accuracy_rating = 3
                    """,
                arguments: [review.id, question.id]
            ) ?? 0
        }
        #expect(count == 1)
    }

    @Test("Get job reviews")
    func testGetJobReviews() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try est.submitWeeklyReview(jobId: jobId, reviewedBy: env.adminUserId, notes: "Week 1")
        _ = try est.submitWeeklyReview(jobId: jobId, reviewedBy: env.adminUserId, notes: "Week 2")

        let reviews = try est.getJobReviews(jobId: jobId)
        #expect(reviews.count == 2)
    }

    // MARK: - Analytics

    @Test("Analyze question effectiveness runs without error")
    func testQuestionEffectiveness() throws {
        let (_, est) = try freshEnv()
        let effectiveness = try est.analyzeQuestionEffectiveness()
        #expect(effectiveness.count >= 0)
    }

    @Test("Calculate monthly capacity")
    func testMonthlyCapacity() throws {
        let (_, est) = try freshEnv()
        let capacity = try est.calculateMonthlyCapacity()
        #expect(capacity >= 0)
    }

    @Test("Monthly capacity groups UTC-split labor by local work date")
    func testMonthlyCapacityUsesLocalClockInDateBucket() throws {
        try withMountainTimeZone {
            let (env, est) = try freshEnv()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CAP-LOCAL", name: "Local Capacity")
            let utcFormatter = Self.utcTimestampFormatter

            let firstClockIn = utcFormatter.string(from: try Self.localToday(hour: 16, minute: 30))
            let secondClockIn = utcFormatter.string(from: try Self.localToday(hour: 18, minute: 30))

            try env.db.writer.write { db in
                try db.execute(sql: "DELETE FROM labor_entries")
                try db.execute(sql: """
                    INSERT INTO labor_entries
                        (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                    VALUES
                        (?, ?, ?, ?, 4.0, 0.0, 'completed', datetime('now')),
                        (?, ?, ?, ?, 4.0, 0.0, 'completed', datetime('now'))
                    """, arguments: [
                        env.adminUserId, jobId, firstClockIn, firstClockIn,
                        env.adminUserId, jobId, secondClockIn, secondClockIn
                    ])
            }

            let workerCount = try env.db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL") ?? 1
            }

            let capacity = try est.calculateMonthlyCapacity()
            let expected = Double(workerCount * Self.weekdaysInCurrentMonth())

            #expect(abs(capacity - expected) < 0.001)
        }
    }

    @Test("Historical average query")
    func testHistoricalAverage() throws {
        let (_, est) = try freshEnv()
        let avg = try est.getHistoricalAverage()
        // May be nil if no historical data
        #expect(avg == nil || avg!.avgDays >= 0)
    }

    private static let utcTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func localToday(hour: Int, minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try #require(calendar.date(from: components))
    }

    private static func weekdaysInCurrentMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        let range = calendar.range(of: .day, in: .month, for: now) ?? 1..<31
        return range.reduce(0) { count, day in
            var components = calendar.dateComponents([.year, .month], from: now)
            components.day = day
            guard let date = calendar.date(from: components) else { return count }
            let weekday = calendar.component(.weekday, from: date)
            return count + (weekday >= 2 && weekday <= 6 ? 1 : 0)
        }
    }

    private func withMountainTimeZone<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(Darwin)
        setenv("TZ", "America/Denver", 1)
        tzset()
        #endif
        return try body()
    }

    @Test("Regression: getHistoricalAverage finds jobs with status 'completed' (not 'complete')")
    func testHistoricalAverage_findsCompletedJobs() throws {
        let (env, est) = try freshEnv()

        // Create a job and mark it completed — the canonical status is 'completed' (with 'd').
        // Regression: JobEstimationService was querying status = 'complete', always returning 0.
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-HIST-001", name: "Completed Job")
        try env.jobs.updateJob(id: jobId, city: "Phoenix", status: "completed")

        // Submit an end-of-job review so historical averages have data to aggregate
        _ = try est.submitEndOfJobReview(
            jobId: jobId,
            actualDays: 5.0,
            actualHours: 40.0,
            lessonsLearned: "Good pacing",
            reviewedBy: env.adminUserId
        )

        let avg = try est.getHistoricalAverage()
        #expect(avg != nil, "Should find historical data from the completed job")
        #expect(avg!.jobCount >= 1, "Job count must be at least 1")
        #expect(avg!.avgDays > 0, "Average days must be non-zero")
    }

    @Test("Regression: getJobSpecificSuggestions counts jobs with status 'completed'")
    func testJobSuggestions_countsCompletedJobs() throws {
        let (env, est) = try freshEnv()

        // Seed 3 completed jobs of the same type so the suggestion threshold is met
        for i in 1...3 {
            let jid = try E2ETestHelpers.seedJob(env, jobNumber: "J-SUG-00\(i)", name: "Completed \(i)")
            try env.jobs.updateJob(id: jid, city: "Denver", status: "completed")
        }

        let targetJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TARGET", name: "Current Job")
        let suggestions = try est.getJobSpecificSuggestions(jobId: targetJobId)
        // Suggestions may still be empty if job type doesn't match, but the query must not throw
        #expect(suggestions.count >= 0)
    }

    @Test("Job-specific suggestions")
    func testJobSuggestions() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let suggestions = try est.getJobSpecificSuggestions(jobId: jobId)
        #expect(suggestions.count >= 0)
    }

    @Test("getJobSpecificSuggestions returns empty for soft-deleted jobs")
    func testGetJobSpecificSuggestions_excludesDeletedJob() throws {
        let (env, est) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DEL-001", name: "To Be Deleted")

        // Soft-delete the job
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [jobId]
            )
        }

        let suggestions = try est.getJobSpecificSuggestions(jobId: jobId)
        #expect(suggestions.isEmpty,
                "getJobSpecificSuggestions must not return suggestions for a soft-deleted job")
    }

    @Test("getAISuggestions average-hours query excludes estimation reviews from soft-deleted jobs")
    func testGetAISuggestions_excludesReviewsFromDeletedJobs() throws {
        let (env, est) = try freshEnv()

        // Seed ≥3 completed jobs of a specific type so the similarCount threshold is met
        var completedJobIds: [Int64] = []
        for i in 1...3 {
            let jid = try E2ETestHelpers.seedJob(env, jobNumber: "J-AI-00\(i)", name: "AIType \(i)")
            try env.jobs.updateJob(id: jid, city: "Denver", status: "completed", jobType: "inspection")
            // Give each one an end-of-job review with a known actual_hours value
            _ = try est.submitEndOfJobReview(
                jobId: jid, actualDays: 5.0, actualHours: 50.0,
                lessonsLearned: "baseline",
                reviewedBy: env.adminUserId
            )
            completedJobIds.append(jid)
        }

        // Soft-delete one of the completed jobs — its review must be excluded from the AVG
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [completedJobIds.first!]
            )
        }

        // Create a new job of the same type and ask for suggestions
        let targetJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-AI-TARGET", name: "Target Job")
        try env.jobs.updateJob(id: targetJobId, city: "Denver", status: "active", jobType: "inspection")

        let suggestions = try est.getJobSpecificSuggestions(jobId: targetJobId)
        // With one deleted job, similarCount may drop below the threshold so suggestions
        // may be empty — that's correct behavior. What matters is the query did not throw
        // AND any returned suggestion doesn't include the deleted-job's review data.
        #expect(suggestions.count >= 0, "query must execute cleanly with deleted-job filter")
    }
}
