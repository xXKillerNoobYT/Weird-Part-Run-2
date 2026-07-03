import Foundation

/// A panel schedule documenting circuit breaker assignments in an electrical panel.
public struct PanelSchedule: Codable, Identifiable, Sendable {
    public var id: String
    public var panelName: String
    public var panelType: PanelType
    public var totalSpaces: Int
    public var mainBreakerAmps: Int?
    public var voltage: Int
    public var phase: Int
    public var location: String?
    public var circuits: [CircuitEntry]

    public init(
        id: String = UUID().uuidString,
        panelName: String = "Panel A",
        panelType: PanelType = .loadCenter,
        totalSpaces: Int = 20,
        mainBreakerAmps: Int? = 200,
        voltage: Int = 240,
        phase: Int = 1,
        location: String? = nil,
        circuits: [CircuitEntry] = []
    ) {
        self.id = id
        self.panelName = panelName
        self.panelType = panelType
        self.totalSpaces = totalSpaces
        self.mainBreakerAmps = mainBreakerAmps
        self.voltage = voltage
        self.phase = phase
        self.location = location
        self.circuits = circuits
    }

    /// The panel sizes the schedule builder UI supports selecting.
    public static let supportedTotalSpaces = [2, 4, 8, 12, 16, 20, 24, 30, 42]

    /// The fallback panel size used when a decoded value is unusable.
    public static let defaultTotalSpaces = 20

    /// Clamps a raw `totalSpaces` value onto a supported panel size.
    ///
    /// Panel schedules are decoded from notebook block JSON and sync payloads,
    /// so malformed values (negative, zero, or out-of-range) can reach the
    /// model. Rendering `0..<(totalSpaces / 2)` with a negative value traps at
    /// runtime (issue #1239), so every load path must normalize first.
    ///
    /// - Non-positive values fall back to the default panel size (20) so any
    ///   existing circuits stay visible and repairable.
    /// - Values between supported sizes round **up** to the next size so no
    ///   in-range circuit becomes hidden.
    /// - Values above the largest supported size clamp down to it (42).
    public static func normalizedTotalSpaces(_ raw: Int) -> Int {
        guard raw > 0 else { return defaultTotalSpaces }
        guard let clamped = supportedTotalSpaces.first(where: { $0 >= raw }) else {
            return supportedTotalSpaces.max() ?? defaultTotalSpaces
        }
        return clamped
    }

    /// Returns a copy whose `totalSpaces` is clamped to a supported panel size.
    /// Apply this to every schedule decoded from JSON before rendering it.
    public func clampingTotalSpacesToSupportedRange() -> PanelSchedule {
        var normalized = self
        normalized.totalSpaces = Self.normalizedTotalSpaces(totalSpaces)
        return normalized
    }

    /// Returns a copy safe to persist for the current panel size.
    ///
    /// Users can shrink `totalSpaces` from the builder settings while stale circuit
    /// entries remain in memory. Persisting the schedule unchanged would hide those
    /// circuits in the UI while keeping them in the saved JSON payload. Normalizing
    /// before save makes the persisted circuit list match the visible panel range.
    public func pruningCircuitsOutsideTotalSpaces() -> PanelSchedule {
        var normalized = self
        normalized.circuits = circuits.filter { circuit in
            circuit.spaceNumber >= 1 && circuit.spaceNumber <= totalSpaces
        }
        return normalized
    }

    /// Returns a copy safe to persist after panel builder edits.
    ///
    /// A circuit marked spare should not retain active breaker/load metadata that
    /// will be hidden by the grid and exports. Normalize the panel size, the
    /// visible panel range, and the per-circuit spare payload before writing
    /// notebook JSON. Clamping runs first so pruning uses the repaired size.
    public func normalizedForPersistence() -> PanelSchedule {
        var normalized = clampingTotalSpacesToSupportedRange()
            .pruningCircuitsOutsideTotalSpaces()
        normalized.circuits = normalized.circuits.map { $0.normalizedForPersistence() }
        return normalized
    }

    /// Circuits that would be removed by `pruningCircuitsOutsideTotalSpaces()`.
    public var circuitsOutsideTotalSpaces: [CircuitEntry] {
        circuits.filter { circuit in
            circuit.spaceNumber < 1 || circuit.spaceNumber > totalSpaces
        }
    }

    // MARK: - Circuit Position Validation (drag/drop + move mode)

    /// Validation errors for the *visible* panel range (1...totalSpaces).
    /// This is independent of the #1239 clamping/pruning above, which
    /// repairs a malformed `totalSpaces` itself; this instead validates
    /// circuit *placement* within an already-valid panel size — same-side
    /// double-breaker span and space occupancy conflicts.
    public var validationErrors: [PanelScheduleValidationError] {
        var errors: [PanelScheduleValidationError] = []
        var occupied: [Int: CircuitEntry] = [:]
        for circuit in circuits {
            guard (1...max(totalSpaces, 1)).contains(circuit.spaceNumber) else { continue }
            for space in occupiedSpaces(for: circuit) {
                guard (1...max(totalSpaces, 1)).contains(space) else {
                    errors.append(.doubleBreakerOutOfRange(space: circuit.spaceNumber))
                    continue
                }
                if let existing = occupied[space], existing.id != circuit.id {
                    errors.append(.spaceConflict(space: space, first: existing.spaceNumber, second: circuit.spaceNumber))
                } else {
                    occupied[space] = circuit
                }
            }
        }
        return errors
    }

    public var isValid: Bool {
        validationErrors.isEmpty
    }

    public func validated() throws {
        if let error = validationErrors.first {
            throw error
        }
    }

    /// Spaces a circuit occupies. Double breakers reserve the matching space
    /// two positions down on the same side (1+3, 2+4, ...).
    public func occupiedSpaces(for circuit: CircuitEntry) -> [Int] {
        guard circuit.breakerType == .double else {
            return [circuit.spaceNumber]
        }
        return [circuit.spaceNumber, circuit.spaceNumber + 2]
    }

    /// Inserts or replaces a circuit by id (falling back to matching space
    /// number for callers still keying off position), validating the result
    /// before committing.
    public mutating func upsertCircuit(_ circuit: CircuitEntry) throws {
        var candidate = self
        if let index = candidate.circuits.firstIndex(where: { $0.id == circuit.id || $0.spaceNumber == circuit.spaceNumber }) {
            candidate.circuits[index] = circuit
        } else {
            candidate.circuits.append(circuit)
        }
        try candidate.validated()
        self = candidate
    }

    /// Moves an existing circuit to a new space (drag/drop or tap-to-move),
    /// validating the destination before committing.
    public mutating func moveCircuit(id circuitId: String, to targetSpace: Int) throws {
        guard let index = circuits.firstIndex(where: { $0.id == circuitId }) else {
            throw PanelScheduleValidationError.circuitNotFound
        }
        var moved = circuits[index]
        moved.spaceNumber = targetSpace
        var candidate = self
        candidate.circuits[index] = moved
        try candidate.validated()
        self = candidate
    }
}

/// Panel types in electrical installations.
public enum PanelType: String, Codable, Sendable, CaseIterable {
    case mdp = "MDP"
    case subPanel = "Sub Panel"
    case disconnect = "Disconnect"
    case loadCenter = "Load Center"
    case smallPanel = "Small Panel"
}

/// A single circuit entry in a panel schedule.
public struct CircuitEntry: Codable, Identifiable, Sendable {
    public let id: String
    public var spaceNumber: Int
    public var breakerAmps: Int?
    public var breakerType: BreakerType
    public var circuitDescription: String
    public var wire: String?
    public var conduit: String?
    public var isSpare: Bool
    public var isFedFrom: String?
    public var classification: CircuitClassification
    public var secondaryCircuitDescription: String?

    public init(
        id: String = UUID().uuidString,
        spaceNumber: Int,
        breakerAmps: Int? = nil,
        breakerType: BreakerType = .spare,
        circuitDescription: String = "",
        wire: String? = nil,
        conduit: String? = nil,
        isSpare: Bool = true,
        isFedFrom: String? = nil,
        classification: CircuitClassification = .spare,
        secondaryCircuitDescription: String? = nil
    ) {
        self.id = id
        self.spaceNumber = spaceNumber
        self.breakerAmps = breakerAmps
        self.breakerType = breakerType
        self.circuitDescription = circuitDescription
        self.wire = wire
        self.conduit = conduit
        self.isSpare = isSpare
        self.isFedFrom = isFedFrom
        self.classification = classification
        self.secondaryCircuitDescription = secondaryCircuitDescription
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case spaceNumber
        case breakerAmps
        case breakerType
        case circuitDescription
        case wire
        case conduit
        case isSpare
        case isFedFrom
        case classification
        case secondaryCircuitDescription
    }

    /// Custom decode so panel JSON saved before `classification` and
    /// `secondaryCircuitDescription` existed keeps decoding without errors.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        spaceNumber = try container.decode(Int.self, forKey: .spaceNumber)
        breakerAmps = try container.decodeIfPresent(Int.self, forKey: .breakerAmps)
        breakerType = try container.decodeIfPresent(BreakerType.self, forKey: .breakerType) ?? .spare
        circuitDescription = try container.decodeIfPresent(String.self, forKey: .circuitDescription) ?? ""
        wire = try container.decodeIfPresent(String.self, forKey: .wire)
        conduit = try container.decodeIfPresent(String.self, forKey: .conduit)
        isSpare = try container.decodeIfPresent(Bool.self, forKey: .isSpare) ?? (breakerType == .spare)
        isFedFrom = try container.decodeIfPresent(String.self, forKey: .isFedFrom)
        classification = try container.decodeIfPresent(CircuitClassification.self, forKey: .classification)
            ?? (isSpare ? .spare : .special)
        secondaryCircuitDescription = try container.decodeIfPresent(String.self, forKey: .secondaryCircuitDescription)
    }

    /// Returns a persistable copy where spare circuits cannot keep hidden
    /// active-circuit metadata.
    public func normalizedForPersistence() -> CircuitEntry {
        guard isSpare else { return self }

        var normalized = self
        normalized.breakerAmps = nil
        normalized.breakerType = .spare
        normalized.circuitDescription = ""
        normalized.wire = nil
        normalized.conduit = nil
        normalized.isFedFrom = nil
        normalized.classification = .spare
        normalized.secondaryCircuitDescription = nil
        return normalized
    }
}

/// Breaker types for circuit entries.
public enum BreakerType: String, Codable, Sendable, CaseIterable {
    case single = "Single"
    case double = "Double"
    case tandem = "Tandem"
    case gfci = "GFCI"
    case afci = "AFCI"
    case dualFunction = "Dual Function"
    case spare = "Spare"
    case blank = "Blank"
}

/// Classification used for panel schedule color coding and downstream reporting.
public enum CircuitClassification: String, Codable, Sendable, CaseIterable {
    case lighting = "Lighting"
    case receptacle = "Receptacle"
    case motor = "Motor"
    case spare = "Spare"
    case blank = "Blank"
    case special = "Special"
}

public enum PanelScheduleValidationError: Error, LocalizedError, Equatable, Sendable {
    case spaceConflict(space: Int, first: Int, second: Int)
    case doubleBreakerOutOfRange(space: Int)
    case circuitNotFound

    public var errorDescription: String? {
        switch self {
        case .spaceConflict(let space, let first, let second):
            return "Space \(space) is already occupied by circuits \(first) and \(second)."
        case .doubleBreakerOutOfRange(let space):
            return "Double breaker at space \(space) must have the matching space below it on the same side."
        case .circuitNotFound:
            return "Circuit could not be found."
        }
    }
}
