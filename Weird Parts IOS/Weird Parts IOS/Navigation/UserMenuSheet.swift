import SwiftUI
import WiredPartCore

/// Full-screen settings sheet presented from the user icon in the toolbar.
///
/// Organized into logical sections with permission gating — items the current
/// user doesn't have access to are hidden entirely. The sheet uses a
/// NavigationStack so tapping any row pushes the corresponding settings page.
struct UserMenuSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @Environment(\.dismiss) private var dismiss
    @Binding var showLogoutConfirm: Bool

    // MARK: - Section Definitions

    /// A single item in the settings menu.
    private struct MenuItem: Identifiable {
        let id: String          // matches AppTab.id
        let label: String
        let icon: String        // SF Symbol
        let tabId: String       // passed to SettingsRouter
        let permission: String? // nil = always visible
    }

    /// A group of related menu items.
    private struct MenuSection: Identifiable {
        let id: String
        let title: String
        let items: [MenuItem]
    }

    /// All settings sections, organized logically.
    private var sections: [MenuSection] {
        [
            MenuSection(id: "general", title: "General", items: [
                MenuItem(id: "settings-themes", label: "Themes", icon: "paintpalette.fill", tabId: "settings-themes", permission: nil),
                MenuItem(id: "settings-app-config", label: "App Config", icon: "slider.horizontal.3", tabId: "settings-app-config", permission: nil),
                MenuItem(id: "settings-notifications", label: "Notifications", icon: "bell.fill", tabId: "settings-notifications", permission: nil),
                MenuItem(id: "settings-about", label: "About", icon: "info.circle.fill", tabId: "settings-about", permission: nil),
                MenuItem(id: "settings-updates", label: "Updates", icon: "arrow.down.circle.fill", tabId: "settings-updates", permission: nil),
            ]),
            MenuSection(id: "company", title: "Company", items: [
                MenuItem(id: "settings-company", label: "Company Profile", icon: "building.2.fill", tabId: "settings-company", permission: nil),
                MenuItem(id: "settings-pdf", label: "PDF Settings", icon: "doc.fill", tabId: "settings-pdf", permission: nil),
                MenuItem(id: "settings-billing", label: "Billing & Pay", icon: "dollarsign.circle.fill", tabId: "settings-billing", permission: nil),
                MenuItem(id: "settings-clockout", label: "Clock-Out Questions", icon: "questionmark.circle.fill", tabId: "settings-clockout", permission: nil),
            ]),
            MenuSection(id: "data", title: "Data & Sync", items: [
                MenuItem(id: "settings-sync", label: "Sync", icon: "arrow.triangle.2.circlepath", tabId: "settings-sync", permission: nil),
                MenuItem(id: "settings-bluetooth", label: "Bluetooth", icon: "wave.3.right", tabId: "settings-bluetooth", permission: nil),
                MenuItem(id: "settings-backups", label: "Backups", icon: "externaldrive.fill", tabId: "settings-backups", permission: nil),
                MenuItem(id: "settings-export", label: "Data Export", icon: "square.and.arrow.up.fill", tabId: "settings-export", permission: "export_reports"),
                MenuItem(id: "settings-remote-sync", label: "Remote Sync", icon: "icloud.and.arrow.up.and.arrow.down", tabId: "settings-remote-sync", permission: "manage_devices"),
            ]),
            MenuSection(id: "security", title: "Security & Devices", items: [
                MenuItem(id: "settings-security", label: "Security", icon: "lock.shield.fill", tabId: "settings-security", permission: "manage_devices"),
                MenuItem(id: "settings-keys", label: "Key Management", icon: "key.fill", tabId: "settings-keys", permission: "manage_devices"),
                MenuItem(id: "settings-device-management", label: "Devices", icon: "desktopcomputer.and.arrow.down", tabId: "settings-device-management", permission: "manage_devices"),
                MenuItem(id: "settings-bootstrap", label: "Bootstrap", icon: "desktopcomputer", tabId: "settings-bootstrap", permission: "manage_devices"),
            ]),
            MenuSection(id: "advanced", title: "Advanced", items: [
                MenuItem(id: "settings-integrations", label: "Integrations", icon: "puzzlepiece.extension.fill", tabId: "settings-integrations", permission: "manage_settings"),
                MenuItem(id: "settings-supplier-bridge", label: "Supplier Bridge", icon: "link.circle.fill", tabId: "settings-supplier-bridge", permission: "manage_settings"),
                MenuItem(id: "settings-ai-config", label: "AI Config", icon: "brain.fill", tabId: "settings-ai-config", permission: "manage_settings"),
                MenuItem(id: "settings-shared-channels", label: "Shared Channels", icon: "bubble.left.and.text.bubble.right.fill", tabId: "settings-shared-channels", permission: "manage_settings"),
                MenuItem(id: "settings-audit", label: "Audit Log", icon: "list.bullet.clipboard.fill", tabId: "settings-audit", permission: "view_activity_log"),
            ]),
            MenuSection(id: "danger", title: "Danger Zone", items: [
                MenuItem(id: "settings-reset", label: "Database Reset", icon: "arrow.counterclockwise.circle.fill", tabId: "settings-reset", permission: "manage_devices"),
            ]),
        ]
    }

    /// Filter sections to only show items the user has permission for.
    /// Sections with zero visible items are hidden entirely.
    private var visibleSections: [MenuSection] {
        sections.compactMap { section in
            let visibleItems = section.items.filter { item in
                guard let perm = item.permission else { return true }
                return appCore.hasPermission(perm)
            }
            guard !visibleItems.isEmpty else { return nil }
            return MenuSection(id: section.id, title: section.title, items: visibleItems)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // User profile header
                userProfileSection

                // Navigation style picker
                Section("Navigation") {
                    Picker(selection: $tabPrefs.navigationStyle) {
                        ForEach(NavigationStyle.allCases, id: \.self) { style in
                            Label(style.label, systemImage: style.icon)
                                .tag(style)
                        }
                    } label: {
                        Label("Page Layout", systemImage: "rectangle.3.group")
                    }
                    .onChange(of: tabPrefs.navigationStyle) { _, _ in
                        tabPrefs.saveNavigationStyle()
                    }
                }

                // Settings sections
                ForEach(visibleSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            NavigationLink(value: item.tabId) {
                                Label(item.label, systemImage: item.icon)
                            }
                        }
                    }
                }

                // Log Out
                Section {
                    Button(role: .destructive) {
                        dismiss()
                        // Small delay so the sheet dismisses before the confirmation shows
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            showLogoutConfirm = true
                        }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { tabId in
                SettingsRouter(tabId: tabId)
                    .environmentObject(appCore)
            }
        }
    }

    // MARK: - User Profile Section

    @ViewBuilder
    private var userProfileSection: some View {
        if let user = appCore.currentUser {
            Section {
                HStack(spacing: DS.Space.lg - 2) {
                    DSAvatarView(name: user.displayName, size: .medium)

                    VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                        Text(user.displayName)
                            .dsStyle(.sectionTitle)
                        if let email = user.email, !email.isEmpty {
                            Text(email)
                                .dsStyle(.detail)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, DS.Space.xxs)
            }
        }
    }
}

#Preview {
    @Previewable @State var showLogout = false
    UserMenuSheet(showLogoutConfirm: $showLogout)
        .environmentObject(AppCore())
        .environmentObject(TabBarPreferences())
}
