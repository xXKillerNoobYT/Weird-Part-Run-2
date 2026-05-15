import Foundation
import GRDB

// MARK: - Part Confidence

/// Per part+area confidence score that decays daily and resets on audit.
public struct PartConfidence: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var partId: Int64
    public var areaId: Int64
    public var confidencePercent: Double
    public var reliabilityLevel: Int
    public var lastAuditDate: String?
    public var lastAuditBy: Int64?
    public var lastAuditCount: Int?
    public var systemCount: Int
    public var decayRate: Double
    public var movementDecayFactor: Double
    public var cleanAuditStreak: Int
    public var misplacementCount: Int
    public var lastMisplacementDate: String?
    public var totalAuditCount: Int
    public var totalVarianceDollars: Double
    public var createdAt: String?
    public var updatedAt: String?

    public static let databaseTableName = "part_confidence"

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case areaId = "area_id"
        case confidencePercent = "confidence_percent"
        case reliabilityLevel = "reliability_level"
        case lastAuditDate = "last_audit_date"
        case lastAuditBy = "last_audit_by"
        case lastAuditCount = "last_audit_count"
        case systemCount = "system_count"
        case decayRate = "decay_rate"
        case movementDecayFactor = "movement_decay_factor"
        case cleanAuditStreak = "clean_audit_streak"
        case misplacementCount = "misplacement_count"
        case lastMisplacementDate = "last_misplacement_date"
        case totalAuditCount = "total_audit_count"
        case totalVarianceDollars = "total_variance_dollars"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Audit Session V2

/// A counting/organization/speed/consensus audit session.
public struct AuditSessionV2: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var sessionType: String
    public var startedBy: Int64
    public var floorPlanId: Int64?
    public var targetAreaId: Int64?
    public var targetUnitId: Int64?
    public var status: String
    public var partsCounted: Int
    public var discrepanciesFound: Int
    public var misplacedFound: Int
    public var startedAt: String?
    public var completedAt: String?
    public var deletedAt: String?

    public static let databaseTableName = "audit_sessions_v2"

    enum CodingKeys: String, CodingKey {
        case id
        case sessionType = "session_type"
        case startedBy = "started_by"
        case floorPlanId = "floor_plan_id"
        case targetAreaId = "target_area_id"
        case targetUnitId = "target_unit_id"
        case status
        case partsCounted = "parts_counted"
        case discrepanciesFound = "discrepancies_found"
        case misplacedFound = "misplaced_found"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Audit Count

/// A single part count within an audit session.
public struct AuditCount: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var sessionId: Int64
    public var partId: Int64
    public var areaId: Int64
    public var systemCount: Int
    public var userCount: Int
    public var variance: Int
    public var varianceDollars: Double
    public var variancePercent: Double
    public var result: String
    public var countedBy: Int64
    public var countedAt: String?

    public static let databaseTableName = "audit_counts"

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case partId = "part_id"
        case areaId = "area_id"
        case systemCount = "system_count"
        case userCount = "user_count"
        case variance
        case varianceDollars = "variance_dollars"
        case variancePercent = "variance_percent"
        case result
        case countedBy = "counted_by"
        case countedAt = "counted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Misplaced Parts Log

/// Records a part found in the wrong location during audit.
public struct MisplacedPartsLog: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var partId: Int64
    public var foundAtAreaId: Int64
    public var homeAreaId: Int64?
    public var qtyFound: Int
    public var resolution: String
    public var resolvedBy: Int64?
    public var resolvedAt: String?
    public var foundBy: Int64
    public var foundAt: String?

    public static let databaseTableName = "misplaced_parts_log"

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case foundAtAreaId = "found_at_area_id"
        case homeAreaId = "home_area_id"
        case qtyFound = "qty_found"
        case resolution
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
        case foundBy = "found_by"
        case foundAt = "found_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - User Warehouse Rating

/// Per-user warehouse reliability score across multiple dimensions.
public struct UserWarehouseRating: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var userId: Int64
    public var overallRating: Double
    public var accuracyRating: Double
    public var effortRating: Double
    public var placementRating: Double
    public var wizardCompliance: Double
    public var speedRating: Double
    public var proactiveRating: Double
    public var totalAudits: Int
    public var totalAccurate: Int
    public var totalMisplacementsFound: Int
    public var totalProactiveFixes: Int
    public var updatedAt: String?

    public static let databaseTableName = "user_warehouse_ratings"

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case overallRating = "overall_rating"
        case accuracyRating = "accuracy_rating"
        case effortRating = "effort_rating"
        case placementRating = "placement_rating"
        case wizardCompliance = "wizard_compliance"
        case speedRating = "speed_rating"
        case proactiveRating = "proactive_rating"
        case totalAudits = "total_audits"
        case totalAccurate = "total_accurate"
        case totalMisplacementsFound = "total_misplacements_found"
        case totalProactiveFixes = "total_proactive_fixes"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Organization Rating

/// Per-area warehouse organization quality score.
public struct OrganizationRating: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var areaId: Int64
    public var overallRating: Double
    public var labelsAccurate: Bool
    public var partsInHome: Bool
    public var noDuplicates: Bool
    public var notOvercrowded: Bool
    public var binsAssigned: Bool
    public var similarPartsNearby: Bool
    public var cleanAuditCount: Int
    public var lastOrgCheck: String?
    public var lastOrgCheckBy: Int64?
    public var updatedAt: String?

    public static let databaseTableName = "organization_ratings"

    enum CodingKeys: String, CodingKey {
        case id
        case areaId = "area_id"
        case overallRating = "overall_rating"
        case labelsAccurate = "labels_accurate"
        case partsInHome = "parts_in_home"
        case noDuplicates = "no_duplicates"
        case notOvercrowded = "not_overcrowded"
        case binsAssigned = "bins_assigned"
        case similarPartsNearby = "similar_parts_nearby"
        case cleanAuditCount = "clean_audit_count"
        case lastOrgCheck = "last_org_check"
        case lastOrgCheckBy = "last_org_check_by"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Consolidation Vote

/// Suggestion to consolidate a part from multiple areas into one.
public struct ConsolidationVote: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var partId: Int64
    public var currentAreas: String
    public var chosenAreaId: Int64?
    public var status: String
    public var managerOverride: Bool
    public var dismissReason: String?
    public var ignoreCount: Int
    public var createdAt: String?
    public var decidedAt: String?
    public var deletedAt: String?

    public static let databaseTableName = "consolidation_votes"

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case currentAreas = "current_areas"
        case chosenAreaId = "chosen_area_id"
        case status
        case managerOverride = "manager_override"
        case dismissReason = "dismiss_reason"
        case ignoreCount = "ignore_count"
        case createdAt = "created_at"
        case decidedAt = "decided_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Multi-User Audit Assignment

/// Assignment for independent verification of low-confidence parts by multiple users.
/// When a part has low audit confidence, 2-3 different users are assigned to count it
/// independently. Results are compared to reach consensus.
public struct MultiUserAuditAssignment: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var partId: Int64
    public var partName: String
    public var binLocation: String?
    public var assignedUserId: Int64
    public var assignedUserName: String?
    public var countedQuantity: Int?
    public var countedAt: String?
    public var status: String  // "pending", "counted", "resolved"
    public var auditSessionId: Int64?
    public var expectedQuantity: Int?
    public var resolvedQuantity: Int?
    public var resolutionMethod: String?
    public var resolvedBy: Int64?
    public var resolvedAt: String?
    public var notes: String?
    public var createdAt: String?

    public static let databaseTableName = "multi_user_audit_assignments"

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case partName = "part_name"
        case binLocation = "bin_location"
        case assignedUserId = "assigned_user_id"
        case assignedUserName = "assigned_user_name"
        case countedQuantity = "counted_quantity"
        case countedAt = "counted_at"
        case status
        case auditSessionId = "audit_session_id"
        case expectedQuantity = "expected_quantity"
        case resolvedQuantity = "resolved_quantity"
        case resolutionMethod = "resolution_method"
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
        case notes
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Consolidation Vote Entry

/// An individual user's vote on a consolidation suggestion.
public struct ConsolidationVoteEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var voteId: Int64
    public var userId: Int64
    public var chosenAreaId: Int64
    public var votedAt: String?

    public static let databaseTableName = "consolidation_vote_entries"

    enum CodingKeys: String, CodingKey {
        case id
        case voteId = "vote_id"
        case userId = "user_id"
        case chosenAreaId = "chosen_area_id"
        case votedAt = "voted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
