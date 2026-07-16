import SwiftUI

/// Full-screen editor for customizing the tab bar order.
///
/// Users freely drag modules in one continuous list. The first 4 rows become
/// the "Fast Access Bar" and the remaining rows live under "More". Clear
/// messaging explains **why** the limit exists (iOS tab bars support at most
/// 4 items + More) without making users jump between two separate drag lists.
struct TabBarEditorView: View {
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// All permission-visible modules in the user's current order.
    let allVisibleModules: [AppModule]

    @State private var orderedIds: [String] = []

    @State private var showResetConfirmation = false
    @State private var showDemoteMinimumWarning = false

    private var bottomIds: [String] { Array(orderedIds.prefix(min(4, orderedIds.count))) }
    private var moreIds: [String] { Array(orderedIds.dropFirst(min(4, orderedIds.count))) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Explanation banner
                infoBanner

                List {
                    Section {
                        ForEach(Array(orderedIds.enumerated()), id: \.element) { index, moduleId in
                            if let mod = allModulesById[moduleId] {
                                moduleRow(mod, index: index, showsMoreDivider: index == 4)
                            }
                        }
                        .onMove { from, to in
                            orderedIds.move(fromOffsets: from, toOffset: to)
                            showDemoteMinimumWarning = false
                        }
                    } header: {
                        HStack {
                            Text("Drag Tab Order")
                            Spacer()
                            Text("\(bottomIds.count) Fast • \(moreIds.count) More")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        if showDemoteMinimumWarning {
                            Label(
                                "Keep at least one module in Fast Access Bar.",
                                systemImage: "info.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        } else {
                            Text("Drag any module above or below the More divider. The first 4 rows appear in the bottom tab bar; everything below appears under More.")
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Edit Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        showResetConfirmation = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadCurrentOrder()
            }
            .alert("Reset tab order?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetToDefaultsDraft()
                }
            } message: {
                Text("This resets your draft tab layout to defaults. Tap Done to save it.")
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
                    Text("Drag any row to reorder. Drop it above the More divider for fast access, or below the divider to hide it under More.")
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

    private var moreDivider: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
            Label("More menu starts here", systemImage: "ellipsis.circle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
        }
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("More menu starts here. Drag rows above this divider for fast access, or below it for the More menu.")
    }

    @ViewBuilder
    private func moduleRow(_ module: AppModule, index: Int, showsMoreDivider: Bool) -> some View {
        let isFastAccess = index < 4

        VStack(spacing: 8) {
            if showsMoreDivider {
                moreDivider
            }

            HStack(spacing: 12) {
                Image(systemName: module.icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(module.label)
                        .font(.body)

                    Text(isFastAccess ? "Fast Access Bar" : "More menu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Move-between-sections button
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if isFastAccess {
                            demoteModule(module.id)
                        } else {
                            promoteModule(module.id)
                        }
                    }
                } label: {
                    Image(systemName: isFastAccess ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isFastAccess ? .orange : .green)
                }
                .buttonStyle(.plain)
                .dsMinTapTarget()
                .accessibilityLabel(isFastAccess
                                    ? "Move \(module.label) to More menu"
                                    : "Move \(module.label) to tab bar")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Movement

    /// Move a module from "More" into "Fast Access Bar".
    /// Inserts at the bottom of the first 4 rows so the displaced row naturally
    /// drops below the divider into More.
    private func promoteModule(_ id: String) {
        guard let index = orderedIds.firstIndex(of: id), index >= 4 else { return }
        orderedIds.remove(at: index)
        orderedIds.insert(id, at: min(3, orderedIds.count))
        showDemoteMinimumWarning = false
    }

    /// Move a module from "Fast Access Bar" to the top of "More".
    /// Requires at least 1 module remain in the bar.
    private func demoteModule(_ id: String) {
        guard let index = orderedIds.firstIndex(of: id), index < 4 else { return }
        guard bottomIds.count > 1 else {
            showDemoteMinimumWarning = true
            return
        }
        orderedIds.remove(at: index)
        orderedIds.insert(id, at: min(4, orderedIds.count))
        showDemoteMinimumWarning = false
    }

    // MARK: - Persistence

    private func loadCurrentOrder() {
        let ordered = tabPrefs.orderedModules(from: allVisibleModules)
        orderedIds = ordered.map(\.id)
        showDemoteMinimumWarning = false
    }

    private func resetToDefaultsDraft() {
        orderedIds = allVisibleModules.map(\.id)
        showDemoteMinimumWarning = false
    }

    private func saveAndDismiss() {
        tabPrefs.tabOrder = orderedIds
        tabPrefs.save()
        dismiss()
    }
}
