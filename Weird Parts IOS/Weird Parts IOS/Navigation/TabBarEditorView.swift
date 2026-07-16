import SwiftUI

struct TabBarEditorLayout: Equatable, Sendable {
    var orderedIds: [String]

    var bottomIds: [String] { Array(orderedIds.prefix(min(4, orderedIds.count))) }
    var moreIds: [String] { Array(orderedIds.dropFirst(min(4, orderedIds.count))) }
    var hasMoreDestination: Bool { !moreIds.isEmpty }
    var exportsFastDemoteActions: Bool { hasMoreDestination }

    private var dividerRenderedIndex: Int? { hasMoreDestination ? bottomIds.count : nil }
    private var renderedItemCount: Int { orderedIds.count + (hasMoreDestination ? 1 : 0) }

    /// Maps a rendered list row back to the persisted module-order index.
    /// The synthetic More divider has no module index.
    func moduleIndex(forRenderedIndex renderedIndex: Int) -> Int? {
        guard (0..<renderedItemCount).contains(renderedIndex) else { return nil }
        guard let dividerRenderedIndex else { return renderedIndex }
        if renderedIndex == dividerRenderedIndex { return nil }
        return renderedIndex > dividerRenderedIndex ? renderedIndex - 1 : renderedIndex
    }

    /// Reorders persisted module IDs from SwiftUI's rendered `onMove` indices.
    /// Crossing the dynamic divider must advance one module beyond the visual
    /// sentinel so an adjacent cross-boundary drop cannot collapse to a no-op.
    func movingModules(fromRenderedOffsets source: IndexSet, toRenderedOffset destination: Int) -> [String] {
        guard !source.isEmpty,
              source.allSatisfy({ (0..<renderedItemCount).contains($0) }),
              (0...renderedItemCount).contains(destination) else { return orderedIds }

        let moduleOffsets = source.compactMap(moduleIndex(forRenderedIndex:))
        guard moduleOffsets.count == source.count else { return orderedIds }

        var moduleDestination = destination
        if let dividerRenderedIndex {
            let allSourcesAreFast = source.allSatisfy { $0 < dividerRenderedIndex }
            let allSourcesAreMore = source.allSatisfy { $0 > dividerRenderedIndex }

            if destination > dividerRenderedIndex {
                moduleDestination = allSourcesAreFast ? destination : destination - 1
            } else if destination == dividerRenderedIndex, allSourcesAreMore {
                moduleDestination = destination - 1
            }
        }

        var movedIds = orderedIds
        movedIds.move(
            fromOffsets: IndexSet(moduleOffsets),
            toOffset: min(max(0, moduleDestination), orderedIds.count)
        )
        return movedIds
    }
}

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

    private var layout: TabBarEditorLayout { TabBarEditorLayout(orderedIds: orderedIds) }
    private var bottomIds: [String] { layout.bottomIds }
    private var moreIds: [String] { layout.moreIds }
    private var hasMoreDestination: Bool { layout.hasMoreDestination }

    private enum EditorItem: Identifiable, Equatable {
        case module(String)
        case moreDivider

        var id: String {
            switch self {
            case .module(let id): "module-\(id)"
            case .moreDivider: "more-divider"
            }
        }
    }

    private var editorItems: [EditorItem] {
        var items = bottomIds.map(EditorItem.module)
        if !moreIds.isEmpty {
            items.append(.moreDivider)
            items.append(contentsOf: moreIds.map(EditorItem.module))
        }
        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Explanation banner
                infoBanner

                List {
                    Section {
                        ForEach(editorItems) { item in
                            switch item {
                            case .module(let moduleId):
                                if let index = orderedIds.firstIndex(of: moduleId),
                                   let module = allModulesById[moduleId] {
                                    moduleRow(module, index: index)
                                }
                            case .moreDivider:
                                moreDivider
                            }
                        }
                        .onMove { from, to in
                            moveEditorItems(from: from, to: to)
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
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .moveDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("More menu starts here. Drag rows above this divider for fast access, or below it for the More menu.")
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func moduleRow(_ module: AppModule, index: Int) -> some View {
        let isFastAccess = index < 4

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

            if !isFastAccess || hasMoreDestination {
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

    /// Reorders persisted module IDs by explicitly translating the rendered
    /// list indices around the synthetic More divider.
    private func moveEditorItems(from source: IndexSet, to destination: Int) {
        orderedIds = layout.movingModules(
            fromRenderedOffsets: source,
            toRenderedOffset: destination
        )
        showDemoteMinimumWarning = false
    }

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
