import Foundation
import Testing
@testable import WiredPartCore

@Suite("Required text validation")
struct RequiredTextValidationTests {
    @Test("central helper rejects whitespace and newline-only required text")
    func centralHelperRejectsNewlineOnlyText() {
        #expect("   ".isBlankRequiredText)
        #expect("\n\t\r".isBlankRequiredText)
        #expect("  Durable Name\n".normalizedRequiredText == "Durable Name")

        let optionalWhitespace: String? = "\n\t"
        #expect(optionalWhitespace.normalizedOptionalText == nil)
    }

    @Test("chat service rejects newline-only required text at service boundary")
    func chatRejectsNewlineOnlyRequiredText() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: ChatService.ChatError.self) {
            _ = try env.chat.createChannel(
                name: "\n\t",
                channelType: "group",
                jobId: nil,
                createdBy: env.adminUserId
            )
        }

        let channelId = try env.chat.createChannel(
            name: "Crew chat",
            channelType: "group",
            jobId: nil,
            createdBy: env.adminUserId
        )
        #expect(throws: ChatService.ChatError.self) {
            _ = try env.chat.sendMessage(
                channelId: channelId,
                senderId: env.adminUserId,
                content: "\n\t"
            )
        }
    }

    @Test("warehouse floor plan required text rejects newline-only values")
    func warehouseRejectsNewlineOnlyRequiredText() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            _ = try env.warehouse.createFloorPlan(name: "\n\t", widthInches: 120, lengthInches: 120)
        }

        let plan = try env.warehouse.createFloorPlan(name: "Main floor", widthInches: 120, lengthInches: 120)
        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            _ = try env.warehouse.addFloorFeature(
                floorPlanId: plan.id!,
                featureType: "\n\t",
                label: nil,
                gridX: 0,
                gridY: 0
            )
        }
    }

    @Test("reports service trims saved report names and rejects newline-only report metadata")
    func reportsNormalizeAndRejectRequiredText() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: ReportsError.requiredFieldEmpty) {
            _ = try env.reports.saveReportConfig(
                name: "\n\t",
                type: "labor",
                columns: ["employee"],
                filters: [:],
                userId: env.adminUserId,
                isShared: false
            )
        }

        let reportId = try env.reports.saveReportConfig(
            name: "  Weekly Labor\n",
            type: "  labor\n",
            columns: ["employee"],
            filters: [:],
            userId: env.adminUserId,
            isShared: false
        )
        let saved = try env.reports.getSavedReports(userId: env.adminUserId)
        let report = try #require(saved.first { $0.id == reportId })
        #expect(report.name == "Weekly Labor")
        #expect(report.reportType == "labor")
    }
}
