import SwiftUI
import WiredPartCore

/// Permissions matrix editor — hat x permission grid.
///
/// Shows all hats as columns and all permission keys as rows,
/// with toggles to enable/disable each combination.
struct IOSPermissionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var hats: [PeopleService.HatListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedHat: PeopleService.HatListItem?
    @State private var hatPermissions: [String] = []

    /// All known permission keys
    private let allPermissions: [PermissionGroup] = [
        PermissionGroup(name: "Parts & Warehouse", keys: [
            "view_parts_catalog", "edit_parts_catalog", "edit_pricing", "show_dollar_values",
            "manage_deprecation", "view_warehouse", "manage_warehouse", "move_stock_warehouse",
        ]),
        PermissionGroup(name: "Jobs & Labor", keys: [
            "view_jobs", "manage_jobs", "clock_in_out", "consume_parts_any_job",
            "view_labor", "manage_labor",
        ]),
        PermissionGroup(name: "Orders", keys: [
            "view_orders", "manage_orders", "approve_returns",
        ]),
        PermissionGroup(name: "Fleet & Tools", keys: [
            "view_fleet", "manage_fleet", "view_trucks", "manage_trucks", "move_stock_truck",
            "view_tools", "manage_tools",
        ]),
        PermissionGroup(name: "People", keys: [
            "view_people", "manage_people", "view_customers", "view_contractors",
        ]),
        PermissionGroup(name: "Scheduling", keys: [
            "view_scheduling", "manage_scheduling", "manage_dispatch",
            "view_schedule", "manage_schedule", "dispatch_employees",
            "manage_time_off", "manage_subcontractors",
        ]),
        PermissionGroup(name: "Chat", keys: [
            "view_chat", "manage_chat", "moderate_chat", "use_chat", "ask_qa", "send_rfi",
        ]),
        PermissionGroup(name: "Reports & Admin", keys: [
            "view_reports", "export_reports", "manage_settings", "manage_devices",
            "manage_templates", "manage_notebooks", "perform_audit",
            "manager_override", "view_activity_log", "manage_remote_sync",
        ]),
    ]

    struct PermissionGroup: Identifiable {
        let id = UUID()
        let name: String
        let keys: [String]
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading permissions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                permissionsContent
            }
        }
        .navigationTitle("Permissions")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var permissionsContent: some View {
        VStack(spacing: 0) {
            hatSelector
            permissionsList
        }
    }

    private var hatSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(hats) { hat in
                    Button {
                        selectHat(hat)
                    } label: {
                        Text(hat.name)
                            .font(.caption)
                            .fontWeight(selectedHat?.id == hat.id ? .bold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedHat?.id == hat.id ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(selectedHat?.id == hat.id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var permissionsList: some View {
        List {
            if let hat = selectedHat {
                ForEach(allPermissions) { group in
                    Section(group.name) {
                        ForEach(group.keys, id: \.self) { key in
                            permissionRow(key: key, hatId: hat.id)
                        }
                    }
                }
            } else {
                Section {
                    Text("Select a hat above to view and edit permissions")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func permissionRow(key: String, hatId: Int64) -> some View {
        let isEnabled = hatPermissions.contains(key)
        return Toggle(isOn: Binding(
            get: { isEnabled },
            set: { newValue in
                togglePermission(key: key, enabled: newValue)
            }
        )) {
            Text(formatPermissionKey(key))
                .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private func formatPermissionKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func selectHat(_ hat: PeopleService.HatListItem) {
        selectedHat = hat
        loadHatPermissions(hatId: hat.id)
    }

    private func loadHatPermissions(hatId: Int64) {
        guard let auth = appCore.authService else {
            loadError = "Auth service is not available."
            return
        }
        do {
            hatPermissions = try auth.getHatPermissions(hatId)
        } catch {
            loadError = "Failed to load permissions: \(error.localizedDescription)"
        }
    }

    private func togglePermission(key: String, enabled: Bool) {
        guard let auth = appCore.authService else {
            loadError = "Service not available"
            return
        }
        guard let hat = selectedHat else { return }
        do {
            if enabled {
                try auth.addHatPermission(hatId: hat.id, permissionKey: key)
                if !hatPermissions.contains(key) {
                    hatPermissions.append(key)
                }
            } else {
                try auth.removeHatPermission(hatId: hat.id, permissionKey: key)
                hatPermissions.removeAll { $0 == key }
            }
        } catch {
            loadError = "Failed to update permission: \(error.localizedDescription)"
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service is not available."
            return
        }
        isLoading = hats.isEmpty
        loadError = nil
        do {
            hats = try service.listHats()
            // Auto-select first hat
            if selectedHat == nil, let first = hats.first {
                selectHat(first)
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
