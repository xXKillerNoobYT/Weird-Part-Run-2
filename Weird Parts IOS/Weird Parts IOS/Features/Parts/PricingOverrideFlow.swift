import SwiftUI
import WiredPartCore

/// Flow for setting pricing at a hierarchy level with override confirmation.
///
/// Presents a multi-step sheet:
/// 1. Pick the hierarchy level (Category, Style, Type, Brand)
/// 2. Pick the specific entity at that level
/// 3. Enter the new markup/margin/fixed price
/// 4. Preview up to 15 random affected parts (read-only)
/// 5. If overrides exist, step through them ONE AT A TIME (Replace or Keep)
struct PricingTierSetSheet: View {
    let onComplete: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Step tracking
    @State private var step: FlowStep = .selectLevel
    @State private var pricingMode: String = "markup"

    // Selections
    @State private var selectedLevel: HierarchyLevel = .category
    @State private var selectedEntityId: Int64?
    @State private var selectedEntityName: String = ""

    // Data for pickers
    @State private var categories: [PartCategory] = []
    @State private var styles: [PartStyle] = []
    @State private var types: [PartType] = []
    @State private var brands: [Brand] = []

    // Price input
    @State private var markupText = ""
    @State private var marginText = ""
    @State private var fixedPriceText = ""
    @State private var useFixedPrice = false

    // Preview
    @State private var previewParts: [PartsService.PricingPreviewPart] = []

    // Override conflicts
    @State private var conflicts: [PartsService.OverrideConflict] = []
    @State private var currentConflictIndex = 0
    @State private var conflictDecisions: [Int64: Bool] = [:] // tierId -> replace (true) or keep (false)

    @State private var isSaving = false
    @State private var saveError: String?

    enum FlowStep {
        case selectLevel
        case selectEntity
        case setPrice
        case preview
        case resolveConflicts
        case done
    }

    enum HierarchyLevel: String, CaseIterable {
        case category = "Category"
        case style = "Style"
        case type = "Type"
        case brand = "Brand"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .selectLevel: selectLevelView
                case .selectEntity: selectEntityView
                case .setPrice: setPriceView
                case .preview: previewView
                case .resolveConflicts: resolveConflictsView
                case .done: doneView
                }
            }
            .navigationTitle("Set Tier Pricing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                guard let service = appCore.partsService else { return }
                pricingMode = (try? service.getCompanyCostSetting(key: "pricing_mode")) ?? "markup"
            }
        }
    }

    // MARK: - Step 1: Select Level

    @ViewBuilder
    private var selectLevelView: some View {
        List {
            Section("Which level should this price apply to?") {
                ForEach(HierarchyLevel.allCases, id: \.self) { level in
                    Button {
                        selectedLevel = level
                        Task { await loadEntitiesForLevel(level) }
                        step = .selectEntity
                    } label: {
                        HStack {
                            Image(systemName: iconForLevel(level))
                            Text(level.rawValue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Text("Prices set at a higher level cascade down to all items below — unless a more specific price has been set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Select Entity

    @ViewBuilder
    private var selectEntityView: some View {
        List {
            Section("Select a \(selectedLevel.rawValue)") {
                switch selectedLevel {
                case .category:
                    ForEach(categories, id: \.id) { cat in
                        entityButton(name: cat.name, id: cat.id ?? 0)
                    }
                case .style:
                    ForEach(styles, id: \.id) { style in
                        entityButton(name: style.name, id: style.id ?? 0)
                    }
                case .type:
                    ForEach(types, id: \.id) { type in
                        entityButton(name: type.name, id: type.id ?? 0)
                    }
                case .brand:
                    ForEach(brands, id: \.id) { brand in
                        entityButton(name: brand.name, id: brand.id ?? 0)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { step = .selectLevel } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entityButton(name: String, id: Int64) -> some View {
        Button {
            selectedEntityId = id
            selectedEntityName = name
            step = .setPrice
        } label: {
            HStack {
                Text(name)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Set Price

    @ViewBuilder
    private var setPriceView: some View {
        Form {
            Section {
                LabeledContent("Level", value: selectedLevel.rawValue)
                LabeledContent("Name", value: selectedEntityName)
            }

            Section("Pricing") {
                Toggle("Fixed Sell Price", isOn: $useFixedPrice.animation())

                if useFixedPrice {
                    HStack {
                        Text("Price"); Spacer(); Text("$")
                        TextField("0.00", text: $fixedPriceText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .keyboardType(.decimalPad)
                    }
                    .frame(minHeight: 44)
                } else if pricingMode == "markup" {
                    HStack {
                        Text("Markup"); Spacer()
                        TextField("0", text: $markupText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                } else {
                    HStack {
                        Text("Margin"); Spacer()
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
                Button("Preview Impact") {
                    Task { await loadPreviewAndConflicts() }
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { step = .selectEntity } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Preview (READ ONLY)

    @ViewBuilder
    private var previewView: some View {
        List {
            Section {
                Text("Setting \(selectedLevel.rawValue) \"\(selectedEntityName)\" to \(previewPriceDescription)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Section("Sample of Affected Parts (\(previewParts.count))") {
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
                Text("This is a random sample for preview only. The actual price will apply to ALL parts at this level without an existing override.")
                    .font(.caption2)
            }

            Section {
                if conflicts.isEmpty {
                    // No conflicts — can apply directly
                    Button {
                        Task { await applyTierPricing() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView() } else {
                                Text("Apply Pricing")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .frame(minHeight: 44)
                    .disabled(isSaving)
                } else {
                    Button {
                        currentConflictIndex = 0
                        step = .resolveConflicts
                    } label: {
                        HStack {
                            Spacer()
                            VStack(spacing: 2) {
                                Text("Apply & Review \(conflicts.count) Override\(conflicts.count == 1 ? "" : "s")")
                                    .fontWeight(.semibold)
                                Text("You'll review each override one at a time")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .frame(minHeight: 52)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { step = .setPrice } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }

    // MARK: - Step 5: Resolve Conflicts ONE AT A TIME

    @ViewBuilder
    private var resolveConflictsView: some View {
        if currentConflictIndex < conflicts.count {
            let conflict = conflicts[currentConflictIndex]
            let progress = currentConflictIndex + 1

            VStack(spacing: 0) {
                // Progress indicator
                HStack {
                    Text("Override \(progress) of \(conflicts.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(conflicts.count - progress) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

                ProgressView(value: Double(progress), total: Double(conflicts.count))
                    .tint(.accentColor)
                    .padding(.horizontal)

                List {
                    Section("Existing Override") {
                        LabeledContent("Level", value: conflict.tier.tierLevel)
                        LabeledContent("Current Sell Price") {
                            Text(String(format: "$%.2f", conflict.currentSellPrice))
                                .fontWeight(.medium)
                        }
                        LabeledContent("Parts Affected", value: "\(conflict.affectedPartCount)")
                    }

                    Section("Proposed Change") {
                        LabeledContent("New Sell Price") {
                            Text(String(format: "$%.2f", conflict.newSellPrice))
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                        }
                        LabeledContent("Difference") {
                            let diff = conflict.difference
                            Text(String(format: "%@$%.2f", diff >= 0 ? "+" : "", diff))
                                .fontWeight(.medium)
                                .foregroundStyle(diff >= 0 ? .green : .red)
                        }
                    }

                    Section {
                        // REPLACE — use new price, remove override
                        Button {
                            if let tierId = conflict.tier.id {
                                conflictDecisions[tierId] = true
                            }
                            advanceConflict()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Replace Override")
                                        .fontWeight(.medium)
                                    Text("Remove this override, use the new \(selectedLevel.rawValue) price")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 52)
                        }
                        .buttonStyle(.plain)

                        // KEEP — leave existing override
                        Button {
                            if let tierId = conflict.tier.id {
                                conflictDecisions[tierId] = false
                            }
                            advanceConflict()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.shield")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Keep Override")
                                        .fontWeight(.medium)
                                    Text("This override stays — price won't change")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 52)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Done

    @ViewBuilder
    private var doneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Pricing Updated")
                .font(.title2)
                .fontWeight(.bold)

            let replaced = conflictDecisions.values.filter { $0 }.count
            let kept = conflictDecisions.values.filter { !$0 }.count
            if replaced > 0 || kept > 0 {
                VStack(spacing: 4) {
                    if replaced > 0 {
                        Text("\(replaced) override\(replaced == 1 ? "" : "s") replaced")
                            .font(.subheadline)
                    }
                    if kept > 0 {
                        Text("\(kept) override\(kept == 1 ? "" : "s") kept")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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
    }

    // MARK: - Helpers

    private var hasValidInput: Bool {
        if useFixedPrice { return Double(fixedPriceText) != nil }
        if pricingMode == "markup" { return Double(markupText) != nil }
        return Double(marginText) != nil
    }

    private var previewPriceDescription: String {
        if useFixedPrice { return "$\(fixedPriceText)" }
        if pricingMode == "markup" { return "\(markupText)% markup" }
        return "\(marginText)% margin"
    }

    private func iconForLevel(_ level: HierarchyLevel) -> String {
        switch level {
        case .category: return "folder"
        case .style: return "paintbrush"
        case .type: return "cube"
        case .brand: return "tag"
        }
    }

    private func loadEntitiesForLevel(_ level: HierarchyLevel) async {
        guard let service = appCore.partsService else { return }
        do {
            switch level {
            case .category:
                categories = try service.listCategories()
            case .style:
                styles = try service.listStyles()
            case .type:
                types = try service.listTypes()
            case .brand:
                let results = try service.listBrands()
                brands = results.map(\.brand)
            }
        } catch {
            print("[PricingTierSetSheet] Load error: \(error)")
        }
    }

    private func loadPreviewAndConflicts() async {
        guard let service = appCore.partsService else { return }
        saveError = nil
        do {
            let catId = selectedLevel == .category ? selectedEntityId : nil
            let styId = selectedLevel == .style ? selectedEntityId : nil
            let typId = selectedLevel == .type ? selectedEntityId : nil
            let brnId = selectedLevel == .brand ? selectedEntityId : nil

            let markup = pricingMode == "markup" ? Double(markupText) : nil
            let margin = pricingMode == "margin" ? Double(marginText) : nil
            let fixed = useFixedPrice ? Double(fixedPriceText) : nil

            previewParts = try service.getPreviewParts(
                categoryId: catId, styleId: styId, typeId: typId, brandId: brnId,
                newMarkupPercent: markup, newMarginPercent: margin, newFixedPrice: fixed
            )

            conflicts = try service.findOverrideConflicts(
                categoryId: catId, styleId: styId, typeId: typId, brandId: brnId,
                newMarkupPercent: markup, newMarginPercent: margin, newFixedPrice: fixed
            )

            step = .preview
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func advanceConflict() {
        if currentConflictIndex + 1 < conflicts.count {
            currentConflictIndex += 1
        } else {
            // All conflicts resolved — apply the tier and decisions
            Task { await applyTierPricing() }
        }
    }

    private func applyTierPricing() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                isSaving = false
                return
            }

            let catId = selectedLevel == .category ? selectedEntityId : nil
            let styId = selectedLevel == .style ? selectedEntityId : nil
            let typId = selectedLevel == .type ? selectedEntityId : nil
            let brnId = selectedLevel == .brand ? selectedEntityId : nil

            let markup = pricingMode == "markup" ? Double(markupText) : nil
            let margin = pricingMode == "margin" ? Double(marginText) : nil
            let fixed = useFixedPrice ? Double(fixedPriceText) : nil

            // Set the tier
            _ = try service.setPricingTier(
                categoryId: catId, styleId: styId, typeId: typId, brandId: brnId,
                markupPercent: markup, marginPercent: margin, fixedSellPrice: fixed
            )

            // Process conflict decisions
            for (tierId, shouldReplace) in conflictDecisions {
                if shouldReplace {
                    try service.removePricingTier(tierId: tierId)
                }
                // If keep, do nothing — the tier stays
            }

            step = .done
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
