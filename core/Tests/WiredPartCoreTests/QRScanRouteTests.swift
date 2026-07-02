import Testing
import Foundation
@testable import WiredPartCore

/// Coverage for the QR quick-action route payload (issue #700): scanned entity
/// context must survive the scanner → destination-page hand-off exactly once.
@Suite("QR Scan Route Tests")
struct QRScanRouteTests {

    private func makeContext(
        entityType: QREntityType? = .part,
        entityId: Int64? = 42,
        action: QRScanAction = .view,
        stashedAt: Date = Date()
    ) -> QRScanRouteContext {
        QRScanRouteContext(
            entityType: entityType,
            entityId: entityId,
            code: "WP-CODE-42",
            searchHint: "PRT-042",
            locationUnitId: nil,
            action: action,
            stashedAt: stashedAt
        )
    }

    @Test("Stashed context is consumed once with full payload intact")
    func testStashConsumeRoundTrip() {
        let store = QRScanRouteStore()
        let context = makeContext(entityType: .part, entityId: 42, action: .moveStock)

        store.stash(context, for: "warehouse-movements")

        let consumed = store.consume(for: "warehouse-movements")
        #expect(consumed == context)
        #expect(consumed?.entityType == .part)
        #expect(consumed?.entityId == 42)
        #expect(consumed?.searchHint == "PRT-042")
        #expect(consumed?.action == .moveStock)

        // Consume-once: a second visit to the destination gets nothing.
        #expect(store.consume(for: "warehouse-movements") == nil)
    }

    @Test("Consuming an unrelated destination returns nil and leaves the stash intact")
    func testConsumeUnrelatedDestination() {
        let store = QRScanRouteStore()
        store.stash(makeContext(), for: "parts-catalog")

        #expect(store.consume(for: "jobs-list") == nil)
        #expect(store.consume(for: "parts-catalog") != nil)
    }

    @Test("Stale contexts are dropped instead of hijacking a later visit")
    func testStaleContextExpires() {
        let store = QRScanRouteStore()
        let stashedAt = Date(timeIntervalSinceNow: -(QRScanRouteStore.defaultMaxAge + 1))
        store.stash(makeContext(stashedAt: stashedAt), for: "parts-catalog")

        #expect(store.consume(for: "parts-catalog") == nil)
        // The expired entry is removed, not retried.
        #expect(store.consume(for: "parts-catalog") == nil)
    }

    @Test("Context within the freshness window is still delivered")
    func testFreshContextWithinWindow() {
        let store = QRScanRouteStore()
        let stashedAt = Date(timeIntervalSinceNow: -(QRScanRouteStore.defaultMaxAge - 5))
        store.stash(makeContext(stashedAt: stashedAt), for: "tools-registry")

        #expect(store.consume(for: "tools-registry") != nil)
    }

    @Test("Re-stashing a destination replaces the previous context")
    func testRestashReplacesPrevious() {
        let store = QRScanRouteStore()
        store.stash(makeContext(entityId: 1, action: .view), for: "jobs-list")
        store.stash(makeContext(entityType: .job, entityId: 2, action: .view), for: "jobs-list")

        let consumed = store.consume(for: "jobs-list")
        #expect(consumed?.entityType == .job)
        #expect(consumed?.entityId == 2)
    }

    @Test("clearAll drops every pending context")
    func testClearAll() {
        let store = QRScanRouteStore()
        store.stash(makeContext(), for: "parts-catalog")
        store.stash(makeContext(entityType: .tool), for: "tools-registry")

        store.clearAll()

        #expect(store.consume(for: "parts-catalog") == nil)
        #expect(store.consume(for: "tools-registry") == nil)
    }

    @Test("Location context carries the warehouse area and storage unit ids")
    func testLocationContextPayload() {
        let store = QRScanRouteStore()
        let context = QRScanRouteContext(
            entityType: .bin,
            entityId: 7,          // warehouse area id
            code: "A1-L2-B3",
            searchHint: "A1-L2-B3",
            locationUnitId: 3,
            action: .floorPlan
        )
        store.stash(context, for: "warehouse-locations")

        let consumed = store.consume(for: "warehouse-locations")
        #expect(consumed?.entityId == 7)
        #expect(consumed?.locationUnitId == 3)
        #expect(consumed?.action == .floorPlan)
    }
}
