import Foundation
import Testing
@testable import WiredPartCore

@Suite("Panel schedule tests")
struct PanelScheduleTests {
    @Test("Pruning removes circuits outside total spaces before persistence")
    func pruningCircuitsOutsideTotalSpacesDropsHiddenCircuits() {
        let schedule = PanelSchedule(
            totalSpaces: 20,
            circuits: [
                CircuitEntry(spaceNumber: 1, breakerAmps: 20, breakerType: .single, circuitDescription: "Office", isSpare: false),
                CircuitEntry(spaceNumber: 20, breakerAmps: 20, breakerType: .single, circuitDescription: "Shop", isSpare: false),
                CircuitEntry(spaceNumber: 21, breakerAmps: 15, breakerType: .single, circuitDescription: "Hidden old circuit", isSpare: false),
                CircuitEntry(spaceNumber: 42, breakerAmps: 30, breakerType: .double, circuitDescription: "Hidden range", isSpare: false)
            ]
        )

        let normalized = schedule.pruningCircuitsOutsideTotalSpaces()

        #expect(normalized.totalSpaces == 20)
        #expect(normalized.circuits.map(\.spaceNumber) == [1, 20])
        #expect(normalized.circuits.allSatisfy { $0.spaceNumber <= normalized.totalSpaces })
        #expect(schedule.circuitsOutsideTotalSpaces.map(\.spaceNumber) == [21, 42])
    }

    @Test("Spare circuits drop hidden active metadata before persistence")
    func spareCircuitsDropActiveMetadataBeforePersistence() {
        let activeSpare = CircuitEntry(
            spaceNumber: 7,
            breakerAmps: 20,
            breakerType: .single,
            circuitDescription: "Old office outlets",
            wire: "#12 THHN",
            conduit: "3/4 EMT",
            isSpare: true,
            isFedFrom: "MDP"
        )

        let normalizedCircuit = activeSpare.normalizedForPersistence()

        #expect(normalizedCircuit.spaceNumber == 7)
        #expect(normalizedCircuit.isSpare)
        #expect(normalizedCircuit.breakerAmps == nil)
        #expect(normalizedCircuit.breakerType == .spare)
        #expect(normalizedCircuit.circuitDescription.isEmpty)
        #expect(normalizedCircuit.wire == nil)
        #expect(normalizedCircuit.conduit == nil)
        #expect(normalizedCircuit.isFedFrom == nil)
    }

    @Test("Panel persistence normalizes spare circuits and hidden range together")
    func panelPersistenceNormalizesSpareCircuitsAndHiddenRange() {
        let schedule = PanelSchedule(
            totalSpaces: 20,
            circuits: [
                CircuitEntry(
                    spaceNumber: 1,
                    breakerAmps: 20,
                    breakerType: .single,
                    circuitDescription: "Hidden active data",
                    wire: "#12 THHN",
                    conduit: "1/2 EMT",
                    isSpare: true,
                    isFedFrom: "Panel B"
                ),
                CircuitEntry(spaceNumber: 21, breakerAmps: 15, breakerType: .single, circuitDescription: "Hidden old circuit", isSpare: false)
            ]
        )

        let normalized = schedule.normalizedForPersistence()

        #expect(normalized.circuits.count == 1)
        let circuit = normalized.circuits[0]
        #expect(circuit.spaceNumber == 1)
        #expect(circuit.isSpare)
        #expect(circuit.breakerAmps == nil)
        #expect(circuit.breakerType == .spare)
        #expect(circuit.circuitDescription.isEmpty)
        #expect(circuit.wire == nil)
        #expect(circuit.conduit == nil)
        #expect(circuit.isFedFrom == nil)
    }

    @Test("Malformed totalSpaces values clamp to supported panel sizes",
          arguments: [
            (-2, 20),   // negative → default (issue #1239 crash repro)
            (0, 20),    // zero → default
            (3, 4),     // between sizes → round up
            (15, 16),   // odd → next even supported size
            (18, 20),   // between sizes → round up
            (30, 30),   // supported value unchanged
            (43, 42),   // above max → clamp down
            (999, 42)   // absurd → clamp down
          ])
    func malformedTotalSpacesClampsToSupportedSize(raw: Int, expected: Int) {
        #expect(PanelSchedule.normalizedTotalSpaces(raw) == expected)

        let schedule = PanelSchedule(totalSpaces: raw)
        let clamped = schedule.clampingTotalSpacesToSupportedRange()
        #expect(clamped.totalSpaces == expected)
        #expect(PanelSchedule.supportedTotalSpaces.contains(clamped.totalSpaces))

        // The exact expression the builder renders must be constructible —
        // a negative upper bound used to trap here (issue #1239).
        let rows = 0..<max(clamped.totalSpaces / 2, 0)
        #expect(!rows.isEmpty)
    }

    @Test("Decoding malformed JSON totalSpaces stays renderable and persistable")
    func decodedMalformedTotalSpacesIsRepairable() throws {
        let json = """
        {"id":"p1","panelName":"Panel A","panelType":"Load Center",
         "totalSpaces":-2,"mainBreakerAmps":200,"voltage":240,"phase":1,
         "circuits":[
            {"id":"c1","spaceNumber":1,"breakerAmps":20,"breakerType":"Single",
             "circuitDescription":"Office","isSpare":false},
            {"id":"c2","spaceNumber":21,"breakerAmps":15,"breakerType":"Single",
             "circuitDescription":"Out of range","isSpare":false}
         ]}
        """
        let decoded = try JSONDecoder().decode(PanelSchedule.self, from: Data(json.utf8))
        #expect(decoded.totalSpaces == -2)

        // Load path: clamping repairs the size without dropping circuits.
        let display = decoded.clampingTotalSpacesToSupportedRange()
        #expect(display.totalSpaces == 20)
        #expect(display.circuits.count == 2)

        // Save path: persistence clamps first, then prunes against the
        // repaired size — never against the malformed one.
        let persisted = decoded.normalizedForPersistence()
        #expect(persisted.totalSpaces == 20)
        #expect(persisted.circuits.map(\.spaceNumber) == [1])
    }
}
