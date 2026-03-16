import Testing
import Foundation
@testable import WiredPartCore

@Suite("Image Matcher Tests")
struct ImageMatcherTests {

    // MARK: - Cosine Similarity Tests

    @Test("Cosine similarity of identical vectors is 1.0")
    func testIdenticalVectors() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [1.0, 0.0, 0.0]
        let similarity = ImageMatcher.cosineSimilarity(a, b)
        #expect(abs(similarity - 1.0) < 0.001)
    }

    @Test("Cosine similarity of orthogonal vectors is 0.0")
    func testOrthogonalVectors() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [0.0, 1.0, 0.0]
        let similarity = ImageMatcher.cosineSimilarity(a, b)
        #expect(abs(similarity) < 0.001)
    }

    @Test("Cosine similarity of opposite vectors is -1.0")
    func testOppositeVectors() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [-1.0, 0.0, 0.0]
        let similarity = ImageMatcher.cosineSimilarity(a, b)
        #expect(abs(similarity + 1.0) < 0.001)
    }

    @Test("Cosine similarity of empty vectors is 0.0")
    func testEmptyVectors() {
        let similarity = ImageMatcher.cosineSimilarity([], [])
        #expect(similarity == 0)
    }

    @Test("Cosine similarity of mismatched lengths is 0.0")
    func testMismatchedLengths() {
        let a: [Float] = [1.0, 2.0]
        let b: [Float] = [1.0, 2.0, 3.0]
        let similarity = ImageMatcher.cosineSimilarity(a, b)
        #expect(similarity == 0)
    }

    // MARK: - Vector Serialization Tests

    @Test("Vector serialize/deserialize round-trip")
    func testVectorSerialization() {
        let original: [Float] = [1.0, 2.5, -3.14, 0.0, 42.0]
        let data = ImageMatcher.serializeVector(original)
        let restored = ImageMatcher.deserializeVector(data)

        #expect(original.count == restored.count)
        for i in 0..<original.count {
            #expect(abs(original[i] - restored[i]) < 0.0001)
        }
    }

    @Test("Empty vector serialization")
    func testEmptyVectorSerialization() {
        let empty: [Float] = []
        let data = ImageMatcher.serializeVector(empty)
        let restored = ImageMatcher.deserializeVector(data)
        #expect(restored.isEmpty)
    }

    // MARK: - Matcher Integration Tests

    @Test("Search without loading index throws")
    func testSearchWithoutIndex() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let matcher = ImageMatcher(db: db)

        await #expect(throws: ImageMatchError.self) {
            try await matcher.search(queryVector: [1.0, 2.0, 3.0])
        }
    }

    @Test("Search with empty index returns empty")
    func testSearchEmptyIndex() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let matcher = ImageMatcher(db: db)

        try await matcher.loadIndex(adapterType: "apple_vision")
        let results = try await matcher.search(queryVector: [1.0, 2.0, 3.0])
        #expect(results.isEmpty)
    }

    @Test("Index part image and search finds it")
    func testIndexAndSearch() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Insert a test category and part
        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO part_categories (id, name) VALUES (1, 'Wire')"
            )
            try dbConnection.execute(
                sql: "INSERT INTO parts (id, name, code, category_id) VALUES (1, 'Test Wire', 'TW-001', 1)"
            )
        }

        let matcher = ImageMatcher(db: db)
        let vector: [Float] = Array(repeating: 0.5, count: 10)

        try await matcher.indexPartImage(
            partId: 1,
            vector: vector,
            adapterType: "test",
            imageHash: "abc123"
        )

        try await matcher.loadIndex(adapterType: "test")
        #expect(await matcher.indexCount == 1)

        // Search with exact same vector — should match with high similarity
        let results = try await matcher.search(queryVector: vector, topN: 5)
        #expect(!results.isEmpty)
        if let top = results.first {
            #expect(top.partId == 1)
            #expect(top.similarity > 0.99)
        }
    }

    // MARK: - Match Result Tests

    @Test("ImageMatchResult similarity percentage")
    func testSimilarityPercent() {
        let result = ImageMatchResult(
            partId: 1,
            similarity: 0.85,
            partName: "Test",
            partCode: nil
        )
        #expect(result.similarityPercent == "85%")
    }
}
