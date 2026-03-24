import Foundation
import GRDB

// MARK: - EstimationQuestion

/// A configurable question asked at a specific stage of job estimation.
public struct EstimationQuestion: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "estimation_questions"

    public var id: Int64?
    public var questionText: String
    public var questionGroup: String    // scope, complexity, access, materials, labor
    public var stage: String            // bid, pre_start, during, before_trim, punch_list
    public var answerType: String       // number, choice, boolean, text
    public var choices: String?         // JSON array for choice type
    public var weight: Double
    public var isActive: Int
    public var sortOrder: Int
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case questionGroup = "question_group"
        case stage
        case answerType = "answer_type"
        case choices, weight
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Decode the choices JSON string into an array of strings.
    public var decodedChoices: [String]? {
        guard let choices, let data = choices.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}

// MARK: - EstimationResponse

/// A response to an estimation question for a specific job and stage.
public struct EstimationResponse: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "estimation_responses"

    public var id: Int64?
    public var jobId: Int64
    public var questionId: Int64
    public var stage: String
    public var responseValue: String?
    public var isUnknown: Int           // 1 = "?" response
    public var answeredBy: Int64?
    public var answeredAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case questionId = "question_id"
        case stage
        case responseValue = "response_value"
        case isUnknown = "is_unknown"
        case answeredBy = "answered_by"
        case answeredAt = "answered_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EstimationResult

/// A calculated estimation result for a job at a specific stage.
public struct EstimationResult: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "estimation_results"

    public var id: Int64?
    public var jobId: Int64
    public var stage: String
    public var estimatedDays: Double?
    public var estimatedHours: Double?
    public var confidencePercent: Double?
    public var aiSuggested: Int
    public var notes: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case stage
        case estimatedDays = "estimated_days"
        case estimatedHours = "estimated_hours"
        case confidencePercent = "confidence_percent"
        case aiSuggested = "ai_suggested"
        case notes
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EstimationReview

/// A weekly or end-of-job review comparing estimates to actuals.
public struct EstimationReview: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "estimation_reviews"

    public var id: Int64?
    public var jobId: Int64
    public var reviewType: String       // weekly, end_of_job
    public var actualDays: Double?
    public var actualHours: Double?
    public var estimateAtStart: Double?
    public var variancePercent: Double?
    public var lessonsLearned: String?
    public var reviewedBy: Int64?
    public var reviewedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case reviewType = "review_type"
        case actualDays = "actual_days"
        case actualHours = "actual_hours"
        case estimateAtStart = "estimate_at_start"
        case variancePercent = "variance_percent"
        case lessonsLearned = "lessons_learned"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EstimationQuestionRejection

/// Logged when a question is rejected/deactivated; AI can reconsider later.
public struct EstimationQuestionRejection: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "estimation_question_rejections"

    public var id: Int64?
    public var questionId: Int64
    public var rejectedBy: Int64?
    public var reason: String?
    public var rejectedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionId = "question_id"
        case rejectedBy = "rejected_by"
        case reason
        case rejectedAt = "rejected_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Non-Persisted Result Types

/// Historical average data for similar jobs.
public struct HistoricalAverage: Sendable {
    public let jobCount: Int
    public let avgDays: Double
    public let avgHours: Double
    public let minDays: Double
    public let maxDays: Double
}

/// Question effectiveness score from AI analysis.
public struct QuestionEffectiveness: Identifiable, Sendable {
    public let id: Int64
    public let questionText: String
    public let correlationScore: Double     // 0-1
    public let timesAsked: Int
    public let timesUnknown: Int
    public let recommendation: String       // keep, modify, remove, needs_more_data
}
