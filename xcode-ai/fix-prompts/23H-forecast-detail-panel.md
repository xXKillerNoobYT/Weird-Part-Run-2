# 23H — Forecasting Detail Panel Redesign

> **Chain position:** 23A → … → 23G → **23H**
> **Prerequisite:** 23G complete (location picker + recommendations UI)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The current forecast detail sheet is a read-only `List` of `LabeledContent` rows showing forecast metrics. It needs to become a full part editor with stock health visualization per location. When a user taps a part in the forecast list, they should be able to see AND edit all part info, see stock levels across all locations with health bars, and take actions.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift` — current `ForecastDetailSheet`
- `core/Sources/WiredPartCore/Services/PartsService.swift` — `listLocationStockTargets()`, `LocationStockTargetWithStock`
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — `Part` model fields

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift` — replace `ForecastDetailSheet`

## Task

### Step 1: Replace ForecastDetailSheet

Replace the existing `ForecastDetailSheet` with a comprehensive detail view. The new sheet has 4 sections:

```swift
private struct ForecastDetailSheet: View {
    let row: PartsService.ForecastDataRow
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var locationTargets: [PartsService.LocationStockTargetWithStock] = []
    @State private var isLoadingLocations = true
    @State private var editError: String?
    @State private var isSaving = false

    // Editable fields
    @State private var editName: String = ""
    @State private var editCode: String = ""
    @State private var editMinStock: String = ""
    @State private var editTargetStock: String = ""
    @State private var editMaxStock: String = ""

    var body: some View {
        NavigationStack {
            List {
                partInfoSection
                stockHealthSection
                forecastMetricsSection
                actionsSection
            }
            .navigationTitle("Part Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(editError != nil)) {
                Button("OK") { editError = nil }
            } message: {
                Text(editError ?? "")
            }
            .task {
                editName = row.part.name
                editCode = row.part.code ?? ""
                editMinStock = "\(row.part.minStockLevel ?? 0)"
                editTargetStock = "\(row.part.targetStockLevel ?? 0)"
                editMaxStock = "\(row.part.maxStockLevel ?? 0)"
                await loadLocationData()
            }
        }
    }
```

### Step 2: Part Info Section (editable)

```swift
    @ViewBuilder
    private var partInfoSection: some View {
        Section("Part Info") {
            LabeledContent("Name") {
                TextField("Name", text: $editName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Code") {
                TextField("Code", text: $editCode)
                    .multilineTextAlignment(.trailing)
                    .monospaced()
            }

            if let category = row.part.categoryName {
                LabeledContent("Category", value: category)
            }
            if let brand = row.part.brandName {
                LabeledContent("Brand", value: brand)
            }

            // Global stock levels (editable)
            LabeledContent("Min Stock (Global)") {
                TextField("0", text: $editMinStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            LabeledContent("Target Stock (Global)") {
                TextField("0", text: $editTargetStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            LabeledContent("Max Stock (Global)") {
                TextField("0", text: $editMaxStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }

            LabeledContent("Total Stock (All Locations)", value: "\(row.currentStock)")

            // Save button
            if hasChanges {
                Button {
                    Task { await savePartChanges() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().padding(.trailing, 4) }
                        Text("Save Changes")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    private var hasChanges: Bool {
        editName != row.part.name ||
        editCode != (row.part.code ?? "") ||
        editMinStock != "\(row.part.minStockLevel ?? 0)" ||
        editTargetStock != "\(row.part.targetStockLevel ?? 0)" ||
        editMaxStock != "\(row.part.maxStockLevel ?? 0)"
    }
```

### Step 3: Stock Health Per Location Section

```swift
    @ViewBuilder
    private var stockHealthSection: some View {
        Section("Stock by Location") {
            if isLoadingLocations {
                ProgressView("Loading locations...")
            } else if locationTargets.isEmpty {
                Text("No stock at any location")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(locationTargets) { target in
                    VStack(alignment: .leading, spacing: 6) {
                        // Location header
                        HStack {
                            Image(systemName: locationIcon(target.locationType))
                                .foregroundStyle(.secondary)
                            Text(target.locationName)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(target.currentStock)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(healthColor(target.healthScore))
                        }

                        // Health bar
                        stockHealthBar(target: target)

                        // MIN | TARGET | MAX labels
                        HStack {
                            Text("MIN: \(target.minStock)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("TGT: \(target.targetStock)")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Spacer()
                            Text("MAX: \(target.maxStock)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // Certainty + category
                        HStack {
                            if let cert = target.certaintyRating {
                                Text("Certainty: \(Int(cert * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(cert >= 0.8 ? .green : .orange)
                            }
                            Spacer()
                            if let adu = target.forecastAdu30, adu > 0 {
                                Text(String(format: "Usage: %.1f", adu))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func stockHealthBar(target: PartsService.LocationStockTargetWithStock) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let maxVal = max(target.maxStock, target.currentStock, 1)

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 12)

                // MIN zone (red)
                if target.minStock > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.2))
                        .frame(width: width * CGFloat(target.minStock) / CGFloat(maxVal), height: 12)
                }

                // Current stock bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(healthColor(target.healthScore))
                    .frame(width: max(4, width * CGFloat(target.currentStock) / CGFloat(maxVal)), height: 12)

                // TARGET marker (center line)
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: 16)
                    .offset(x: width * CGFloat(target.targetStock) / CGFloat(maxVal) - 1)
            }
        }
        .frame(height: 16)
    }

    private func healthColor(_ score: Double) -> Color {
        if score <= -0.5 { return .red }       // well below MIN
        if score < 0 { return .orange }         // below TARGET
        if score <= 0.5 { return .green }       // at/near TARGET
        if score < 1.0 { return .yellow }       // approaching MAX
        return .red                              // at/above MAX
    }

    private func locationIcon(_ type: String) -> String {
        switch type {
        case "warehouse": return "building.2"
        case "truck": return "truck.box"
        case "trailer": return "shippingbox"
        default: return "mappin"
        }
    }
```

### Step 4: Forecast Metrics Section

```swift
    @ViewBuilder
    private var forecastMetricsSection: some View {
        Section("Forecast Metrics") {
            if let adu30 = row.part.forecastAdu30 {
                LabeledContent("Avg Daily Usage (30d)", value: String(format: "%.2f", adu30))
            }
            if let adu90 = row.part.forecastAdu90 {
                LabeledContent("Avg Daily Usage (90d)", value: String(format: "%.2f", adu90))
            }
            // Trend
            if let adu30 = row.part.forecastAdu30, let adu90 = row.part.forecastAdu90, adu90 > 0 {
                let ratio = adu30 / adu90
                LabeledContent("Usage Trend") {
                    HStack(spacing: 4) {
                        if ratio > 1.15 {
                            Image(systemName: "arrow.up.right").foregroundStyle(.red)
                            Text("Increasing").foregroundStyle(.red)
                        } else if ratio < 0.85 {
                            Image(systemName: "arrow.down.right").foregroundStyle(.green)
                            Text("Decreasing").foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text("Stable")
                        }
                    }
                    .font(.subheadline)
                }
            }
            if let days = row.part.forecastDaysUntilLow {
                LabeledContent("Days Until Low") {
                    Text("\(days)")
                        .fontWeight(.bold)
                        .foregroundStyle(days <= 7 ? .red : days <= 30 ? .orange : .green)
                }
            }
            if let suggested = row.part.forecastSuggestedOrder, suggested > 0 {
                LabeledContent("Suggested Order") {
                    Text("\(suggested)")
                        .fontWeight(.bold)
                        .foregroundStyle(.accentColor)
                }
            }
            if let lastRun = row.part.forecastLastRun {
                LabeledContent("Last Recalculated", value: lastRun)
            }
        }
    }
```

### Step 5: Actions Section

```swift
    @ViewBuilder
    private var actionsSection: some View {
        Section("Actions") {
            // Add to wishlist
            Button {
                // TODO: Wire up in wishlist prompt (Orders review)
            } label: {
                Label("Add to Wishlist", systemImage: "heart")
            }

            // View in catalog
            Button {
                // TODO: Navigate to catalog with this part selected
            } label: {
                Label("View in Catalog", systemImage: "list.bullet")
            }
        }
    }
```

### Step 6: Data loading and saving

```swift
    @Sendable
    private func loadLocationData() async {
        guard let service = appCore.partsService else {
            isLoadingLocations = false
            return
        }
        do {
            let targets = try service.listLocationStockTargets(partId: row.part.id!)
            await MainActor.run {
                locationTargets = targets
                isLoadingLocations = false
            }
        } catch {
            await MainActor.run {
                isLoadingLocations = false
            }
        }
    }

    private func savePartChanges() async {
        isSaving = true
        guard let service = appCore.partsService else {
            editError = "Service not available"
            isSaving = false
            return
        }

        // Validate MIN < TARGET < MAX
        let min = Int(editMinStock) ?? 0
        let target = Int(editTargetStock) ?? 0
        let max = Int(editMaxStock) ?? 0
        guard min < target else {
            editError = "Min stock must be less than target stock"
            isSaving = false
            return
        }
        guard target < max else {
            editError = "Target stock must be less than max stock"
            isSaving = false
            return
        }

        do {
            // Update part via service
            var updatedPart = row.part
            updatedPart.name = editName
            updatedPart.code = editCode.isEmpty ? nil : editCode
            updatedPart.minStockLevel = min
            updatedPart.targetStockLevel = target
            updatedPart.maxStockLevel = max
            try service.updatePart(updatedPart)

            await MainActor.run {
                isSaving = false
            }
        } catch {
            await MainActor.run {
                editError = "Save failed: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}
```

## Important Notes

- The health bar shows MIN as a red zone on the left, the stock fill in a color based on healthScore, and a thin TARGET marker line in the middle. MAX is the right edge.
- `healthScore` is already computed on `LocationStockTargetWithStock` from prompt 23D.
- The Part model field names (e.g., `minStockLevel`, `targetStockLevel`, `categoryName`, `brandName`) must match the actual CodingKeys in `PartsModels.swift`. Read the Part struct first and adjust names accordingly.
- The `updatePart()` method must exist in PartsService. Check if it does — if not, use whatever update method exists (e.g., `savePart()`, `editPart()`).
- The "Add to Wishlist" and "View in Catalog" buttons are placeholder actions for now — they'll be wired up during the Orders and Catalog page reviews.
- The `MIN < TARGET < MAX` validation matches the validation rules confirmed in the design.

## Success Criteria

- [ ] Detail sheet shows editable Part Info section (name, code, global min/target/max)
- [ ] Save Changes button validates MIN < TARGET < MAX
- [ ] Stock Health section shows per-location rows with health bar visualization
- [ ] Health bar shows MIN red zone, stock fill colored by health, TARGET marker line
- [ ] Each location shows: name, icon, current qty, MIN/TARGET/MAX, certainty %, usage
- [ ] Forecast Metrics section shows ADU, trend, days until low, suggested order
- [ ] Actions section with placeholder wishlist and catalog buttons
- [ ] Error handling for save failures
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23H Results (YYYY-MM-DD)
- ForecastDetailSheet redesigned: 4 sections (Part Info, Stock Health, Forecast, Actions)
- Editable fields: name, code, global min/target/max with MIN<TARGET<MAX validation
- Per-location stock health bars with color coding
- Placeholder actions for wishlist and catalog navigation
- Build: [PASS/FAIL]
```

**Forecasting page prompt chain complete (23A-23H).**
