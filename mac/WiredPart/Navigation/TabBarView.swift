import SwiftUI

/// Horizontal tab bar for the selected module's visible tabs.
/// If the module has grouped tabs (e.g. Office), section headers are displayed.
struct TabBarView: View {
    @EnvironmentObject private var appCore: AppCore
    let module: NavModule
    @Binding var selectedPath: String

    private var visibleTabs: [NavTab] {
        NavigationConfig.visibleTabs(for: module, permissions: appCore.permissions)
    }

    /// Whether this module uses grouped tabs (any tab has a non-nil group).
    private var isGrouped: Bool {
        visibleTabs.contains { $0.group != nil }
    }

    /// Ordered unique group names preserving definition order.
    private var groupNames: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tab in visibleTabs {
            if let group = tab.group, !seen.contains(group) {
                seen.insert(group)
                result.append(group)
            }
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if isGrouped {
                groupedLayout
            } else {
                flatLayout
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Flat Layout

    @ViewBuilder
    private var flatLayout: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                tabButton(tab)
            }
        }
    }

    // MARK: - Grouped Layout

    @ViewBuilder
    private var groupedLayout: some View {
        HStack(spacing: 12) {
            ForEach(groupNames, id: \.self) { groupName in
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupName.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)

                    HStack(spacing: 2) {
                        ForEach(visibleTabs.filter { $0.group == groupName }) { tab in
                            tabButton(tab)
                        }
                    }
                }

                if groupName != groupNames.last {
                    Divider()
                        .frame(height: 28)
                }
            }
        }
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: NavTab) -> some View {
        let isSelected = selectedPath == tab.path
        return Button {
            selectedPath = tab.path
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                Text(tab.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}
