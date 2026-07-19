import XCTest
@testable import Weird_Parts

/// Focused regression coverage for GitHub #86's router-owned context fallback.
/// These source-contract tests keep every AppTab covered without requiring
/// mutable backend fixtures or exposing business records to the assistant.
final class AIPageRouteContextRegressionTests: XCTestCase {
    func testRouterPublishesMinimalCurrentRouteAndLifecycleEvents() throws {
        let navigation = try Self.readSource("Navigation/NavigationConfig.swift")
        let router = try Self.readSource("Navigation/IOSContentRouter.swift")

        XCTAssertTrue(navigation.contains("WiredPart.routePageActive"))
        XCTAssertTrue(navigation.contains("WiredPart.routePageInactive"))
        XCTAssertTrue(navigation.contains("WiredPart.requestCurrentPageContext"))
        XCTAssertTrue(router.contains(".onAppear { postRouteContext() }"))
        XCTAssertTrue(router.contains(".onChange(of: path)"))
        XCTAssertTrue(router.contains("publisher(for: .requestCurrentPageContext)"))
        XCTAssertTrue(router.contains("name: .routePageInactive"))
        XCTAssertTrue(router.contains("guard let descriptor = routeDescriptor else { return }"))

        for allowedKey in ["\"context\"", "\"path\"", "\"pageId\"", "\"module\"", "\"page\""] {
            XCTAssertTrue(router.contains(allowedKey))
        }
        for forbiddenTerm in ["password", "token", "privateNotes", "mutationId", "rawDump"] {
            XCTAssertFalse(router.contains("\"\(forbiddenTerm)\":"))
        }
    }

    func testAssistantRequestsFreshRouteAndClearsItSafely() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("post(name: .requestCurrentPageContext"))
        XCTAssertTrue(assistant.contains("publisher(for: .routePageActive)"))
        XCTAssertTrue(assistant.contains("publisher(for: .routePageInactive)"))
        XCTAssertTrue(assistant.contains("path == activeRoutePath"))
        XCTAssertTrue(assistant.contains("Current Route Context (READ-ONLY)"))

        let clear = try TestSourceSlicer.braceBalancedBody(
            after: "private func clearVolatilePageContext()",
            in: assistant
        )
        XCTAssertTrue(clear.contains("routeContext = nil"))
        XCTAssertTrue(clear.contains("activeRoutePath = nil"))
    }

    @MainActor
    func testSupplierContextBuilderExcludesRecordAndFreeFormFields() {
        let excludedSentinels = [
            "SUPPLIER_NAME_SENTINEL",
            "CONTACT_NAME_SENTINEL",
            "EMAIL_SENTINEL",
            "PHONE_SENTINEL",
            "ADDRESS_SENTINEL",
            "WEBSITE_SENTINEL",
            "REP_NAME_SENTINEL",
            "REP_EMAIL_SENTINEL",
            "REP_PHONE_SENTINEL",
            "PRIVATE_NOTES_SENTINEL",
            "DELIVERY_METHOD_SENTINEL",
            "DELIVERY_DAYS_SENTINEL",
            "ACCOUNT_NUMBER_SENTINEL",
        ]
        let supplier = SupplierListRow(
            id: 987_654_321,
            name: excludedSentinels[0],
            contactName: excludedSentinels[1],
            email: excludedSentinels[2],
            phone: excludedSentinels[3],
            address: excludedSentinels[4],
            website: excludedSentinels[5],
            repName: excludedSentinels[6],
            repEmail: excludedSentinels[7],
            repPhone: excludedSentinels[8],
            notes: excludedSentinels[9],
            deliveryMethod: excludedSentinels[10],
            deliveryDays: excludedSentinels[11],
            accountNumber: excludedSentinels[12],
            onTimeRate: 12.34,
            qualityScore: 23.45,
            reliabilityScore: 34.56,
            isActive: 1,
            brandCount: 67_890,
            partCount: 54_321
        )

        let context = SupplierAIPageContextBuilder.build(
            suppliers: [supplier],
            visibleCount: 1,
            searchIsActive: true,
            showingActiveOnly: true,
            sortLabel: "Name A→Z"
        )

        for sentinel in excludedSentinels {
            XCTAssertFalse(context.contains(sentinel), "Leaked excluded supplier field: \(sentinel)")
        }
        for excludedValue in ["987654321", "12.34", "23.45", "34.56", "67890", "54321"] {
            XCTAssertFalse(context.contains(excludedValue), "Leaked record-specific supplier value: \(excludedValue)")
        }
        XCTAssertTrue(context.contains("Total suppliers: 1"))
        XCTAssertTrue(context.contains("Visible suppliers: 1"))
        XCTAssertTrue(context.contains("Search: active"))
        XCTAssertTrue(context.contains("Filter: active suppliers"))
        XCTAssertTrue(context.contains("Sort: Name A→Z"))
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
