# 16F — Bulk Markup Editor + Pricing Settings

> **Chain position:** 16A–16E → **16F** → 16G → 16H → 16I
> **Prerequisite:** 16E complete (override flow, pricing tiers working)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Two features in one prompt:

1. **Bulk Markup Editor:** Let the user change markup/margin for many parts at once. Shows preview of 15 random affected parts (locked for the session). The user can then choose to review affected parts one at a time if they want, OR just apply.

2. **Pricing Settings:** Company-wide settings panel — toggle between Markup and Margin mode, set default markup %, set stale price threshold.

**Key files:**
- Create: `Weird Parts IOS/Weird Parts IOS/Features/Parts/PricingBulkEditSheet.swift`
- Create: `Weird Parts IOS/Weird Parts IOS/Features/Parts/PricingSettingsSheet.swift`
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsPricingPage.swift` (replace placeholders in sheet handler)

## Task

### Step 1: Create `PricingBulkEditSheet.swift`

```swift
import SwiftUI
import WiredPartCore

/// Bulk edit markup/margin across a filtered set of parts.
/// Shows a preview of 15 random affected parts locked for the session.
/// User can optionally step through affected parts one at a time.
struct PricingBulkEditSheet: View {
    let onComplete: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var pricingMode = "markup"
    @State private var scope: BulkScope = .all
    @State private var categoryId: Int64?
    @State private var categories: [PartCategory] = []

    @State private var markupText = ""
    @State private var marginText = ""

    // Preview — locked set of 15 parts
    @State private var previewParts: [PartsService.PricingPreviewPart] = []
    @State private var showPreview = false

    // One-at-a-time review
    @State private var reviewIndex: Int?

    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isComplete = false

    enum BulkScope: String, CaseIterable {
        case all = "All Parts"
        case category = "By Category"
    }

    var body: some View {
        NavigationStack {
            if isComplete {
                completeView
            } else if let idx = reviewIndex {
                reviewOneAtATime(index: idx)
            } else if showPreview {
                previewView
            } else {
                inputView
            }
        }
    }

    // MARK: - Input View

    @ViewBuilder
    private var inputView: some View {
        Form {
            Section("Scope") {
                Picker("Apply to", selection: $scope) {
                    ForEach(BulkScope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                if scope == .category {
                    Picker("Category", selection: $categoryId) {
                        Text("Select...").tag(nil as Int64?)
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id as Int64?)
                        }
                    }
                }
            }

            Section("New \(pricingMode == "markup" ? "Markup" : "Margin")") {
                if pricingMode == "markup" {
                    HStack {
                        Text("Markup")
                        Spacer()
                        TextField("0", text: $markupText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                } else {
                    HStack {
                        Text("Margin")
                        Spacer()
                        TextField("0", text: $marginText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                }
            }

            Section {
                Button("Load Preview") {
                    Task { await loadPreview() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(!hasValidInput)
            }

            if let error = saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Bulk Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            guard let service = appCore.partsService else { return }
            pricingMode = (try? service.getCompanyCostSetting(key: "pricing_mode")) ?? "markup"
            categories = (try? service.listCategories()) ?? []
        }
    }

    // MARK: - Preview View (READ ONLY)

    @ViewBuilder
    private var previewView: some View {
        List {
            Section("Preview: \(previewParts.count) Sample Parts") {
                ForEach(previewParts, id: \.partId) { part in
                    HStack {
                        Text(part.partName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f → $%.2f", part.currentSellPrice, part.newSellPrice))
                                .font(.caption)
                                .monospaced()
                            let diff = part.difference
                            Text(String(format: "%@$%.2f", diff >= 0 ? "+" : "", diff))
                                .font(.caption2)
                                .foregroundStyle(diff >= 0 ? .green : .red)
                        }
                    }
                    .frame(minHeight: 40)
                }
            } footer: {
                Text("Random sample locked for this session. Actual change applies to all qualifying parts.")
                    .font(.caption2)
            }

            Section {
                // Apply to all
                Button {
                    Task { await applyBulk() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else {
                            Text("Apply to All")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .frame(minHeight: 44)
                .disabled(isSaving)

                // Review one at a time (optional)
                Button {
                    reviewIndex = 0
                } label: {
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Text("Review One at a Time")
                            Text("Step through each part in the preview")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .frame(minHeight: 52)
            }
        }
        .navigationTitle("Preview")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showPreview = false } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }

    // MARK: - Review One at a Time

    @ViewBuilder
    private func reviewOneAtATime(index: Int) -> some View {
        if index < previewParts.count {
            let part = previewParts[index]
            List {
                Section {
                    HStack {
                        Text("Part \(index + 1) of \(previewParts.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    ProgressView(value: Double(index + 1), total: Double(previewParts.count))
                        .tint(.accentColor)
                }

                Section("Part Details") {
                    LabeledContent("Name", value: part.partName)
                    LabeledContent("Avg Cost") {
                        Text(String(format: "$%.2f", part.weightedAvgCost))
                    }
                }

                Section("Price Change") {
                    LabeledContent("Current \(pricingMode == "markup" ? "Markup" : "Margin")") {
                        Text(String(format: "%.1f%%", part.currentMarkup))
                    }
                    LabeledContent("New \(pricingMode == "markup" ? "Markup" : "Margin")") {
                        Text(String(format: "%.1f%%", part.newMarkup))
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Current Sell") {
                        Text(String(format: "$%.2f", part.currentSellPrice))
                    }
                    LabeledContent("New Sell") {
                        Text(String(format: "$%.2f", part.newSellPrice))
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    let diff = part.difference
                    LabeledContent("Difference") {
                        Text(String(format: "%@$%.2f", diff >= 0 ? "+" : "", diff))
                            .foregroundStyle(diff >= 0 ? .green : .red)
                    }
                }

                Section {
                    if index + 1 < previewParts.count {
                        Button("Next Part") { reviewIndex = index + 1 }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Button {
                            Task { await applyBulk() }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Apply to All")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("Review")
        }
    }

    // MARK: - Complete

    @ViewBuilder
    private var completeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Bulk Update Applied")
                .font(.title2)
                .fontWeight(.bold)
            Text("Pricing has been updated across all qualifying parts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") {
                Task {
                    await onComplete()
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
    }

    // MARK: - Logic

    private var hasValidInput: Bool {
        if pricingMode == "markup" { return Double(markupText) != nil }
        return Double(marginText) != nil
    }

    private func loadPreview() async {
        guard let service = appCore.partsService else { return }
        saveError = nil
        do {
            let markup = pricingMode == "markup" ? Double(markupText) : nil
            let margin = pricingMode == "margin" ? Double(marginText) : nil

            previewParts = try service.getPreviewParts(
                categoryId: scope == .category ? categoryId : nil,
                newMarkupPercent: markup,
                newMarginPercent: margin
            )
            showPreview = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func applyBulk() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                isSaving = false
                return
            }

            let markup = pricingMode == "markup" ? Double(markupText) : nil
            let margin = pricingMode == "margin" ? Double(marginText) : nil

            // Set tier at the appropriate level
            if scope == .category, let catId = categoryId {
                try service.setPricingTier(categoryId: catId, markupPercent: markup, marginPercent: margin)
            } else {
                // "All" scope — update default markup in company settings
                if let m = markup {
                    try service.updateCompanyCostSetting(key: "default_markup_percent", value: String(format: "%.5f", m))
                }
                if let m = margin {
                    // Convert margin to markup for default setting
                    let convertedMarkup = m < 100 ? (m / (100 - m)) * 100 : 100
                    try service.updateCompanyCostSetting(key: "default_markup_percent", value: String(format: "%.5f", convertedMarkup))
                }
            }

            isComplete = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

### Step 2: Create `PricingSettingsSheet.swift`

```swift
import SwiftUI
import WiredPartCore

/// Company-wide pricing settings: mode toggle, default markup, stale threshold.
struct PricingSettingsSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var pricingMode = "markup"
    @State private var defaultMarkup = ""
    @State private var staleThresholdDays = ""
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Pricing Mode") {
                    Picker("Display Mode", selection: $pricingMode) {
                        Text("Markup (% on cost)").tag("markup")
                        Text("Margin (% of sell price)").tag("margin")
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if pricingMode == "markup" {
                        Text("Markup: (Sell - Cost) ÷ Cost × 100\nExample: Cost $10, Sell $15 = 50% markup")
                    } else {
                        Text("Margin: (Sell - Cost) ÷ Sell × 100\nExample: Cost $10, Sell $15 = 33.3% margin")
                    }
                }

                Section("Default Markup") {
                    HStack {
                        Text("Default")
                        Spacer()
                        TextField("50", text: $defaultMarkup)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                } footer: {
                    Text("Applied to parts with no tier pricing set at any level.")
                }

                Section("Stale Price Alert") {
                    HStack {
                        Text("Alert after")
                        Spacer()
                        TextField("90", text: $staleThresholdDays)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 60)
                            .keyboardType(.numberPad)
                        Text("days")
                    }
                    .frame(minHeight: 44)
                } footer: {
                    Text("Parts not updated in this many days show a warning when ordering. Recommended: check the receipt to verify pricing.")
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Pricing Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving)
                }
            }
            .task { await loadSettings() }
        }
    }

    private func loadSettings() async {
        guard let service = appCore.partsService else { return }
        pricingMode = (try? service.getCompanyCostSetting(key: "pricing_mode")) ?? "markup"
        defaultMarkup = (try? service.getCompanyCostSetting(key: "default_markup_percent")) ?? "50"
        staleThresholdDays = (try? service.getCompanyCostSetting(key: "stale_price_threshold_days")) ?? "90"
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                isSaving = false
                return
            }
            try service.updateCompanyCostSetting(key: "pricing_mode", value: pricingMode)
            try service.updateCompanyCostSetting(key: "default_markup_percent", value: defaultMarkup)
            try service.updateCompanyCostSetting(key: "stale_price_threshold_days", value: staleThresholdDays)
            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

### Step 3: Replace placeholders in PartsPricingPage.swift

In the `sheetContent` switch, replace the placeholder cases:

```swift
case .bulkEdit:
    PricingBulkEditSheet { await loadData() }
case .pricingSettings:
    PricingSettingsSheet { await loadData() }
```

## Success Criteria

- [ ] Bulk edit: scope picker (all / by category), markup/margin input, preview of 15 locked parts
- [ ] Preview is READ ONLY — shows sample with old/new/diff
- [ ] Optional "Review One at a Time" steps through preview parts sequentially
- [ ] "Apply to All" sets tier or updates default setting
- [ ] Pricing settings: mode toggle (markup/margin), default markup %, stale threshold days
- [ ] Settings show explanatory text for markup vs margin formulas
- [ ] Both sheets accessible from pricing page toolbar menu
- [ ] No placeholder text remaining in sheet handler
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16F Results (YYYY-MM-DD)
- Created PricingBulkEditSheet.swift, PricingSettingsSheet.swift
- Bulk edit with scope, preview (15 locked parts), optional one-at-a-time review
- Settings: pricing_mode, default_markup_percent, stale_price_threshold_days
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 16G.**
