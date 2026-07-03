import XCTest

enum TestSourceSlicer {
    /// Extracts the brace-balanced body that follows the first occurrence of
    /// `anchor`, so source-scan assertions stay scoped to the code under test.
    static func braceBalancedBody(after anchor: String, in source: String) throws -> String {
        guard let anchorRange = source.range(of: anchor) else {
            throw XCTSkip("Expected anchor \(anchor) in source")
        }
        guard let openBrace = source[anchorRange.upperBound...].firstIndex(of: "{") else {
            throw XCTSkip("Expected opening brace after \(anchor)")
        }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let char = source[index]
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            let next = source.index(after: index)
            if depth == 0 {
                return String(source[openBrace..<next])
            }
            index = next
        }

        throw XCTSkip("Expected closing brace for \(anchor)")
    }
}
