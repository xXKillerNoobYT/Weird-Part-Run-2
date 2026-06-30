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
}
