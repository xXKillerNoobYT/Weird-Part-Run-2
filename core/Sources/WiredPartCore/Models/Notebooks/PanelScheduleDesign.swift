import Foundation

// Panel Schedule Builder visual redesign — domain layer (slice 1).
// Spec: docs/plans/panel-schedule-builder-visual-redesign.md §2–§3.
// Additive alongside PanelScheduleModels.swift: `CircuitEntry` and the
// #1514/#1515 validation invariants stay authoritative for persisted
// schedules; this layer models the redesigned builder's richer space
// entries and electrical math. UI colors are hex strings here — core is
// UI-framework-free.

// MARK: - Voltage systems

/// The service voltage systems the panel setup sheet offers.
public enum PanelVoltageSystem: String, Codable, Sendable, CaseIterable {
    case v120Single2Wire = "120V 1Ø 2-wire"
    case v120_240Single3Wire = "120/240V 1Ø 3-wire"
    case v120_208Three = "120/208V 3Ø"
    case v277_480Three = "277/480V 3Ø"

    /// Line-to-neutral volts (single-pole circuits).
    public var vln: Double {
        switch self {
        case .v120Single2Wire, .v120_240Single3Wire, .v120_208Three: return 120
        case .v277_480Three: return 277
        }
    }

    /// Line-to-line volts (2/3-pole circuits).
    public var vll: Double {
        switch self {
        case .v120Single2Wire: return 120
        case .v120_240Single3Wire: return 240
        case .v120_208Three: return 208
        case .v277_480Three: return 480
        }
    }

    /// Number of phase legs feeding the panel.
    public var legCount: Int {
        switch self {
        case .v120Single2Wire: return 1
        case .v120_240Single3Wire: return 2
        case .v120_208Three, .v277_480Three: return 3
        }
    }

    /// Leg (0-based) serving a given space number.
    /// `phaseFor(space) = legs[(ceil(space/2) - 1) % legCount]` per spec §2.
    public func legIndex(forSpace space: Int) -> Int {
        let row = (space + 1) / 2 // ceil(space/2) for positive ints
        return (row - 1).quotientAndRemainder(dividingBy: legCount).remainder
    }
}

/// Phase-leg display metadata (letters + hex colors per spec §2).
public enum PanelPhaseLeg: Int, CaseIterable, Sendable {
    case a = 0, b = 1, c = 2

    public var letter: String { ["A", "B", "C"][rawValue] }
    public var colorHex: String { ["#0A84FF", "#FF9F0A", "#BF5AF2"][rawValue] }
    /// Tie accent for 240V pairs inside quads (spec §2).
    public static let tieColorHex = "#5E5CE6"
}

// MARK: - Breaker type catalog

/// The redesigned color-coded breaker type catalog (spec §2 table).
/// Distinct from the legacy `BreakerType` persistence enum — a design entry
/// describes protection function; the space entry's kind describes form.
public enum DesignBreakerType: String, Codable, Sendable, CaseIterable {
    case standard = "STD"
    case gfci = "GFCI"
    case afci = "AFCI"
    case dualFunction = "DF"
    case gfpe = "GFPE"
    case hacr = "HACR"
    case general = "GEN"
    case spare = "SPARE"

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .gfci: return "GFCI"
        case .afci: return "AFCI"
        case .dualFunction: return "Dual-Fn"
        case .gfpe: return "GFPE"
        case .hacr: return "HACR"
        case .general: return "General"
        case .spare: return "Spare"
        }
    }

    /// Short code printed on schedules (spec: AFCI prints "CAFI").
    public var shortCode: String {
        switch self {
        case .afci: return "CAFI"
        case .spare: return "—"
        default: return rawValue
        }
    }

    public var colorHex: String {
        switch self {
        case .standard: return "#0A84FF"
        case .gfci: return "#00B0A6"
        case .afci: return "#FF9F0A"
        case .dualFunction: return "#BF5AF2"
        case .gfpe: return "#FF375F"
        case .hacr: return "#30D158"
        case .general: return "#8E8E93"
        case .spare: return "#C7C7CC"
        }
    }

    /// Types offered for tandem halves (spec §2 amp/type constraints).
    public static let tandemAllowed: [DesignBreakerType] = [.standard, .gfci, .afci, .dualFunction]
    /// Types offered for quad 2-pole sections.
    public static let quadTwoPoleAllowed: [DesignBreakerType] = [.standard, .hacr, .gfpe, .gfci]

    /// Amp choices per context (spec §2).
    public static let fullAmpChoices = [15, 20, 25, 30, 40, 50, 60, 70, 90, 100]
    public static let tandemHalfAmpChoices = [15, 20, 30]
    public static let quadTwoPoleAmpChoices = [15, 20, 30, 40, 50, 60]
}

// MARK: - Space entries

/// One sub-circuit inside a space entry (a tandem half, a quad section, or
/// the single circuit of a full entry).
public struct DesignSubCircuit: Codable, Sendable, Equatable {
    public var amps: Int
    public var type: DesignBreakerType
    /// Connected ("used") amps for load math — the value behind the A/W toggle.
    public var usedAmps: Double
    public var name: String
    public var note: String

    public init(amps: Int, type: DesignBreakerType = .standard, usedAmps: Double = 0, name: String = "", note: String = "") {
        self.amps = amps
        self.type = type
        self.usedAmps = usedAmps
        self.name = name
        self.note = note
    }
}

/// Quad occupancy modes (spec §2).
public enum QuadMode: String, Codable, Sendable, CaseIterable {
    /// Four independent 120V singles (labels 8a, 8b, 10a, 10b).
    case four
    /// Outer singles + tied inner 2-pole 240V (e.g. 20·30·20; label 8–10).
    case center
    /// Two independent 2-pole breakers (e.g. 30/50; labels 8–10↑, 8–10↓).
    case double
}

/// A redesigned panel space entry. A panel maps space numbers to entries;
/// entries with poles > 1 or quad kinds span additional same-side spaces.
public enum DesignSpaceEntry: Codable, Sendable, Equatable {
    /// Standard breaker: 1/2/3 poles spanning s, s+2, s+4 on one side.
    case full(poles: Int, circuit: DesignSubCircuit)
    /// Twin — two half-width circuits in ONE space, both on that space's leg.
    case tandem(upper: DesignSubCircuit, lower: DesignSubCircuit)
    /// Quad — occupies s and s+2, contents per mode. `sections` are ordered
    /// top-to-bottom (four: 4 singles; center: [outerTop, inner2P, outerBottom];
    /// double: [upper2P, lower2P]).
    case quad(mode: QuadMode, sections: [DesignSubCircuit])

    /// Spaces this entry occupies when anchored at `space`.
    public func occupiedSpaces(anchoredAt space: Int) -> [Int] {
        switch self {
        case .full(let poles, _):
            return (0..<max(poles, 1)).map { space + $0 * 2 }
        case .tandem:
            return [space]
        case .quad:
            return [space, space + 2]
        }
    }

    /// Sub-circuits with the leg offset (in same-side steps) each one loads.
    /// Offsets feed `PanelVoltageSystem.legIndex(forSpace: space + 2*offset)`.
    /// Multi-pole circuits appear once per spanned leg with their VA split
    /// handled by the math layer (spec §3).
    public var sections: [DesignSubCircuit] {
        switch self {
        case .full(_, let circuit): return [circuit]
        case .tandem(let upper, let lower): return [upper, lower]
        case .quad(_, let sections): return sections
        }
    }
}

// MARK: - Electrical math (spec §3)

public enum PanelPhaseMath {
    /// Volts seen by a circuit of the given pole count.
    public static func circuitVolts(poles: Int, system: PanelVoltageSystem) -> Double {
        poles >= 2 ? system.vll : system.vln
    }

    /// Connected VA for a circuit (spec: 3-pole uses vll·√3).
    public static func watts(amps: Double, poles: Int, system: PanelVoltageSystem) -> Double {
        guard amps > 0 else { return 0 }
        if poles >= 3 { return amps * system.vll * 3.0.squareRoot() }
        return amps * circuitVolts(poles: poles, system: system)
    }

    /// Per-leg connected VA for one anchored entry (spec §3 splitting rules).
    /// Returns a `legCount`-sized array.
    public static func perLegVA(
        entry: DesignSpaceEntry,
        anchoredAt space: Int,
        system: PanelVoltageSystem
    ) -> [Double] {
        var legs = [Double](repeating: 0, count: system.legCount)
        func add(_ va: Double, toLegOfSpace s: Int) {
            legs[system.legIndex(forSpace: s)] += va
        }
        switch entry {
        case .full(let poles, let circuit):
            guard circuit.type != .spare else { break }
            let total = watts(amps: circuit.usedAmps, poles: poles, system: system)
            let spanned = entry.occupiedSpaces(anchoredAt: space)
            for s in spanned { add(total / Double(spanned.count), toLegOfSpace: s) }
        case .tandem(let upper, let lower):
            for half in [upper, lower] where half.type != .spare {
                add(watts(amps: half.usedAmps, poles: 1, system: system), toLegOfSpace: space)
            }
        case .quad(let mode, let sections):
            switch mode {
            case .four:
                // Top two on leg(space); bottom two on leg(space+2).
                for (index, section) in sections.prefix(4).enumerated() where section.type != .spare {
                    let s = index < 2 ? space : space + 2
                    add(watts(amps: section.usedAmps, poles: 1, system: system), toLegOfSpace: s)
                }
            case .center:
                // [outerTop(1P @space), inner 2P (split across both), outerBottom(1P @space+2)]
                if sections.indices.contains(0), sections[0].type != .spare {
                    add(watts(amps: sections[0].usedAmps, poles: 1, system: system), toLegOfSpace: space)
                }
                if sections.indices.contains(1), sections[1].type != .spare {
                    let inner = watts(amps: sections[1].usedAmps, poles: 2, system: system)
                    add(inner / 2, toLegOfSpace: space)
                    add(inner / 2, toLegOfSpace: space + 2)
                }
                if sections.indices.contains(2), sections[2].type != .spare {
                    add(watts(amps: sections[2].usedAmps, poles: 1, system: system), toLegOfSpace: space + 2)
                }
            case .double:
                // Two independent 2-pole breakers; each splits across both legs.
                for section in sections.prefix(2) where section.type != .spare {
                    let va = watts(amps: section.usedAmps, poles: 2, system: system)
                    add(va / 2, toLegOfSpace: space)
                    add(va / 2, toLegOfSpace: space + 2)
                }
            }
        }
        return legs
    }

    /// Balanced service amps from a total connected VA (spec §3).
    public static func serviceAmps(totalVA: Double, system: PanelVoltageSystem) -> Double {
        guard totalVA > 0 else { return 0 }
        switch system {
        case .v120_208Three, .v277_480Three:
            return totalVA / (3.0.squareRoot() * system.vll)
        case .v120_240Single3Wire:
            return totalVA / system.vll
        case .v120Single2Wire:
            return totalVA / system.vln
        }
    }

    /// Editor "Estimate" helper: 80% of breaker size (spec §3).
    public static func estimatedUsedAmps(forBreakerAmps amps: Int) -> Double {
        Double(amps) * 0.8
    }

    /// Standard service/OCPD sizes for the "Min. service" print field (§5).
    public static let standardServiceSizes = [
        60, 100, 125, 150, 175, 200, 225, 250, 300, 350, 400,
        450, 500, 600, 700, 800, 1000, 1200,
    ]

    /// Next standard size at or above `amps` (caps at the largest listed).
    public static func nextStandardServiceSize(atLeast amps: Double) -> Int {
        standardServiceSizes.first { Double($0) >= amps } ?? standardServiceSizes[standardServiceSizes.count - 1]
    }

    /// Copper THHN wire-size auto-column (spec §5 table).
    public static func wireSize(forBreakerAmps amps: Int) -> String? {
        switch amps {
        case ...0: return nil
        case ...15: return "#14 Cu"
        case ...20: return "#12 Cu"
        case ...30: return "#10 Cu"
        case ...50: return "#8 Cu"
        case ...60: return "#6 Cu"
        case ...70: return "#4 Cu"
        case ...100: return "#3 Cu"
        case ...125: return "#1 Cu"
        case ...150: return "#1/0 Cu"
        case ...175: return "#2/0 Cu"
        case ...200: return "#3/0 Cu"
        default: return nil
        }
    }
}
