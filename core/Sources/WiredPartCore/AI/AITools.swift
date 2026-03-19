import Foundation

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

#endif // canImport(FoundationModels)
