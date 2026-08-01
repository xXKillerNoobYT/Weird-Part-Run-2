import Foundation

// Panel Schedule Builder redesign — panel state (slice 3 foundation).
// Spec: docs/plans/panel-schedule-builder-visual-redesign.md §1–§3.
// The redesigned builder's document: panel setup + a map of anchor space →
// DesignSpaceEntry, with the spec's save semantics (saving an entry deletes
// anything it overlaps), CTL-aware tandem slotting, aggregate phase math for
// the balance card, and a legacy CircuitEntry projection so the existing
// print/export pipeline keeps working until the print slice replaces it.

/// Panel setup fields from the setup sheet (spec §2).
public struct DesignPanelSetup: Codable, Sendable, Equatable {
    public var brand: String
    public var model: String
    public var panelKind: PanelKind
    public var voltageSystem: PanelVoltageSystem
    /// CTL on = tandems allowed in any slot; off = only marked slots.
    public var ctlTandemsAnySlot: Bool
    /// Spaces marked for tandems when CTL is off (e.g. a 40/40 panel's marks).
    public var ctlMarkedSpaces: Set<Int>
    public var totalSpaces: Int
    public var mainAmps: Int

    public enum PanelKind: String, Codable, Sendable, CaseIterable {
        case mainBreaker = "Main Breaker"
        case mainLug = "Main Lug"
        case subPanel = "Sub-Panel"
    }

    public static let brandChoices = ["Square D", "Eaton", "Siemens", "GE", "Cutler-Hammer", "Murray"]
    public static let mainAmpChoices = [100, 125, 150, 200, 225, 400]

    public init(
        brand: String = "Square D",
        model: String = "QO",
        panelKind: PanelKind = .mainBreaker,
        voltageSystem: PanelVoltageSystem = .v120_240Single3Wire,
        ctlTandemsAnySlot: Bool = true,
        ctlMarkedSpaces: Set<Int> = [],
        totalSpaces: Int = 40,
        mainAmps: Int = 200
    ) {
        self.brand = brand
        self.model = model
        self.panelKind = panelKind
        self.voltageSystem = voltageSystem
        self.ctlTandemsAnySlot = ctlTandemsAnySlot
        self.ctlMarkedSpaces = ctlMarkedSpaces
        self.totalSpaces = Self.clampSpaces(totalSpaces)
        self.mainAmps = mainAmps
    }

    /// Spaces are even, clamped 4...200 (spec §2 setup sheet).
    public static func clampSpaces(_ raw: Int) -> Int {
        let clamped = min(max(raw, 4), 200)
        return clamped - (clamped % 2)
    }
}

/// Errors from redesigned-panel placement.
public enum DesignPanelError: Error, Equatable, Sendable {
    /// Entry would occupy a space outside 1...totalSpaces.
    case outOfRange(spaces: [Int])
    /// Tandem placed in an unmarked slot while CTL is off.
    case tandemSlotNotMarked(space: Int)
}

/// The redesigned panel document.
public struct DesignPanelState: Codable, Sendable, Equatable {
    public var setup: DesignPanelSetup
    /// Anchor space number → entry. Anchors are the entry's topmost space.
    public var entries: [Int: DesignSpaceEntry]
    /// Layout the user last chose (Classic | List | Visual; spec §1 —
    /// state survives relaunch via persistence with the notebook JSON).
    public var layout: Layout

    public enum Layout: String, Codable, Sendable, CaseIterable {
        case classic = "Classic"
        case list = "List"
        case visual = "Visual"
    }

    public init(
        setup: DesignPanelSetup = DesignPanelSetup(),
        entries: [Int: DesignSpaceEntry] = [:],
        layout: Layout = .visual
    ) {
        self.setup = setup
        self.entries = entries
        self.layout = layout
    }

    // MARK: - Occupancy

    /// Anchor owning each occupied space.
    public var occupancy: [Int: Int] {
        var map: [Int: Int] = [:]
        for (anchor, entry) in entries {
            for space in entry.occupiedSpaces(anchoredAt: anchor) {
                map[space] = anchor
            }
        }
        return map
    }

    public func entry(coveringSpace space: Int) -> (anchor: Int, entry: DesignSpaceEntry)? {
        guard let anchor = occupancy[space], let entry = entries[anchor] else { return nil }
        return (anchor, entry)
    }

    public var freeSpaces: [Int] {
        let occupied = Set(occupancy.keys)
        return (1...setup.totalSpaces).filter { !occupied.contains($0) }
    }

    /// The next free space for List view's Add Circuit (spec §1).
    public var nextFreeSpace: Int? { freeSpaces.first }

    // MARK: - Mutation (spec §2 save semantics)

    /// Saves an entry at an anchor. Per spec, saving deletes ANY overlapping
    /// entries; passing nil clears the anchor's entry (SPARE semantics).
    /// Throws for out-of-range placement or CTL-violating tandems — those are
    /// user-visible errors, not silent repairs.
    public mutating func save(_ entry: DesignSpaceEntry?, atAnchor anchor: Int) throws {
        guard let entry else {
            entries[anchor] = nil
            return
        }
        let spaces = entry.occupiedSpaces(anchoredAt: anchor)
        let outside = spaces.filter { $0 < 1 || $0 > setup.totalSpaces }
        guard outside.isEmpty else { throw DesignPanelError.outOfRange(spaces: outside) }

        if case .tandem = entry, !setup.ctlTandemsAnySlot, !setup.ctlMarkedSpaces.contains(anchor) {
            throw DesignPanelError.tandemSlotNotMarked(space: anchor)
        }

        // Delete anything the new entry overlaps (including an entry whose
        // span reaches into our spaces from an earlier anchor).
        let conflictingAnchors = Set(spaces.compactMap { occupancy[$0] })
        for conflicting in conflictingAnchors { entries[conflicting] = nil }
        entries[anchor] = entry
    }

    // MARK: - Aggregates (phase balance card, spec §1/§3)

    /// Per-leg connected VA across the whole panel.
    public var perLegVA: [Double] {
        var legs = [Double](repeating: 0, count: setup.voltageSystem.legCount)
        for (anchor, entry) in entries {
            let entryLegs = PanelPhaseMath.perLegVA(entry: entry, anchoredAt: anchor, system: setup.voltageSystem)
            for (index, va) in entryLegs.enumerated() { legs[index] += va }
        }
        return legs
    }

    /// Per-leg connected amps (VA / vln — leg amps are line-to-neutral).
    public var perLegAmps: [Double] {
        perLegVA.map { $0 / setup.voltageSystem.vln }
    }

    public var totalConnectedVA: Double { perLegVA.reduce(0, +) }

    public var serviceAmps: Double {
        PanelPhaseMath.serviceAmps(totalVA: totalConnectedVA, system: setup.voltageSystem)
    }

    /// Largest-leg callout numbers (amps, fraction of main; spec §1).
    public var largestLeg: (leg: Int, amps: Double, fractionOfMain: Double) {
        let amps = perLegAmps
        let maxIndex = amps.indices.max(by: { amps[$0] < amps[$1] }) ?? 0
        let fraction = setup.mainAmps > 0 ? min(amps[maxIndex] / Double(setup.mainAmps), 1.0) : 0
        return (maxIndex, amps[maxIndex], fraction)
    }

    // MARK: - Legacy projection (export compatibility until the print slice)

    /// Flattens entries into legacy `CircuitEntry` rows so the existing PDF
    /// export keeps producing correct-if-plainer output. Sub-circuits get
    /// their own rows labeled per spec (6a/6b, 8–10↑ …) via the description.
    public func legacyCircuits() -> [CircuitEntry] {
        var rows: [CircuitEntry] = []
        for (anchor, entry) in entries.sorted(by: { $0.key < $1.key }) {
            switch entry {
            case .full(let poles, let circuit):
                rows.append(CircuitEntry(
                    spaceNumber: anchor,
                    breakerAmps: circuit.amps,
                    breakerType: poles >= 2 ? .double : .single,
                    circuitDescription: circuit.name,
                    isSpare: circuit.type == .spare,
                    classification: circuit.type == .spare ? .spare : .special
                ))
            case .tandem(let upper, let lower):
                rows.append(CircuitEntry(
                    spaceNumber: anchor,
                    breakerAmps: upper.amps,
                    breakerType: .tandem,
                    circuitDescription: upper.name,
                    isSpare: upper.type == .spare,
                    classification: .special,
                    secondaryCircuitDescription: lower.name.isEmpty ? nil : lower.name
                ))
            case .quad(_, let sections):
                for (offset, section) in sections.enumerated() where section.type != .spare {
                    rows.append(CircuitEntry(
                        spaceNumber: anchor,
                        breakerAmps: section.amps,
                        breakerType: .tandem,
                        circuitDescription: section.name.isEmpty ? "Quad \(offset + 1)" : section.name,
                        isSpare: false,
                        classification: .special
                    ))
                }
            }
        }
        return rows
    }
}

// MARK: - Legacy migration (integration slice)

extension DesignPanelState {
    /// Best-effort seed from a legacy `PanelSchedule` so an existing panel
    /// opens in the redesigned builder with its circuits in place. Singles
    /// become 1-pole fulls, doubles 2-pole fulls, tandems twin entries;
    /// spares are skipped (open spaces). Entries that no longer fit (overlap
    /// or out of range) are dropped rather than corrupting the map — the
    /// legacy entry remains untouched as the source of truth for exports
    /// until the user saves from the new builder.
    public static func migrated(fromLegacy legacy: PanelSchedule) -> DesignPanelState {
        var state = DesignPanelState(setup: DesignPanelSetup(
            totalSpaces: DesignPanelSetup.clampSpaces(legacy.totalSpaces),
            mainAmps: legacy.mainBreakerAmps ?? 200
        ))
        for circuit in legacy.circuits where !circuit.isSpare && circuit.breakerType != .spare && circuit.breakerType != .blank {
            let amps = circuit.breakerAmps ?? 20
            let type: DesignBreakerType
            switch circuit.breakerType {
            case .gfci: type = .gfci
            case .afci: type = .afci
            case .dualFunction: type = .dualFunction
            default: type = .standard
            }
            let sub = DesignSubCircuit(amps: amps, type: type, name: circuit.circuitDescription)
            let entry: DesignSpaceEntry
            switch circuit.breakerType {
            case .double:
                entry = .full(poles: 2, circuit: sub)
            case .tandem:
                entry = .tandem(
                    upper: sub,
                    lower: DesignSubCircuit(
                        amps: amps,
                        type: type,
                        name: circuit.secondaryCircuitDescription ?? ""
                    )
                )
            default:
                entry = .full(poles: 1, circuit: sub)
            }
            try? state.save(entry, atAnchor: circuit.spaceNumber)
        }
        return state
    }
}

// MARK: - Add to JPO (spec §1)

extension DesignPanelState {
    /// One line per breaker to purchase, for a draft JPO's notes. Breakers
    /// are hardware, not catalog parts, so v1 ships the list as human-readable
    /// notes on an empty draft JPO — the office resolves parts from there.
    /// Identical breakers aggregate ("2× 20A/1P GFCI").
    public func breakerShoppingList() -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        func add(_ description: String) {
            if counts[description] == nil { order.append(description) }
            counts[description, default: 0] += 1
        }
        for (_, entry) in entries.sorted(by: { $0.key < $1.key }) {
            switch entry {
            case .full(let poles, let circuit):
                guard circuit.type != .spare else { continue }
                add("\(circuit.amps)A/\(max(1, min(poles, 3)))P \(circuit.type.displayName)")
            case .tandem(let upper, let lower):
                let halves = [upper, lower].filter { $0.type != .spare }
                guard !halves.isEmpty else { continue }
                let spec = halves.map { "\($0.amps)A" }.joined(separator: "/")
                add("Tandem \(spec) \(halves[0].type.displayName)")
            case .quad(let mode, let sections):
                let active = sections.filter { $0.type != .spare }
                guard !active.isEmpty else { continue }
                let spec = active.map { "\($0.amps)A" }.joined(separator: "/")
                let modeName = mode == .four ? "4×1P" : mode == .center ? "120/240/120" : "2×2P"
                add("Quad (\(modeName)) \(spec)")
            }
        }
        return order.map { key in
            let count = counts[key] ?? 1
            return count > 1 ? "\(count)× \(key)" : "1× \(key)"
        }
    }
}
