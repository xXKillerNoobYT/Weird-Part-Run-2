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

    @Test("Panel types expose picker options derived from global supported sizes",
          arguments: [
            (PanelType.mdp, [42]),
            (PanelType.subPanel, [20, 24, 30, 42]),
            (PanelType.loadCenter, [20, 24, 30]),
            (PanelType.smallPanel, [8, 12, 16, 20]),
            (PanelType.disconnect, [2])
          ])
    func panelTypeAllowedSpacesComposeWithGlobalNormalization(
        panelType: PanelType,
        expectedSpaces: [Int]
    ) {
        #expect(panelType.allowedTotalSpaces == expectedSpaces)
        #expect(panelType.allowedTotalSpaces.allSatisfy(PanelSchedule.supportedTotalSpaces.contains))
        #expect(!panelType.allows(totalSpaces: expectedSpaces.last! + 1))
    }

    @Test("Malformed load values stay circuit-editable and repairable without circuit loss")
    func malformedMDPLoadCanBeCorrectedWithoutLosingCircuits() throws {
        let decoded = PanelSchedule(
            panelType: .mdp,
            totalSpaces: -2,
            circuits: [
                CircuitEntry(id: "visible", spaceNumber: 1, circuitDescription: "Office", isSpare: false),
                CircuitEntry(id: "preserved", spaceNumber: 20, circuitDescription: "Shop", isSpare: false)
            ]
        )

        let display = decoded.clampingTotalSpacesToSupportedRange()

        #expect(display.totalSpaces == 20)
        #expect(display.circuits.map(\.id) == ["visible", "preserved"])
        #expect(display.panelSettingsValidationError == .invalidPanelTypeSpaceCount(
            panelType: .mdp,
            spaces: 20,
            allowedSpaces: [42]
        ))

        // Safe-loaded schedules can continue through circuit edit/save paths
        // before a user explicitly repairs their type/size settings.
        var repaired = display
        try repaired.moveCircuit(id: "visible", to: 3)
        try repaired.validated()
        try repaired.updatePanelSettings(panelType: .mdp, totalSpaces: 42)

        #expect(repaired.panelType == .mdp)
        #expect(repaired.totalSpaces == 42)
        #expect(repaired.circuits.map(\.id) == ["visible", "preserved"])
        #expect(repaired.circuits.first { $0.id == "visible" }?.spaceNumber == 3)
        #expect(repaired.normalizedForPersistence().circuits.map(\.id) == ["visible", "preserved"])
    }

    @Test("Invalid user panel-space edits are rejected atomically without circuit loss")
    func invalidPanelSpaceEditLeavesScheduleUnchanged() throws {
        var schedule = PanelSchedule(
            panelType: .loadCenter,
            totalSpaces: 20,
            circuits: [
                CircuitEntry(id: "office", spaceNumber: 1, circuitDescription: "Office", isSpare: false),
                CircuitEntry(id: "shop", spaceNumber: 20, circuitDescription: "Shop", isSpare: false)
            ]
        )

        #expect(throws: PanelScheduleValidationError.invalidPanelTypeSpaceCount(
            panelType: .disconnect,
            spaces: 20,
            allowedSpaces: [2]
        )) {
            try schedule.updatePanelSettings(panelType: .disconnect, totalSpaces: 20)
        }

        #expect(schedule.panelType == .loadCenter)
        #expect(schedule.totalSpaces == 20)
        #expect(schedule.circuits.map(\.id) == ["office", "shop"])
        #expect(schedule.circuits.map(\.spaceNumber) == [1, 20])
    }

    @Test("Shrinking panel settings rejects hidden circuits atomically")
    func shrinkingPanelSettingsLeavesCircuitsAndSettingsUnchanged() throws {
        var schedule = PanelSchedule(
            panelType: .mdp,
            totalSpaces: 42,
            circuits: [
                CircuitEntry(id: "main", spaceNumber: 1, circuitDescription: "Main feed", isSpare: false),
                CircuitEntry(id: "high-space", spaceNumber: 42, circuitDescription: "Roof unit", isSpare: false)
            ]
        )

        #expect(throws: PanelScheduleValidationError.panelSettingsWouldHideCircuits(
            panelType: .disconnect,
            spaces: 2,
            circuitSpaces: [42]
        )) {
            try schedule.updatePanelSettings(panelType: .disconnect, totalSpaces: 2)
        }

        #expect(schedule.panelType == .mdp)
        #expect(schedule.totalSpaces == 42)
        #expect(schedule.circuits.map(\.id) == ["main", "high-space"])
        #expect(schedule.circuits.map(\.spaceNumber) == [1, 42])
    }

    @Test("Shrinking panel settings rejects a double breaker whose second occupied space would be hidden")
    func shrinkingPanelSettingsRejectsHiddenDoubleBreakerOccupancy() throws {
        var schedule = PanelSchedule(
            panelType: .loadCenter,
            totalSpaces: 24,
            circuits: [
                CircuitEntry(
                    id: "range",
                    spaceNumber: 19,
                    breakerAmps: 40,
                    breakerType: .double,
                    circuitDescription: "Range",
                    isSpare: false,
                    classification: .special
                )
            ]
        )

        #expect(throws: PanelScheduleValidationError.panelSettingsWouldHideCircuits(
            panelType: .loadCenter,
            spaces: 20,
            circuitSpaces: [19]
        )) {
            try schedule.updatePanelSettings(panelType: .loadCenter, totalSpaces: 20)
        }

        #expect(schedule.panelType == .loadCenter)
        #expect(schedule.totalSpaces == 24)
        #expect(schedule.circuits.map(\.id) == ["range"])
        #expect(schedule.circuits.map(\.spaceNumber) == [19])
        #expect(schedule.occupiedSpaces(for: schedule.circuits[0]) == [19, 21])
    }

    // MARK: - Circuit classification, drag/drop move, and position validation

    @Test("Double breakers reserve same-side adjacent spaces")
    func doubleBreakerOverlapIsRejected() throws {
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
    func doubleBreakerOutOfRangeIsRejected() throws {
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

    @Test("Moving a circuit preserves metadata and validates the destination")
    func moveCircuitPreservesClassification() throws {
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

    @Test("Moving a circuit into an occupied space is rejected and the schedule is unchanged")
    func moveCircuitIntoConflictIsRejected() throws {
        var schedule = PanelSchedule(
            totalSpaces: 20,
            circuits: [
                CircuitEntry(id: "a", spaceNumber: 1, circuitDescription: "Office", isSpare: false, classification: .receptacle),
                CircuitEntry(id: "b", spaceNumber: 2, circuitDescription: "Shop", isSpare: false, classification: .receptacle)
            ]
        )

        #expect(throws: PanelScheduleValidationError.self) {
            try schedule.moveCircuit(id: "a", to: 2)
        }
        // Schedule must be unchanged after a rejected move.
        #expect(schedule.circuits.first { $0.id == "a" }?.spaceNumber == 1)
    }

    @Test("Moving an unknown circuit id throws circuitNotFound")
    func moveUnknownCircuitThrows() throws {
        var schedule = PanelSchedule(totalSpaces: 20, circuits: [])
        #expect(throws: PanelScheduleValidationError.circuitNotFound) {
            try schedule.moveCircuit(id: "missing", to: 1)
        }
    }

    @Test("Circuit classification decodes old panel JSON safely")
    func classificationDefaultsWhenDecodingLegacyJSON() throws {
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

    @Test("Small panel type is available and normalizes for persistence")
    func smallPanelTypeSupported() throws {
        #expect(PanelType.allCases.contains(.smallPanel))
        let schedule = PanelSchedule(panelType: .smallPanel, totalSpaces: 8)
        #expect(schedule.panelType == .smallPanel)
        #expect(PanelSchedule.supportedTotalSpaces.contains(schedule.totalSpaces))
    }
}
