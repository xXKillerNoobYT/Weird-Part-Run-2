import XCTest

final class WarehouseTabStripRegressionTests: XCTestCase {
    func testModuleHostSubTabPickerAutoScrollsToSelectedTab() throws {
        let source = try Self.readIOSMainViewSource()

        XCTAssertTrue(
            source.contains("ScrollViewReader { proxy in"),
            "ModuleHostView sub-tab picker should use ScrollViewReader so narrow tab strips can reveal the selected tab."
        )
        XCTAssertTrue(
            source.contains("proxy.scrollTo(selectedTabId, anchor: .center)"),
            "Sub-tab picker should scroll the selected tab into view when the module host appears."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: selectedTabId) { _, selectedId in") &&
                source.contains("proxy.scrollTo(selectedId, anchor: .center)"),
            "Sub-tab picker should re-center the newly selected tab when navigation updates selectedTabId."
        )
        XCTAssertTrue(
            source.contains(".id(tab.id)"),
            "Sub-tab chips should provide stable IDs so ScrollViewReader can target the selected tab."
        )
    }

    private static func readIOSMainViewSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Navigation")
            .appendingPathComponent("IOSMainView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
