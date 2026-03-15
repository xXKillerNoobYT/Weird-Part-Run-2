import SwiftUI

/// Sidebar listing all navigation modules the current user can access.
/// Shows an icon + label per module, with user info and logout at the bottom.
struct SidebarView: View {
    @EnvironmentObject private var appCore: AppCore
    @Binding var selectedModuleId: String
    var onModuleSelected: (NavModule) -> Void

    private var visibleModules: [NavModule] {
        NavigationConfig.visibleModules(permissions: appCore.permissions)
    }

    var body: some View {
        List(selection: $selectedModuleId) {
            ForEach(visibleModules) { module in
                Label(module.label, systemImage: module.icon)
                    .tag(module.id)
            }
        }
        .onChange(of: selectedModuleId) { _, newValue in
            if let module = NavigationConfig.allModules.first(where: { $0.id == newValue }) {
                onModuleSelected(module)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .safeAreaInset(edge: .bottom) {
            userFooter
        }
    }

    // MARK: - User Footer

    @ViewBuilder
    private var userFooter: some View {
        if let user = appCore.currentUser {
            VStack(spacing: 8) {
                Divider()
                HStack {
                    initialsCircle(for: user.displayName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        appCore.logout()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Sign Out")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func initialsCircle(for name: String) -> some View {
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return Text(initials.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.accentColor))
    }
}
