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
    @State private var stickerProgressKey: String?

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
                EmptyStateView(
                    icon: "tag.fill",
                    title: "No Areas Yet",
                    message: "Add storage units in Step 2 first."
                )
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
            let progressKey = try scopedStickerProgressKey()
            stickerProgressKey = progressKey

            // Progress is intentionally scoped to the active database/company/user,
            // floor plan, and generated sticker set. Do not fall back to the
            // legacy floorPlanId-only key: that is the stale-state leak tracked by
            // GitHub #861. Remove it opportunistically once this setup is opened.
            UserDefaults.standard.removeObject(forKey: legacyStickerProgressKey)
            if let saved = UserDefaults.standard.array(forKey: progressKey) as? [String] {
                let validCodes = Set(allAreas.map(\.fullLocationCode))
                checkedStickers = Set(saved).intersection(validCodes)
            } else {
                checkedStickers = []
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
        // Persist progress under the scoped current setup key.
        let progressKey = stickerProgressKey ?? (try? scopedStickerProgressKey())
        if let progressKey {
            stickerProgressKey = progressKey
            UserDefaults.standard.set(
                Array(checkedStickers).sorted(),
                forKey: progressKey
            )
        }
    }

    private var legacyStickerProgressKey: String {
        "wizard_checked_stickers_\(floorPlanId)"
    }

    private func scopedStickerProgressKey() throws -> String {
        let profile = try appCore.settingsService?.getBusinessProfile()
        let businessScope = [
            "business",
            profile?.id.map(String.init) ?? "none",
            profile?.createdAt ?? "unknown",
            profile?.companyName ?? "no-company"
        ].joined(separator: ":")
        let userScope = [
            "user",
            appCore.currentUser?.id.map(String.init) ?? "none",
            appCore.currentUser?.createdAt ?? "unknown"
        ].joined(separator: ":")
        let stickerSetSignature = deterministicSignature(
            allAreas
                .map(\.fullLocationCode)
                .sorted()
                .joined(separator: "|")
        )

        return [
            "wizard_checked_stickers_v2",
            scopedKeyComponent(businessScope),
            scopedKeyComponent(userScope),
            "floorPlan_\(floorPlanId)",
            "stickers_\(stickerSetSignature)"
        ].joined(separator: "_")
    }

    private func scopedKeyComponent(_ value: String) -> String {
        value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "", { $0.append($1) })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func deterministicSignature(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
