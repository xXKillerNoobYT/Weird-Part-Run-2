import XCTest

final class SearchablePageContextRegressionTests: XCTestCase {
    func testSearchableContextPagesRefreshContextWhenSearchTextChanges() throws {
        let sourceFiles = try Self.swiftSourceFiles()
        var staleContextFiles: [String] = []

        for sourceURL in sourceFiles {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            guard source.contains("searchText"),
                  source.contains("userInfo: [\"context\"") else {
                continue
            }

            if !source.contains(".onChange(of: searchText)") {
                staleContextFiles.append(sourceURL.lastPathComponent)
            }
        }

        XCTAssertTrue(
            staleContextFiles.isEmpty,
            "Searchable pages that post AI/page context must refresh that context when searchText changes. Missing: \(staleContextFiles.sorted().joined(separator: ", "))"
        )
    }

    private static func swiftSourceFiles(file: StaticString = #filePath) throws -> [URL] {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let appSourceRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .appendingPathComponent("Weird Parts IOS")

        guard let enumerator = FileManager.default.enumerator(
            at: appSourceRoot,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("Unable to enumerate app Swift sources at \(appSourceRoot.path)")
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }
}
