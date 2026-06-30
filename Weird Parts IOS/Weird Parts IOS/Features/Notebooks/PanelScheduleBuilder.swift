import SwiftUI
import WiredPartCore

/// Interactive panel schedule builder for documenting circuit breaker assignments.
struct PanelScheduleBuilder: View {
    @Binding var schedule: PanelSchedule
    let onSave: (PanelSchedule) -> Void

    @State private var selectedCircuit: CircuitEntry?
    @State private var showHiddenCircuitPruneConfirmation = false

    private enum ActiveSheet: Identifiable {
        case circuitEditor
        case panelSettings
        var id: String {
            switch self {
            case .circuitEditor: return "circuitEditor"
            case .panelSettings: return "panelSettings"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            ScrollView {
                panelGrid
            }
            Divider()
            panelToolbar
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .circuitEditor:
                if let circuit = selectedCircuit {
                    CircuitEditorSheet(circuit: circuit) { updated in
                        updateCircuit(updated)
                    }
                }
            case .panelSettings:
                PanelSettingsSheet(schedule: $schedule)
            }
        }
        .alert("Remove Hidden Circuits?", isPresented: $showHiddenCircuitPruneConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove & Save", role: .destructive) {
                saveNormalizedSchedule()
            }
        } message: {
            Text("Saving will permanently remove \(schedule.circuitsOutsideTotalSpaces.count) hidden circuit\(schedule.circuitsOutsideTotalSpaces.count == 1 ? "" : "s") outside the visible 1–\(schedule.totalSpaces) panel range.")
        }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        VStack(spacing: 4) {
            Text(schedule.panelName).font(.title2).bold()
            HStack(spacing: 8) {
                Text(schedule.panelType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
                if let amps = schedule.mainBreakerAmps {
                    Text("\(amps)A Main")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(schedule.voltage)V")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(schedule.phase)Φ")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(schedule.totalSpaces) Spaces")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let location = schedule.location, !location.isEmpty {
                Text(location)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    // MARK: - Panel Grid

    private var panelGrid: some View {
        VStack(spacing: 1) {
            // Column headers
            HStack(spacing: 0) {
                Text("#").font(.caption2).bold().frame(width: 22)
                Text("A").font(.caption2).bold().frame(width: 26)
                Text("Circuit").font(.caption2).bold()
                Spacer()
                Rectangle().fill(.clear).frame(width: 4)
                Spacer()
                Text("Circuit").font(.caption2).bold()
                Text("A").font(.caption2).bold().frame(width: 26)
                Text("#").font(.caption2).bold().frame(width: 22)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.gray.opacity(0.1))

            // Circuit rows
            ForEach(0..<(schedule.totalSpaces / 2), id: \.self) { row in
                let leftSpace = row * 2 + 1
                let rightSpace = row * 2 + 2
                let leftCircuit = schedule.circuits.first { $0.spaceNumber == leftSpace }
                let rightCircuit = schedule.circuits.first { $0.spaceNumber == rightSpace }

                HStack(spacing: 0) {
                    circuitCell(spaceNumber: leftSpace, circuit: leftCircuit, isLeft: true)

                    Rectangle()
                        .fill(.gray)
                        .frame(width: 4, height: 44)
                        .accessibilityHidden(true)

                    circuitCell(spaceNumber: rightSpace, circuit: rightCircuit, isLeft: false)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func circuitCell(spaceNumber: Int, circuit: CircuitEntry?, isLeft: Bool) -> some View {
        Button {
            openCircuitEditor(spaceNumber: spaceNumber, circuit: circuit)
        } label: {
            HStack(spacing: 2) {
                if isLeft {
                    Text("\(spaceNumber)")
                        .font(.caption2).fontDesign(.monospaced)
                        .frame(width: 22, alignment: .center)
                    Text(circuit?.breakerAmps.map { "\($0)" } ?? "—")
                        .font(.caption).fontDesign(.monospaced)
                        .frame(width: 26, alignment: .center)
                    Text((circuit?.circuitDescription).flatMap { $0.isEmpty ? nil : $0 } ?? "SPARE")
                        .font(.caption).lineLimit(1)
                    Spacer()
                } else {
                    Spacer()
                    Text((circuit?.circuitDescription).flatMap { $0.isEmpty ? nil : $0 } ?? "SPARE")
                        .font(.caption).lineLimit(1)
                    Text(circuit?.breakerAmps.map { "\($0)" } ?? "—")
                        .font(.caption).fontDesign(.monospaced)
                        .frame(width: 26, alignment: .center)
                    Text("\(spaceNumber)")
                        .font(.caption2).fontDesign(.monospaced)
                        .frame(width: 22, alignment: .center)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(circuitBackground(circuit))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(circuitAccessibilityLabel(spaceNumber: spaceNumber, circuit: circuit))
        .accessibilityValue(circuitAccessibilityValue(circuit))
        .accessibilityHint("Opens the editor for circuit \(spaceNumber).")
        .accessibilityIdentifier("panel-schedule-circuit-\(spaceNumber)")
    }

    private func openCircuitEditor(spaceNumber: Int, circuit: CircuitEntry?) {
        selectedCircuit = circuit ?? CircuitEntry(spaceNumber: spaceNumber)
        activeSheet = .circuitEditor
    }

    private func circuitDisplayName(_ circuit: CircuitEntry?) -> String {
        let description = circuit?.circuitDescription.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? "SPARE" : description
    }

    private func circuitAccessibilityLabel(spaceNumber: Int, circuit: CircuitEntry?) -> String {
        "Circuit \(spaceNumber), \(circuitDisplayName(circuit))"
    }

    private func circuitAccessibilityValue(_ circuit: CircuitEntry?) -> String {
        guard let circuit, !circuit.isSpare else {
            return "Spare circuit, no breaker assigned"
        }

        var details: [String] = []
        if let amps = circuit.breakerAmps {
            details.append("\(amps) amp")
        } else {
            details.append("No amp rating")
        }
        details.append("\(circuit.breakerType.rawValue) breaker")

        let description = circuit.circuitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            details.append(description)
        }
        if let fedFrom = circuit.isFedFrom?.trimmingCharacters(in: .whitespacesAndNewlines), !fedFrom.isEmpty {
            details.append("fed from \(fedFrom)")
        }
        return details.joined(separator: ", ")
    }

    private func circuitBackground(_ circuit: CircuitEntry?) -> Color {
        guard let circuit, !circuit.isSpare else { return .yellow.opacity(0.05) }
        switch circuit.breakerType {
        case .double: return .blue.opacity(0.1)
        case .tandem: return .purple.opacity(0.1)
        case .gfci, .afci, .dualFunction: return .green.opacity(0.1)
        case .spare: return .yellow.opacity(0.1)
        case .blank: return .gray.opacity(0.1)
        default: return .clear
        }
    }

    // MARK: - Toolbar

    private var panelToolbar: some View {
        HStack {
            Button {
                activeSheet = .panelSettings
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

            Spacer()

            // Legend
            HStack(spacing: 8) {
                legendDot(.blue, "240V")
                legendDot(.purple, "Tandem")
                legendDot(.green, "GFI/AFI")
                legendDot(.yellow, "Spare")
            }

            Spacer()

            Button {
                if schedule.circuitsOutsideTotalSpaces.isEmpty {
                    saveNormalizedSchedule()
                } else {
                    showHiddenCircuitPruneConfirmation = true
                }
            } label: {
                Label("Save", systemImage: "checkmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color.opacity(0.3)).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Circuit Management

    private func updateCircuit(_ circuit: CircuitEntry) {
        if let index = schedule.circuits.firstIndex(where: { $0.spaceNumber == circuit.spaceNumber }) {
            schedule.circuits[index] = circuit
        } else {
            schedule.circuits.append(circuit)
        }
    }

    private func saveNormalizedSchedule() {
        let normalized = schedule.pruningCircuitsOutsideTotalSpaces()
        schedule = normalized
        onSave(normalized)
    }
}

// MARK: - Circuit Editor Sheet

struct CircuitEditorSheet: View {
    @State var circuit: CircuitEntry
    let onSave: (CircuitEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    private let ampOptions = [15, 20, 30, 40, 50, 60, 100]

    var body: some View {
        NavigationStack {
            Form {
                Section("Breaker") {
                    Picker("Amps", selection: $circuit.breakerAmps) {
                        Text("None").tag(nil as Int?)
                        ForEach(ampOptions, id: \.self) { amps in
                            Text("\(amps)A").tag(amps as Int?)
                        }
                    }
                    Picker("Type", selection: $circuit.breakerType) {
                        ForEach(BreakerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
                Section("Circuit") {
                    TextField("Description (e.g. Kitchen Outlets)", text: $circuit.circuitDescription)
                    TextField("Wire (e.g. #12 THHN)", text: Binding(
                        get: { circuit.wire ?? "" },
                        set: { circuit.wire = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Conduit (e.g. 3/4 EMT)", text: Binding(
                        get: { circuit.conduit ?? "" },
                        set: { circuit.conduit = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Fed From (e.g. MDP)", text: Binding(
                        get: { circuit.isFedFrom ?? "" },
                        set: { circuit.isFedFrom = $0.isEmpty ? nil : $0 }
                    ))
                    Toggle("Spare", isOn: $circuit.isSpare)
                }
            }
            .navigationTitle("Circuit \(circuit.spaceNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(circuit)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Panel Settings Sheet

private struct PanelSettingsSheet: View {
    @Binding var schedule: PanelSchedule
    @Environment(\.dismiss) private var dismiss

    private let spaceOptions = [2, 4, 8, 12, 16, 20, 24, 30, 42]
    private let ampOptions = [100, 125, 150, 200, 225, 400, 600]

    var body: some View {
        NavigationStack {
            Form {
                Section("Panel") {
                    TextField("Panel Name", text: $schedule.panelName)
                    Picker("Type", selection: $schedule.panelType) {
                        ForEach(PanelType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    TextField("Location", text: Binding(
                        get: { schedule.location ?? "" },
                        set: { schedule.location = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section("Electrical") {
                    Picker("Total Spaces", selection: $schedule.totalSpaces) {
                        ForEach(spaceOptions, id: \.self) { size in
                            Text("\(size) spaces").tag(size)
                        }
                    }
                    if !schedule.circuitsOutsideTotalSpaces.isEmpty {
                        Label(
                            "Saving will remove \(schedule.circuitsOutsideTotalSpaces.count) hidden circuit\(schedule.circuitsOutsideTotalSpaces.count == 1 ? "" : "s") outside the visible 1–\(schedule.totalSpaces) panel range.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    Picker("Main Breaker", selection: $schedule.mainBreakerAmps) {
                        Text("None / MLO").tag(nil as Int?)
                        ForEach(ampOptions, id: \.self) { amps in
                            Text("\(amps)A").tag(amps as Int?)
                        }
                    }
                    Picker("Voltage", selection: $schedule.voltage) {
                        Text("120/240V").tag(240)
                        Text("120/208V").tag(208)
                        Text("277/480V").tag(480)
                    }
                    Picker("Phase", selection: $schedule.phase) {
                        Text("Single Phase").tag(1)
                        Text("Three Phase").tag(3)
                    }
                }
            }
            .navigationTitle("Panel Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
