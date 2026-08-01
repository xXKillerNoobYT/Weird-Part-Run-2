import Foundation
import Testing
@testable import WiredPartCore

@Suite("Design panel state")
struct DesignPanelStateTests {

    private func makePanel(spaces: Int = 40) -> DesignPanelState {
        DesignPanelState(setup: DesignPanelSetup(totalSpaces: spaces))
    }

    @Test("Save deletes overlapped entries (spec save semantics)")
    func saveOverlapResolution() throws {
        var panel = makePanel()
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, name: "A")), atAnchor: 3)
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, name: "B")), atAnchor: 5)
        // A 3-pole at 1 spans 1,3,5 — must evict both existing entries.
        try panel.save(.full(poles: 3, circuit: .init(amps: 60, name: "Sub")), atAnchor: 1)
        #expect(panel.entries.count == 1)
        #expect(panel.entry(coveringSpace: 5)?.anchor == 1)
    }

    @Test("Reverse overlap: saving under an existing span evicts the spanning entry")
    func reverseOverlap() throws {
        var panel = makePanel()
        try panel.save(.full(poles: 2, circuit: .init(amps: 30, name: "Dryer")), atAnchor: 2)
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, name: "Lights")), atAnchor: 4)
        #expect(panel.entries[2] == nil)
        #expect(panel.entries[4] != nil)
    }

    @Test("Nil save clears the anchor (SPARE semantics)")
    func clearAnchor() throws {
        var panel = makePanel()
        try panel.save(.tandem(upper: .init(amps: 15), lower: .init(amps: 20)), atAnchor: 6)
        try panel.save(nil, atAnchor: 6)
        #expect(panel.entries.isEmpty)
    }

    @Test("Out-of-range placement throws with the offending spaces")
    func outOfRange() {
        var panel = makePanel(spaces: 8)
        #expect(throws: DesignPanelError.outOfRange(spaces: [9])) {
            try panel.save(.quad(mode: .four, sections: []), atAnchor: 7)
        }
    }

    @Test("CTL off restricts tandems to marked slots")
    func ctlSlotting() throws {
        var panel = DesignPanelState(setup: DesignPanelSetup(
            ctlTandemsAnySlot: false, ctlMarkedSpaces: [39, 40], totalSpaces: 40
        ))
        #expect(throws: DesignPanelError.tandemSlotNotMarked(space: 5)) {
            try panel.save(.tandem(upper: .init(amps: 15), lower: .init(amps: 15)), atAnchor: 5)
        }
        try panel.save(.tandem(upper: .init(amps: 15), lower: .init(amps: 15)), atAnchor: 39)
        #expect(panel.entries[39] != nil)
    }

    @Test("Free spaces and next-free respect spans")
    func freeSpaces() throws {
        var panel = makePanel(spaces: 8)
        try panel.save(.full(poles: 2, circuit: .init(amps: 30)), atAnchor: 1) // occupies 1,3
        #expect(panel.nextFreeSpace == 2)
        #expect(!panel.freeSpaces.contains(3))
    }

    @Test("Phase aggregates sum entries per leg and derive service amps")
    func aggregates() throws {
        var panel = DesignPanelState(setup: DesignPanelSetup(
            voltageSystem: .v120_240Single3Wire, totalSpaces: 8, mainAmps: 100
        ))
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, usedAmps: 10)), atAnchor: 1) // leg A: 1200 VA
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, usedAmps: 20)), atAnchor: 3) // leg B: 2400 VA
        #expect(panel.perLegVA == [1200, 2400])
        #expect(panel.perLegAmps == [10, 20])
        #expect(panel.totalConnectedVA == 3600)
        #expect(panel.serviceAmps == 15) // 3600 / 240
        let largest = panel.largestLeg
        #expect(largest.leg == 1)
        #expect(largest.amps == 20)
        #expect(abs(largest.fractionOfMain - 0.2) < 0.0001)
    }

    @Test("Setup clamps spaces even within 4...200")
    func spaceClamp() {
        #expect(DesignPanelSetup.clampSpaces(3) == 4)
        #expect(DesignPanelSetup.clampSpaces(41) == 40)
        #expect(DesignPanelSetup.clampSpaces(999) == 200)
    }

    @Test("Legacy projection flattens kinds into printable rows")
    func legacyProjection() throws {
        var panel = makePanel()
        try panel.save(.full(poles: 2, circuit: .init(amps: 30, name: "Dryer")), atAnchor: 2)
        try panel.save(.tandem(upper: .init(amps: 15, name: "Hall"), lower: .init(amps: 20, name: "Bath")), atAnchor: 5)
        try panel.save(.quad(mode: .double, sections: [
            .init(amps: 30, name: "Dryer 2"), .init(amps: 50, name: "Range"),
        ]), atAnchor: 7)
        let rows = panel.legacyCircuits()
        #expect(rows.count == 4)
        #expect(rows.first?.breakerType == .double)
        #expect(rows.contains { $0.secondaryCircuitDescription == "Bath" })
        #expect(rows.contains { $0.circuitDescription == "Range" })
    }

    @Test("State round-trips through Codable including layout")
    func codableRoundTrip() throws {
        var panel = makePanel()
        panel.layout = .classic
        try panel.save(.quad(mode: .center, sections: [
            .init(amps: 20), .init(amps: 30, type: .hacr), .init(amps: 20),
        ]), atAnchor: 9)
        let data = try JSONEncoder().encode(panel)
        let decoded = try JSONDecoder().decode(DesignPanelState.self, from: data)
        #expect(decoded == panel)
    }

    @Test("Legacy migration preserves breaker protection types and skips blank or spare circuits")
    func legacyMigration() {
        let legacy = PanelSchedule(totalSpaces: 20, mainBreakerAmps: 100, circuits: [
            CircuitEntry(spaceNumber: 1, breakerAmps: 20, breakerType: .single, circuitDescription: "Lights", isSpare: false),
            CircuitEntry(spaceNumber: 2, breakerAmps: 30, breakerType: .double, circuitDescription: "Dryer", isSpare: false),
            CircuitEntry(spaceNumber: 5, breakerAmps: 15, breakerType: .tandem, circuitDescription: "Hall", isSpare: false, secondaryCircuitDescription: "Bath"),
            CircuitEntry(spaceNumber: 7, breakerType: .spare, isSpare: true),
            CircuitEntry(spaceNumber: 8, breakerType: .blank, circuitDescription: "Blank", isSpare: false),
            CircuitEntry(spaceNumber: 9, breakerAmps: 20, breakerType: .gfci, circuitDescription: "Bath GFCI", isSpare: false),
            CircuitEntry(spaceNumber: 10, breakerAmps: 20, breakerType: .afci, circuitDescription: "Bedroom AFCI", isSpare: false),
            CircuitEntry(spaceNumber: 11, breakerAmps: 20, breakerType: .dualFunction, circuitDescription: "Kitchen DF", isSpare: false),
        ])
        let state = DesignPanelState.migrated(fromLegacy: legacy)
        #expect(state.setup.mainAmps == 100)
        #expect(state.entries.count == 6)
        if case .full(let poles, let c)? = state.entries[2] { #expect(poles == 2); #expect(c.name == "Dryer") }
        else { Issue.record("expected 2P full at 2") }
        if case .tandem(let up, let low)? = state.entries[5] { #expect(up.name == "Hall"); #expect(low.name == "Bath") }
        else { Issue.record("expected tandem at 5") }
        #expect(state.entries[7] == nil)
        #expect(state.entries[8] == nil)
        if case .full(_, let c)? = state.entries[9] { #expect(c.type == .gfci) }
        else { Issue.record("expected GFCI at 9") }
        if case .full(_, let c)? = state.entries[10] { #expect(c.type == .afci) }
        else { Issue.record("expected AFCI at 10") }
        if case .full(_, let c)? = state.entries[11] { #expect(c.type == .dualFunction) }
        else { Issue.record("expected dual-function breaker at 11") }
    }

    @Test("Breaker shopping list aggregates identical breakers and skips spares")
    func shoppingList() throws {
        var panel = makePanel()
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, type: .gfci, name: "Kitchen")), atAnchor: 1)
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, type: .gfci, name: "Bath")), atAnchor: 3)
        try panel.save(.full(poles: 2, circuit: .init(amps: 30, name: "Dryer")), atAnchor: 2)
        try panel.save(.tandem(upper: .init(amps: 15), lower: .init(amps: 20)), atAnchor: 5)
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, type: .spare)), atAnchor: 7)
        let list = panel.breakerShoppingList()
        #expect(list.contains("2× 20A/1P GFCI"))
        #expect(list.contains("1× 30A/2P Standard"))
        #expect(list.contains("1× Tandem 15A/20A Standard"))
        #expect(list.count == 3)
    }
}
