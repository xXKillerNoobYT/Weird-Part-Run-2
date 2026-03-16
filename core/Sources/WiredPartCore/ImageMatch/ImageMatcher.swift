import Foundation
import GRDB

// MARK: - Image Matcher

/// Camera-based part matching using feature vector similarity search.
///
/// Pipeline:
/// 1. User photographs an unknown part
/// 2. `ImageFeatureAdapter` extracts a feature vector from the photo
/// 3. `ImageMatcher` compares against stored part feature vectors
/// 4. Top-N matches returned with similarity scores
/// 5. User confirms the correct match
///
/// Feature vectors are stored in `part_image_features` and loaded into
/// an in-memory index for fast cosine similarity search.
public actor ImageMatcher {
    private let db: AppDatabase
    private var featureIndex: [IndexEntry] = []
    private var isIndexLoaded = false

    /// Adapter type this index was built for.
    private var indexAdapterType: String?

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Index Management

    /// Load the feature index from the database into memory.
    ///
    /// Filters to only load vectors from the specified adapter type,
    /// since vectors from different adapters are not comparable.
    public func loadIndex(adapterType: String) throws {
        let rows: [(partId: Int64, vector: [Float])] = try db.writer.read { dbConnection in
            try Row.fetchAll(
                dbConnection,
                sql: """
                    SELECT part_id, feature_vector
                    FROM part_image_features
                    WHERE adapter_type = ?
                    """,
                arguments: [adapterType]
            ).compactMap { row in
                guard let partId = row["part_id"] as? Int64,
                      let vectorData = row["feature_vector"] as? Data else {
                    return nil
                }
                let vector = Self.deserializeVector(vectorData)
                return (partId: partId, vector: vector)
            }
        }

        featureIndex = rows.map { IndexEntry(partId: $0.partId, vector: $0.vector) }
        indexAdapterType = adapterType
        isIndexLoaded = true
    }

    /// Number of entries in the feature index.
    public var indexCount: Int { featureIndex.count }

    /// Whether the index has been loaded.
    public var isReady: Bool { isIndexLoaded }

    // MARK: - Search

    /// Find the top-N most similar parts to a query feature vector.
    ///
    /// - Parameters:
    ///   - queryVector: Feature vector extracted from the query image.
    ///   - topN: Maximum number of results to return (default: 5).
    ///   - minimumSimilarity: Minimum cosine similarity threshold (default: 0.3).
    /// - Returns: Matching parts sorted by similarity (highest first).
    public func search(
        queryVector: [Float],
        topN: Int = 5,
        minimumSimilarity: Float = 0.3
    ) throws -> [ImageMatchResult] {
        guard isIndexLoaded else {
            throw ImageMatchError.indexNotLoaded
        }

        guard !featureIndex.isEmpty else {
            return []
        }

        // Compute cosine similarity against all indexed vectors
        var scored: [(partId: Int64, similarity: Float)] = featureIndex.compactMap { entry in
            let sim = Self.cosineSimilarity(queryVector, entry.vector)
            guard sim >= minimumSimilarity else { return nil }
            return (partId: entry.partId, similarity: sim)
        }

        // Sort by similarity descending, take top N
        scored.sort { $0.similarity > $1.similarity }
        let topResults = scored.prefix(topN)

        // Fetch part details for results
        return try topResults.map { result in
            let partInfo = try fetchPartInfo(partId: result.partId)
            return ImageMatchResult(
                partId: result.partId,
                similarity: result.similarity,
                partName: partInfo.name,
                partCode: partInfo.code
            )
        }
    }

    // MARK: - Index a Part Image

    /// Store a feature vector for a part image in the database.
    ///
    /// - Parameters:
    ///   - partId: The part's database ID.
    ///   - vector: The feature vector.
    ///   - adapterType: The adapter that generated this vector.
    ///   - imageHash: SHA-256 hash of the source image (for dedup).
    public func indexPartImage(
        partId: Int64,
        vector: [Float],
        adapterType: String,
        imageHash: String
    ) throws {
        let vectorData = Self.serializeVector(vector)

        try db.writer.write { dbConnection in
            // Upsert: replace if same part_id + adapter_type + image_hash
            try dbConnection.execute(
                sql: """
                    INSERT OR REPLACE INTO part_image_features
                        (part_id, feature_vector, adapter_type, image_hash, created_at)
                    VALUES (?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [partId, vectorData, adapterType, imageHash]
            )
        }

        // Update in-memory index if adapter matches
        if indexAdapterType == adapterType {
            // Remove old entry for this part and add new one
            featureIndex.removeAll { $0.partId == partId }
            featureIndex.append(IndexEntry(partId: partId, vector: vector))
        }
    }

    // MARK: - Log Match Attempt

    /// Record a match attempt for diagnostics (local-only, not synced).
    public func logMatchAttempt(
        queryImageHash: String,
        topMatchPartId: Int64?,
        topSimilarity: Float?,
        userConfirmedPartId: Int64?,
        resultCount: Int
    ) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO image_match_history
                        (query_image_hash, top_match_part_id, top_similarity,
                         user_confirmed_part_id, result_count, created_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [
                    queryImageHash, topMatchPartId, topSimilarity,
                    userConfirmedPartId, resultCount
                ]
            )
        }
    }

    // MARK: - Private Helpers

    private func fetchPartInfo(partId: Int64) throws -> (name: String, code: String?) {
        try db.writer.read { dbConnection in
            guard let row = try Row.fetchOne(
                dbConnection,
                sql: "SELECT name, code FROM parts WHERE id = ?",
                arguments: [partId]
            ) else {
                return (name: "Unknown Part", code: nil)
            }
            return (
                name: row["name"] as? String ?? "Unknown Part",
                code: row["code"] as? String
            )
        }
    }

    /// Cosine similarity between two vectors.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    /// Serialize a float vector to binary Data for SQLite storage.
    static func serializeVector(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Deserialize binary Data back to a float vector.
    static func deserializeVector(_ data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }
    }

    // MARK: - Index Entry

    private struct IndexEntry {
        let partId: Int64
        let vector: [Float]
    }
}

// MARK: - Image Match Result

/// A single match result from the image matcher.
public struct ImageMatchResult: Sendable, Identifiable {
    public var id: Int64 { partId }
    public let partId: Int64
    /// Cosine similarity score from 0.0 to 1.0.
    public let similarity: Float
    public let partName: String
    public let partCode: String?

    /// Similarity as a percentage string.
    public var similarityPercent: String {
        "\(Int(similarity * 100))%"
    }
}

// MARK: - Image Match Errors

public enum ImageMatchError: Error, LocalizedError, Sendable {
    case indexNotLoaded
    case noMatchesFound
    case featureExtractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .indexNotLoaded:
            return "Image match index has not been loaded"
        case .noMatchesFound:
            return "No matching parts found"
        case .featureExtractionFailed(let reason):
            return "Failed to extract features: \(reason)"
        }
    }
}
