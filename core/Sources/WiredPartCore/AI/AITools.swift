import Foundation
import GRDB

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Tool Definitions

/// Tools that the Foundation Models LLM can call to query the local database.
/// Each tool conforms to the FoundationModels `Tool` protocol and uses
/// `@Generable` for its arguments so the model can generate structured calls.
///
/// These tools are only available on macOS 26+ / iOS 26+ where the
/// FoundationModels framework exists.

#if canImport(FoundationModels)

// MARK: - Search Parts Tool

@available(macOS 26.0, iOS 26.0, *)
public struct SearchPartsTool: FoundationModels.Tool {
    public let name = "searchParts"
    public let description = "Search the parts catalog by name, SKU, or category"

    @Generable
    public struct Arguments {
        @Guide(description: "Search query for parts")
        var query: String
    }

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_parts_catalog") else {
            return "You don't have permission to search parts. Ask your admin for access."
        }
        let service = PartsService(db: db)
        let results = try service.searchParts(query: arguments.query, limit: 5)
        if results.isEmpty {
            return "No parts found matching '\(arguments.query)'"
        }
        return results.map { "- \($0.name) (Code: \($0.code ?? "N/A"))" }
            .joined(separator: "\n")
    }
}

// MARK: - Search Contacts Tool

@available(macOS 26.0, iOS 26.0, *)
public struct SearchContactsTool: FoundationModels.Tool {
    public let name = "searchContacts"
    public let description = "Search for customers and contacts by name or company"

    @Generable
    public struct Arguments {
        @Guide(description: "Search query for contacts")
        var query: String
    }

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_people") else {
            return "You don't have permission to search contacts. Ask your admin for access."
        }
        let service = PeopleService(db: db)
        let customers = try service.listCustomers(search: arguments.query)
        if customers.isEmpty {
            return "No contacts found matching '\(arguments.query)'"
        }
        return customers.prefix(5).map {
            "- \($0.companyName ?? "Unknown") (Contact: \($0.contactName ?? "N/A"), Email: \($0.email ?? "N/A"))"
        }.joined(separator: "\n")
    }
}

// MARK: - Search Jobs Tool

@available(macOS 26.0, iOS 26.0, *)
public struct SearchJobsTool: FoundationModels.Tool {
    public let name = "searchJobs"
    public let description = "Search for jobs by name, number, or status"

    @Generable
    public struct Arguments {
        @Guide(description: "Search query for jobs")
        var query: String
    }

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_jobs") else {
            return "You don't have permission to search jobs. Ask your admin for access."
        }
        let service = JobsService(db: db)
        let jobs = try service.listJobs(search: arguments.query, limit: 5)
        if jobs.isEmpty {
            return "No jobs found matching '\(arguments.query)'"
        }
        return jobs.map {
            "- \($0.jobName) (#\($0.jobNumber), Status: \($0.status))"
        }.joined(separator: "\n")
    }
}

// MARK: - Get Supplier Info Tool

@available(macOS 26.0, iOS 26.0, *)
public struct GetSupplierInfoTool: FoundationModels.Tool {
    public let name = "getSupplierInfo"
    public let description = "Look up supplier details by name, including contact info and linked parts/brands"

    @Generable
    public struct Arguments {
        @Guide(description: "Search query for supplier name")
        var query: String
    }

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_parts_catalog") else {
            return "You don't have permission to look up suppliers. Ask your admin for access."
        }
        let service = PartsService(db: db)
        let results = try service.listSuppliers(search: arguments.query)
        if results.isEmpty {
            return "No suppliers found matching '\(arguments.query)'"
        }
        return results.prefix(5).map { item in
            let s = item.supplier
            var line = "- \(s.name)"
            if let contact = s.contactName { line += " (Contact: \(contact))" }
            if let phone = s.phone { line += " Phone: \(phone)" }
            if let email = s.email { line += " Email: \(email)" }
            line += " | \(item.brandCount) brand(s)"
            return line
        }.joined(separator: "\n")
    }
}

// MARK: - List Companion Rules Tool

@available(macOS 26.0, iOS 26.0, *)
public struct ListCompanionRulesTool: FoundationModels.Tool {
    public let name = "listCompanionRules"
    public let description = "List all companion rules showing which categories/styles/types are linked together. Use this to explain what companion rules exist and how they work."

    @Generable
    public struct Arguments {}

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_parts_catalog") else {
            return "You don't have permission to view companion rules."
        }
        let service = PartsService(db: db)
        let rules = try service.listCompanionRulesHierarchy()
        if rules.isEmpty { return "No companion rules exist yet." }
        var result = "Active Companion Rules (\(rules.count)):\n\n"
        for rule in rules {
            let srcNames = rule.sources.map { src in
                "Category \(src.categoryId)" + (src.styleId != nil ? " > Style \(src.styleId!)" : "")
            }.joined(separator: ", ")
            let tgtNames = rule.targets.map { tgt in
                "Category \(tgt.categoryId)" + (tgt.styleId != nil ? " > Style \(tgt.styleId!)" : "")
            }.joined(separator: ", ")
            result += "• \(rule.name) [\(rule.matchLevel)] — \(srcNames) → \(tgtNames)"
            if rule.tryMatchBrand == 1 { result += " [Brand Match]" }
            if rule.autoColorMatch == 1 { result += " [Color Match]" }
            if rule.isOrphaned { result += " ⚠️ ORPHANED" }
            if rule.childCount > 0 { result += " (\(rule.childCount) sub-rules)" }
            result += "\n"
        }
        return result
    }
}

// MARK: - Get Active Polls Tool

@available(macOS 26.0, iOS 26.0, *)
public struct GetActiveCompanionPollsTool: FoundationModels.Tool {
    public let name = "getActivePolls"
    public let description = "Get currently active companion polls that users are voting on. Shows what category pairings are being proposed."

    @Generable
    public struct Arguments {}

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_parts_catalog") else {
            return "You don't have permission to view companion polls."
        }
        let service = PartsService(db: db)
        let polls = try service.getActivePolls(userId: 0, isAdmin: false)
        if polls.isEmpty {
            return "No active polls right now. The system needs at least 3 months of ordering data to start suggesting companion rules."
        }
        var result = "Active Polls (\(polls.count)):\n\n"
        for poll in polls {
            result += "• \(poll.proposedRuleName) [\(poll.matchLevel)]\n"
            result += "  \(poll.sourceName) → \(poll.targetName)\n"
            result += "  Status: \(poll.status), \(poll.daysRemaining) days remaining\n"
            result += "  Total votes: \(poll.totalVotes)\n\n"
        }
        return result
    }
}

// MARK: - Explain Co-Occurrence Tool

@available(macOS 26.0, iOS 26.0, *)
public struct ExplainCoOccurrenceTool: FoundationModels.Tool {
    public let name = "explainCoOccurrence"
    public let description = "Explain why a specific category pairing was suggested by showing the co-occurrence data: how many jobs had both categories, total points, and confidence score."

    @Generable
    public struct Arguments {
        @Guide(description: "First category name")
        var categoryA: String
        @Guide(description: "Second category name")
        var categoryB: String
    }

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_parts_catalog") else {
            return "You don't have permission to view co-occurrence data."
        }
        let catASearch = "%\(arguments.categoryA.lowercased())%"
        let catBSearch = "%\(arguments.categoryB.lowercased())%"
        let catAName = arguments.categoryA
        let catBName = arguments.categoryB
        let row: Row? = try db.writer.read { dbConn -> Row? in
            try Row.fetchOne(dbConn, sql: """
                SELECT cop.points, cop.co_occurrence_count, cop.confidence,
                       cop.rejection_count, cop.is_blocked, cop.match_level,
                       ca.name AS cat_a_name, cb.name AS cat_b_name
                FROM co_occurrence_pairs cop
                JOIN part_categories ca ON ca.id = cop.category_a_id
                JOIN part_categories cb ON cb.id = cop.category_b_id
                WHERE (LOWER(ca.name) LIKE ? AND LOWER(cb.name) LIKE ?)
                   OR (LOWER(ca.name) LIKE ? AND LOWER(cb.name) LIKE ?)
                LIMIT 1
                """, arguments: [catASearch, catBSearch, catBSearch, catASearch])
        }
        guard let row = row else {
            return "No co-occurrence data found for '\(catAName)' and '\(catBName)'. These categories may not appear together on jobs."
        }
        let catA: String = row["cat_a_name"] ?? "Unknown"
        let catB: String = row["cat_b_name"] ?? "Unknown"
        let pts: Int = row["points"] ?? 0
        let count: Int = row["co_occurrence_count"] ?? 0
        let conf: Double = row["confidence"] ?? 0.0
        let level: String = row["match_level"] ?? "category"
        let rejections: Int = row["rejection_count"] ?? 0
        let blocked: Int = row["is_blocked"] ?? 0
        return """
        Co-occurrence: \(catA) + \(catB)
        Points: \(pts)
        Co-occurred on \(count) jobs
        Confidence: \(Int(conf * 100))%
        Level: \(level)
        Rejections: \(rejections)\(blocked == 1 ? " (BLOCKED)" : "")
        """
    }
}

// MARK: - Get Voting Summary Tool

@available(macOS 26.0, iOS 26.0, *)
public struct GetVotingSummaryTool: FoundationModels.Tool {
    public let name = "getVotingSummary"
    public let description = "Get a summary of recent poll results and voting patterns. Shows which pairings passed or failed."

    @Generable
    public struct Arguments {}

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_parts_catalog") else {
            return "You don't have permission to view voting data."
        }
        let service = PartsService(db: db)
        let results = try service.getLastWeekResults(userId: 0)
        if results.isEmpty { return "No poll results from the past week." }
        var result = "Recent Poll Results:\n\n"
        for r in results {
            result += "• \(r.pollName): \(r.passed ? "Passed" : "Didn't Pass")\n"
        }
        return result
    }
}

// MARK: - Get Forecast Data Tool

@available(macOS 26.0, iOS 26.0, *)
public struct GetForecastDataTool: FoundationModels.Tool {
    public let name = "getForecastData"
    public let description = """
        Get demand forecasting data for parts. Returns parts with their average daily usage (ADU), \
        reorder points, suggested order quantities, and days until low stock. \
        Can filter by urgency level (critical, warning, healthy) or search by part name.
        """

    @Generable
    public struct Arguments {
        @Guide(description: "Urgency filter: critical (≤7 days), warning (7-30 days), healthy (>30 days), or omit for all")
        var urgency: String?
        @Guide(description: "Search by part name or code")
        var search: String?
        @Guide(description: "Maximum results to return (default 10, max 25)")
        var limit: Int?
    }

    private let db: AppDatabase
    private let permissions: [String]

    public init(db: AppDatabase, permissions: [String]) {
        self.db = db
        self.permissions = permissions
    }

    public func call(arguments: Arguments) async throws -> String {
        guard permissions.contains("view_parts_catalog") || permissions.contains("admin") else {
            return "You don't have permission to view forecast data."
        }

        // Extract values before the @Sendable closure to avoid capturing non-Sendable Arguments
        let urgency = arguments.urgency?.lowercased()
        let search = arguments.search
        let maxLimit = min(arguments.limit ?? 10, 25)

        return try await db.writer.read { dbConn in
            var whereClauses = ["p.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []

            if let urgency {
                switch urgency {
                case "critical":
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) <= 7")
                case "warning":
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) > 7")
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) <= 30")
                case "healthy":
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) > 30")
                default:
                    break
                }
            }

            if let search, !search.isEmpty {
                whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                let pattern = "%\(search)%"
                args.append(pattern)
                args.append(pattern)
            }

            args.append(maxLimit)

            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT p.name, p.code,
                       p.forecast_adu_30, p.forecast_adu_90,
                       p.forecast_reorder_point, p.forecast_suggested_order,
                       p.forecast_days_until_low, p.forecast_last_run,
                       COALESCE(SUM(s.qty), 0) AS current_stock
                FROM parts p
                LEFT JOIN stock s ON s.part_id = p.id AND s.deleted_at IS NULL
                WHERE \(whereClauses.joined(separator: " AND "))
                GROUP BY p.id
                ORDER BY COALESCE(p.forecast_days_until_low, 9999) ASC
                LIMIT ?
                """, arguments: StatementArguments(args))

            if rows.isEmpty {
                return "No parts found matching that criteria."
            }

            var result = "Found \(rows.count) parts:\n"
            for row in rows {
                let name: String = row["name"] ?? "?"
                let code: String? = row["code"]
                let adu30: Double? = row["forecast_adu_30"]
                let days: Int? = row["forecast_days_until_low"]
                let suggested: Int? = row["forecast_suggested_order"]
                let stock: Int = row["current_stock"] ?? 0

                var line = "• \(name)"
                if let c = code { line += " (\(c))" }
                line += " — Stock: \(stock)"
                if let d = days { line += ", \(d) days until low" }
                if let a = adu30 { line += ", ADU: \(String(format: "%.1f", a))/day" }
                if let s = suggested, s > 0 { line += ", suggest ordering \(s)" }
                result += line + "\n"
            }
            return result
        }
    }
}

#endif // canImport(FoundationModels)
