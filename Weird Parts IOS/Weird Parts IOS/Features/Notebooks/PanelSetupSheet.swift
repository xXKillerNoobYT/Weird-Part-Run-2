import SwiftUI
import WiredPartCore

/// Panel setup sheet (plan §2): brand, model, panel kind, voltage system,
/// CTL tandem slotting, spaces (chips + custom stepper, even 4–200), and
/// main rating. Edits a copy and commits on Save so Cancel is safe.
struct PanelSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DesignPanelSetup
    let onSave: (DesignPanelSetup) -> Void

    init(setup: DesignPanelSetup, onSave: @escaping (DesignPanelSetup) -> Void) {
        _draft = State(initialValue: setup)
        self.onSave = onSave
    }

    private static let spaceChips = [4, 8, 12, 16, 20, 24, 30, 40, 42, 60, 72]

    var body: some View {
        NavigationStack {
            Form {
                Section("Panel") {
                    Picker("Brand", selection: $draft.brand) {
                        ForEach(DesignPanelSetup.brandChoices, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Model (QO, BR, PON…)", text: $draft.model)
                        .accessibilityIdentifier("panelSetupModel")
                    Picker("Type", selection: $draft.panelKind) {
                        ForEach(DesignPanelSetup.PanelKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("Voltage system") {
                    Picker("System", selection: $draft.voltageSystem) {
                        ForEach(PanelVoltageSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("panelSetupVoltage")
                }

                Section {
                    Toggle("Tandems in any slot (CTL)", isOn: $draft.ctlTandemsAnySlot)
                        .accessibilityIdentifier("panelSetupCTL")
                } footer: {
                    Text(draft.ctlTandemsAnySlot
                         ? "Twin breakers can go in any space."
                         : "Twin breakers only in this panel's marked slots (e.g. a 40/40 listing). Mark slots by tapping them in the builder — unmarked slots reject tandems.")
                }

                Section("Spaces") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.spaceChips, id: \.self) { count in
                                let selected = draft.totalSpaces == count
                                Button("\(count)") {
                                    draft.totalSpaces = DesignPanelSetup.clampSpaces(count)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                                .accessibilityIdentifier("panelSetupSpaces_\(count)")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                    Stepper(
                        "Custom: \(draft.totalSpaces) spaces",
                        value: Binding(
                            get: { draft.totalSpaces },
                            set: { draft.totalSpaces = DesignPanelSetup.clampSpaces($0) }
                        ),
                        in: 4...200,
                        step: 2
                    )
                    .accessibilityIdentifier("panelSetupSpacesStepper")
                }

                Section("Main rating") {
                    Picker("Main", selection: $draft.mainAmps) {
                        ForEach(DesignPanelSetup.mainAmpChoices, id: \.self) { Text("\($0)A").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("panelSetupMain")
                }
            }
            .navigationTitle("Panel Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("panelSetupCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("panelSetupSave")
                }
            }
        }
    }
}

#Preview {
    PanelSetupSheet(setup: DesignPanelSetup()) { _ in }
}
