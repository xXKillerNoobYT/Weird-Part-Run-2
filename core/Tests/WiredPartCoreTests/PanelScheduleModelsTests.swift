import Foundation
import Testing
@testable import WiredPartCore

@Suite("PanelSchedule model validation")
struct PanelScheduleModelsTests {

    @Test("Double breakers reserve same-side adjacent spaces")
    func testDoubleBreakerOverlapIsRejected() throws {
        let doubleBreaker = CircuitEntry(
            id: "a",
            spaceNumber: 1,
            breakerAmps: 30,
            breakerType: .double,
            circuitDescription: "Range",
            isSpare: false,
            classification: .special
        )
        let occupiedLowerSpace = CircuitEntry(
            id: "b",
            spaceNumber: 3,
            breakerAmps: 20,
            breakerType: .single,
            circuitDescription: "Kitchen",
            isSpare: false,
            classification: .receptacle
        )
        let schedule = PanelSchedule(totalSpaces: 20, circuits: [doubleBreaker, occupiedLowerSpace])

        #expect(schedule.validationErrors.contains(.spaceConflict(space: 3, first: 1, second: 3)))
    }

    @Test("Double breakers cannot hang past the last same-side space")
    func testDoubleBreakerOutOfRangeIsRejected() throws {
        let schedule = PanelSchedule(
            totalSpaces: 20,
            circuits: [
                CircuitEntry(
                    spaceNumber: 19,
                    breakerAmps: 40,
                    breakerType: .double,
                    circuitDescription: "Condenser",
                    isSpare: false,
                    classification: .motor
                )
            ]
        )

        #expect(schedule.validationErrors.contains(.doubleBreakerOutOfRange(space: 19)))
    }

    @Test("Panel type space constraints are enforced")
    func testPanelTypeSpaceConstraints() throws {
        let disconnect = PanelSchedule(panelType: .disconnect, totalSpaces: 20)
        let smallPanel = PanelSchedule(panelType: .smallPanel, totalSpaces: 12)

        #expect(disconnect.validationErrors.contains(.invalidPanelSpaceCount(panelType: .disconnect, spaces: 20)))
        #expect(smallPanel.isValid)
    }

    @Test("Moving a circuit preserves metadata and validates destination")
    func testMoveCircuitPreservesClassification() throws {
        var schedule = PanelSchedule(
            totalSpaces: 20,
            circuits: [
                CircuitEntry(
                    id: "lighting-1",
                    spaceNumber: 1,
                    breakerAmps: 15,
                    breakerType: .single,
                    circuitDescription: "Hall lights",
                    isSpare: false,
                    classification: .lighting
                )
            ]
        )

        try schedule.moveCircuit(id: "lighting-1", to: 5)

        let moved = try #require(schedule.circuits.first)
        #expect(moved.spaceNumber == 5)
        #expect(moved.classification == .lighting)
        #expect(moved.circuitDescription == "Hall lights")
    }

    @Test("Circuit classification decodes old panel JSON safely")
    func testClassificationDefaultsWhenDecodingLegacyJSON() throws {
        let json = """
        {
          "id": "schedule",
          "panelName": "Panel A",
          "panelType": "Load Center",
          "totalSpaces": 20,
          "mainBreakerAmps": 200,
          "voltage": 240,
          "phase": 1,
          "circuits": [
            {
              "id": "legacy",
              "spaceNumber": 1,
              "breakerType": "Single",
              "circuitDescription": "Kitchen",
              "isSpare": false
            }
          ]
        }
        """

        let schedule = try JSONDecoder().decode(PanelSchedule.self, from: Data(json.utf8))

        #expect(schedule.circuits.first?.classification == .special)
    }
}
