import SwiftUI

/// Full-screen editor for customizing the tab bar order.
///
/// Shows two sections:
///   - **Bottom Tabs** (first 4) — draggable to reorder
///   - **More** (remaining) — draggable, can be promoted to bottom
///
/// Users drag modules between sections to decide which appear in the
/// bottom tab bar vs. the "More" overflow. The total set of modules
/// shown is already permission-filtered before being passed in.
struct TabBarEditorView: View {
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @Environment(\.dismiss) private var dismiss

    /// All permission-visible modules in the user's current order.
    let allVisibleModules: [AppModule]

    @State private var orderedIds: [String] = []

    /// First 4 are "bottom tabs", rest are "more"
    private var bottomIds: [String] { Array(orderedIds.prefix(4)) }
    private var moreIds: [String] { Array(orderedIds.dropFirst(4)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(bottomIds, id: \.self) { moduleId in
                        if let mod = allModulesById[moduleId] {
                            moduleRow(mod, isBottom: true)
                        }
                    }
                    .onMove { from, to in
                        moveWithinBottom(from: from, to: to)
                    }
                } header: {
                    Text("Bottom Tabs")
                } footer: {
                    Text("These \(min(bottomIds.count, 4)) modules show in the bottom tab bar.")
                }

                Section {
                    ForEach(moreIds, id: \.self) { moduleId in
                        if let mod = allModulesById[moduleId] {
                            moduleRow(mod, isBottom: false)
                        }
                    }
                    .onMove { from, to in
                        moveWithinMore(from: from, to: to)
                    }
                } header: {
                    Text("More")
                } footer: {
                    Text("Tap the arrow to move modules between sections.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        orderedIds = allVisibleModules.map(\.id)
                        tabPrefs.reset()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        tabPrefs.tabOrder = orderedIds
                        tabPrefs.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let ordered = tabPrefs.orderedModules(from: allVisibleModules)
                orderedIds = ordered.map(\.id)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func moduleRow(_ module: AppModule, isBottom: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            Text(module.label)
                .font(.body)

            Spacer()

            // Promote / demote button
            Button {
                withAnimation {
                    if isBottom {
                        demoteModule(module.id)
                    } else {
                        promoteModule(module.id)
                    }
                }
            } label: {
                Image(systemName: isBottom ? "arrow.down.circle" : "arrow.up.circle")
                    .font(.title3)
                    .foregroundStyle(isBottom ? .orange : .green)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Reorder Helpers

    /// Move a module from "more" into "bottom tabs" (position 4 → end of bottom).
    /// If bottom is already at 4, the last bottom item gets demoted.
    private func promoteModule(_ id: String) {
        guard let moreIndex = orderedIds.dropFirst(4).firstIndex(of: id) else { return }
        orderedIds.remove(at: moreIndex)

        // Insert at position 3 (end of bottom section), pushing existing #4 to More
        let insertAt = min(3, orderedIds.count)
        orderedIds.insert(id, at: insertAt)
    }

    /// Move a module from "bottom tabs" to the top of the "more" section.
    /// Only allow if there would still be at least 1 bottom tab.
    private func demoteModule(_ id: String) {
        guard let bottomIndex = orderedIds.prefix(4).firstIndex(of: id) else { return }
        // Don't allow demoting the last bottom tab
        let currentBottomCount = min(orderedIds.count, 4)
        guard currentBottomCount > 1 else { return }

        orderedIds.remove(at: bottomIndex)
        // Insert at position 4 (top of "more")
        let insertAt = min(4, orderedIds.count)
        orderedIds.insert(id, at: insertAt)
    }

    private func moveWithinBottom(from: IndexSet, to: Int) {
        orderedIds.move(fromOffsets: from, toOffset: to)
    }

    private func moveWithinMore(from: IndexSet, to: Int) {
        // Offset indices to account for the bottom section
        let bottomCount = min(orderedIds.count, 4)
        let adjustedFrom = IndexSet(from.map { $0 + bottomCount })
        let adjustedTo = to + bottomCount
        orderedIds.move(fromOffsets: adjustedFrom, toOffset: adjustedTo)
    }
}
