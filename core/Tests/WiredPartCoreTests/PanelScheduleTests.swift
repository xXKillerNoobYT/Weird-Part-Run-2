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
}
