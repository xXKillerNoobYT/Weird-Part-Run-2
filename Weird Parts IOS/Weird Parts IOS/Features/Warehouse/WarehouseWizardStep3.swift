import SwiftUI
import WiredPartCore

/// Step 3: Number Everything — interactive sticker checklist.
///
/// Auto-generates a sticker list from all areas created in Step 2.
/// The user checks off each sticker as they physically label the location.
struct WarehouseWizardStep3: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var allAreas: [WizardAreaInfo] = []
    @State private var checkedStickers: Set<String> = []
    @State private var checkedCount: Int = 0

    private var stickerGroups: [(unitName: String, items: [WizardAreaInfo])] {
        Dictionary(grouping: allAreas, by: \.unitName)
            .sorted { $0.key < $1.key }
            .map { (unitName: $0.key, items: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            VStack(spacing: 8) {
                Text("Write these codes on stickers and place them on each location")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Grab a Sharpie and sticker sheet. Check each off as you place it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()

            // Progress bar
            let total = allAreas.count
            HStack {
                Text("\(checkedCount) of \(total) stickers placed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: Double(checkedCount), total: Double(max(total, 1)))
                    .frame(width: 100)
            }
            .padding(.horizontal)

            if allAreas.isEmpty {
                ContentUnavailableView {
                    Label("No Areas Yet", systemImage: "tag.fill")
                } description: {
                    Text("Add storage units in Step 2 first.")
                }
            } else {
                List {
                    ForEach(stickerGroups, id: \.unitName) { group in
                        Section(group.unitName) {
                            ForEach(group.items) { item in
                                Button {
                                    toggleSticker(item.fullLocationCode)
                                } label: {
                                    HStack {
                                        Image(systemName: checkedStickers.contains(item.fullLocationCode)
                                            ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(
                                                checkedStickers.contains(item.fullLocationCode)
                                                    ? .green : .secondary
                                            )
                                        VStack(alignment: .leading) {
                                            Text(item.fullLocationCode)
                                                .font(.subheadline)
                                                .monospaced()
                                                .fontWeight(.medium)
                                            Text("\(item.levelCode), \(item.areaCode)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { loadAreas() }
    }

    private func loadAreas() {
        do {
            guard let service = appCore.warehouseService else { stepError = "Warehouse service not available"; return }
            allAreas = try loadAllWizardAreas(floorPlanId: floorPlanId, service: service)
            // Restore checked stickers from UserDefaults
            if let saved = UserDefaults.standard.array(
                forKey: "wizard_checked_stickers_\(floorPlanId)"
            ) as? [String] {
                checkedStickers = Set(saved)
            }
            checkedCount = allAreas.filter { checkedStickers.contains($0.fullLocationCode) }.count
        } catch {
            stepError = userFriendlyError(error, context: "load areas")
        }
    }

    private func toggleSticker(_ code: String) {
        if checkedStickers.contains(code) {
            checkedStickers.remove(code)
            checkedCount -= 1
        } else {
            checkedStickers.insert(code)
            checkedCount += 1
        }
        // Persist progress
        UserDefaults.standard.set(
            Array(checkedStickers),
            forKey: "wizard_checked_stickers_\(floorPlanId)"
        )
    }
}
