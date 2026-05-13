import Foundation
import Testing
@testable import WiredPartCore

@Suite("Supplier Website Sourcing Tests")
struct SupplierWebsiteSourcingTests {
    @Test("linked supplier part number returns supplier website candidate")
    func linkedSupplierPartNumberReturnsCandidate() throws {
        let env = try E2ETestHelpers.setUp()
        let (categoryId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let supplierId = try env.parts.createSupplier(
            name: "Graybar",
            website: "https://graybar.example/search"
        )
        let partId = try env.parts.createPart(
            categoryId: categoryId,
            name: "Warehouse Pull Box",
            code: "WPB-400"
        )
        _ = try env.parts.addPartSupplierLink(
            partId: partId,
            supplierId: supplierId,
            supplierPartNumber: "SUP-WPB-400"
        )

        let candidates = try env.parts.supplierWebsiteSourcingCandidates(query: "SUP-WPB-400")

        #expect(candidates.count == 1)
        #expect(candidates[0].kind == .linkedPart)
        #expect(candidates[0].supplierName == "Graybar")
        #expect(candidates[0].partId == partId)
        #expect(candidates[0].supplierPartNumber == "SUP-WPB-400")
        #expect(candidates[0].handoffURL.absoluteString.contains("q=SUP-WPB-400"))
    }

    @Test("unmatched query returns general supplier website handoffs")
    func unmatchedQueryReturnsGeneralSupplierWebsiteHandoffs() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.parts.createSupplier(
            name: "CED",
            website: "ced.example/catalog"
        )
        _ = try env.parts.createSupplier(
            name: "No Website Supply"
        )

        let candidates = try env.parts.supplierWebsiteSourcingCandidates(query: "unknown breaker")

        #expect(candidates.count == 1)
        #expect(candidates[0].kind == .generalWebsite)
        #expect(candidates[0].supplierName == "CED")
        #expect(candidates[0].partId == nil)
        #expect(candidates[0].handoffURL.scheme == "https")
        #expect(candidates[0].handoffURL.absoluteString.contains("q=unknown%20breaker"))
    }

    @Test("supplier website handoff URL only accepts web URLs and appends query")
    func handoffURLSafety() throws {
        let safeURL = try #require(PartsService.supplierWebsiteHandoffURL(
            website: "https://supplier.example/path?dept=parts#details",
            query: "12/2 romex"
        ))

        #expect(safeURL.absoluteString == "https://supplier.example/path?dept=parts&q=12/2%20romex")
        #expect(PartsService.supplierWebsiteHandoffURL(website: "javascript:alert(1)", query: "wire") == nil)
        #expect(PartsService.supplierWebsiteHandoffURL(website: "ftp://supplier.example", query: "wire") == nil)
    }
}
