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
}

/// Panel types in electrical installations.
public enum PanelType: String, Codable, Sendable, CaseIterable {
    case mdp = "MDP"
    case subPanel = "Sub Panel"
    case disconnect = "Disconnect"
    case loadCenter = "Load Center"
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

    public init(
        id: String = UUID().uuidString,
        spaceNumber: Int,
        breakerAmps: Int? = nil,
        breakerType: BreakerType = .spare,
        circuitDescription: String = "",
        wire: String? = nil,
        conduit: String? = nil,
        isSpare: Bool = true,
        isFedFrom: String? = nil
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
