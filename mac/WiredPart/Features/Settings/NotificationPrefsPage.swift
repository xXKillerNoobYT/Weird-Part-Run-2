import SwiftUI

/// Notification preferences page.
///
/// Lists 13 notification types grouped by domain with toggles.
/// Uses local @State since notification preferences are stored per-device
/// and the full notification service is a future phase.
struct NotificationPrefsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var prefs: [String: Bool] = [:]

    private struct NotifGroup {
        let name: String
        let items: [(id: String, label: String, permission: String?)]
    }

    private let groups: [NotifGroup] = [
        NotifGroup(name: "Inventory", items: [
            ("low_stock",       "Low Stock Alerts",        nil),
            ("reorder_point",   "Reorder Point Reached",   nil),
            ("stock_movement",  "Stock Movement",          "view_warehouse"),
        ]),
        NotifGroup(name: "Orders", items: [
            ("order_status",    "Order Status Changes",    "view_orders"),
            ("delivery_eta",    "Delivery ETA Updates",    "view_orders"),
            ("approval_needed", "Approval Needed",         "manage_orders"),
        ]),
        NotifGroup(name: "Jobs", items: [
            ("job_assigned",    "Job Assigned",            "view_jobs"),
            ("clock_reminder",  "Clock-In/Out Reminders",  nil),
            ("daily_report",    "Daily Report Due",        "view_jobs"),
        ]),
        NotifGroup(name: "Fleet", items: [
            ("maintenance_due", "Maintenance Due",         "view_fleet"),
            ("inspection_due",  "Inspection Due",          "view_fleet"),
        ]),
        NotifGroup(name: "System", items: [
            ("sync_status",     "Sync Status",             nil),
            ("cert_expiry",     "Certification Expiry",    "view_people"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Notification Preferences")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Choose which notifications you want to receive on this device.")
                    .foregroundStyle(.secondary)

                ForEach(groups, id: \.name) { group in
                    GroupBox(group.name) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(group.items, id: \.id) { item in
                                notificationRow(item)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadPrefs() }
    }

    private func notificationRow(_ item: (id: String, label: String, permission: String?)) -> some View {
        let hasPermission = item.permission == nil || appCore.hasPermission(item.permission!)
        let binding = Binding<Bool>(
            get: { prefs[item.id] ?? true },
            set: { newValue in
                prefs[item.id] = newValue
                savePrefs()
            }
        )

        return HStack {
            Toggle(item.label, isOn: binding)
                .disabled(!hasPermission)
            if !hasPermission {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadPrefs() {
        // Load from UserDefaults (per-device preference)
        if let data = UserDefaults.standard.dictionary(forKey: "notification_prefs") as? [String: Bool] {
            prefs = data
        }
    }

    private func savePrefs() {
        UserDefaults.standard.set(prefs, forKey: "notification_prefs")
    }
}
