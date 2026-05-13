import SwiftUI
import WiredPartCore

/// Full-screen settings sheet presented from the user icon in the toolbar.
///
/// Organized into 10 logical sections with iOS Settings-style navigation,
/// permission gating, and a searchable filter bar. Items the current user
/// doesn't have access to are hidden entirely.
struct UserMenuSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @EnvironmentObject private var tabPrefs: TabBarPreferences
    @Environment(\.dismiss) private var dismiss
    @Binding var showLogoutConfirm: Bool

    @State private var searchText = ""

    // MARK: - Section Definitions

    /// A single item in the settings menu.
    private struct MenuItem: Identifiable {
        let id: String          // matches AppTab.id
        let label: String
        let icon: String        // SF Symbol
        let tabId: String       // passed to SettingsRouter
        let permission: String? // nil = always visible
        let keywords: [String]  // searchable terms
    }

    /// A group of related menu items.
    private struct MenuSection: Identifiable {
        let id: String
        let title: String
        let icon: String        // SF Symbol for section header
        let items: [MenuItem]
    }

    /// All settings sections, organized into 10 logical groups.
    private var sections: [MenuSection] {
        [
            // 1. General
            MenuSection(id: "general", title: "General", icon: "gear", items: [
                MenuItem(id: "settings-about", label: "About", icon: "info.circle.fill",
                         tabId: "settings-about", permission: nil,
                         keywords: ["about", "version", "app info", "build"]),
                MenuItem(id: "settings-help", label: "Help", icon: "questionmark.circle.fill",
                         tabId: "settings-help", permission: nil,
                         keywords: ["help", "setup", "onboarding", "restart setup", "getting set up"]),
                MenuItem(id: "settings-themes", label: "Themes", icon: "paintpalette.fill",
                         tabId: "settings-themes", permission: nil,
                         keywords: ["themes", "dark mode", "light mode", "appearance", "colors"]),
                MenuItem(id: "settings-notifications", label: "Notifications", icon: "bell.fill",
                         tabId: "settings-notifications", permission: nil,
                         keywords: ["notifications", "alerts", "sounds", "badges", "push"]),
                MenuItem(id: "settings-privacy", label: "Privacy", icon: "hand.raised.fill",
                         tabId: "settings-privacy", permission: nil,
                         keywords: ["privacy", "telemetry", "onboarding", "local data", "analytics"]),
                MenuItem(id: "settings-app-config", label: "App Config", icon: "slider.horizontal.3",
                         tabId: "settings-app-config", permission: nil,
                         keywords: ["app config", "configuration", "preferences", "general settings"]),
            ]),

            // 2. Company
            MenuSection(id: "company", title: "Company", icon: "building.2", items: [
                MenuItem(id: "settings-company", label: "Company Profiles", icon: "building.2.fill",
                         tabId: "settings-company", permission: nil,
                         keywords: ["company", "profile", "business", "organization", "name", "address"]),
                MenuItem(id: "settings-billing", label: "Billing & Pay", icon: "dollarsign.circle.fill",
                         tabId: "settings-billing", permission: nil,
                         keywords: ["billing", "pay", "wages", "overtime", "rates", "payroll"]),
                MenuItem(id: "settings-pdf", label: "PDF Settings", icon: "doc.fill",
                         tabId: "settings-pdf", permission: nil,
                         keywords: ["pdf", "documents", "print", "export", "templates", "logo"]),
                MenuItem(id: "settings-payment-tracking", label: "Payment Tracking", icon: "banknote.fill",
                         tabId: "settings-payment-tracking", permission: nil,
                         keywords: ["payment", "tracking", "invoices", "receivables", "collections"]),
            ]),

            // 3. Operations
            MenuSection(id: "operations", title: "Operations", icon: "wrench.and.screwdriver", items: [
                MenuItem(id: "settings-breaks", label: "Break & Lunch Policy", icon: "cup.and.saucer.fill",
                         tabId: "settings-breaks", permission: nil,
                         keywords: ["break", "lunch", "policy", "paid", "unpaid", "rest", "meal"]),
                MenuItem(id: "settings-tool-policies", label: "Tool Policies", icon: "wrench.fill",
                         tabId: "settings-tool-policies", permission: nil,
                         keywords: ["tool", "policies", "checkout", "return", "maintenance", "calibration"]),
                MenuItem(id: "settings-pretrip-checklists", label: "Pre-Trip Checklists", icon: "checklist",
                         tabId: "settings-pretrip-checklists", permission: nil,
                         keywords: ["pre-trip", "checklist", "inspection", "vehicle", "safety", "dot"]),
                MenuItem(id: "settings-dispatch-preferences", label: "Dispatch Preferences", icon: "location.circle.fill",
                         tabId: "settings-dispatch-preferences", permission: nil,
                         keywords: ["dispatch", "preferences", "scheduling", "assignment", "routing"]),
            ]),

            // 4. Warehouse
            MenuSection(id: "warehouse", title: "Warehouse", icon: "shippingbox", items: [
                MenuItem(id: "settings-forecast-config", label: "Forecast Config", icon: "chart.line.uptrend.xyaxis",
                         tabId: "settings-forecast-config", permission: nil,
                         keywords: ["forecast", "config", "demand", "adu", "prediction", "reorder"]),
                MenuItem(id: "settings-org-thresholds", label: "Organization Thresholds", icon: "gauge.with.dots.needle.33percent",
                         tabId: "settings-org-thresholds", permission: nil,
                         keywords: ["organization", "thresholds", "stock levels", "min", "max", "target", "reorder point"]),
                MenuItem(id: "settings-audit-settings", label: "Audit Settings", icon: "magnifyingglass.circle.fill",
                         tabId: "settings-audit-settings", permission: nil,
                         keywords: ["audit", "settings", "inventory", "count", "cycle", "reconciliation"]),
            ]),

            // 5. Sync & Devices
            MenuSection(id: "sync", title: "Sync & Devices", icon: "arrow.triangle.2.circlepath", items: [
                MenuItem(id: "settings-sync", label: "Sync", icon: "arrow.triangle.2.circlepath",
                         tabId: "settings-sync", permission: nil,
                         keywords: ["sync", "synchronization", "server", "data", "interval", "auto sync"]),
                MenuItem(id: "settings-bluetooth", label: "Bluetooth", icon: "wave.3.right",
                         tabId: "settings-bluetooth", permission: nil,
                         keywords: ["bluetooth", "pairing", "devices", "wireless", "peer", "multipeer"]),
                MenuItem(id: "settings-device-management", label: "Device Management", icon: "desktopcomputer.and.arrow.down",
                         tabId: "settings-device-management", permission: "manage_devices",
                         keywords: ["device", "management", "register", "deregister", "fleet"]),
                MenuItem(id: "settings-bootstrap", label: "Bootstrap", icon: "desktopcomputer",
                         tabId: "settings-bootstrap", permission: "manage_devices",
                         keywords: ["bootstrap", "initial setup", "onboarding", "first sync"]),
            ]),

            // 6. Security
            MenuSection(id: "security", title: "Security", icon: "lock.shield", items: [
                MenuItem(id: "settings-security", label: "Security Admin", icon: "lock.shield.fill",
                         tabId: "settings-security", permission: "manage_devices",
                         keywords: ["security", "admin", "permissions", "roles", "access", "hats"]),
                MenuItem(id: "settings-keys", label: "Key Management", icon: "key.fill",
                         tabId: "settings-keys", permission: "manage_devices",
                         keywords: ["key", "management", "encryption", "pgp", "certificates", "signing"]),
                MenuItem(id: "settings-audit", label: "Audit Log", icon: "list.bullet.clipboard.fill",
                         tabId: "settings-audit", permission: "view_activity_log",
                         keywords: ["audit", "log", "activity", "history", "changes", "trail"]),
            ]),

            // 7. Data
            MenuSection(id: "data", title: "Data", icon: "externaldrive", items: [
                MenuItem(id: "settings-backups", label: "Backups", icon: "externaldrive.fill",
                         tabId: "settings-backups", permission: nil,
                         keywords: ["backup", "restore", "database", "snapshot", "recovery"]),
                MenuItem(id: "settings-export", label: "Data Export", icon: "square.and.arrow.up.fill",
                         tabId: "settings-export", permission: "export_reports",
                         keywords: ["export", "data", "csv", "download", "reports"]),
                MenuItem(id: "settings-reset", label: "Database Reset", icon: "arrow.counterclockwise.circle.fill",
                         tabId: "settings-reset", permission: "manage_devices",
                         keywords: ["reset", "database", "wipe", "clear", "factory"]),
            ]),

            // 8. AI & Integrations
            MenuSection(id: "ai", title: "AI & Integrations", icon: "cpu", items: [
                MenuItem(id: "settings-ai-config", label: "AI Config", icon: "brain.fill",
                         tabId: "settings-ai-config", permission: "manage_settings",
                         keywords: ["ai", "config", "artificial intelligence", "model", "llm", "foundation"]),
                MenuItem(id: "settings-integrations", label: "Integrations", icon: "puzzlepiece.extension.fill",
                         tabId: "settings-integrations", permission: "manage_settings",
                         keywords: ["integrations", "api", "third party", "connect", "webhook"]),
                MenuItem(id: "settings-supplier-bridge", label: "Supplier Bridge", icon: "link.circle.fill",
                         tabId: "settings-supplier-bridge", permission: "manage_settings",
                         keywords: ["supplier", "bridge", "vendor", "portal", "catalog", "ordering"]),
            ]),

            // 9. Templates
            MenuSection(id: "templates", title: "Templates", icon: "doc.text", items: [
                MenuItem(id: "settings-daily-report-templates", label: "Daily Reports", icon: "doc.text.fill",
                         tabId: "settings-daily-report-templates", permission: nil,
                         keywords: ["daily", "report", "template", "end of day", "summary"]),
                MenuItem(id: "settings-job-estimation-questions", label: "Job Estimation Questions", icon: "questionmark.bubble.fill",
                         tabId: "settings-job-estimation-questions", permission: nil,
                         keywords: ["job", "estimation", "questions", "bid", "quote", "assessment"]),
                MenuItem(id: "settings-report-templates", label: "Report Templates", icon: "doc.on.doc.fill",
                         tabId: "settings-report-templates", permission: nil,
                         keywords: ["report", "templates", "format", "layout", "custom"]),
                MenuItem(id: "settings-clockout", label: "Clock-Out Questions", icon: "questionmark.circle.fill",
                         tabId: "settings-clockout", permission: nil,
                         keywords: ["clock out", "questions", "survey", "end shift", "checkout"]),
            ]),

            // 10. Advanced
            MenuSection(id: "advanced", title: "Advanced", icon: "gearshape.2", items: [
                MenuItem(id: "settings-updates", label: "Update Protocol", icon: "arrow.down.circle.fill",
                         tabId: "settings-updates", permission: nil,
                         keywords: ["update", "protocol", "version", "upgrade", "install"]),
                MenuItem(id: "settings-remote-sync", label: "Remote Sync", icon: "icloud.and.arrow.up.and.arrow.down",
                         tabId: "settings-remote-sync", permission: "manage_devices",
                         keywords: ["remote", "sync", "internet", "cloud", "offsite"]),
                MenuItem(id: "settings-shared-channels", label: "Shared Channels", icon: "bubble.left.and.text.bubble.right.fill",
                         tabId: "settings-shared-channels", permission: "manage_settings",
                         keywords: ["shared", "channels", "broadcast", "messaging", "company wide"]),
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
            return MenuSection(id: section.id, title: section.title, icon: section.icon, items: visibleItems)
        }
    }

    /// Flat list of all visible items matching the search query.
    private var searchFilteredItems: [MenuItem] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        return visibleSections.flatMap(\.items).filter { item in
            item.label.lowercased().contains(query) ||
            item.keywords.contains { $0.contains(query) }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // User profile header
                userProfileSection

                Section("Setup") {
                    FirstLaunchSetupRestartRow(telemetrySource: "settingsRoot")
                }

                // Navigation style picker
                Section {
                    ForEach(NavigationStyle.allCases, id: \.self) { style in
                        Button {
                            tabPrefs.navigationStyle = style
                            tabPrefs.saveNavigationStyle()
                        } label: {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(style.label)
                                        Text(style.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: style.icon)
                                }
                                Spacer()
                                if tabPrefs.navigationStyle == style {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .fontWeight(.semibold)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tabPrefs.navigationStyle == style ? .isSelected : [])
                    }
                } header: {
                    Label("Page Layout", systemImage: "rectangle.3.group")
                }

                // Settings sections — grouped or flat-filtered
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Grouped view
                    ForEach(visibleSections) { section in
                        Section {
                            ForEach(section.items) { item in
                                NavigationLink(value: item.tabId) {
                                    HStack {
                                        Label(item.label, systemImage: item.icon)
                                        Spacer()
                                        SyncScopeIndicator(scope: SyncScope.scope(for: item.tabId), compact: true)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Label(section.title, systemImage: section.icon)
                                Spacer()
                                let dominant = SyncScope.dominantScope(for: section.items.map(\.tabId))
                                Text(dominant.shortLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    // Flat search results
                    let results = searchFilteredItems
                    if results.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        Section("Results") {
                            ForEach(results) { item in
                                NavigationLink(value: item.tabId) {
                                    HStack {
                                        Label(item.label, systemImage: item.icon)
                                        Spacer()
                                        SyncScopeIndicator(scope: SyncScope.scope(for: item.tabId), compact: true)
                                    }
                                }
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
            .searchable(text: $searchText, prompt: "Search Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { tabId in
                SettingsRouter(tabId: tabId)
                    .environmentObject(appCore)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissSettingsSheet)) { _ in
                dismiss()
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
