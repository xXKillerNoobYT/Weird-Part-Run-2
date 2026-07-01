import Foundation
import Testing

struct NavigationPlaceholderRegressionTests {
    @Test func visibleNavigationLinksDoNotUseBareTextDestinations() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        let sourceRoot = repoRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Weird Parts IOS")

        let sourceFiles = try swiftFiles(under: sourceRoot)
        var violations: [String] = []

        for file in sourceFiles {
            let content = try String(contentsOf: file, encoding: .utf8)
            if containsBareTextNavigationDestination(content) {
                violations.append(file.path.replacingOccurrences(of: repoRoot.path + "/", with: ""))
            }
        }

        #expect(violations.isEmpty, "NavigationLink destinations should not be bare Text placeholders: \(violations.joined(separator: ", "))")
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let values = try url.resourceValues(forKeys: Set(keys))
            return values.isRegularFile == true ? url : nil
        }
    }

    private func containsBareTextNavigationDestination(_ content: String) -> Bool {
        let patterns = [
            #"NavigationLink\s*\{\s*Text\s*\(\s*\"[^\"]+\"\s*\)\s*\}"#,
            #"NavigationLink\s*\(\s*destination\s*:\s*Text\s*\(\s*\"[^\"]+\"\s*\)"#
        ]

        return patterns.contains { pattern in
            content.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
