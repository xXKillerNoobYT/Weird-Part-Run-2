import SwiftUI
import WiredPartCore

/// Step 5: Count Everything — per-area counting with hidden system counts.
///
/// The user walks through each area that has assigned parts
/// and enters a fresh count. System counts are HIDDEN to prevent cheating.
struct WarehouseWizardStep5: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var allAreas: [WizardAreaInfo] = []
    @State private var countAreaIndex = 0
    @State private var partsToCount: [WarehouseService.AreaContentsItem] = []
    @State private var countText: [Int64: String] = [:]
    @State private var submittedAreas: Set<Int64> = []
    @State private var auditSessionId: Int64?

    private var currentArea: WizardAreaInfo? {
        guard countAreaIndex >= 0, countAreaIndex < allAreas.count else { return nil }
        return allAreas[countAreaIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if allAreas.isEmpty {
                EmptyStateView(
                    icon: "number.circle.fill",
                    title: "No Areas Yet",
                    message: "Add storage units in Step 2 and assign parts in Step 4 first."
                )
            } else if let area = currentArea {
                areaContent(area)
            }
        }
        .task { loadAllData() }
    }

    // MARK: - Area Content

    @ViewBuilder
    private func areaContent(_ area: WizardAreaInfo) -> some View {
        // Current area header
        VStack(spacing: 4) {
            Text("Count parts at:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(area.fullLocationCode)
                .font(.title3)
                .fontWeight(.bold)
                .monospaced()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.indigo.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()

        Text("Count each part on the shelf. System counts are hidden so you count fresh.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal)

        if partsToCount.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No parts assigned to this area")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
        } else {
            List {
                ForEach(partsToCount, id: \.partId) { partInfo in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(partInfo.partName)
                                .font(.subheadline)
                            if let code = partInfo.partNumber {
                                Text(code)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        TextField("Qty", text: Binding(
                            get: { countText[partInfo.partId] ?? "" },
                            set: { countText[partInfo.partId] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)

                        if let text = countText[partInfo.partId],
                           !text.isEmpty, Int(text) != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)

            // Submit button
            Button("Submit Counts for This Area") {
                submitCountsForArea()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .disabled(countText.values.allSatisfy { $0.isEmpty || Int($0) == nil })
        }

        if submittedAreas.contains(area.id) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Counts submitted")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(.top, 4)
        }

        Spacer()

        // Area navigation
        HStack {
            Button {
                countAreaIndex = max(0, countAreaIndex - 1)
                loadCountAreaData()
            } label: {
                Label("Prev", systemImage: "chevron.left")
            }
            .disabled(countAreaIndex <= 0)

            Spacer()
            Text("Area \(countAreaIndex + 1) of \(allAreas.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                countAreaIndex = min(allAreas.count - 1, countAreaIndex + 1)
                loadCountAreaData()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(countAreaIndex >= allAreas.count - 1)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadAllData() {
        do {
            guard let service = appCore.warehouseService else { stepError = "Warehouse service not available"; return }
            allAreas = try loadAllWizardAreas(floorPlanId: floorPlanId, service: service)

            // Create audit session for onboarding
            if let userId = appCore.currentUser?.id {
                let session = try service.startAuditSession(
                    sessionType: "onboarding",
                    startedBy: userId,
                    floorPlanId: floorPlanId
                )
                auditSessionId = session.id
            }

            loadCountAreaData()
        } catch {
            stepError = userFriendlyError(error, context: "load count data")
        }
    }

    private func loadCountAreaData() {
        guard let area = currentArea else {
            partsToCount = []
            return
        }
        countText = [:]
        do {
            partsToCount = try appCore.warehouseService?.getAreaContents(areaId: area.id) ?? []
        } catch {
            stepError = userFriendlyError(error, context: "load area parts")
        }
    }

    private func submitCountsForArea() {
        guard let area = currentArea,
              let sessionId = auditSessionId,
              let userId = appCore.currentUser?.id,
              let service = appCore.warehouseService else { return }

        do {
            for partInfo in partsToCount {
                guard let text = countText[partInfo.partId],
                      let userCount = Int(text) else { continue }
                // System count is 0 for onboarding — no prior data exists
                _ = try service.recordAuditCount(
                    sessionId: sessionId,
                    partId: partInfo.partId,
                    areaId: area.id,
                    systemCount: 0,
                    userCount: userCount,
                    countedBy: userId
                )
            }
            submittedAreas.insert(area.id)

            // Auto-advance
            if countAreaIndex < allAreas.count - 1 {
                countAreaIndex += 1
                loadCountAreaData()
            }
        } catch {
            stepError = userFriendlyError(error, context: "submit counts")
        }
    }
}
