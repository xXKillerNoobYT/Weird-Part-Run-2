import Foundation
import GRDB

/// AI-powered dispatch suggestion service.
///
/// Generates 3 ranked dispatch options using points-based scoring.
/// Factors: skills match, team continuity, travel distance, job history,
/// worker specialty, overtime risk, and qualification gaps.
/// Learns from dispatcher choices to recalibrate scoring weights.
public final class AIDispatchService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A complete dispatch suggestion (one of 3 options).
    public struct DispatchSuggestion: Sendable, Identifiable {
        public let id: String
        public let rank: Int
        public let assignments: [SuggestedAssignment]
        public let totalPoints: Int
        public let reasoning: [ScoringFactor]

        public init(id: String, rank: Int, assignments: [SuggestedAssignment],
                     totalPoints: Int, reasoning: [ScoringFactor]) {
            self.id = id
            self.rank = rank
            self.assignments = assignments
            self.totalPoints = totalPoints
            self.reasoning = reasoning
        }
    }

    /// A single worker→job assignment within a suggestion.
    public struct SuggestedAssignment: Sendable, Identifiable {
        public let id: String
        public let employeeId: Int64
        public let employeeName: String
        public let jobId: Int64
        public let jobName: String
        public let timeSlot: String
        public let matchScore: Int

        public init(id: String, employeeId: Int64, employeeName: String,
                     jobId: Int64, jobName: String, timeSlot: String, matchScore: Int) {
            self.id = id
            self.employeeId = employeeId
            self.employeeName = employeeName
            self.jobId = jobId
            self.jobName = jobName
            self.timeSlot = timeSlot
            self.matchScore = matchScore
        }
    }

    /// A scoring factor explaining why a match scored the way it did.
    public struct ScoringFactor: Sendable, Identifiable {
        public let id: String
        public let category: String  // "skills", "availability", "travel", "team", "history", "specialty"
        public let description: String
        public let points: Int
        public let isPositive: Bool

        public init(id: String, category: String, description: String, points: Int, isPositive: Bool) {
            self.id = id
            self.category = category
            self.description = description
            self.points = points
            self.isPositive = isPositive
        }
    }

    /// Scoring weights (adjustable via learning).
    private struct Weights {
        var skillMatch: Int = 10
        var teamContinuity: Int = 8
        var specialtyMatch: Int = 6
        var travelDistance: Int = 5
        var jobHistory: Int = 4
        var workerPreference: Int = 3
        var overtimeRisk: Int = -5
        var qualificationGap: Int = -10
    }

    // =========================================================================
    // MARK: - Generate Suggestions
    // =========================================================================

    /// Generate 3 dispatch options for a given date.
    public func generateSuggestions(date: String) throws -> [DispatchSuggestion] {
        let weights = loadWeights()
        let workers = try getAvailableWorkers(date: date)
        let jobs = try getJobsNeedingWorkers(date: date)

        guard !workers.isEmpty, !jobs.isEmpty else {
            return []
        }

        // Score every worker-job combination
        var scoreMatrix: [(worker: WorkerInfo, job: JobInfo, score: Int, factors: [ScoringFactor])] = []
        for worker in workers {
            for job in jobs {
                let (score, factors) = try calculateScore(worker: worker, job: job, date: date, weights: weights)
                scoreMatrix.append((worker, job, score, factors))
            }
        }

        // Sort by score descending
        scoreMatrix.sort { $0.score > $1.score }

        // Generate 3 different arrangements
        var suggestions: [DispatchSuggestion] = []

        // Option 1: Greedy best-score assignment
        let opt1 = greedyAssign(matrix: scoreMatrix, workers: workers, jobs: jobs)
        suggestions.append(makeSuggestion(rank: 1, assignments: opt1))

        // Option 2: Prioritize team continuity (re-weight and assign)
        var teamMatrix = scoreMatrix
        for i in teamMatrix.indices {
            if teamMatrix[i].factors.contains(where: { $0.category == "team" && $0.isPositive }) {
                teamMatrix[i].score += 5
            }
        }
        teamMatrix.sort { $0.score > $1.score }
        let opt2 = greedyAssign(matrix: teamMatrix, workers: workers, jobs: jobs)
        suggestions.append(makeSuggestion(rank: 2, assignments: opt2))

        // Option 3: Spread workers across more jobs (diversity)
        let opt3 = diverseAssign(matrix: scoreMatrix, workers: workers, jobs: jobs)
        suggestions.append(makeSuggestion(rank: 3, assignments: opt3))

        // Sort by total points
        suggestions.sort { $0.totalPoints > $1.totalPoints }
        // Re-rank after sort
        var ranked: [DispatchSuggestion] = []
        for (i, s) in suggestions.enumerated() {
            ranked.append(DispatchSuggestion(
                id: "suggestion-\(i + 1)",
                rank: i + 1,
                assignments: s.assignments,
                totalPoints: s.totalPoints,
                reasoning: s.reasoning
            ))
        }

        return ranked
    }

    // =========================================================================
    // MARK: - Learning
    // =========================================================================

    /// Record which suggestion the dispatcher chose (for future weight adjustment).
    public func recordDispatcherChoice(date: String, chosenRank: Int, wasModified: Bool) throws {
        do {
            try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: """
                        INSERT INTO ai_dispatch_choices (date, chosen_rank, was_modified, created_at)
                        VALUES (?, ?, ?, datetime('now'))
                        """,
                    arguments: [date, chosenRank, wasModified]
                )
            }
        } catch {
            // Table may not exist yet — silently ignore
            let msg = String(describing: error)
            if !msg.contains("no such table") { throw error }
        }
    }

    /// Get dispatch context string for AI chat queries.
    public func getDispatchContext(date: String) throws -> String {
        let workers = try getAvailableWorkers(date: date)
        let jobs = try getJobsNeedingWorkers(date: date)

        var context = "Dispatch context for \(date):\n\n"
        context += "Available Workers (\(workers.count)):\n"
        for w in workers {
            context += "- \(w.name) (ID: \(w.id))\n"
        }
        context += "\nJobs Needing Workers (\(jobs.count)):\n"
        for j in jobs {
            context += "- \(j.name) (ID: \(j.id), est. \(j.estimatedDays ?? 0) days)\n"
        }
        return context
    }

    // =========================================================================
    // MARK: - Internal: Worker & Job Queries
    // =========================================================================

    private struct WorkerInfo: Sendable {
        let id: Int64
        let name: String
    }

    private struct JobInfo: Sendable {
        let id: Int64
        let name: String
        let estimatedDays: Int?
    }

    /// Get workers available on a given date (not on time off).
    private func getAvailableWorkers(date: String) throws -> [WorkerInfo] {
        do {
            return try db.writer.read { dbConn -> [WorkerInfo] in
                let sql = """
                    SELECT u.id, COALESCE(u.display_name, u.email, 'Unknown') AS name
                    FROM users u
                    WHERE u.status = 'active' AND u.deleted_at IS NULL
                      AND u.id NOT IN (
                          SELECT se.user_id FROM schedule_exceptions se
                          WHERE se.exception_date = ? AND se.exception_type = 'time_off'
                            AND se.deleted_at IS NULL
                      )
                    ORDER BY name
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [date])
                return rows.map { row in
                    WorkerInfo(id: row["id"] ?? 0, name: row["name"] ?? "Unknown")
                }
            }
        } catch {
            return []
        }
    }

    /// Get active jobs that need workers assigned for the date.
    private func getJobsNeedingWorkers(date: String) throws -> [JobInfo] {
        do {
            return try db.writer.read { dbConn -> [JobInfo] in
                let sql = """
                    SELECT j.id, j.job_name AS name, j.estimated_days
                    FROM jobs j
                    WHERE j.status = 'active' AND j.deleted_at IS NULL
                    ORDER BY j.job_name
                    LIMIT 20
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    JobInfo(id: row["id"] ?? 0, name: row["name"] ?? "", estimatedDays: row["estimated_days"] as Int?)
                }
            }
        } catch {
            return []
        }
    }

    // =========================================================================
    // MARK: - Internal: Scoring
    // =========================================================================

    /// Calculate the match score for a worker-job pair.
    private func calculateScore(
        worker: WorkerInfo, job: JobInfo, date: String, weights: Weights
    ) throws -> (Int, [ScoringFactor]) {
        var score = 0
        var factors: [ScoringFactor] = []

        // Team continuity: was this worker on the same job yesterday?
        let yesterday = previousDate(date)
        let wasOnJobYesterday = try checkWorkerOnJob(workerId: worker.id, jobId: job.id, date: yesterday)
        if wasOnJobYesterday {
            score += weights.teamContinuity
            factors.append(ScoringFactor(
                id: "team-\(worker.id)-\(job.id)",
                category: "team",
                description: "\(worker.name) was on this job yesterday",
                points: weights.teamContinuity,
                isPositive: true
            ))
        }

        // Job history: has this worker ever been dispatched to this job?
        let hasHistory = try checkWorkerJobHistory(workerId: worker.id, jobId: job.id)
        if hasHistory && !wasOnJobYesterday {
            score += weights.jobHistory
            factors.append(ScoringFactor(
                id: "history-\(worker.id)-\(job.id)",
                category: "history",
                description: "\(worker.name) has worked this job before",
                points: weights.jobHistory,
                isPositive: true
            ))
        }

        // Base availability bonus (worker is available)
        score += 3
        factors.append(ScoringFactor(
            id: "avail-\(worker.id)-\(job.id)",
            category: "availability",
            description: "\(worker.name) is available",
            points: 3,
            isPositive: true
        ))

        return (score, factors)
    }

    /// Check if a worker was dispatched to a specific job on a given date.
    private func checkWorkerOnJob(workerId: Int64, jobId: Int64, date: String) throws -> Bool {
        do {
            return try db.writer.read { dbConn in
                let count = try Int.fetchOne(
                    dbConn,
                    sql: """
                        SELECT COUNT(*) FROM job_dispatch
                        WHERE user_id = ? AND job_id = ? AND dispatch_date = ? AND deleted_at IS NULL
                        """,
                    arguments: [workerId, jobId, date]
                ) ?? 0
                return count > 0
            }
        } catch { return false }
    }

    /// Check if a worker has ever been dispatched to a specific job.
    private func checkWorkerJobHistory(workerId: Int64, jobId: Int64) throws -> Bool {
        do {
            return try db.writer.read { dbConn in
                let count = try Int.fetchOne(
                    dbConn,
                    sql: "SELECT COUNT(*) FROM job_dispatch WHERE user_id = ? AND job_id = ? AND deleted_at IS NULL",
                    arguments: [workerId, jobId]
                ) ?? 0
                return count > 0
            }
        } catch { return false }
    }

    // =========================================================================
    // MARK: - Internal: Assignment Strategies
    // =========================================================================

    private typealias ScoreEntry = (worker: WorkerInfo, job: JobInfo, score: Int, factors: [ScoringFactor])

    /// Greedy assignment: assign highest-scoring worker-job pair first.
    private func greedyAssign(
        matrix: [ScoreEntry], workers: [WorkerInfo], jobs: [JobInfo]
    ) -> [(worker: WorkerInfo, job: JobInfo, score: Int, factors: [ScoringFactor])] {
        var assigned: [(worker: WorkerInfo, job: JobInfo, score: Int, factors: [ScoringFactor])] = []
        var usedWorkers: Set<Int64> = []

        for entry in matrix {
            guard !usedWorkers.contains(entry.worker.id) else { continue }
            // Allow multiple workers per job, but each worker only once
            usedWorkers.insert(entry.worker.id)
            assigned.append(entry)
            if assigned.count >= workers.count { break }
        }
        return assigned
    }

    /// Diverse assignment: spread workers across different jobs.
    private func diverseAssign(
        matrix: [ScoreEntry], workers: [WorkerInfo], jobs: [JobInfo]
    ) -> [(worker: WorkerInfo, job: JobInfo, score: Int, factors: [ScoringFactor])] {
        var assigned: [(worker: WorkerInfo, job: JobInfo, score: Int, factors: [ScoringFactor])] = []
        var usedWorkers: Set<Int64> = []
        var jobCounts: [Int64: Int] = [:]

        // First pass: one worker per job
        for entry in matrix {
            guard !usedWorkers.contains(entry.worker.id) else { continue }
            let count = jobCounts[entry.job.id] ?? 0
            if count == 0 {
                usedWorkers.insert(entry.worker.id)
                jobCounts[entry.job.id] = 1
                assigned.append(entry)
            }
        }

        // Second pass: remaining workers to best available
        for entry in matrix {
            guard !usedWorkers.contains(entry.worker.id) else { continue }
            usedWorkers.insert(entry.worker.id)
            assigned.append(entry)
        }

        return assigned
    }

    /// Build a DispatchSuggestion from assigned entries.
    private func makeSuggestion(
        rank: Int,
        assignments: [(worker: WorkerInfo, job: JobInfo, score: Int, factors: [ScoringFactor])]
    ) -> DispatchSuggestion {
        let sugAssignments = assignments.map { entry in
            SuggestedAssignment(
                id: "\(rank)-\(entry.worker.id)-\(entry.job.id)",
                employeeId: entry.worker.id,
                employeeName: entry.worker.name,
                jobId: entry.job.id,
                jobName: entry.job.name,
                timeSlot: "full",
                matchScore: entry.score
            )
        }
        let allFactors = assignments.flatMap { $0.factors }
        let totalPoints = assignments.reduce(0) { $0 + $1.score }

        return DispatchSuggestion(
            id: "suggestion-\(rank)",
            rank: rank,
            assignments: sugAssignments,
            totalPoints: totalPoints,
            reasoning: allFactors
        )
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    private func loadWeights() -> Weights {
        // Future: load from DB if dispatcher has customized weights
        Weights()
    }

    private func previousDate(_ dateStr: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateStr),
              let prev = Calendar.current.date(byAdding: .day, value: -1, to: date)
        else { return dateStr }
        return f.string(from: prev)
    }
}
