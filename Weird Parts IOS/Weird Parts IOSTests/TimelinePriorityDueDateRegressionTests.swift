import XCTest

final class TimelinePriorityDueDateRegressionTests: XCTestCase {
    func testImpactedTimelineRowsUseDueDateColorAPIWithoutFallbackBranching() throws {
        let questionsSource = try Self.readFeatureSource(area: "Chat", fileName: "IOSQuestionsPage.swift")
        let escalationSource = try Self.readFeatureSource(area: "Chat", fileName: "IOSEscalationTimeline.swift")
        let rfiSource = try Self.readFeatureSource(area: "Chat", fileName: "IOSRFIListPage.swift")
        let approvalsSource = try Self.readFeatureSource(area: "Office", fileName: "IOSUnifiedApprovalsPage.swift")
        let jpoDetailSource = try Self.readFeatureSource(area: "Orders", fileName: "IOSJPODetailPage.swift")
        let jpoListSource = try Self.readFeatureSource(area: "Orders", fileName: "IOSJPOsPage.swift")

        XCTAssertTrue(questionsSource.contains("TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)"))
        XCTAssertTrue(escalationSource.contains("TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)"))
        XCTAssertTrue(rfiSource.contains("TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)"))
        XCTAssertTrue(approvalsSource.contains("TimelinePriorityColor.color(priority: jpo.priority, dueDateString: jpo.dueDate)"))
        XCTAssertTrue(jpoDetailSource.contains("TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)"))
        XCTAssertTrue(jpoListSource.contains("TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)"))

        XCTAssertFalse(questionsSource.contains("TimelinePriorityColor.fallbackColor(priority: priority)"))
        XCTAssertFalse(escalationSource.contains("TimelinePriorityColor.fallbackColor(priority: priority)"))
        XCTAssertFalse(rfiSource.contains("TimelinePriorityColor.fallbackColor(priority: priority)"))
        XCTAssertFalse(approvalsSource.contains("TimelinePriorityColor.fallbackColor(priority: jpo.priority)"))
        XCTAssertFalse(jpoDetailSource.contains("TimelinePriorityColor.fallbackColor(priority: priority)"))
        XCTAssertFalse(jpoListSource.contains("TimelinePriorityColor.fallbackColor(priority: priority)"))
    }

    func testTimelinePriorityColorNoLongerTracksDueDateBackfillTodoInFallback() throws {
        let timelineColorSource = try Self.readSharedSource(fileName: "TimelinePriorityColor.swift")
        XCTAssertFalse(
            timelineColorSource.contains("TODO: When due dates are added to these models, replace with time-based color")
        )
    }

    private static func readFeatureSource(
        area: String,
        fileName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent(area)
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readSharedSource(
        fileName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Shared")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
