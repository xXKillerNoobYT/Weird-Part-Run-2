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
        .interactiveDismissDisabled(isSaving)
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

            Section {
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
            } header: {
                Text("New \(pricingMode == "markup" ? "Markup" : "Margin")")
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
                    .disabled(isSaving)
            }
        }
        .task {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                return
            }
            do {
                pricingMode = try service.getCompanyCostSetting(key: "pricing_mode") ?? "markup"
                categories = try service.listCategories()
            } catch {
                saveError = userFriendlyError(error, context: "load pricing settings")
            }
        }
    }

    // MARK: - Preview View (READ ONLY)

    @ViewBuilder
    private var previewView: some View {
        // Fix #147: empty state when no parts match the bulk filter,
        // so the user understands why there's nothing to preview rather than
        // seeing only the "Apply to All" / "Review One at a Time" buttons.
        if previewParts.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Parts Match",
                message: "No parts match the current bulk-edit filter. Adjust the filter on the previous step or close this sheet."
            )
            .padding()
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
        } else {
        List {
            Section {
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
            } header: {
                Text("Preview: \(previewParts.count) Sample Parts")
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
        }   // close `else` branch from #147 empty-state guard
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
                    LabeledContent {
                        Text(String(format: "%.1f%%", part.currentMarkup))
                    } label: {
                        Text("Current \(pricingMode == "markup" ? "Markup" : "Margin")")
                    }
                    LabeledContent {
                        Text(String(format: "%.1f%%", part.newMarkup))
                            .foregroundStyle(.green)
                    } label: {
                        Text("New \(pricingMode == "markup" ? "Markup" : "Margin")")
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
                .decorativeIconFont(64)
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
                    dismiss()
                    await onComplete()
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
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            return
        }
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
            saveError = userFriendlyError(error, context: "save data")
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
                _ = try service.setPricingTier(categoryId: catId, markupPercent: markup, marginPercent: margin)
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
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}
