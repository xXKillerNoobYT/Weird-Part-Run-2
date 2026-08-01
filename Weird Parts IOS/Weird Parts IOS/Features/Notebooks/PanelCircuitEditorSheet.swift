import SwiftUI
import WiredPartCore

/// Redesigned circuit editor bottom sheet (plan §4, slice 2b).
///
/// Consumes `PanelEditorDraft` (WiredPartCore) for every decidable rule —
/// kind/mode switching, presets, amp/type constraints, round-tripping —
/// and only renders. Presented by the builder on space tap (wired in the
/// layouts slice); until then it is reachable from the existing builder
/// behind its editor entry point.
struct PanelCircuitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PanelEditorDraft
    let voltageSystem: PanelVoltageSystem
    let onSave: (DesignSpaceEntry?) -> Void

    /// Unit toggle: false = amps, true = watts (spec §3 A↔W everywhere).
    @State private var showWatts = false

    init(
        draft: PanelEditorDraft,
        voltageSystem: PanelVoltageSystem,
        onSave: @escaping (DesignSpaceEntry?) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.voltageSystem = voltageSystem
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kindPicker
                    if draft.kind == .full {
                        polesPicker
                    }
                    if draft.kind == .quad {
                        quadModePicker
                    }
                    presetRow
                    ForEach(draft.sections.indices, id: \.self) { index in
                        sectionCard(index)
                    }
                }
                .padding()
            }
            .navigationTitle("Space \(draft.anchorSpace)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("panelEditorCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft.builtEntry)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("panelEditorSave")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        onSave(nil) // spec: SPARE/clear removes the entry
                        dismiss()
                    } label: {
                        Label("Clear Space", systemImage: "trash")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("panelEditorClear")
                }
            }
        }
    }

    // MARK: - Pickers

    private var kindPicker: some View {
        Picker("Form factor", selection: Binding(
            get: { draft.kind },
            set: { draft.switchKind(to: $0) }
        )) {
            ForEach(PanelEditorKind.allCases, id: \.self) { kind in
                Text(kind.rawValue).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("panelEditorKind")
    }

    private var polesPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Poles", selection: $draft.poles) {
                Text("1P").tag(1)
                Text("2P").tag(2)
                Text("3P").tag(3)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("panelEditorPoles")
            if draft.poles > 1 {
                Text("Spans spaces \(draft.occupiedSpaces.map(String.init).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("panelEditorSpanNote")
            }
        }
    }

    private var quadModePicker: some View {
        Picker("Quad mode", selection: Binding(
            get: { draft.quadMode },
            set: { draft.switchQuadMode(to: $0) }
        )) {
            Text("4×1P").tag(QuadMode.four)
            Text("120/240/120").tag(QuadMode.center)
            Text("2×2P").tag(QuadMode.double)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("panelEditorQuadMode")
    }

    @ViewBuilder
    private var presetRow: some View {
        let presets = PanelBuildPreset.presets(for: draft.kind, quadMode: draft.quadMode)
        if !presets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Common builds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button(preset.label) { draft.apply(preset: preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("panelPreset_\(preset.label)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section card

    private func sectionCard(_ index: Int) -> some View {
        let section = draft.sections[index]
        return VStack(alignment: .leading, spacing: 10) {
            if draft.sections.count > 1 {
                Text(sectionTitle(index))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            ampChips(index)
            typeChips(index)
            loadStepper(index)

            TextField("Circuit name (printed on the schedule)", text: Binding(
                get: { draft.sections[index].name },
                set: { draft.sections[index].name = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("panelCircuitName_\(index)")

            TextField("Description (optional, shows in print Notes)", text: Binding(
                get: { draft.sections[index].note },
                set: { draft.sections[index].note = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .accessibilityIdentifier("panelCircuitNote_\(index)")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(alignment: .topTrailing) {
            if isTiedSection(index) {
                Text("240V tied")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill((Color(hex: PanelPhaseLeg.tieColorHex) ?? .indigo).opacity(0.18)))
                    .foregroundStyle(Color(hex: PanelPhaseLeg.tieColorHex) ?? .indigo)
                    .padding(6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panelEditorSection_\(index)")
        .id("\(draft.kind.rawValue)-\(draft.quadMode.rawValue)-\(index)-\(section.amps)")
    }

    private func sectionTitle(_ index: Int) -> String {
        switch draft.kind {
        case .full: return "Circuit"
        case .tandem: return index == 0 ? "Upper (a)" : "Lower (b)"
        case .quad:
            switch draft.quadMode {
            case .four: return ["Top a", "Top b", "Bottom a", "Bottom b"][min(index, 3)]
            case .center: return ["Outer top", "Center 2-pole", "Outer bottom"][min(index, 2)]
            case .double: return index == 0 ? "Upper 2-pole" : "Lower 2-pole"
            }
        }
    }

    /// Center-quad inner section (index 1) is the tied 240V pair (spec §2).
    private func isTiedSection(_ index: Int) -> Bool {
        draft.kind == .quad && draft.quadMode == .center && index == 1
    }

    private func ampChips(_ index: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(draft.ampChoices(forSection: index), id: \.self) { amp in
                    let selected = draft.sections[index].amps == amp
                    Button("\(amp)A") {
                        draft.sections[index].amps = amp
                        draft.sections[index].usedAmps = min(draft.sections[index].usedAmps, Double(amp))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 44)
                    .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                    .accessibilityIdentifier("panelAmp_\(index)_\(amp)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func typeChips(_ index: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(draft.typeChoices(forSection: index), id: \.self) { type in
                    let selected = draft.sections[index].type == type
                    Button {
                        draft.sections[index].type = type
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: type.colorHex) ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(type.displayName)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                    .accessibilityIdentifier("panelType_\(index)_\(type.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func loadStepper(_ index: Int) -> some View {
        let poles = sectionPoles(index)
        let usedAmps = draft.sections[index].usedAmps
        let watts = PanelPhaseMath.watts(amps: usedAmps, poles: poles, system: voltageSystem)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Stepper(
                    value: Binding(
                        get: { draft.sections[index].usedAmps },
                        set: { draft.sections[index].usedAmps = max(0, min($0, Double(draft.sections[index].amps))) }
                    ),
                    step: 1
                ) {
                    Text(showWatts
                         ? "\(Int(watts)) W connected"
                         : String(format: "%.0f A connected", usedAmps))
                        .font(.callout.monospacedDigit())
                }
                .accessibilityIdentifier("panelLoadStepper_\(index)")
                Button("Estimate") {
                    draft.sections[index].usedAmps =
                        PanelPhaseMath.estimatedUsedAmps(forBreakerAmps: draft.sections[index].amps)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .frame(minHeight: 44)
                .accessibilityIdentifier("panelEstimate_\(index)")
            }
            HStack {
                Text(showWatts
                     ? String(format: "= %.0f A @ %dP", usedAmps, poles)
                     : "= \(Int(watts)) W @ \(poles)P")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(showWatts ? "Show amps" : "Show watts") { showWatts.toggle() }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("panelUnitToggle_\(index)")
            }
        }
    }

    /// Effective pole count for a section's VA math (spec §3).
    private func sectionPoles(_ index: Int) -> Int {
        switch draft.kind {
        case .full: return max(1, min(draft.poles, 3))
        case .tandem: return 1
        case .quad:
            switch draft.quadMode {
            case .four: return 1
            case .center: return index == 1 ? 2 : 1
            case .double: return 2
            }
        }
    }
}

#Preview("Editor — quad center") {
    PanelCircuitEditorSheet(
        draft: .defaults(kind: .quad, quadMode: .center, anchorSpace: 8),
        voltageSystem: .v120_240Single3Wire
    ) { _ in }
}
