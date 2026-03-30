# 43D — Panel Schedule Builder

> **Chain position:** 43A → 43B → 43C → **43D**
> **Prerequisite:** 43A (notebook structure)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `NotebooksService.swift` to understand block-based entries. Then create a dedicated Panel Schedule Builder tool that lives within the notebook system. This is an electrical industry tool for documenting circuit breaker assignments.

## Context

Electricians need to create panel schedules — a document showing which circuit breaker controls which circuit in an electrical panel. This is currently done on paper or in Excel. Building it into the notebook system makes it digital, printable, and linked to the job. The builder handles different panel sizes (2-space to 42-space), dual/tandem breakers, 240V spanning breakers, and exports to PDF.

## Task

### Step 1: Create Panel Schedule Models

Create `core/Sources/WiredPartCore/Models/Notebooks/PanelScheduleModels.swift`:

```swift
import Foundation

struct PanelSchedule: Codable, Identifiable, Sendable {
    var id: Int64?
    var notebookEntryId: Int64  // Links to a notebook entry (block_type = "panel_schedule")
    var panelName: String       // "MDP", "Panel A", "Sub Panel 1"
    var panelType: PanelType
    var totalSpaces: Int        // 2, 4, 8, 12, 16, 20, 24, 30, 42
    var mainBreakerAmps: Int?   // 100, 200, 400
    var voltage: Int            // 120/240, 208, 480
    var phase: Int              // 1 or 3
    var location: String?       // "Garage", "Mechanical Room"
    var circuits: [CircuitEntry]

    enum CodingKeys: String, CodingKey {
        case id, circuits, voltage, phase, location
        case notebookEntryId = "notebook_entry_id"
        case panelName = "panel_name"
        case panelType = "panel_type"
        case totalSpaces = "total_spaces"
        case mainBreakerAmps = "main_breaker_amps"
    }
}

enum PanelType: String, Codable, Sendable, CaseIterable {
    case mdp = "MDP"              // Main Distribution Panel
    case subPanel = "Sub Panel"
    case disconnect = "Disconnect"
    case loadCenter = "Load Center"
}

struct CircuitEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var spaceNumber: Int         // 1-42 (odd = left, even = right)
    var breakerAmps: Int?        // 15, 20, 30, 40, 50, 60, 100
    var breakerType: BreakerType
    var circuitDescription: String
    var wire: String?            // "#12 THHN", "#10/3 NM-B"
    var conduit: String?         // "3/4 EMT", "1/2 PVC"
    var isSpare: Bool
    var isFedFrom: String?       // Which panel feeds this circuit
}

enum BreakerType: String, Codable, Sendable, CaseIterable {
    case single = "Single"       // 1 space
    case double = "Double"       // 2 spaces (240V)
    case tandem = "Tandem"       // 2 circuits in 1 space
    case gfci = "GFCI"
    case afci = "AFCI"
    case dualFunction = "Dual Function"  // GFCI + AFCI
    case spare = "Spare"
    case blank = "Blank"         // Space blocked off
}
```

### Step 2: Create PanelScheduleBuilder View

Create `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/PanelScheduleBuilder.swift`:

```swift
import SwiftUI

struct PanelScheduleBuilder: View {
    @Binding var schedule: PanelSchedule
    @State private var selectedCircuit: CircuitEntry?
    @State private var showCircuitEditor = false
    @State private var showPDFPreview = false
    @State private var showPanelSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Panel header
            panelHeader

            // Circuit grid — two columns (odd left, even right)
            ScrollView {
                panelGrid
            }

            // Toolbar
            panelToolbar
        }
        .sheet(isPresented: $showCircuitEditor) {
            if let circuit = selectedCircuit {
                CircuitEditorSheet(circuit: circuit) { updated in
                    updateCircuit(updated)
                }
            }
        }
    }

    var panelHeader: some View {
        VStack(spacing: 4) {
            Text(schedule.panelName).font(.title2).bold()
            HStack {
                Text(schedule.panelType.rawValue)
                if let amps = schedule.mainBreakerAmps {
                    Text("•")
                    Text("\(amps)A Main")
                }
                Text("•")
                Text("\(schedule.totalSpaces) Spaces")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    var panelGrid: some View {
        // Two-column layout: odd numbers on left, even on right
        // Each row shows: [space#] [amps] [description] | [description] [amps] [space#]
        VStack(spacing: 1) {
            ForEach(0..<(schedule.totalSpaces / 2), id: \.self) { row in
                let leftSpace = row * 2 + 1
                let rightSpace = row * 2 + 2
                let leftCircuit = schedule.circuits.first { $0.spaceNumber == leftSpace }
                let rightCircuit = schedule.circuits.first { $0.spaceNumber == rightSpace }

                HStack(spacing: 0) {
                    // Left side
                    circuitCell(spaceNumber: leftSpace, circuit: leftCircuit, isLeft: true)

                    // Center divider (main bus)
                    Rectangle()
                        .fill(.gray)
                        .frame(width: 4)

                    // Right side
                    circuitCell(spaceNumber: rightSpace, circuit: rightCircuit, isLeft: false)
                }
                .frame(height: 36)
            }
        }
        .padding(.horizontal)
    }

    func circuitCell(spaceNumber: Int, circuit: CircuitEntry?, isLeft: Bool) -> some View {
        Button {
            selectedCircuit = circuit ?? CircuitEntry(
                id: UUID(), spaceNumber: spaceNumber,
                breakerAmps: nil, breakerType: .spare,
                circuitDescription: "", wire: nil, conduit: nil,
                isSpare: true, isFedFrom: nil
            )
            showCircuitEditor = true
        } label: {
            HStack {
                if isLeft {
                    Text("\(spaceNumber)").font(.caption2).frame(width: 20)
                    Text("\(circuit?.breakerAmps ?? 0)").font(.caption).frame(width: 24)
                    Text(circuit?.circuitDescription ?? "SPARE")
                        .font(.caption).lineLimit(1)
                    Spacer()
                } else {
                    Spacer()
                    Text(circuit?.circuitDescription ?? "SPARE")
                        .font(.caption).lineLimit(1)
                    Text("\(circuit?.breakerAmps ?? 0)").font(.caption).frame(width: 24)
                    Text("\(spaceNumber)").font(.caption2).frame(width: 20)
                }
            }
            .padding(.horizontal, 4)
            .background(circuitBackground(circuit))
        }
        .buttonStyle(.plain)
    }

    func circuitBackground(_ circuit: CircuitEntry?) -> Color {
        guard let circuit = circuit else { return .clear }
        if circuit.isSpare { return .yellow.opacity(0.1) }
        switch circuit.breakerType {
        case .double: return .blue.opacity(0.1)  // 240V
        case .tandem: return .purple.opacity(0.1)
        case .gfci, .afci, .dualFunction: return .green.opacity(0.1)
        default: return .clear
        }
    }
}
```

### Step 3: Circuit Editor Sheet

```swift
struct CircuitEditorSheet: View {
    @State var circuit: CircuitEntry
    let onSave: (CircuitEntry) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Breaker") {
                    Picker("Amps", selection: $circuit.breakerAmps) {
                        ForEach([15, 20, 30, 40, 50, 60, 100], id: \.self) { amps in
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
                    TextField("Description", text: $circuit.circuitDescription)
                    TextField("Wire", text: Binding(
                        get: { circuit.wire ?? "" },
                        set: { circuit.wire = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Conduit", text: Binding(
                        get: { circuit.conduit ?? "" },
                        set: { circuit.conduit = $0.isEmpty ? nil : $0 }
                    ))
                    Toggle("Spare", isOn: $circuit.isSpare)
                }
            }
            .navigationTitle("Circuit \(circuit.spaceNumber)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(circuit); dismiss() }
                }
            }
        }
    }
}
```

### Step 4: PDF Export

```swift
// Export panel schedule to PDF
func exportToPDF() -> Data {
    // Use UIGraphicsPDFRenderer
    // Header: company info, panel name, job info
    // Grid: two-column circuit layout matching the screen
    // Footer: notes, date, electrician name
    // Support custom paper sizes (letter, legal, card stock)
}
```

### Step 5: Company Header Designer

For PDF export, add a simple header designer:
- Drag-drop text, logo image, QR code, location info
- Saved as company-wide setting
- Applied to all PDF exports (panel schedules, reports)

## Important Notes
- Odd spaces are left column, even spaces are right column (industry standard)
- 240V double breakers span two consecutive spaces (e.g., spaces 1+3 or 2+4)
- Tandem breakers put two circuits in one space
- Panel sizes: 2, 4, 8, 12, 16, 20, 24, 30, 42 spaces
- Color coding: 240V=blue, tandem=purple, GFCI/AFCI=green, spare=yellow
- The panel schedule stores as JSON in a notebook entry (block_type = "panel_schedule")

## Success Criteria
- [ ] PanelScheduleModels.swift created with all models
- [ ] PanelScheduleBuilder.swift shows two-column grid
- [ ] Tappable circuit cells open editor
- [ ] Circuit editor with amps, type, description, wire, conduit
- [ ] 240V double breakers span properly
- [ ] Color coding by breaker type
- [ ] PDF export with company header
- [ ] Panel schedule stored as notebook entry
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 43D Results (YYYY-MM-DD)
- Models: PanelSchedule, CircuitEntry, BreakerType, PanelType
- UI: PanelScheduleBuilder with two-column grid
- Circuit editor sheet
- PDF export
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 43E.**
