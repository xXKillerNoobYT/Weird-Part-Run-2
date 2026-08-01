import Foundation

// Panel Schedule Builder redesign — print document model (slice 4a).
// Spec: docs/plans/panel-schedule-builder-visual-redesign.md §5.
// Everything the printed schedule contains, assembled as plain data the
// PDF renderer (slice 4b) draws verbatim. All decidable content — rows,
// labels, load summary, demand math, wire column, notes — is built and
// testable here.

/// Persisted print configuration (set once, reused for every schedule).
public struct PanelPrintConfig: Codable, Sendable, Equatable {
    // Company letterhead
    public var companyName: String
    public var licenseNumber: String
    public var phone: String
    public var address: String
    public var email: String
    public var website: String
    /// Stored logo reference (app documents-relative path; picked via UI).
    public var logoPath: String?

    // Project / title block
    public var project: String
    public var jobNumber: String
    public var location: String
    public var fedFrom: String
    public var revision: String
    public var drawnBy: String
    public var checkedBy: String

    // Panel details
    public var aicKA: String
    public var feederConductor: String
    public var mounting: Mounting
    public var enclosure: Enclosure

    // Demand + toggles
    /// Percent 25...150, default 100 (spec §5 stepper).
    public var demandFactorPercent: Int
    public var showVAColumn: Bool
    public var showWireColumn: Bool
    public var showEmptySpaces: Bool
    public var showPhaseBars: Bool
    public var showDemandCalc: Bool
    public var showNotes: Bool
    public var showSignatures: Bool
    public var grayscale: Bool
    public var paper: Paper

    public enum Mounting: String, Codable, Sendable, CaseIterable {
        case surface = "Surface"
        case flush = "Flush"
    }

    public enum Enclosure: String, Codable, Sendable, CaseIterable {
        case nema1 = "NEMA 1"
        case nema3r = "NEMA 3R"
        case nema12 = "NEMA 12"
    }

    public enum Paper: String, Codable, Sendable, CaseIterable {
        case letter = "Letter"
        case legal = "Legal"
        case a4 = "A4"

        /// Page size in points (72/in) for the PDF renderer.
        public var pointSize: (width: Double, height: Double) {
            switch self {
            case .letter: return (612, 792)
            case .legal: return (612, 1008)
            case .a4: return (595, 842)
            }
        }
    }

    public init(
        companyName: String = "", licenseNumber: String = "", phone: String = "",
        address: String = "", email: String = "", website: String = "", logoPath: String? = nil,
        project: String = "", jobNumber: String = "", location: String = "",
        fedFrom: String = "", revision: String = "A", drawnBy: String = "", checkedBy: String = "",
        aicKA: String = "22", feederConductor: String = "", mounting: Mounting = .surface,
        enclosure: Enclosure = .nema1,
        demandFactorPercent: Int = 100,
        showVAColumn: Bool = true, showWireColumn: Bool = false, showEmptySpaces: Bool = false,
        showPhaseBars: Bool = true, showDemandCalc: Bool = false, showNotes: Bool = true,
        showSignatures: Bool = false, grayscale: Bool = false, paper: Paper = .letter
    ) {
        self.companyName = companyName
        self.licenseNumber = licenseNumber
        self.phone = phone
        self.address = address
        self.email = email
        self.website = website
        self.logoPath = logoPath
        self.project = project
        self.jobNumber = jobNumber
        self.location = location
        self.fedFrom = fedFrom
        self.revision = revision
        self.drawnBy = drawnBy
        self.checkedBy = checkedBy
        self.aicKA = aicKA
        self.feederConductor = feederConductor
        self.mounting = mounting
        self.enclosure = enclosure
        self.demandFactorPercent = min(max(demandFactorPercent, 25), 150)
        self.showVAColumn = showVAColumn
        self.showWireColumn = showWireColumn
        self.showEmptySpaces = showEmptySpaces
        self.showPhaseBars = showPhaseBars
        self.showDemandCalc = showDemandCalc
        self.showNotes = showNotes
        self.showSignatures = showSignatures
        self.grayscale = grayscale
        self.paper = paper
    }
}

/// The fully assembled print document — pure data the renderer draws.
public struct PanelPrintDocument: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let slot: String            // "3", "6a", "8–10↑" …
        public let loadServed: String
        public let wire: String?           // when showWireColumn
        public let breaker: String         // "20A/1P"
        public let typeShortCode: String   // STD/GFCI/CAFI/… ("—" for open)
        public let typeColorHex: String
        public let va: Int?                // when showVAColumn
        public let phases: String          // "A", "A·B" …
        public let isEmpty: Bool           // italic "SPACE — open" row
    }

    public struct LoadSummary: Sendable, Equatable {
        public let perLegVA: [Int]
        public let perLegAmps: [Int]
        public let perLegPercent: [Int]
        public let totalConnectedVA: Int
        public let serviceAmps: Int
        public let imbalancePercent: Int          // amber when > 20 (renderer)
        public let demandFactorPercent: Int?      // when showDemandCalc
        public let demandVA: Int?
        public let demandAmps: Int?
        public let minServiceAmps: Int?           // next standard size
    }

    public let titleRight: [String]               // "PANEL SCHEDULE", name, date
    public let meta: String                       // "Brand Model · 120/240V 1Ø · 200A MCB · 40 sp"
    public let titleBlock: [(label: String, value: String)]
    public let rows: [Row]
    public let summary: LoadSummary
    public let notes: [String]
    public let footer: String

    public static let disclaimer =
        "Generated by WiredPart · Planning estimate — verify against NEC & local AHJ before construction."

    public static func == (lhs: PanelPrintDocument, rhs: PanelPrintDocument) -> Bool {
        lhs.titleRight == rhs.titleRight && lhs.meta == rhs.meta
            && lhs.titleBlock.map(\.label) == rhs.titleBlock.map(\.label)
            && lhs.titleBlock.map(\.value) == rhs.titleBlock.map(\.value)
            && lhs.rows == rhs.rows && lhs.summary == rhs.summary
            && lhs.notes == rhs.notes && lhs.footer == rhs.footer
    }

    // MARK: - Assembly

    public static func assemble(
        panelName: String,
        panel: DesignPanelState,
        config: PanelPrintConfig,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> PanelPrintDocument {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        let system = panel.setup.voltageSystem

        // Title + meta
        let titleRight = ["PANEL SCHEDULE", panelName, formatter.string(from: date)]
        let meta = "\(panel.setup.brand) \(panel.setup.model) · \(system.rawValue) · "
            + "\(panel.setup.mainAmps)A \(panel.setup.panelKind == .mainBreaker ? "MCB" : panel.setup.panelKind == .mainLug ? "MLO" : "Sub") · "
            + "\(panel.setup.totalSpaces) sp"

        // Title block (spec's 12 fields, 3-col grid handled by renderer)
        let titleBlock: [(String, String)] = [
            ("Project", config.project),
            ("Location", config.location),
            ("Voltage/Phase", system.rawValue),
            ("Job No.", config.jobNumber),
            ("Fed From", config.fedFrom),
            ("Main", "\(panel.setup.mainAmps)A \(panel.setup.panelKind == .mainBreaker ? "MCB" : "MLO")"),
            ("Mounting", config.mounting.rawValue),
            ("Enclosure", config.enclosure.rawValue),
            ("Bus/AIC", "\(panel.setup.mainAmps)A · \(config.aicKA)kAIC"),
            ("Spaces", "\(panel.setup.totalSpaces) · \(panel.freeSpaces.count) free"),
            ("Feeder", config.feederConductor),
            ("Rev", config.revision),
        ]

        // Rows: one per sub-circuit, anchor-ordered; optional empty rows.
        var rows: [Row] = []
        var notes: [String] = []
        var renderedSpaces = Set<Int>()
        for (anchor, entry) in panel.entries.sorted(by: { $0.key < $1.key }) {
            renderedSpaces.formUnion(entry.occupiedSpaces(anchoredAt: anchor))
            let sectionPoles = polesPerSection(entry: entry)
            for (index, section) in entry.sections.enumerated() where section.type != .spare {
                let poles = sectionPoles[index]
                let slot = slotLabel(anchor: anchor, entry: entry, sectionIndex: index)
                let va = PanelPhaseMath.watts(amps: section.usedAmps, poles: poles, system: system)
                rows.append(Row(
                    slot: slot,
                    loadServed: section.name.isEmpty ? section.type.displayName : section.name,
                    wire: config.showWireColumn ? PanelPhaseMath.wireSize(forBreakerAmps: section.amps) : nil,
                    breaker: "\(section.amps)A/\(poles)P",
                    typeShortCode: section.type.shortCode,
                    typeColorHex: section.type.colorHex,
                    va: config.showVAColumn ? Int(va.rounded()) : nil,
                    phases: phaseLabel(anchor: anchor, entry: entry, sectionIndex: index, system: system),
                    isEmpty: false
                ))
                if config.showNotes, !section.note.isEmpty {
                    notes.append("#\(slot) \(section.name.isEmpty ? section.type.displayName : section.name): \(section.note)")
                }
            }
        }
        if config.showEmptySpaces {
            for space in 1...panel.setup.totalSpaces where !renderedSpaces.contains(space) {
                rows.append(Row(
                    slot: "\(space)", loadServed: "SPACE — open", wire: nil,
                    breaker: "—", typeShortCode: "—", typeColorHex: DesignBreakerType.spare.colorHex,
                    va: nil, phases: "", isEmpty: true
                ))
            }
            rows.sort { lhs, rhs in numericPrefix(lhs.slot) < numericPrefix(rhs.slot) }
        }

        // Load summary
        let perLegVA = panel.perLegVA
        let perLegAmps = panel.perLegAmps
        let main = Double(panel.setup.mainAmps)
        let maxLeg = perLegAmps.max() ?? 0
        let minLeg = perLegAmps.min() ?? 0
        let imbalance = maxLeg > 0 ? Int(((maxLeg - minLeg) / maxLeg * 100).rounded()) : 0
        let demandVA = Double(config.demandFactorPercent) / 100.0 * panel.totalConnectedVA
        let demandAmps = PanelPhaseMath.serviceAmps(totalVA: demandVA, system: system)
        let summary = LoadSummary(
            perLegVA: perLegVA.map { Int($0.rounded()) },
            perLegAmps: perLegAmps.map { Int($0.rounded()) },
            perLegPercent: perLegAmps.map { main > 0 ? Int(($0 / main * 100).rounded()) : 0 },
            totalConnectedVA: Int(panel.totalConnectedVA.rounded()),
            serviceAmps: Int(panel.serviceAmps.rounded()),
            imbalancePercent: imbalance,
            demandFactorPercent: config.showDemandCalc ? config.demandFactorPercent : nil,
            demandVA: config.showDemandCalc ? Int(demandVA.rounded()) : nil,
            demandAmps: config.showDemandCalc ? Int(demandAmps.rounded()) : nil,
            minServiceAmps: config.showDemandCalc
                ? PanelPhaseMath.nextStandardServiceSize(atLeast: demandAmps) : nil
        )

        let footer = "\(config.paper.rawValue) · \(disclaimer)"

        return PanelPrintDocument(
            titleRight: titleRight, meta: meta, titleBlock: titleBlock,
            rows: rows, summary: summary,
            notes: config.showNotes ? notes : [], footer: footer
        )
    }

    // MARK: - Labeling helpers

    private static func polesPerSection(entry: DesignSpaceEntry) -> [Int] {
        switch entry {
        case .full(let poles, _): return [max(1, min(poles, 3))]
        case .tandem: return [1, 1]
        case .quad(let mode, let sections):
            switch mode {
            case .four: return Array(repeating: 1, count: sections.count)
            case .center: return sections.indices.map { $0 == 1 ? 2 : 1 }
            case .double: return Array(repeating: 2, count: sections.count)
            }
        }
    }

    private static func slotLabel(anchor: Int, entry: DesignSpaceEntry, sectionIndex: Int) -> String {
        switch entry {
        case .full(let poles, _):
            guard poles > 1 else { return "\(anchor)" }
            let last = anchor + (poles - 1) * 2
            return "\(anchor)–\(last)"
        case .tandem:
            return "\(anchor)\(sectionIndex == 0 ? "a" : "b")"
        case .quad(let mode, _):
            switch mode {
            case .four:
                let base = sectionIndex < 2 ? anchor : anchor + 2
                return "\(base)\(sectionIndex % 2 == 0 ? "a" : "b")"
            case .center:
                return sectionIndex == 1 ? "\(anchor)–\(anchor + 2)" : "\(sectionIndex == 0 ? anchor : anchor + 2)"
            case .double:
                return "\(anchor)–\(anchor + 2)\(sectionIndex == 0 ? "↑" : "↓")"
            }
        }
    }

    private static func phaseLabel(anchor: Int, entry: DesignSpaceEntry, sectionIndex: Int, system: PanelVoltageSystem) -> String {
        let spaces: [Int]
        switch entry {
        case .full:
            spaces = entry.occupiedSpaces(anchoredAt: anchor)
        case .tandem:
            spaces = [anchor]
        case .quad(let mode, _):
            switch mode {
            case .four: spaces = [sectionIndex < 2 ? anchor : anchor + 2]
            case .center: spaces = sectionIndex == 1 ? [anchor, anchor + 2] : [sectionIndex == 0 ? anchor : anchor + 2]
            case .double: spaces = [anchor, anchor + 2]
            }
        }
        let legs = Array(Set(spaces.map { system.legIndex(forSpace: $0) })).sorted()
        return legs.compactMap { PanelPhaseLeg(rawValue: $0)?.letter }.joined(separator: "·")
    }

    private static func numericPrefix(_ slot: String) -> Int {
        Int(slot.prefix(while: \.isNumber)) ?? Int.max
    }
}
