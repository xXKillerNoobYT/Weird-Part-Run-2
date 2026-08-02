import Foundation
import CryptoKit
import GRDB

/// Agent Link (MCP) — link lifecycle + audit trail.
///
/// Plan: `docs/plans/devices-add-mcp-agent-link.md` (owner decisions
/// 2026-08-01). The app serves MCP to AI desktop apps (Claude/GPT) on the
/// SAME Mac only; `AgentLinkServer` binds strictly to loopback. This service
/// owns everything durable: minting per-agent bearer tokens (returned exactly
/// once, stored only as SHA-256 hex — `String.hashValue` is banned for
/// anything stable, and plain hashes of low-entropy input would be crackable,
/// so tokens are 32 random bytes), verification, revocation, and the
/// append-only `agent_link_calls` audit trail surfaced on the Devices page.
public final class AgentLinkService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Model

    public enum Scope: String, Sendable, CaseIterable {
        /// The seven read-only tools.
        case read
        /// Reads plus the single v1 write: append a job note.
        case readNotes = "read_notes"

        /// Whether this scope may invoke the named tool.
        public func allows(tool: String) -> Bool {
            switch self {
            case .read:
                return tool != "job_note_append"
            case .readNotes:
                return true
            }
        }
    }

    public struct AgentLink: Sendable, Equatable, Identifiable {
        public let id: Int64
        public let name: String
        public let scope: Scope
        /// User who created the link; the write tool acts as this user.
        public let createdBy: Int64?
        public let createdAt: String
        public let lastSeenAt: String?
        public let callCount: Int
        public let revokedAt: String?

        public var isRevoked: Bool { revokedAt != nil }
    }

    public struct AuditEntry: Sendable, Equatable {
        public let tool: String
        public let status: String
        public let createdAt: String
    }

    public enum AgentLinkError: Error, Equatable {
        case linkNotFound
    }

    // MARK: - Token handling

    /// Random 32-byte token, base64url without padding, `wpal_` prefixed so a
    /// leaked string is recognizable in logs/scanners as a WiredPart agent key.
    static func mintToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        let b64 = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "wpal_" + b64
    }

    static func tokenHash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Lifecycle

    /// Create a link. The returned token is shown ONCE and never recoverable —
    /// only its SHA-256 lands in the database.
    public func createLink(
        name: String, scope: Scope, createdBy: Int64? = nil
    ) throws -> (link: AgentLink, token: String) {
        let token = Self.mintToken()
        let hash = Self.tokenHash(token)
        let link = try db.writer.write { dbc -> AgentLink in
            try dbc.execute(
                sql: """
                INSERT INTO agent_links (name, scope, token_hash, created_by) VALUES (?, ?, ?, ?)
                """,
                arguments: [name, scope.rawValue, hash, createdBy]
            )
            let id = dbc.lastInsertedRowID
            guard let row = try Row.fetchOne(
                dbc, sql: "SELECT * FROM agent_links WHERE id = ?", arguments: [id]
            ) else { throw AgentLinkError.linkNotFound }
            return Self.link(from: row)
        }
        return (link, token)
    }

    /// All links, newest first, revoked included (the UI shows them struck).
    public func listLinks() throws -> [AgentLink] {
        try db.writer.read { dbc in
            try Row.fetchAll(dbc, sql: "SELECT * FROM agent_links ORDER BY id DESC")
                .map(Self.link(from:))
        }
    }

    /// Revoke immediately; verification fails from the next request on.
    /// Revoking twice keeps the original revocation time.
    public func revoke(linkId: Int64) throws {
        let changed = try db.writer.write { dbc -> Int in
            try dbc.execute(
                sql: """
                UPDATE agent_links SET revoked_at = datetime('now')
                WHERE id = ? AND revoked_at IS NULL
                """,
                arguments: [linkId]
            )
            return dbc.changesCount
        }
        if changed == 0 {
            // Distinguish "already revoked" (fine) from "no such link".
            let exists = try db.writer.read { dbc in
                try Bool.fetchOne(
                    dbc, sql: "SELECT EXISTS(SELECT 1 FROM agent_links WHERE id = ?)",
                    arguments: [linkId]
                ) ?? false
            }
            if !exists { throw AgentLinkError.linkNotFound }
        }
    }

    /// Resolve a bearer token to its active link; nil for unknown or revoked.
    public func verify(token: String) throws -> AgentLink? {
        guard let found = try lookup(token: token), found.active else { return nil }
        return found.link
    }

    /// Like `verify`, but also matches revoked links so the server can audit
    /// an attempt on a revoked token against the link it belonged to.
    public func lookup(token: String) throws -> (link: AgentLink, active: Bool)? {
        let hash = Self.tokenHash(token)
        return try db.writer.read { dbc in
            try Row.fetchOne(
                dbc,
                sql: "SELECT * FROM agent_links WHERE token_hash = ?",
                arguments: [hash]
            ).map { row in
                let link = Self.link(from: row)
                return (link, !link.isRevoked)
            }
        }
    }

    // MARK: - Audit

    /// Record one tool call (or auth failure) and refresh the link's
    /// last-seen/call-count counters in the same transaction.
    public func recordCall(
        linkId: Int64,
        tool: String,
        argumentDigest: String?,
        status: String
    ) throws {
        try db.writer.write { dbc in
            try dbc.execute(
                sql: """
                INSERT INTO agent_link_calls (link_id, tool, argument_digest, status)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [linkId, tool, argumentDigest, status]
            )
            try dbc.execute(
                sql: """
                UPDATE agent_links
                SET last_seen_at = datetime('now'), call_count = call_count + 1
                WHERE id = ?
                """,
                arguments: [linkId]
            )
        }
    }

    public func auditTrail(linkId: Int64, limit: Int = 100) throws -> [AuditEntry] {
        try db.writer.read { dbc in
            try Row.fetchAll(
                dbc,
                sql: """
                SELECT tool, status, created_at FROM agent_link_calls
                WHERE link_id = ? ORDER BY id DESC LIMIT ?
                """,
                arguments: [linkId, limit]
            ).map { AuditEntry(tool: $0["tool"], status: $0["status"], createdAt: $0["created_at"]) }
        }
    }

    // MARK: - Row mapping

    private static func link(from row: Row) -> AgentLink {
        AgentLink(
            id: row["id"],
            name: row["name"],
            scope: Scope(rawValue: row["scope"]) ?? .read,
            createdBy: row["created_by"],
            createdAt: row["created_at"],
            lastSeenAt: row["last_seen_at"],
            callCount: row["call_count"],
            revokedAt: row["revoked_at"]
        )
    }
}
