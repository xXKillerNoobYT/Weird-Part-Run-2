import SwiftUI
import UIKit
import WiredPartCore

/// Interactive panel schedule builder for documenting circuit breaker assignments.
struct PanelScheduleBuilder: View {
    @Binding var schedule: PanelSchedule
    let onSave: (PanelSchedule) -> Void

    @State private var selectedCircuit: CircuitEntry?
    @State private var showHiddenCircuitPruneConfirmation = false
    @State private var movingCircuitId: String?
    @State private var validationMessage: String?
    @State private var exportOptions = PanelScheduleExportOptions()
    @State private var exportMessage: String?
    // Anchor rect (in the window's coordinate space) for the Export menu's
    // Print PDF button, so the iPad popover presentation of
    // UIPrintInteractionController has a source to point at.
    @State private var exportMenuAnchorRect: CGRect = .zero
    private let moveModeBannerHorizontalReservation = DS.Space.sm * 6

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
            case .share(let url): return "share-\(url.absoluteString)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                panelHeader
                Divider()
                if let movingCircuit = movingCircuitDescription {
                    // Keep move guidance outside the scroll content. The panel grid
                    // has a wider intrinsic width on compact phones, which otherwise
                    // made the banner inherit that width and clip both horizontal edges.
                    PanelQualityInstructionBanner(
                        message: "Move \(movingCircuit): tap a destination space or drag it onto the grid.",
                        accessibilityIdentifier: "panelScheduleMoveModeBanner"
                    )
                    // Reserve both the explicit banner margin and the compact root's
                    // inherited horizontal inset before fixing the banner width.
                    .frame(width: max(geometry.size.width - moveModeBannerHorizontalReservation, 0), alignment: .leading)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.top, DS.Space.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                ScrollView {
                    panelGrid
                }
                Divider()
                panelToolbar
            }
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
        .alert("Remove Hidden Circuits?", isPresented: $showHiddenCircuitPruneConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove & Save", role: .destructive) {
                saveNormalizedSchedule()
            }
        } message: {
            Text("Saving will permanently remove \(schedule.circuitsOutsideTotalSpaces.count) hidden circuit\(schedule.circuitsOutsideTotalSpaces.count == 1 ? "" : "s") outside the visible 1–\(schedule.totalSpaces) panel range.")
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

    /// Adaptive grid-line color — reads as crisp panel lines in light AND dark mode
    /// (the old hardcoded `.gray` spine glowed in dark mode; clear gaps left ragged
    /// translucent seams between the tinted cells).
    private var gridLineColor: Color { Color(.systemGray4) }

    private var panelGrid: some View {
        VStack(spacing: DS.Space.sm) {
            // The grid itself: opaque cells laid over a grid-line-colored backing,
            // so the 1pt gaps render as intentional, uniform panel lines — then the
            // whole panel is clipped + stroked for a clean rounded outer edge (the
            // owner-reported "funny edges").
            VStack(spacing: 1) {
                // Column headers
                HStack(spacing: 0) {
                    Text("#").font(.caption2).bold().frame(width: 22)
                    Text("A").font(.caption2).bold().frame(width: 26)
                    Text("Circuit").font(.caption2).bold()
                    Spacer()
                    // Continuous center spine — same color as the row spine so the
                    // panel's backbone runs unbroken from header to last row.
                    Rectangle().fill(gridLineColor).frame(width: 4)
                        .accessibilityHidden(true)
                    Spacer()
                    Text("Circuit").font(.caption2).bold()
                    Text("A").font(.caption2).bold().frame(width: 26)
                    Text("#").font(.caption2).bold().frame(width: 22)
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xxs)
                .background(Color(.secondarySystemBackground))

                // Circuit rows — max() keeps the range valid even if a malformed
                // negative totalSpaces slips past load-path clamping (#1239).
                ForEach(0..<max(schedule.totalSpaces / 2, 0), id: \.self) { row in
                    let leftSpace = row * 2 + 1
                    let rightSpace = row * 2 + 2
                    let leftCircuit = schedule.circuits.first { $0.spaceNumber == leftSpace }
                    let rightCircuit = schedule.circuits.first { $0.spaceNumber == rightSpace }

                    HStack(spacing: 0) {
                        circuitCell(spaceNumber: leftSpace, circuit: leftCircuit, isLeft: true)

                        Rectangle()
                            .fill(gridLineColor)
                            .frame(width: 4)
                            .accessibilityHidden(true)

                        circuitCell(spaceNumber: rightSpace, circuit: rightCircuit, isLeft: false)
                    }
                    .fixedSize(horizontal: false, vertical: true)   // spine stretches to full row height
                }
            }
            .background(gridLineColor)   // shows through the 1pt gaps as uniform grid lines
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(gridLineColor, lineWidth: 1)
            )
        }
        .padding(.horizontal, DS.Space.sm)
    }

    private func circuitCell(spaceNumber: Int, circuit: CircuitEntry?, isLeft: Bool) -> some View {
        Button {
            if movingCircuitId != nil {
                moveSelectedCircuit(to: spaceNumber)
            } else {
                openCircuitEditor(spaceNumber: spaceNumber, circuit: circuit)
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text((circuit?.circuitDescription).flatMap { $0.isEmpty ? nil : $0 } ?? "SPARE")
                            .font(.caption).lineLimit(1)
                        if let secondary = circuit?.secondaryCircuitDescription, !secondary.isEmpty {
                            Text("+ \(secondary)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                } else {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text((circuit?.circuitDescription).flatMap { $0.isEmpty ? nil : $0 } ?? "SPARE")
                            .font(.caption).lineLimit(1)
                        if let secondary = circuit?.secondaryCircuitDescription, !secondary.isEmpty {
                            Text("+ \(secondary)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
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
            .frame(maxHeight: .infinity)
            .frame(minHeight: 44)
            // Opaque base under the translucent classification tint: without it the
            // tints composite over whatever is behind the grid, leaving ragged
            // translucent seams at cell boundaries (the "funny edges").
            .background(circuitBackground(circuit).background(Color(.systemBackground)))
            .overlay {
                if movingCircuitId != nil {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.blue.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(circuit?.id ?? "")
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, !id.isEmpty else { return false }
            return moveCircuit(id: id, to: spaceNumber)
        }
        .contextMenu {
            if let circuit {
                Button {
                    movingCircuitId = circuit.id
                } label: {
                    Label("Move Circuit", systemImage: "arrow.left.arrow.right")
                }
                Button {
                    openCircuitEditor(spaceNumber: spaceNumber, circuit: circuit)
                } label: {
                    Label("Edit Circuit", systemImage: "pencil")
                }
            }
        }
        .accessibilityLabel(circuitAccessibilityLabel(spaceNumber: spaceNumber, circuit: circuit))
        .accessibilityValue(circuitAccessibilityValue(circuit))
        .accessibilityHint(movingCircuitId != nil ? "Moves the selected circuit here." : "Opens the editor for circuit \(spaceNumber).")
        .accessibilityIdentifier("panel-schedule-circuit-\(spaceNumber)")
        .accessibilityAction(named: Text(circuit == nil ? "Place selected circuit here" : "Move circuit")) {
            if let circuit {
                movingCircuitId = circuit.id
            } else if movingCircuitId != nil {
                moveSelectedCircuit(to: spaceNumber)
            }
        }
    }

    private func openCircuitEditor(spaceNumber: Int, circuit: CircuitEntry?) {
        selectedCircuit = circuit ?? CircuitEntry(spaceNumber: spaceNumber)
        activeSheet = .circuitEditor
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
        _ = moveCircuit(id: movingCircuitId, to: spaceNumber)
    }

    /// Attempts to move a circuit and returns whether it succeeded. Callers that
    /// bridge to SwiftUI drag-and-drop must propagate this so a rejected move
    /// (validation failure) cancels the drop instead of appearing to succeed.
    @discardableResult
    private func moveCircuit(id: String, to spaceNumber: Int) -> Bool {
        do {
            try schedule.moveCircuit(id: id, to: spaceNumber)
            movingCircuitId = nil
            return true
        } catch {
            validationMessage = error.localizedDescription
            return false
        }
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
        details.append(circuit.classification.rawValue)

        let description = circuit.circuitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            details.append(description)
        }
        if let secondary = circuit.secondaryCircuitDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !secondary.isEmpty {
            details.append("plus \(secondary)")
        }
        if let fedFrom = circuit.isFedFrom?.trimmingCharacters(in: .whitespacesAndNewlines), !fedFrom.isEmpty {
            details.append("fed from \(fedFrom)")
        }
        return details.joined(separator: ", ")
    }

    private func circuitBackground(_ circuit: CircuitEntry?) -> Color {
        guard let circuit, !circuit.isSpare else { return .yellow.opacity(0.05) }
        // Breaker-type safety coloring (GFCI/AFCI/dual-function) takes priority: it's the
        // pre-existing, safety-relevant visual cue and must stay reachable regardless of
        // classification, per #1379 review — classification color coding is additive, not
        // a replacement for it.
        switch circuit.breakerType {
        case .gfci, .afci, .dualFunction: return .green.opacity(0.1)
        case .double: return .blue.opacity(0.1)
        case .tandem: return .purple.opacity(0.1)
        case .spare: return .yellow.opacity(0.1)
        case .blank: return .gray.opacity(0.1)
        case .single: break
        }
        switch circuit.classification {
        case .lighting: return .cyan.opacity(0.12)
        case .receptacle: return .orange.opacity(0.12)
        case .motor: return .red.opacity(0.12)
        case .spare: return .yellow.opacity(0.1)
        case .blank: return .gray.opacity(0.1)
        case .special: return .clear
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
                legendDot(.green, "GFI/AFI")
                legendDot(.yellow, "Spare")
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
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { exportMenuAnchorRect = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, newValue in
                            exportMenuAnchorRect = newValue
                        }
                }
            )

            Button {
                guard validateBeforeSave() else { return }
                // A #1239-safe-loaded type/size mismatch can have retained
                // circuits outside the display-normalized range. Those circuits
                // remain editable and must persist until the user explicitly
                // corrects the settings pair through Panel Settings. Valid
                // schedules keep the existing explicit prune confirmation.
                if schedule.panelSettingsValidationError != nil || schedule.circuitsOutsideTotalSpaces.isEmpty {
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
        let normalized = circuit.normalizedForPersistence()
        var candidate = schedule
        if let index = candidate.circuits.firstIndex(where: { $0.spaceNumber == normalized.spaceNumber }) {
            candidate.circuits[index] = normalized
        } else {
            candidate.circuits.append(normalized)
        }
        do {
            try candidate.validated()
            schedule = candidate
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    /// Runs position validation before the existing #1239 prune/save flow.
    /// Returns `false` (and surfaces `validationMessage`) if the schedule has
    /// an unresolved double-breaker span or space conflict.
    private func validateBeforeSave() -> Bool {
        do {
            try schedule.validated()
            return true
        } catch {
            validationMessage = error.localizedDescription
            return false
        }
    }

    private func saveNormalizedSchedule() {
        let normalized = schedule.normalizedForPersistence()
        schedule = normalized
        onSave(normalized)
    }

    // MARK: - Export

    private func exportPanelScheduleForShare() {
        do {
            let url = try PanelSchedulePDFExporter(schedule: schedule, options: exportOptions).writeToTemporaryFile()
            activeSheet = .share(url)
        } catch {
            exportMessage = userFriendlyError(error, context: "export panel schedule")
        }
    }

    private func printPanelSchedule() {
        do {
            let url = try PanelSchedulePDFExporter(schedule: schedule, options: exportOptions).writeToTemporaryFile()

            let printController = UIPrintInteractionController.shared
            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.jobName = "\(schedule.panelName) Panel Schedule"
            printInfo.outputType = .general
            printController.printInfo = printInfo
            printController.printingItem = url

            let completion: UIPrintInteractionController.CompletionHandler = { _, _, error in
                if let error {
                    exportMessage = userFriendlyError(error, context: "print panel schedule")
                }
            }

            // `present(animated:completionHandler:)` is documented as
            // iPhone/iPod-touch only and raises "this method is not supported
            // on the iPad idiom" at runtime on iPad. The app ships
            // TARGETED_DEVICE_FAMILY = "1,2" (iPhone + iPad), so both paths
            // must be handled: iPad requires the popover-anchored
            // `present(from:in:animated:completionHandler:)`.
            if UIDevice.current.userInterfaceIdiom == .pad {
                guard let rootViewController = Self.activeRootViewController() else {
                    exportMessage = userFriendlyError(
                        PanelScheduleExportError.outputPathUnavailable,
                        context: "print panel schedule"
                    )
                    return
                }
                let anchorRect = exportMenuAnchorRect == .zero
                    ? CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 1, height: 1)
                    : rootViewController.view.convert(exportMenuAnchorRect, from: nil)
                printController.present(
                    from: anchorRect,
                    in: rootViewController.view,
                    animated: true,
                    completionHandler: completion
                )
            } else {
                printController.present(animated: true, completionHandler: completion)
            }
        } catch {
            exportMessage = userFriendlyError(error, context: "print panel schedule")
        }
    }

    /// The current key window's root view controller, used to anchor the
    /// iPad popover presentation of `UIPrintInteractionController`.
    private static func activeRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow }?.rootViewController
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
                        onSave(circuit.normalizedForPersistence())
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

    // Type and size are one atomic settings pair. Keep user edits local until
    // `updatePanelSettings` has accepted the pair so a rejected shrink cannot
    // partially mutate the schedule or hide a double-breaker's second space.
    @State private var draftPanelType: PanelType
    @State private var draftTotalSpaces: Int
    @State private var settingsValidationMessage: String?

    private let ampOptions = [100, 125, 150, 200, 225, 400, 600]

    init(schedule: Binding<PanelSchedule>) {
        self._schedule = schedule

        let savedSchedule = schedule.wrappedValue
        let allowedSpaces = savedSchedule.panelType.allowedTotalSpaces
        self._draftPanelType = State(initialValue: savedSchedule.panelType)
        self._draftTotalSpaces = State(initialValue:
            allowedSpaces.contains(savedSchedule.totalSpaces)
                ? savedSchedule.totalSpaces
                : allowedSpaces.first ?? savedSchedule.totalSpaces
        )
    }

    /// Mirrors the atomic model validation so a draft warning includes the
    /// second occupied space of a double breaker (for example 19/21), not only
    /// circuit origin spaces beyond the proposed panel size.
    private var circuitOriginSpacesThatWouldBeHidden: [Int] {
        schedule.circuits
            .filter { circuit in
                schedule.occupiedSpaces(for: circuit).contains { occupiedSpace in
                    occupiedSpace < 1 || occupiedSpace > draftTotalSpaces
                }
            }
            .map(\.spaceNumber)
            .sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Panel") {
                    TextField("Panel Name", text: $schedule.panelName)
                    Picker("Type", selection: $draftPanelType) {
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
                    Picker("Total Spaces", selection: $draftTotalSpaces) {
                        ForEach(draftPanelType.allowedTotalSpaces, id: \.self) { size in
                            Text("\(size) spaces").tag(size)
                        }
                    }
                    if !circuitOriginSpacesThatWouldBeHidden.isEmpty {
                        Label(
                            "The selected settings would hide circuit\(circuitOriginSpacesThatWouldBeHidden.count == 1 ? "" : "s") at space\(circuitOriginSpacesThatWouldBeHidden.count == 1 ? "" : "s") \(circuitOriginSpacesThatWouldBeHidden.map(String.init).joined(separator: ", ")). Move or remove \(circuitOriginSpacesThatWouldBeHidden.count == 1 ? "it" : "them") before saving.",
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
            .onChange(of: draftPanelType) { _, newType in
                guard !newType.allowedTotalSpaces.contains(draftTotalSpaces),
                      let firstAllowedSpace = newType.allowedTotalSpaces.first else {
                    return
                }
                draftTotalSpaces = firstAllowedSpace
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        do {
                            try schedule.updatePanelSettings(
                                panelType: draftPanelType,
                                totalSpaces: draftTotalSpaces
                            )
                            dismiss()
                        } catch {
                            settingsValidationMessage = error.localizedDescription
                        }
                    }
                        .fontWeight(.semibold)
                }
            }
            .alert("Panel settings issue", isPresented: Binding(
                get: { settingsValidationMessage != nil },
                set: { if !$0 { settingsValidationMessage = nil } }
            )) {
                Button("OK", role: .cancel) { settingsValidationMessage = nil }
            } message: {
                Text(settingsValidationMessage ?? "")
            }
        }
    }
}
