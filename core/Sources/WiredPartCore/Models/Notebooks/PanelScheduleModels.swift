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

    public var validationErrors: [PanelScheduleValidationError] {
        var errors: [PanelScheduleValidationError] = []
        if !panelType.allowedSpaces.contains(totalSpaces) {
            errors.append(.invalidPanelSpaceCount(panelType: panelType, spaces: totalSpaces))
        }

        var occupied: [Int: CircuitEntry] = [:]
        for circuit in circuits {
            guard (1...totalSpaces).contains(circuit.spaceNumber) else {
                errors.append(.spaceOutOfRange(space: circuit.spaceNumber, totalSpaces: totalSpaces))
                continue
            }
            for space in occupiedSpaces(for: circuit) {
                guard (1...totalSpaces).contains(space) else {
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

    public func occupiedSpaces(for circuit: CircuitEntry) -> [Int] {
        guard circuit.breakerType == .double else {
            return [circuit.spaceNumber]
        }
        return [circuit.spaceNumber, circuit.spaceNumber + 2]
    }

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

    public var allowedSpaces: ClosedRange<Int> {
        switch self {
        case .mdp: return 42...84
        case .subPanel: return 20...42
        case .loadCenter: return 20...40
        case .smallPanel: return 8...20
        case .disconnect: return 2...2
        }
    }
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
    case invalidPanelSpaceCount(panelType: PanelType, spaces: Int)
    case spaceOutOfRange(space: Int, totalSpaces: Int)
    case doubleBreakerOutOfRange(space: Int)
    case spaceConflict(space: Int, first: Int, second: Int)
    case circuitNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidPanelSpaceCount(let panelType, let spaces):
            return "\(panelType.rawValue) panels do not support \(spaces) spaces."
        case .spaceOutOfRange(let space, let totalSpaces):
            return "Space \(space) is outside this \(totalSpaces)-space panel."
        case .doubleBreakerOutOfRange(let space):
            return "Double breaker at space \(space) must have the matching space below it on the same side."
        case .spaceConflict(let space, let first, let second):
            return "Space \(space) is already occupied by circuits \(first) and \(second)."
        case .circuitNotFound:
            return "Circuit could not be found."
        }
    }
}
