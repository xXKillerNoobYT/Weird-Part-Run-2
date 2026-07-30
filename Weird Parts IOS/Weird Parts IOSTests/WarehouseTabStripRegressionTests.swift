import XCTest

final class WarehouseTabStripRegressionTests: XCTestCase {
    func testWarehouseSettingsTabIsReachableForWarehouseDashboardSetupQA() throws {
        let source = try Self.readNavigationConfigSource()
        let settingsTab = try Self.lineContaining("id: \"warehouse-settings\"", in: source)

        XCTAssertFalse(
            settingsTab.contains("permission: \"manage_warehouse\""),
            "Warehouse Settings must stay reachable to view_warehouse users so QA can open the Warehouse Setup section and both setup wizards."
        )
    }

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

    func testModuleHostSubTabPickerExportsButtonIdentityAndSelectionState() throws {
        let source = try Self.readIOSMainViewSource()
        let picker = try Self.section(
            from: "private var subTabPicker",
            through: "/// Gradient scrim shown at a sub-tab strip edge",
            in: source
        )

        XCTAssertTrue(
            picker.contains(".accessibilityIdentifier(\"subtab_\\(tab.id)\")") &&
                picker.contains(".accessibilityLabel(tab.label)"),
            "Each horizontal sub-tab Button needs a stable subtab_<id> identity and its visible name."
        )
        XCTAssertFalse(
            picker.contains(".accessibilityElement(children: .ignore)"),
            "Creating an accessibility wrapper around a sub-tab can export its identifier as Other instead of Button."
        )
        XCTAssertTrue(
            picker.contains(".accessibilityValue(isSelected(tab) ? \"Selected\" : \"Not selected\")") &&
                picker.contains(".accessibilityAddTraits(isSelected(tab) ? .isSelected : [])") &&
                picker.contains(".accessibilityRemoveTraits(isSelected(tab) ? [] : .isSelected)"),
            "The active horizontal sub-tab should add selected state and every inactive chip should explicitly remove it."
        )
    }

    private static func lineContaining(_ needle: String, in source: String) throws -> String {
        guard let line = source.split(separator: "\n").first(where: { $0.contains(needle) }) else {
            XCTFail("Missing expected source line containing \(needle)")
            return ""
        }
        return String(line)
    }

    private static func section(from startNeedle: String, through endNeedle: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startNeedle))
        let tail = source[start.lowerBound...]
        let end = try XCTUnwrap(tail.range(of: endNeedle))
        return String(tail[..<end.lowerBound])
    }

    private static func readNavigationConfigSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Navigation")
            .appendingPathComponent("NavigationConfig.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
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
