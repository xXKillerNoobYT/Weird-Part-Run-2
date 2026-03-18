import SwiftUI

/// Horizontal capsule sub-tab picker for module navigation.
///
/// Extracted from IOSMainView's inline subTabPicker. Uses `.buttonStyle(.glass)`
/// for iOS 26 Liquid Glass on navigation-level controls.
///
/// Usage:
///   SubTabPicker(
///       items: tabs.map { (id: $0.id, label: $0.label, icon: $0.icon) },
///       selection: $selectedTabId
///   )
struct SubTabPicker<ID: Hashable>: View {
    let items: [(id: ID, label: String, icon: String?)]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.sm) {
                ForEach(items, id: \.id) { item in
                    Button {
                        dsAnimate(DS.Anim.fast) {
                            selection = item.id
                        }
                    } label: {
                        HStack(spacing: DS.Space.xxs) {
                            if let icon = item.icon {
                                Image(systemName: icon)
                                    .font(.caption)
                            }
                            Text(item.label)
                                .font(.subheadline)
                                .fontWeight(selection == item.id ? .semibold : .regular)
                        }
                        .padding(.horizontal, DS.Space.lg - 2)
                        .padding(.vertical, DS.Space.sm)
                        .background(
                            Capsule()
                                .fill(selection == item.id ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(selection == item.id ? .white : .primary)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)
        }
        .background(DS.Background.page)
    }
}

#Preview {
    @Previewable @State var selected = "catalog"
    SubTabPicker(
        items: [
            (id: "catalog", label: "Catalog", icon: "shippingbox"),
            (id: "categories", label: "Categories", icon: "folder"),
            (id: "suppliers", label: "Suppliers", icon: "building.2"),
            (id: "brands", label: "Brands", icon: "tag"),
        ],
        selection: $selected
    )
}
