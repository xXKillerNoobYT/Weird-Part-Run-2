import SwiftUI
import WiredPartCore

/// Stock target values for a part (MIN / TARGET / MAX).
struct WizardTargetValue {
    var min: Int
    var target: Int
    var max: Int
}

/// Step 6: Set Targets — MIN/TARGET/MAX per part with AI suggestions.
///
/// Shows all parts that have been assigned to warehouse areas. The user
/// can accept AI-suggested defaults or enter custom values. Targets are
/// saved to the `parts` table via `PartsService.updatePart()`.
struct WarehouseWizardStep6: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var assignedParts: [PartForTargets] = []
    @State private var targetValues: [Int64: WizardTargetValue] = [:]
    @State private var saveSuccess = false

    struct PartForTargets: Identifiable {
        let id: Int64
        let name: String
        let code: String?
        let currentMin: Int
        let currentTarget: Int
        let currentMax: Int
    }

    // AI-like suggestion using sensible defaults
    private func aiSuggestion(for part: PartForTargets) -> WizardTargetValue {
        // In production, use usage history / forecasting data.
        // For onboarding, provide sensible defaults.
        if part.currentMin > 0 || part.currentTarget > 0 || part.currentMax > 0 {
            return WizardTargetValue(
                min: part.currentMin,
                target: part.currentTarget,
                max: part.currentMax
            )
        }
        return WizardTargetValue(min: 2, target: 5, max: 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            // AI suggestion banner
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("Values suggested based on common patterns. Adjust as needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.05))

            if assignedParts.isEmpty {
                EmptyStateView(
                    icon: "target",
                    title: "No Parts to Configure",
                    message: "Assign parts to locations in Step 4 first."
                )
            } else {
                partsList

                // Bulk actions
                HStack(spacing: 12) {
                    Button("Accept All AI Values") {
                        for part in assignedParts {
                            targetValues[part.id] = aiSuggestion(for: part)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Save Targets") {
                        saveAllTargets()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                if saveSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Targets saved successfully")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .padding(.bottom)
                }
            }
        }
        .task { loadParts() }
    }

    // MARK: - Parts List

    @ViewBuilder
    private var partsList: some View {
        List {
            ForEach(assignedParts) { part in
                VStack(alignment: .leading, spacing: 8) {
                    Text(part.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let code = part.code {
                        Text(code)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        targetInput("MIN", partId: part.id, keyPath: \.min)
                        targetInput("TARGET", partId: part.id, keyPath: \.target)
                        targetInput("MAX", partId: part.id, keyPath: \.max)
                    }

                    let suggestion = aiSuggestion(for: part)
                    Button {
                        targetValues[part.id] = suggestion
                    } label: {
                        Label(
                            "Accept AI: \(suggestion.min)/\(suggestion.target)/\(suggestion.max)",
                            systemImage: "sparkles"
                        )
                        .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Target Input

    @ViewBuilder
    private func targetInput(
        _ label: String,
        partId: Int64,
        keyPath: WritableKeyPath<WizardTargetValue, Int>
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("0", value: Binding(
                get: {
                    targetValues[partId]?[keyPath: keyPath] ?? 0
                },
                set: { newVal in
                    var tv = targetValues[partId] ?? WizardTargetValue(min: 0, target: 0, max: 0)
                    tv[keyPath: keyPath] = newVal
                    targetValues[partId] = tv
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numberPad)
            .frame(width: 60)
            .multilineTextAlignment(.center)
        }
    }

    // MARK: - Data Loading

    private func loadParts() {
        do {
            guard let service = appCore.warehouseService else { stepError = "Warehouse service not available"; return }
            let areas = try loadAllWizardAreas(floorPlanId: floorPlanId, service: service)

            // Collect unique assigned parts across all areas
            var seenPartIds: Set<Int64> = []
            var parts: [PartForTargets] = []
            targetValues = [:]

            for area in areas {
                let contents = try service.getAreaContents(areaId: area.id)
                for item in contents {
                    guard !seenPartIds.contains(item.partId) else { continue }
                    seenPartIds.insert(item.partId)

                    // Get current target values from the parts table
                    let detail = try? appCore.partsService?.getPart(id: item.partId)
                    let minStock = detail?.part.minStockLevel ?? 0
                    let targetStock = detail?.part.targetStockLevel ?? 0
                    let maxStock = detail?.part.maxStockLevel ?? 0

                    parts.append(PartForTargets(
                        id: item.partId,
                        name: item.partName,
                        code: item.partNumber,
                        currentMin: minStock,
                        currentTarget: targetStock,
                        currentMax: maxStock
                    ))

                    // Pre-populate target values
                    targetValues[item.partId] = WizardTargetValue(
                        min: minStock,
                        target: targetStock,
                        max: maxStock
                    )
                }
            }

            assignedParts = parts
        } catch {
            stepError = userFriendlyError(error, context: "load parts for targets")
        }
    }

    private func validateTargetHierarchy(_ values: WizardTargetValue, partName: String) throws {
        guard values.min <= values.target else {
            throw PartsService.PartsError.invalidInput("\(partName): MIN must be less than or equal to TARGET.")
        }
        guard values.target <= values.max else {
            throw PartsService.PartsError.invalidInput("\(partName): TARGET must be less than or equal to MAX.")
        }
    }

    private func saveAllTargets() {
        guard let service = appCore.partsService else { stepError = "Parts service not available"; return }
        saveSuccess = false

        do {
            for part in assignedParts {
                if let values = targetValues[part.id] {
                    try validateTargetHierarchy(values, partName: part.name)
                }
            }

            for part in assignedParts {
                guard let values = targetValues[part.id] else { continue }
                try service.updatePart(
                    id: part.id,
                    minStockLevel: values.min,
                    maxStockLevel: values.max,
                    targetStockLevel: values.target
                )
            }
            saveSuccess = true
        } catch PartsService.PartsError.invalidInput(let message) {
            stepError = message
        } catch {
            stepError = userFriendlyError(error, context: "save stock targets")
        }
    }
}
