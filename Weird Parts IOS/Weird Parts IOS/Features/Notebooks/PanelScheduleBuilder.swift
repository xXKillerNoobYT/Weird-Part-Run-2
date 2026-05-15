import SwiftUI
import UIKit
import WiredPartCore

/// Interactive panel schedule builder for documenting circuit breaker assignments.
struct PanelScheduleBuilder: View {
    @Binding var schedule: PanelSchedule
    let onSave: (PanelSchedule) -> Void

    @State private var selectedCircuit: CircuitEntry?
    @State private var movingCircuitId: String?
    @State private var validationMessage: String?
    @State private var exportOptions = PanelScheduleExportOptions()
    @State private var exportURL: URL?
    @State private var exportMessage: String?

    private enum ActiveSheet: Identifiable {
        case circuitEditor
        case panelSettings
        case headerSettings
        case share(URL)
        var id: String {
            switch self {
            case .circuitEditor: return "circuitEditor"
            case .panelSettings: return "panelSettings"
            case .headerSettings: return "headerSettings"
            case .share: return "share"
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
            case .headerSettings:
                PanelScheduleHeaderSheet(options: $exportOptions)
            case .share(let url):
                PanelScheduleShareSheet(items: [url])
            }
        }
        .alert("Panel schedule issue", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "")
        }
        .alert("Panel schedule export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("OK", role: .cancel) { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
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
            if let movingCircuit = movingCircuitDescription {
                Text("Move \(movingCircuit): tap a destination space or drag it onto the grid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.08))
            }

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
                        .frame(width: 4, height: 36)

                    circuitCell(spaceNumber: rightSpace, circuit: rightCircuit, isLeft: false)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func circuitCell(spaceNumber: Int, circuit: CircuitEntry?, isLeft: Bool) -> some View {
        Button {
            if movingCircuitId != nil {
                moveSelectedCircuit(to: spaceNumber)
            } else {
                selectedCircuit = circuit ?? CircuitEntry(spaceNumber: spaceNumber)
                activeSheet = .circuitEditor
            }
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
                    if let secondary = circuit?.secondaryCircuitDescription, !secondary.isEmpty {
                        Text("+ \(secondary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                } else {
                    Spacer()
                    if let secondary = circuit?.secondaryCircuitDescription, !secondary.isEmpty {
                        Text("+ \(secondary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
            .frame(height: 36)
            .background(circuitBackground(circuit))
            .overlay {
                if movingCircuitId != nil {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.blue.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .buttonStyle(.plain)
        .draggable(circuit?.id ?? "")
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, !id.isEmpty else { return false }
            moveCircuit(id: id, to: spaceNumber)
            return true
        }
        .contextMenu {
            if let circuit {
                Button {
                    movingCircuitId = circuit.id
                } label: {
                    Label("Move Circuit", systemImage: "arrow.left.arrow.right")
                }
                Button {
                    selectedCircuit = circuit
                    activeSheet = .circuitEditor
                } label: {
                    Label("Edit Circuit", systemImage: "pencil")
                }
            }
        }
        .accessibilityLabel(accessibilityLabel(spaceNumber: spaceNumber, circuit: circuit))
        .accessibilityAction(named: Text(circuit == nil ? "Place selected circuit here" : "Move circuit")) {
            if let circuit {
                movingCircuitId = circuit.id
            } else if movingCircuitId != nil {
                moveSelectedCircuit(to: spaceNumber)
            }
        }
    }

    private func circuitBackground(_ circuit: CircuitEntry?) -> Color {
        guard let circuit, !circuit.isSpare else { return .yellow.opacity(0.05) }
        switch circuit.classification {
        case .lighting: return .cyan.opacity(0.12)
        case .receptacle: return .orange.opacity(0.12)
        case .motor: return .red.opacity(0.12)
        case .spare: return .yellow.opacity(0.1)
        case .blank: return .gray.opacity(0.1)
        case .special: break
        }
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
                legendDot(.cyan, "Light")
                legendDot(.orange, "Recept")
                legendDot(.red, "Motor")
                legendDot(.blue, "Double")
                legendDot(.purple, "Tandem")
            }
            .lineLimit(1)

            Spacer()

            if movingCircuitId != nil {
                Button {
                    movingCircuitId = nil
                } label: {
                    Label("Cancel Move", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Menu {
                Button {
                    activeSheet = .headerSettings
                } label: {
                    Label("Custom Header", systemImage: "text.badge.plus")
                }

                Button {
                    exportPanelScheduleForShare()
                } label: {
                    Label("Export PDF", systemImage: "doc.fill")
                }

                Button {
                    printPanelSchedule()
                } label: {
                    Label("Print PDF", systemImage: "printer")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

            Button {
                do {
                    try schedule.validated()
                    onSave(schedule)
                } catch {
                    validationMessage = error.localizedDescription
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
        do {
            try schedule.upsertCircuit(circuit)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private var movingCircuitDescription: String? {
        guard let movingCircuitId,
              let circuit = schedule.circuits.first(where: { $0.id == movingCircuitId }) else {
            return nil
        }
        return circuit.circuitDescription.isEmpty ? "circuit \(circuit.spaceNumber)" : circuit.circuitDescription
    }

    private func moveSelectedCircuit(to spaceNumber: Int) {
        guard let movingCircuitId else { return }
        moveCircuit(id: movingCircuitId, to: spaceNumber)
    }

    private func moveCircuit(id: String, to spaceNumber: Int) {
        do {
            try schedule.moveCircuit(id: id, to: spaceNumber)
            movingCircuitId = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func accessibilityLabel(spaceNumber: Int, circuit: CircuitEntry?) -> String {
        guard let circuit else {
            return "Empty panel space \(spaceNumber)"
        }
        let description = circuit.circuitDescription.isEmpty ? "Spare" : circuit.circuitDescription
        return "Panel space \(spaceNumber), \(description), \(circuit.classification.rawValue)"
    }

    private func exportPanelScheduleForShare() {
        do {
            let url = try PanelSchedulePDFExporter(schedule: schedule, options: exportOptions).writeToTemporaryFile()
            exportURL = url
            activeSheet = .share(url)
        } catch {
            exportMessage = userFriendlyError(error, context: "export panel schedule")
        }
    }

    private func printPanelSchedule() {
        do {
            let url = try PanelSchedulePDFExporter(schedule: schedule, options: exportOptions).writeToTemporaryFile()
            exportURL = url

            let printController = UIPrintInteractionController.shared
            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.jobName = "\(schedule.panelName) Panel Schedule"
            printInfo.outputType = .general
            printController.printInfo = printInfo
            printController.printingItem = url
            printController.present(animated: true) { _, _, error in
                if let error {
                    exportMessage = userFriendlyError(error, context: "print panel schedule")
                }
            }
        } catch {
            exportMessage = userFriendlyError(error, context: "print panel schedule")
        }
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
                    Picker("Classification", selection: $circuit.classification) {
                        ForEach(CircuitClassification.allCases, id: \.self) { classification in
                            Text(classification.rawValue).tag(classification)
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
                    TextField("Second Circuit (tandem/dual only)", text: Binding(
                        get: { circuit.secondaryCircuitDescription ?? "" },
                        set: { circuit.secondaryCircuitDescription = $0.isEmpty ? nil : $0 }
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

    private let allSpaceOptions = [2, 4, 8, 12, 16, 20, 24, 30, 40, 42]
    private let ampOptions = [100, 125, 150, 200, 225, 400, 600]
    private var allowedSpaceOptions: [Int] {
        allSpaceOptions.filter { schedule.panelType.allowedSpaces.contains($0) }
    }

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
                    .onChange(of: schedule.panelType) { _, newType in
                        if !newType.allowedSpaces.contains(schedule.totalSpaces),
                           let fallback = allSpaceOptions.first(where: { newType.allowedSpaces.contains($0) }) {
                            schedule.totalSpaces = fallback
                        }
                    }
                    TextField("Location", text: Binding(
                        get: { schedule.location ?? "" },
                        set: { schedule.location = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section("Electrical") {
                    Picker("Total Spaces", selection: $schedule.totalSpaces) {
                        ForEach(allowedSpaceOptions, id: \.self) { size in
                            Text("\(size) spaces").tag(size)
                        }
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
