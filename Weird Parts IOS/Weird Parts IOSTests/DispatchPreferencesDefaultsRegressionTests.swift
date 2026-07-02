import XCTest

/// Regression coverage for a divergence found in review of the #439 dispatch
/// re-land (PR #1375): IOSDispatchPreferencesPage's load-path defaults for
/// the flex-pool toggles must match
/// `SettingsService.DispatchPreferenceSettings.defaults` exactly.
///
/// `getDispatchPreferences()` returns `.defaults` whenever the `dispatch`
/// settings category has never been saved, and `SchedulingService`'s
/// `fetchFlexPool`/`claimFlexJob` now gate on that value. If the page's own
/// fallback disagrees, a fresh install shows a stale/incorrect toggle state,
/// and an unrelated save (e.g. only touching crew continuity weight) will
/// silently persist the page's wrong default -- flipping company-wide
/// flex-pool behavior with no toggle ever knowingly touched by the user.
final class DispatchPreferencesDefaultsRegressionTests: XCTestCase {
    private static let pageFile = "IOSDispatchPreferencesPage"
    private static let coreDefaultsFile = "SettingsService"

    func testFlexPoolStateDefaultsMatchServiceDefaults() throws {
        let source = try Self.readSettingsSource(Self.pageFile)

        XCTAssertTrue(
            source.contains("@State private var enableFlexSelfAssign = true"),
            "\(Self.pageFile)'s enableFlexSelfAssign @State default must match "
                + "DispatchPreferenceSettings.defaults.flexSelfAssignEnabled (true)."
        )
        XCTAssertTrue(
            source.contains("@State private var requireManagerApproval = false"),
            "\(Self.pageFile)'s requireManagerApproval @State default must match "
                + "DispatchPreferenceSettings.defaults.flexRequireApproval (false)."
        )
    }

    func testLoadSettingsFlexPoolFallbacksMatchServiceDefaults() throws {
        let source = try Self.readSettingsSource(Self.pageFile)
        let loadBody = try Self.methodBody(named: "loadSettings", in: source)

        XCTAssertTrue(
            loadBody.contains(
                "parser.bool(map, key: \"dispatch_flex_self_assign_enabled\", default: true)"
            ),
            "\(Self.pageFile).loadSettings() must fall back to `true` for "
                + "dispatch_flex_self_assign_enabled, matching "
                + "DispatchPreferenceSettings.defaults.flexSelfAssignEnabled."
        )
        XCTAssertTrue(
            loadBody.contains(
                "parser.bool(map, key: \"dispatch_flex_require_approval\", default: false)"
            ),
            "\(Self.pageFile).loadSettings() must fall back to `false` for "
                + "dispatch_flex_require_approval, matching "
                + "DispatchPreferenceSettings.defaults.flexRequireApproval."
        )
    }

    /// Cross-checks against the actual core defaults so this test fails loudly
    /// (rather than silently drifting) if a future change to
    /// `DispatchPreferenceSettings.defaults` isn't mirrored on the page.
    func testCoreDefaultsHaveNotChangedUnderThisTest() throws {
        let coreSource = try Self.readCoreSource(Self.coreDefaultsFile)
        guard let defaultsRange = coreSource.range(of: "public static let defaults = DispatchPreferenceSettings(") else {
            throw XCTSkip("Expected DispatchPreferenceSettings.defaults in \(Self.coreDefaultsFile)")
        }
        guard let closeParen = coreSource[defaultsRange.upperBound...].range(of: ")") else {
            throw XCTSkip("Expected closing paren for DispatchPreferenceSettings.defaults")
        }
        let defaultsBody = coreSource[defaultsRange.lowerBound..<closeParen.upperBound]

        XCTAssertTrue(
            defaultsBody.contains("flexSelfAssignEnabled: true"),
            "DispatchPreferenceSettings.defaults.flexSelfAssignEnabled changed -- "
                + "update IOSDispatchPreferencesPage's defaults (and this test) to match."
        )
        XCTAssertTrue(
            defaultsBody.contains("flexRequireApproval: false"),
            "DispatchPreferenceSettings.defaults.flexRequireApproval changed -- "
                + "update IOSDispatchPreferencesPage's defaults (and this test) to match."
        )
    }

    private static func methodBody(named methodName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(methodName)(") else {
            throw XCTSkip("Expected method \(methodName) in source")
        }
        guard let openBrace = source[nameRange.upperBound...].firstIndex(of: "{") else {
            throw XCTSkip("Expected opening brace for \(methodName)")
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

        throw XCTSkip("Expected closing brace for \(methodName)")
    }

    private static func readSettingsSource(
        _ pageName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Settings")
            .appendingPathComponent("\(pageName).swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readCoreSource(
        _ fileName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        let sourceURL = projectRoot
            .appendingPathComponent("core")
            .appendingPathComponent("Sources")
            .appendingPathComponent("WiredPartCore")
            .appendingPathComponent("Services")
            .appendingPathComponent("\(fileName).swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
