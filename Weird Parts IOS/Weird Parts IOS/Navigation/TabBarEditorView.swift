import SwiftUI

/// Full-screen editor for customizing the tab bar order.
///
/// Users freely drag modules between the "Fast Access Bar" (≤ 4 slots) and
/// the "More" section. Clear messaging explains **why** the limit exists
/// (iOS tab bars support at most 4 items + More). The editor enforces the
/// cap visually rather than locking modules in place.
struct TabBarEditorView: View {
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// All permission-visible modules in the user's current order.
    let allVisibleModules: [AppModule]

    @State private var bottomIds: [String] = []
    @State private var moreIds: [String] = []

    /// True when the user has tried to exceed the 4-slot limit.
    @State private var showCapWarning = false

    private var isOverCap: Bool { bottomIds.count > 4 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Explanation banner
                infoBanner

                List {
                    // ── Fast Access Bar ──
                    Section {
                        ForEach(bottomIds, id: \.self) { moduleId in
                            if let mod = allModulesById[moduleId] {
                                moduleRow(mod, section: .bottom)
                            }
                        }
                        .onMove { from, to in
                            bottomIds.move(fromOffsets: from, toOffset: to)
                        }
                    } header: {
                        HStack {
                            Text("Fast Access Bar")
                            Spacer()
                            Text("\(bottomIds.count) / 4")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(isOverCap ? .red : .secondary)
                        }
                    } footer: {
                        if isOverCap {
                            Label(
                                "Move \(bottomIds.count - 4) module\(bottomIds.count - 4 == 1 ? "" : "s") to More — the tab bar only fits 4.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.red)
                        } else {
                            Text("These modules appear on the bottom tab bar for quick access.")
                        }
                    }

                    // ── More ──
                    Section {
                        ForEach(moreIds, id: \.self) { moduleId in
                            if let mod = allModulesById[moduleId] {
                                moduleRow(mod, section: .more)
                            }
                        }
                        .onMove { from, to in
                            moreIds.move(fromOffsets: from, toOffset: to)
                        }
                    } header: {
                        Text("More")
                    } footer: {
                        Text("These modules live under the More tab. Tap arrows to move between sections.")
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Edit Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        resetToDefaults()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isOverCap)
                }
            }
            .onAppear {
                loadCurrentOrder()
            }
        }
    }

    // MARK: - Info Banner

    private var infoBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Your Tab Bar")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Drag to reorder. Use arrows to move modules between sections. Up to 4 modules can sit in the fast access bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            if horizontalSizeClass == .regular {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "sidebar.squares.leading")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sidebar Mode")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text("These tabs appear in the bottom tab bar on compact layouts. In sidebar mode, they also determine which sections appear in the sidebar and their order.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Row

    private enum RowSection { case bottom, more }

    @ViewBuilder
    private func moduleRow(_ module: AppModule, section: RowSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            Text(module.label)
                .font(.body)

            Spacer()

            // Move-between-sections button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    switch section {
                    case .bottom:
                        demoteModule(module.id)
                    case .more:
                        promoteModule(module.id)
                    }
                }
            } label: {
                Image(systemName: section == .bottom ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(section == .bottom ? .orange : .green)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Movement

    /// Move a module from "More" into "Fast Access Bar".
    /// Freely adds — the UI shows a warning if > 4 and blocks Done.
    private func promoteModule(_ id: String) {
        guard let index = moreIds.firstIndex(of: id) else { return }
        moreIds.remove(at: index)
        bottomIds.append(id)

        if bottomIds.count > 4 {
            showCapWarning = true
        }
    }

    /// Move a module from "Fast Access Bar" to the top of "More".
    /// Requires at least 1 module remain in the bar.
    private func demoteModule(_ id: String) {
        guard let index = bottomIds.firstIndex(of: id) else { return }
        guard bottomIds.count > 1 else { return }
        bottomIds.remove(at: index)
        moreIds.insert(id, at: 0)
        showCapWarning = false
    }

    // MARK: - Persistence

    private func loadCurrentOrder() {
        let ordered = tabPrefs.orderedModules(from: allVisibleModules)
        let ids = ordered.map(\.id)
        bottomIds = Array(ids.prefix(min(4, ids.count)))
        moreIds = Array(ids.dropFirst(min(4, ids.count)))
    }

    private func resetToDefaults() {
        let defaultIds = allVisibleModules.map(\.id)
        bottomIds = Array(defaultIds.prefix(min(4, defaultIds.count)))
        moreIds = Array(defaultIds.dropFirst(min(4, defaultIds.count)))
        tabPrefs.reset()
    }

    private func saveAndDismiss() {
        guard bottomIds.count <= 4 else { return }
        tabPrefs.tabOrder = bottomIds + moreIds
        tabPrefs.save()
        dismiss()
    }
}
