import Testing
@testable import WiredPartCore

// Slice-1 test matrix for the panel redesign domain layer
// (docs/plans/panel-schedule-builder-visual-redesign.md §7.8):
// phase-total math across entry kinds × quad modes × voltage systems,
// occupancy, next-standard-size, and the wire-size table.
@Suite("Panel redesign domain math")
struct PanelScheduleDesignTests {

    // MARK: Voltage systems + leg mapping

    @Test("Voltage systems expose spec vln/vll/legCount")
    func voltageSystems() {
        #expect(PanelVoltageSystem.v120Single2Wire.legCount == 1)
        #expect(PanelVoltageSystem.v120_240Single3Wire.vll == 240)
        #expect(PanelVoltageSystem.v120_208Three.vln == 120)
        #expect(PanelVoltageSystem.v120_208Three.vll == 208)
        #expect(PanelVoltageSystem.v277_480Three.vln == 277)
        #expect(PanelVoltageSystem.v277_480Three.legCount == 3)
    }

    @Test("Leg mapping follows ceil(space/2) rotation")
    func legMapping() {
        let three = PanelVoltageSystem.v120_208Three
        // Rows: (1,2)→A, (3,4)→B, (5,6)→C, (7,8)→A …
        #expect(three.legIndex(forSpace: 1) == 0)
        #expect(three.legIndex(forSpace: 2) == 0)
        #expect(three.legIndex(forSpace: 3) == 1)
        #expect(three.legIndex(forSpace: 6) == 2)
        #expect(three.legIndex(forSpace: 7) == 0)
        let split = PanelVoltageSystem.v120_240Single3Wire
        #expect(split.legIndex(forSpace: 1) == 0)
        #expect(split.legIndex(forSpace: 3) == 1)
        #expect(split.legIndex(forSpace: 5) == 0)
    }

    // MARK: Watts

    @Test("Watts: 1P uses vln, 2P uses vll, 3P uses vll×√3")
    func wattsByPoles() {
        let sys = PanelVoltageSystem.v120_208Three
        #expect(PanelPhaseMath.watts(amps: 10, poles: 1, system: sys) == 1200)
        #expect(PanelPhaseMath.watts(amps: 10, poles: 2, system: sys) == 2080)
        let threePole = PanelPhaseMath.watts(amps: 10, poles: 3, system: sys)
        #expect(abs(threePole - 208 * 10 * 3.0.squareRoot()) < 0.001)
    }

    // MARK: Per-leg splits — full entries

    @Test("Full 2-pole splits VA evenly across its two legs")
    func fullTwoPoleSplit() {
        let sys = PanelVoltageSystem.v120_240Single3Wire
        let entry = DesignSpaceEntry.full(poles: 2, circuit: .init(amps: 30, usedAmps: 20))
        let legs = PanelPhaseMath.perLegVA(entry: entry, anchoredAt: 1, system: sys)
        // 20A @240V = 4800 VA, split 2400/2400 across legs of spaces 1 and 3.
        #expect(legs == [2400, 2400])
    }

    @Test("Full 3-pole on 3Ø splits √3 VA across all three legs")
    func fullThreePoleSplit() {
        let sys = PanelVoltageSystem.v120_208Three
        let entry = DesignSpaceEntry.full(poles: 3, circuit: .init(amps: 30, usedAmps: 30))
        let legs = PanelPhaseMath.perLegVA(entry: entry, anchoredAt: 1, system: sys)
        let total = 30.0 * 208 * 3.0.squareRoot()
        #expect(legs.count == 3)
        for leg in legs { #expect(abs(leg - total / 3) < 0.001) }
    }

    @Test("Spare full entries contribute nothing")
    func spareExcluded() {
        let sys = PanelVoltageSystem.v120_240Single3Wire
        let entry = DesignSpaceEntry.full(poles: 1, circuit: .init(amps: 20, type: .spare, usedAmps: 15))
        #expect(PanelPhaseMath.perLegVA(entry: entry, anchoredAt: 1, system: sys) == [0, 0])
    }

    // MARK: Per-leg splits — tandem

    @Test("Tandem halves both load the single space's leg")
    func tandemSingleLeg() {
        let sys = PanelVoltageSystem.v120_240Single3Wire
        let entry = DesignSpaceEntry.tandem(
            upper: .init(amps: 15, usedAmps: 10),
            lower: .init(amps: 20, usedAmps: 5)
        )
        let legs = PanelPhaseMath.perLegVA(entry: entry, anchoredAt: 3, system: sys)
        // Space 3 → leg B; (10+5)A @120V = 1800 VA all on leg B.
        #expect(legs == [0, 1800])
    }

    // MARK: Per-leg splits — quad modes

    @Test("Quad four-mode: top pair on anchor leg, bottom pair two spaces down")
    func quadFour() {
        let sys = PanelVoltageSystem.v120_240Single3Wire
        let entry = DesignSpaceEntry.quad(mode: .four, sections: [
            .init(amps: 15, usedAmps: 10), .init(amps: 15, usedAmps: 10),
            .init(amps: 20, usedAmps: 5), .init(amps: 20, usedAmps: 5),
        ])
        let legs = PanelPhaseMath.perLegVA(entry: entry, anchoredAt: 1, system: sys)
        // Top two: 20A@120 = 2400 on leg(1)=A; bottom two: 10A@120 = 1200 on leg(3)=B.
        #expect(legs == [2400, 1200])
    }

    @Test("Quad center-mode: outers on own legs, tied inner 2P split across both")
    func quadCenter() {
        let sys = PanelVoltageSystem.v120_240Single3Wire
        let entry = DesignSpaceEntry.quad(mode: .center, sections: [
            .init(amps: 20, usedAmps: 10),          // outer top → leg A
            .init(amps: 30, usedAmps: 20),          // inner 2P → split A/B
            .init(amps: 20, usedAmps: 10),          // outer bottom → leg B
        ])
        let legs = PanelPhaseMath.perLegVA(entry: entry, anchoredAt: 1, system: sys)
        // Outer: 10A@120=1200 each. Inner: 20A@240=4800 → 2400/leg.
        #expect(legs == [3600, 3600])
    }

    @Test("Quad double-mode: each independent 2P splits across both legs")
    func quadDouble() {
        let sys = PanelVoltageSystem.v120_240Single3Wire
        let entry = DesignSpaceEntry.quad(mode: .double, sections: [
            .init(amps: 30, usedAmps: 24),  // dryer
            .init(amps: 50, usedAmps: 40),  // range
        ])
        let legs = PanelPhaseMath.perLegVA(entry: entry, anchoredAt: 5, system: sys)
        // 24A@240=5760 + 40A@240=9600 → 15360 total, half per leg = 7680.
        #expect(legs == [7680, 7680])
    }

    // MARK: Occupancy

    @Test("Occupancy: full spans s+2 per extra pole; tandem one space; quad two")
    func occupancy() {
        #expect(DesignSpaceEntry.full(poles: 1, circuit: .init(amps: 20)).occupiedSpaces(anchoredAt: 4) == [4])
        #expect(DesignSpaceEntry.full(poles: 3, circuit: .init(amps: 30)).occupiedSpaces(anchoredAt: 1) == [1, 3, 5])
        #expect(DesignSpaceEntry.tandem(upper: .init(amps: 15), lower: .init(amps: 15)).occupiedSpaces(anchoredAt: 6) == [6])
        #expect(DesignSpaceEntry.quad(mode: .four, sections: []).occupiedSpaces(anchoredAt: 8) == [8, 10])
    }

    // MARK: Service sizing + wire table

    @Test("Service amps per system")
    func serviceAmps() {
        #expect(abs(PanelPhaseMath.serviceAmps(totalVA: 41600 * 3.0.squareRoot(), system: .v120_208Three) - 200) < 0.001)
        #expect(PanelPhaseMath.serviceAmps(totalVA: 48000, system: .v120_240Single3Wire) == 200)
        #expect(PanelPhaseMath.serviceAmps(totalVA: 12000, system: .v120Single2Wire) == 100)
    }

    @Test("Next standard service size rounds up and caps")
    func nextStandardSize() {
        #expect(PanelPhaseMath.nextStandardServiceSize(atLeast: 57) == 60)
        #expect(PanelPhaseMath.nextStandardServiceSize(atLeast: 60) == 60)
        #expect(PanelPhaseMath.nextStandardServiceSize(atLeast: 61) == 100)
        #expect(PanelPhaseMath.nextStandardServiceSize(atLeast: 187) == 200)
        #expect(PanelPhaseMath.nextStandardServiceSize(atLeast: 5000) == 1200)
    }

    @Test("Wire-size table matches spec breakpoints")
    func wireTable() {
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 15) == "#14 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 20) == "#12 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 30) == "#10 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 40) == "#8 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 50) == "#8 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 60) == "#6 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 100) == "#3 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 200) == "#3/0 Cu")
        #expect(PanelPhaseMath.wireSize(forBreakerAmps: 0) == nil)
    }

    @Test("Estimate button is 80% of breaker size")
    func estimate() {
        #expect(PanelPhaseMath.estimatedUsedAmps(forBreakerAmps: 20) == 16)
    }

    @Test("Catalog: short codes, colors, and constrained choices")
    func catalog() {
        #expect(DesignBreakerType.afci.shortCode == "CAFI")
        #expect(DesignBreakerType.standard.colorHex == "#0A84FF")
        #expect(DesignBreakerType.tandemAllowed.contains(.gfci))
        #expect(!DesignBreakerType.tandemAllowed.contains(.hacr))
        #expect(DesignBreakerType.quadTwoPoleAllowed.contains(.hacr))
        #expect(DesignBreakerType.fullAmpChoices.last == 100)
    }
}
