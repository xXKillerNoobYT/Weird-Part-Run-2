import SwiftUI
import WiredPartCore

/// Redesigned Panel Schedule Builder (plan §1, slice 3b).
///
/// Renders a `DesignPanelState` binding: segmented layout switcher
/// (Classic | List | Visual, Visual default), the always-visible phase
/// balance card, and the three layouts. Space taps open
/// `PanelCircuitEditorSheet`; saves flow through the state's overlap-evicting
/// `save(_:atAnchor:)`. Persistence of the binding belongs to the notebook
/// page that hosts this view (integration slice).
struct PanelRedesignBuilderView: View {
    @Binding var panel: DesignPanelState
    @State private var editorAnchor: Int?
    @State private var editorDraft: PanelEditorDraft?
    @State private var placementError: String?
    @State private var showWatts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                layoutSwitcher
                phaseBalanceCard
                if let placementError {
                    Text(placementError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("panelPlacementError")
                }
                switch panel.layout {
                case .classic: classicLayout
                case .list: listLayout
                case .visual: visualLayout
                }
            }
            .padding()
        }
        .sheet(item: $editorDraft) { draft in
            PanelCircuitEditorSheet(draft: draft, voltageSystem: panel.setup.voltageSystem) { entry in
                do {
                    placementError = nil
                    try panel.save(entry, atAnchor: draft.anchorSpace)
                } catch let error as DesignPanelError {
                    placementError = Self.message(for: error)
                } catch {
                    placementError = error.localizedDescription
                }
            }
        }
    }

    private static func message(for error: DesignPanelError) -> String {
        switch error {
        case .outOfRange(let spaces):
            return "That breaker would reach space\(spaces.count == 1 ? "" : "s") \(spaces.map(String.init).joined(separator: ", ")) — outside this panel."
        case .tandemSlotNotMarked(let space):
            return "This panel's CTL listing only allows tandems in marked slots — space \(space) isn't one. Change slots or enable “tandems any slot” in Panel setup."
        }
    }

    private func openEditor(atSpace space: Int) {
        if let covering = panel.entry(coveringSpace: space) {
            editorDraft = .from(entry: covering.entry, anchorSpace: covering.anchor)
        } else {
            editorDraft = .defaults(kind: .full, anchorSpace: space)
        }
    }

    // MARK: - Switcher + balance card

    private var layoutSwitcher: some View {
        Picker("Layout", selection: $panel.layout) {
            ForEach(DesignPanelState.Layout.allCases, id: \.self) { layout in
                Text(layout.rawValue).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("panelLayoutSwitcher")
    }

    private var phaseBalanceCard: some View {
        let amps = panel.perLegAmps
        let largest = panel.largestLeg
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Phase balance").font(.headline)
                Spacer()
                Button(showWatts ? "W" : "A") { showWatts.toggle() }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(showWatts ? "Showing watts, switch to amps" : "Showing amps, switch to watts")
                    .accessibilityIdentifier("panelBalanceUnitToggle")
            }
            ForEach(amps.indices, id: \.self) { legIndex in
                let leg = PanelPhaseLeg(rawValue: legIndex) ?? .a
                let fraction = panel.setup.mainAmps > 0
                    ? min(amps[legIndex] / Double(panel.setup.mainAmps), 1) : 0
                HStack(spacing: 8) {
                    Text(leg.letter)
                        .font(.caption.bold())
                        .frame(width: 16)
                        .foregroundStyle(Color(hex: leg.colorHex) ?? .blue)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(Color(hex: leg.colorHex) ?? .blue)
                                .frame(width: max(proxy.size.width * fraction, 2))
                        }
                    }
                    .frame(height: 8)
                    Text(showWatts
                         ? "\(Int(panel.perLegVA[legIndex])) W"
                         : String(format: "%.0f A", amps[legIndex]))
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Leg \(leg.letter): \(Int(amps[legIndex])) amps of \(panel.setup.mainAmps)")
            }
            Text("Largest leg: \(PanelPhaseLeg(rawValue: largest.leg)?.letter ?? "A") · \(Int(largest.amps))A of \(panel.setup.mainAmps)A (\(Int(largest.fractionOfMain * 100))%)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Total connected: \(Int(panel.totalConnectedVA)) W · \(String(format: "%.0f", panel.serviceAmps))A service")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("panelBalanceTotals")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Classic (two columns, white cells, color bars)

    private var classicLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            classicColumn(spaces: oddSpaces)
            classicColumn(spaces: evenSpaces)
        }
    }

    private var oddSpaces: [Int] { stride(from: 1, through: panel.setup.totalSpaces, by: 2).map { $0 } }
    private var evenSpaces: [Int] { stride(from: 2, through: panel.setup.totalSpaces, by: 2).map { $0 } }

    private func classicColumn(spaces: [Int]) -> some View {
        VStack(spacing: 6) {
            ForEach(anchorsToRender(in: spaces), id: \.self) { space in
                classicCell(space: space)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Spaces that render a cell in a column: free spaces + entry anchors
    /// (spanned spaces collapse into their anchor's cell).
    private func anchorsToRender(in spaces: [Int]) -> [Int] {
        spaces.filter { space in
            guard let covering = panel.entry(coveringSpace: space) else { return true }
            return covering.anchor == space
        }
    }

    private func classicCell(space: Int) -> some View {
        Button { openEditor(atSpace: space) } label: {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(cellColor(space: space))
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 2) {
                    if let (anchor, entry) = panel.entry(coveringSpace: space) {
                        Text(slotLabel(anchor: anchor, entry: entry))
                            .font(.caption2.bold())
                        ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                            if section.type != .spare {
                                Text("\(section.amps)A · \(section.name.isEmpty ? section.type.displayName : section.name)")
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("\(space)").font(.caption2.bold())
                        Text("Open").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("panelSpace_\(space)")
        .accessibilityLabel(accessibilitySummary(space: space))
    }

    // MARK: - List (one card per circuit)

    private var listLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                statTile(String(panel.entries.count), "Circuits")
                statTile(String(panel.freeSpaces.count), "Free spaces")
                statTile(String(panel.setup.totalSpaces), "Spaces")
            }
            Button {
                if let next = panel.nextFreeSpace {
                    editorDraft = .defaults(kind: .full, anchorSpace: next)
                }
            } label: {
                Label("Add Circuit", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(panel.nextFreeSpace == nil)
            .accessibilityIdentifier("panelAddCircuit")

            ForEach(panel.entries.sorted(by: { $0.key < $1.key }), id: \.key) { anchor, entry in
                Button { openEditor(atSpace: anchor) } label: {
                    HStack(spacing: 8) {
                        Rectangle().fill(entryColor(entry)).frame(width: 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slotLabel(anchor: anchor, entry: entry)).font(.caption.bold())
                            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                                if section.type != .spare {
                                    Text("\(section.amps)A · \(section.type.shortCode) · \(section.name)")
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        Text(phaseSpanLabel(anchor: anchor, entry: entry))
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("panelListEntry_\(anchor)")
            }
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Visual (dark panel, center bus)

    private var visualLayout: some View {
        VStack(spacing: 4) {
            Text("\(panel.setup.brand.uppercased()) · \(panel.setup.mainAmps)A \(panel.setup.panelKind.rawValue)")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 8)
            HStack(alignment: .top, spacing: 0) {
                visualColumn(spaces: oddSpaces, mirrored: false)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 2)
                visualColumn(spaces: evenSpaces, mirrored: true)
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.09, green: 0.09, blue: 0.11)))
        .environment(\.colorScheme, .dark)
    }

    private func visualColumn(spaces: [Int], mirrored: Bool) -> some View {
        VStack(spacing: 4) {
            ForEach(anchorsToRender(in: spaces), id: \.self) { space in
                visualCell(space: space, mirrored: mirrored)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func visualCell(space: Int, mirrored: Bool) -> some View {
        let covering = panel.entry(coveringSpace: space)
        let color = cellColor(space: space)
        return Button { openEditor(atSpace: space) } label: {
            VStack(alignment: mirrored ? .trailing : .leading, spacing: 1) {
                if let (anchor, entry) = covering {
                    Text(slotLabel(anchor: anchor, entry: entry))
                        .font(.system(size: 9, weight: .bold))
                    ForEach(Array(entry.sections.prefix(2).enumerated()), id: \.offset) { _, section in
                        if section.type != .spare {
                            Text("\(section.amps)A \(section.name)")
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("\(space)").font(.system(size: 9, weight: .bold)).opacity(0.5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: mirrored ? .trailing : .leading)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(covering == nil ? 0.06 : 0.15)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(covering == nil ? 0.2 : 0.8), lineWidth: 1))
            .foregroundStyle(covering == nil ? .white.opacity(0.4) : color)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("panelVisualSpace_\(space)")
        .accessibilityLabel(accessibilitySummary(space: space))
    }

    // MARK: - Shared helpers

    private func cellColor(space: Int) -> Color {
        guard let (_, entry) = panel.entry(coveringSpace: space) else {
            return Color(.systemGray4)
        }
        return entryColor(entry)
    }

    private func entryColor(_ entry: DesignSpaceEntry) -> Color {
        if case .quad(let mode, _) = entry, mode == .center {
            return Color(hex: PanelPhaseLeg.tieColorHex) ?? .indigo
        }
        let type = entry.sections.first(where: { $0.type != .spare })?.type ?? .spare
        return Color(hex: type.colorHex) ?? .gray
    }

    private func slotLabel(anchor: Int, entry: DesignSpaceEntry) -> String {
        let spaces = entry.occupiedSpaces(anchoredAt: anchor)
        switch entry {
        case .full(let poles, _):
            return poles > 1 ? "\(spaces.first ?? anchor)–\(spaces.last ?? anchor)" : "\(anchor)"
        case .tandem:
            return "\(anchor)a/\(anchor)b"
        case .quad(let mode, _):
            let range = "\(spaces.first ?? anchor)–\(spaces.last ?? anchor)"
            switch mode {
            case .four: return "\(anchor)a,b · \(anchor + 2)a,b"
            case .center: return range
            case .double: return "\(range)↑↓"
            }
        }
    }

    private func phaseSpanLabel(anchor: Int, entry: DesignSpaceEntry) -> String {
        let legs = Set(entry.occupiedSpaces(anchoredAt: anchor).map {
            panel.setup.voltageSystem.legIndex(forSpace: $0)
        }).sorted()
        return legs.compactMap { PanelPhaseLeg(rawValue: $0)?.letter }.joined(separator: "·")
    }

    private func accessibilitySummary(space: Int) -> String {
        guard let (anchor, entry) = panel.entry(coveringSpace: space) else {
            return "Space \(space), open. Double tap to add a circuit."
        }
        let names = entry.sections.filter { $0.type != .spare }
            .map { "\($0.amps) amp \($0.type.displayName) \($0.name)" }
            .joined(separator: ", ")
        return "Space \(slotLabel(anchor: anchor, entry: entry)): \(names). Double tap to edit."
    }
}

extension PanelEditorDraft: Identifiable {
    public var id: String { "\(anchorSpace)-\(kind.rawValue)" }
}

#Preview("Redesigned builder") {
    struct Host: View {
        @State var panel: DesignPanelState = {
            var p = DesignPanelState(setup: DesignPanelSetup(totalSpaces: 24))
            try? p.save(.full(poles: 2, circuit: .init(amps: 30, usedAmps: 24, name: "Dryer")), atAnchor: 2)
            try? p.save(.tandem(upper: .init(amps: 15, usedAmps: 10, name: "Hall"), lower: .init(amps: 20, usedAmps: 8, name: "Bath")), atAnchor: 5)
            try? p.save(.quad(mode: .center, sections: [
                .init(amps: 20, usedAmps: 12, name: "Kitchen"),
                .init(amps: 30, type: .hacr, usedAmps: 22, name: "AC"),
                .init(amps: 20, usedAmps: 9, name: "Pantry"),
            ]), atAnchor: 7)
            return p
        }()
        var body: some View { PanelRedesignBuilderView(panel: $panel) }
    }
    return Host()
}
