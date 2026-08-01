import Foundation

// Panel Schedule Builder redesign — circuit editor draft (slice 2, core half).
// Spec: docs/plans/panel-schedule-builder-visual-redesign.md §4.
// Pure state + rules for the editor bottom sheet: form-factor switching with
// defaults reset, common-build presets, and amp/type constraint enforcement.
// The SwiftUI sheet (app target) renders this; everything decidable lives
// here so it is unit-testable without UI.

/// The editor's form-factor segment.
public enum PanelEditorKind: String, Codable, Sendable, CaseIterable {
    case full = "Full"
    case tandem = "Tandem"
    case quad = "Quad · 2sp"
}

/// A common-build preset offered above the sub-circuit cards (spec §4).
public struct PanelBuildPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let kind: PanelEditorKind
    public let quadMode: QuadMode?
    /// Amps per sub-circuit, top-to-bottom in section order.
    public let amps: [Int]

    public init(label: String, kind: PanelEditorKind, quadMode: QuadMode? = nil, amps: [Int]) {
        self.id = "\(kind.rawValue)|\(quadMode?.rawValue ?? "-")|\(label)"
        self.label = label
        self.kind = kind
        self.quadMode = quadMode
        self.amps = amps
    }

    /// The preset catalog per spec §4.
    public static let tandemPresets: [PanelBuildPreset] = [
        .init(label: "20/20", kind: .tandem, amps: [20, 20]),
        .init(label: "15/15", kind: .tandem, amps: [15, 15]),
        .init(label: "15/20", kind: .tandem, amps: [15, 20]),
        .init(label: "20/30", kind: .tandem, amps: [20, 30]),
    ]
    public static let quadCenterPresets: [PanelBuildPreset] = [
        .init(label: "20·30·20", kind: .quad, quadMode: .center, amps: [20, 30, 20]),
        .init(label: "15·20·15", kind: .quad, quadMode: .center, amps: [15, 20, 15]),
        .init(label: "20·40·20", kind: .quad, quadMode: .center, amps: [20, 40, 20]),
    ]
    public static let quadDoublePresets: [PanelBuildPreset] = [
        .init(label: "30/50", kind: .quad, quadMode: .double, amps: [30, 50]),
        .init(label: "20/30", kind: .quad, quadMode: .double, amps: [20, 30]),
        .init(label: "30/30", kind: .quad, quadMode: .double, amps: [30, 30]),
    ]
    public static let quadFourPresets: [PanelBuildPreset] = [
        .init(label: "15×4", kind: .quad, quadMode: .four, amps: [15, 15, 15, 15]),
        .init(label: "20×4", kind: .quad, quadMode: .four, amps: [20, 20, 20, 20]),
        .init(label: "15/15 + 20/20", kind: .quad, quadMode: .four, amps: [15, 15, 20, 20]),
    ]

    public static func presets(for kind: PanelEditorKind, quadMode: QuadMode) -> [PanelBuildPreset] {
        switch kind {
        case .full: return []
        case .tandem: return tandemPresets
        case .quad:
            switch quadMode {
            case .four: return quadFourPresets
            case .center: return quadCenterPresets
            case .double: return quadDoublePresets
            }
        }
    }
}

/// Editable draft behind the circuit editor sheet.
public struct PanelEditorDraft: Sendable, Equatable {
    public var kind: PanelEditorKind
    public var poles: Int                     // full only: 1/2/3
    public var quadMode: QuadMode             // quad only
    public var sections: [DesignSubCircuit]   // count depends on kind/mode
    public let anchorSpace: Int

    // MARK: Construction

    /// Fresh defaults for a kind (spec: switching segments resets the draft).
    public static func defaults(kind: PanelEditorKind, quadMode: QuadMode = .four, anchorSpace: Int) -> PanelEditorDraft {
        switch kind {
        case .full:
            return PanelEditorDraft(kind: .full, poles: 1, quadMode: quadMode,
                                    sections: [DesignSubCircuit(amps: 20)], anchorSpace: anchorSpace)
        case .tandem:
            return PanelEditorDraft(kind: .tandem, poles: 1, quadMode: quadMode,
                                    sections: [DesignSubCircuit(amps: 15), DesignSubCircuit(amps: 15)],
                                    anchorSpace: anchorSpace)
        case .quad:
            return PanelEditorDraft(kind: .quad, poles: 1, quadMode: quadMode,
                                    sections: Self.quadSections(for: quadMode), anchorSpace: anchorSpace)
        }
    }

    /// Draft prefilled from an existing entry (edit round-trip, spec §7.4).
    public static func from(entry: DesignSpaceEntry, anchorSpace: Int) -> PanelEditorDraft {
        switch entry {
        case .full(let poles, let circuit):
            return PanelEditorDraft(kind: .full, poles: poles, quadMode: .four,
                                    sections: [circuit], anchorSpace: anchorSpace)
        case .tandem(let upper, let lower):
            return PanelEditorDraft(kind: .tandem, poles: 1, quadMode: .four,
                                    sections: [upper, lower], anchorSpace: anchorSpace)
        case .quad(let mode, let sections):
            return PanelEditorDraft(kind: .quad, poles: 1, quadMode: mode,
                                    sections: sections, anchorSpace: anchorSpace)
        }
    }

    private static func quadSections(for mode: QuadMode) -> [DesignSubCircuit] {
        switch mode {
        case .four: return (0..<4).map { _ in DesignSubCircuit(amps: 15) }
        case .center: return [DesignSubCircuit(amps: 20), DesignSubCircuit(amps: 30), DesignSubCircuit(amps: 20)]
        case .double: return [DesignSubCircuit(amps: 30), DesignSubCircuit(amps: 30)]
        }
    }

    // MARK: Mutations (each mirrors a sheet control)

    /// Switch the form-factor segment — resets to that kind's defaults.
    public mutating func switchKind(to newKind: PanelEditorKind) {
        guard newKind != kind else { return }
        self = Self.defaults(kind: newKind, quadMode: quadMode, anchorSpace: anchorSpace)
    }

    /// Switch quad mode — resets sections to that mode's defaults.
    public mutating func switchQuadMode(to newMode: QuadMode) {
        guard kind == .quad, newMode != quadMode else { return }
        self = Self.defaults(kind: .quad, quadMode: newMode, anchorSpace: anchorSpace)
    }

    /// Apply a common-build preset (sets amps, keeps names/loads user owns).
    public mutating func apply(preset: PanelBuildPreset) {
        guard preset.kind == kind, preset.quadMode == (kind == .quad ? quadMode : nil) || kind == .tandem else { return }
        for (index, amp) in preset.amps.enumerated() where sections.indices.contains(index) {
            sections[index].amps = amp
            sections[index].usedAmps = min(sections[index].usedAmps, Double(amp))
        }
    }

    /// Amp choices legal for a section index in the current kind/mode (spec §2).
    public func ampChoices(forSection index: Int) -> [Int] {
        switch kind {
        case .full: return DesignBreakerType.fullAmpChoices
        case .tandem: return DesignBreakerType.tandemHalfAmpChoices
        case .quad:
            switch quadMode {
            case .four: return DesignBreakerType.tandemHalfAmpChoices
            case .center:
                // Outer singles use tandem-half sizes; the tied inner 2P uses quad 2P sizes.
                return index == 1 ? DesignBreakerType.quadTwoPoleAmpChoices : DesignBreakerType.tandemHalfAmpChoices
            case .double: return DesignBreakerType.quadTwoPoleAmpChoices
            }
        }
    }

    /// Type choices legal for a section index in the current kind/mode (spec §2).
    public func typeChoices(forSection index: Int) -> [DesignBreakerType] {
        switch kind {
        case .full: return DesignBreakerType.allCases
        case .tandem: return DesignBreakerType.tandemAllowed + [.spare]
        case .quad:
            switch quadMode {
            case .four: return DesignBreakerType.tandemAllowed + [.spare]
            case .center:
                return index == 1 ? DesignBreakerType.quadTwoPoleAllowed + [.spare]
                                  : DesignBreakerType.tandemAllowed + [.spare]
            case .double: return DesignBreakerType.quadTwoPoleAllowed + [.spare]
            }
        }
    }

    // MARK: Output

    /// The entry this draft saves to, or nil when everything is spare/empty
    /// (spec: SPARE clears the space).
    public var builtEntry: DesignSpaceEntry? {
        let active = sections.contains { $0.type != .spare }
        guard active else { return nil }
        switch kind {
        case .full:
            guard let circuit = sections.first else { return nil }
            return .full(poles: max(1, min(poles, 3)), circuit: circuit)
        case .tandem:
            guard sections.count >= 2 else { return nil }
            return .tandem(upper: sections[0], lower: sections[1])
        case .quad:
            return .quad(mode: quadMode, sections: sections)
        }
    }

    /// Spaces the built entry would occupy (for the span note + overlap UI).
    public var occupiedSpaces: [Int] {
        builtEntry?.occupiedSpaces(anchoredAt: anchorSpace)
            ?? [anchorSpace]
    }
}
