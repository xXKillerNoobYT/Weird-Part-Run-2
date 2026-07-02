import XCTest

/// Regression coverage for GitHub #1184 and #1199.
///
/// Icon-only buttons must carry a semantic `.accessibilityLabel` and provide a
/// 44x44pt minimum touch target. This suite statically scans the files fixed in
/// the 2026-07 accessibility pass so the specific controls cannot silently lose
/// their labels or tap targets again.
final class IconButtonAccessibilityRegressionTests: XCTestCase {

    /// Files audited and fixed under issue #1184. Any icon-only button in these
    /// files must have an `.accessibilityLabel` within its modifier chain.
    private static let auditedFiles = [
        "Navigation/IOSMainView.swift",
        "Navigation/TabBarEditorView.swift",
        "Sync/IOSPeerBrowser.swift",
        "Shared/FirstVisitHint.swift",
        "Scanning/IOSAutoFillBanner.swift",
        "Scanning/QRLabelPrintSheet.swift",
        "Features/Scheduling/IOSDispatchPage.swift",
        "Features/Orders/IOSReceiveShipmentPage.swift",
        "Features/Orders/POSendToSupplierSheet.swift",
        "Features/Parts/PartsSuppliersPage.swift",
        "Features/Parts/CompanionSandboxSheet.swift",
        "Features/Warehouse/ZoneGridCanvas.swift",
    ]

    /// Port of the scanner from issue #1184: a `Button` whose nearby label block
    /// contains only `Image(systemName:)` (no visible `Text`/`Label`) must have
    /// an `.accessibilityLabel` in the surrounding window.
    func testAuditedFilesHaveNoUnlabeledIconOnlyButtons() throws {
        for relativePath in Self.auditedFiles {
            let source = try Self.readSource(relativePath)
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let isButtonStart = line.range(of: #"Button\s*\{"#, options: .regularExpression) != nil
                    || line.contains("Button(action:")
                guard isButtonStart else { continue }
                let window = lines[index..<min(index + 40, lines.count)].joined(separator: "\n")
                let looksIconOnly = window.contains("label:")
                    && window.contains("Image(systemName:")
                    && !window.contains("Text(")
                    && !window.contains("Label(")
                if looksIconOnly {
                    XCTAssertTrue(
                        window.contains(".accessibilityLabel"),
                        "\(relativePath):\(index + 1) — icon-only button without .accessibilityLabel. Add a semantic label (issue #1184)."
                    )
                }
            }
        }
    }

    func testUsedStickerPickerKeepsFortyFourPointTouchTargets() throws {
        let source = try Self.readSource("Scanning/QRLabelPrintSheet.swift")

        XCTAssertTrue(
            source.contains(".frame(minWidth: 44, minHeight: 44)"),
            "Used-position sticker buttons must keep a 44x44pt minimum touch target (issue #1199)."
        )
        XCTAssertFalse(
            source.contains(".frame(minHeight: 30)"),
            "The used-position picker must not regress to sub-44pt touch targets (issue #1199)."
        )
        XCTAssertTrue(
            source.contains(".contentShape(Rectangle())"),
            "Used-position buttons must hit-test their full 44pt frame, not just the drawn sticker shape."
        )
    }

    func testDispatchGridEmptyCellKeepsAccessibleAssignTarget() throws {
        let source = try Self.readSource("Features/Scheduling/IOSDispatchPage.swift")

        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Assign worker\")"),
            "The dispatch-grid empty day cell must announce itself as an assign action."
        )
        // Height: the empty-cell button keeps a 44pt-tall hit area.
        XCTAssertTrue(
            source.contains(".frame(minWidth: minDayColumnWidth, minHeight: 44)"),
            "The dispatch-grid empty day cell must provide a 44x44pt hit area (issue #1184)."
        )
        // Width: day columns must never shrink below the 44pt HIG minimum —
        // dayColumnWidth(forAvailableWidth:) clamps to minDayColumnWidth and
        // the grid overflows into a horizontal scroller on narrow phones.
        // Without this, a 390pt iPhone squeezes the 7 shared columns to
        // ~38pt, silently breaking acceptance criterion 2 of issue #1184.
        XCTAssertTrue(
            source.contains("private let minDayColumnWidth: CGFloat = 44"),
            "The dispatch grid must declare a 44pt minimum day-column width (issue #1184)."
        )
        XCTAssertTrue(
            source.contains("max(minDayColumnWidth, flexibleWidth)"),
            "dayColumnWidth(forAvailableWidth:) must clamp day columns to the 44pt minimum (issue #1184)."
        )
        XCTAssertTrue(
            source.contains("ScrollView(.horizontal)"),
            "The dispatch grid must scroll horizontally when 44pt-wide day columns overflow narrow screens (issue #1184)."
        )
        XCTAssertFalse(
            source.contains(".frame(maxWidth: .infinity, minHeight: 24)"),
            "Day cells must use the clamped fixed column width, not an unconstrained flexible width that can compress below 44pt (issue #1184)."
        )
    }

    func testReceiveShipmentSteppersKeepLabelsAndTapTargets() throws {
        let source = try Self.readSource("Features/Orders/IOSReceiveShipmentPage.swift")

        XCTAssertTrue(source.contains(".accessibilityLabel(\"Decrease quantity\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Increase quantity\")"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: ".dsMinTapTarget()").count - 1, 2,
            "The received-quantity plus/minus steppers must keep 44pt tap targets (issue #1184)."
        )
    }

    func testPartsManagementLineStatusIsVisibleToVoiceOver() throws {
        let source = try Self.readSource("Features/Orders/IOSPartsOrderManagementPage.swift")
        let section = try XCTUnwrap(
            source.range(of: "private func statusIcon").map { String(source[$0.lowerBound...].prefix(1200)) },
            "statusIcon helper should exist in IOSPartsOrderManagementPage."
        )

        XCTAssertFalse(
            section.contains(".accessibilityHidden(true)"),
            "Line-status icons are the only channel conveying status — they must not be hidden from VoiceOver (issue #1184)."
        )
        XCTAssertTrue(section.contains(".accessibilityLabel(\"Status: Received\")"))
        XCTAssertTrue(section.contains(".accessibilityLabel(\"Status: On backorder\")"))
        XCTAssertTrue(section.contains(".accessibilityLabel(\"Status: Pending\")"))
    }

    func testMainViewUserMenuAndAssistantButtonsAreLabeled() throws {
        let source = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: ".accessibilityLabel(\"Account and settings\")").count - 1, 2,
            "Both user-menu toolbar buttons (sidebar and tab layouts) must be labeled."
        )
        XCTAssertTrue(source.contains(".accessibilityLabel(\"AI Assistant\")"))
    }

    private static func readSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
