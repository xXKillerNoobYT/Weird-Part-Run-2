import Foundation
import GRDB

// MARK: - Text Predictor

/// Context-aware text prediction engine for form fields.
///
/// Uses a 4-tier priority chain:
/// 1. **Entity lookup** (<10ms) — matches against parts, suppliers, jobs, etc.
/// 2. **Phrase history** (<20ms) — user's previous entries for this field type
/// 3. **Template expansion** (<5ms) — common abbreviations and templates
/// 4. **LLM generation** (<2s) — Foundation Models or llama.cpp for free-text
///
/// History is stored locally in `_text_history` (never synced, per-user keyed).
/// Auto-pruned to 1000 entries per field type, 90-day TTL.
public actor TextPredictor {
    private let db: AppDatabase
    private let aiService: FoundationModelsService?

    /// In-memory cache of recent predictions to avoid repeated DB lookups.
    private var predictionCache: [String: CachedPrediction] = [:]
    private let cacheMaxSize = 200
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    public init(db: AppDatabase, aiService: FoundationModelsService? = nil) {
        self.db = db
        self.aiService = aiService
    }

    // MARK: - Predict

    /// Generate predictions for a text field.
    ///
    /// Returns suggestions from the fastest available source, falling through
    /// the priority chain until results are found.
    ///
    /// - Parameters:
    ///   - partialText: What the user has typed so far.
    ///   - fieldType: The type of field (e.g. "supplier_name", "job_notes").
    ///   - entityType: If this is an entity-reference field, the entity type.
    ///   - contextData: Additional context for LLM predictions.
    ///   - userId: The current user's ID (for history isolation).
    /// - Returns: Up to 5 prediction suggestions, ordered by relevance.
    public func predict(
        partialText: String,
        fieldType: String,
        entityType: PredictionEntityType? = nil,
        contextData: [String: String]? = nil,
        userId: Int64? = nil
    ) async -> [PredictionSuggestion] {
        let trimmed = partialText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        // Check cache first
        let cacheKey = "\(fieldType):\(trimmed)"
        if let cached = predictionCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.suggestions
        }

        var suggestions: [PredictionSuggestion] = []

        // Tier 1: Entity lookup (for entity-reference fields)
        if let entityType {
            let entityResults = try? entityLookup(
                query: trimmed, entityType: entityType
            )
            if let results = entityResults, !results.isEmpty {
                suggestions = results
            }
        }

        // Tier 2: Phrase history
        if suggestions.count < 5 {
            let historyResults = try? phraseHistory(
                partialText: trimmed, fieldType: fieldType, userId: userId
            )
            if let results = historyResults {
                let existing = Set(suggestions.map(\.text))
                let newResults = results.filter { !existing.contains($0.text) }
                suggestions.append(contentsOf: newResults.prefix(5 - suggestions.count))
            }
        }

        // Tier 3: Template expansion
        if suggestions.count < 5 {
            let templateResults = templateExpansion(partialText: trimmed, fieldType: fieldType)
            let existing = Set(suggestions.map(\.text))
            let newResults = templateResults.filter { !existing.contains($0.text) }
            suggestions.append(contentsOf: newResults.prefix(5 - suggestions.count))
        }

        // Tier 4: LLM generation (only for free-text fields, skip for entity refs)
        if suggestions.isEmpty && entityType == nil && trimmed.count >= 10 {
            if let ai = aiService {
                let aiResult = await ai.generateCompletion(
                    partialText: trimmed,
                    fieldType: fieldType,
                    contextData: contextData
                )
                if aiResult.success, let text = aiResult.text {
                    suggestions.append(PredictionSuggestion(
                        text: text,
                        source: .llm,
                        confidence: 0.70
                    ))
                }
            }
        }

        // Cache results
        let result = Array(suggestions.prefix(5))
        updateCache(key: cacheKey, suggestions: result)

        return result
    }

    // MARK: - Record Entry

    /// Record a user's text entry for future predictions.
    ///
    /// Stores the entry in `_text_history` for this field type and user.
    /// Auto-prunes old entries beyond the retention limit.
    public func recordEntry(
        text: String,
        fieldType: String,
        userId: Int64
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 3 else { return }

        try db.writer.write { dbConnection in
            // Insert or update frequency count
            try dbConnection.execute(
                sql: """
                    INSERT INTO _text_history (user_id, field_type, text, frequency, last_used_at, created_at)
                    VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))
                    ON CONFLICT (user_id, field_type, text) DO UPDATE SET
                        frequency = frequency + 1,
                        last_used_at = datetime('now')
                    """,
                arguments: [userId, fieldType, trimmed]
            )

            // Prune old entries (keep max 1000 per field type per user)
            try dbConnection.execute(
                sql: """
                    DELETE FROM _text_history
                    WHERE user_id = ? AND field_type = ?
                    AND id NOT IN (
                        SELECT id FROM _text_history
                        WHERE user_id = ? AND field_type = ?
                        ORDER BY last_used_at DESC
                        LIMIT 1000
                    )
                    """,
                arguments: [userId, fieldType, userId, fieldType]
            )

            // Prune entries older than 90 days
            try dbConnection.execute(
                sql: """
                    DELETE FROM _text_history
                    WHERE last_used_at < datetime('now', '-90 days')
                    """
            )
        }
    }

    // MARK: - Generate Pre-Fill

    /// Generate a complete pre-fill for an empty form field.
    ///
    /// Uses context data and the most common previous entries to suggest
    /// a full field value.
    public func generatePreFill(
        fieldType: String,
        contextData: [String: String],
        userId: Int64
    ) async -> String? {
        // First try: most frequent entry for this field type
        let topEntry: String? = try? await db.writer.read { dbConnection in
            try String.fetchOne(
                dbConnection,
                sql: """
                    SELECT text FROM _text_history
                    WHERE user_id = ? AND field_type = ?
                    ORDER BY frequency DESC, last_used_at DESC
                    LIMIT 1
                    """,
                arguments: [userId, fieldType]
            )
        }

        if let entry = topEntry {
            return entry
        }

        // Fallback: LLM pre-fill
        if let ai = aiService {
            let result = await ai.generatePreFill(
                fieldType: fieldType,
                contextData: contextData
            )
            return result.success ? result.text : nil
        }

        return nil
    }

    // MARK: - Clear History

    /// Clear all prediction history for a user.
    public func clearHistory(userId: Int64) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "DELETE FROM _text_history WHERE user_id = ?",
                arguments: [userId]
            )
        }
        predictionCache.removeAll()
    }

    // MARK: - Tier 1: Entity Lookup

    private func entityLookup(
        query: String,
        entityType: PredictionEntityType
    ) throws -> [PredictionSuggestion] {
        let (tableName, nameColumn) = entityType.tableAndColumn

        let results: [String] = try db.writer.read { dbConnection in
            try String.fetchAll(
                dbConnection,
                sql: """
                    SELECT \(nameColumn) FROM \(tableName)
                    WHERE \(nameColumn) LIKE ? AND deleted_at IS NULL
                    ORDER BY \(nameColumn) ASC
                    LIMIT 5
                    """,
                arguments: ["%\(query)%"]
            )
        }

        return results.map { PredictionSuggestion(text: $0, source: .entityLookup, confidence: 0.95) }
    }

    // MARK: - Tier 2: Phrase History

    private func phraseHistory(
        partialText: String,
        fieldType: String,
        userId: Int64?
    ) throws -> [PredictionSuggestion] {
        guard let userId else { return [] }

        let results: [String] = try db.writer.read { dbConnection in
            try String.fetchAll(
                dbConnection,
                sql: """
                    SELECT text FROM _text_history
                    WHERE user_id = ? AND field_type = ? AND text LIKE ?
                    ORDER BY frequency DESC, last_used_at DESC
                    LIMIT 5
                    """,
                arguments: [userId, fieldType, "\(partialText)%"]
            )
        }

        return results.map { PredictionSuggestion(text: $0, source: .history, confidence: 0.85) }
    }

    // MARK: - Tier 3: Template Expansion

    private func templateExpansion(
        partialText: String,
        fieldType: String
    ) -> [PredictionSuggestion] {
        // Common abbreviations and templates for electrical contracting
        let templates: [String: [String: String]] = [
            "job_notes": [
                "inst": "Installed",
                "repl": "Replaced",
                "insp": "Inspected",
                "comp": "Completed",
                "wait": "Waiting on materials",
                "rough": "Rough-in complete",
                "trim": "Trim-out complete",
                "demo": "Demolition complete",
            ],
            "dispatch_notes": [
                "need": "Need materials from warehouse",
                "crew": "Crew of",
                "start": "Start time:",
                "site": "Site conditions:",
            ],
            "description": [
                "elec": "Electrical",
                "panel": "Panel installation",
                "cond": "Conduit run",
                "wire": "Wire pull",
                "circ": "Circuit installation",
            ],
        ]

        let lowered = partialText.lowercased()
        guard let fieldTemplates = templates[fieldType] else { return [] }

        return fieldTemplates.compactMap { abbrev, expansion in
            guard abbrev.hasPrefix(lowered) || expansion.lowercased().hasPrefix(lowered) else {
                return nil
            }
            return PredictionSuggestion(text: expansion, source: .template, confidence: 0.90)
        }
    }

    // MARK: - Cache

    private func updateCache(key: String, suggestions: [PredictionSuggestion]) {
        if predictionCache.count >= cacheMaxSize {
            // Evict oldest entries
            let sorted = predictionCache.sorted { $0.value.timestamp < $1.value.timestamp }
            for entry in sorted.prefix(cacheMaxSize / 4) {
                predictionCache.removeValue(forKey: entry.key)
            }
        }
        predictionCache[key] = CachedPrediction(suggestions: suggestions, timestamp: Date())
    }

    private struct CachedPrediction {
        let suggestions: [PredictionSuggestion]
        let timestamp: Date
    }
}

// MARK: - Prediction Suggestion

/// A single text prediction suggestion.
public struct PredictionSuggestion: Sendable, Identifiable {
    public let id = UUID()
    public let text: String
    public let source: PredictionSource
    public let confidence: Float
}

// MARK: - Prediction Source

/// Source of a prediction suggestion.
public enum PredictionSource: String, Sendable {
    case entityLookup = "entity"
    case history = "history"
    case template = "template"
    case llm = "llm"
}

// MARK: - Prediction Entity Type

/// Entity types that can be used for prediction lookup.
public enum PredictionEntityType: String, Sendable, CaseIterable {
    case supplier
    case part
    case job
    case employee
    case customer
    case vehicle
    case tool
    case binLocation = "bin_location"

    /// Returns the table name and name column for this entity type.
    var tableAndColumn: (table: String, column: String) {
        switch self {
        case .supplier: return ("suppliers", "name")
        case .part: return ("parts", "name")
        case .job: return ("jobs", "job_name")
        case .employee: return ("users", "display_name")
        case .customer: return ("customers", "company_name")
        case .vehicle: return ("vehicles", "name")
        case .tool: return ("tools", "name")
        case .binLocation: return ("bin_locations", "name")
        }
    }
}
