import SwiftUI
import WiredPartCore

/// Bootstrap administration page.
///
/// Shows the current bootstrap status and allows re-running the
/// bootstrap process on a fresh database. This is primarily for
/// development and troubleshooting.
struct BootstrapAdminPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var userCount = 0
    @State private var hatCount = 0
    @State private var settingCount = 0

    var body: some View {
        Form {
            Section("Bootstrap Status") {
                LabeledContent("Users", value: "\(userCount)")
                LabeledContent("Hats (Roles)", value: "\(hatCount)")
                LabeledContent("Settings", value: "\(settingCount)")
            }

            Section("Current Admin") {
                if let user = appCore.currentUser {
                    LabeledContent("Name", value: user.displayName)
                    LabeledContent("ID", value: "\(user.id ?? 0)")
                    LabeledContent("Active", value: user.isActive == 1 ? "Yes" : "No")
                } else {
                    Text("No user logged in")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Info") {
                Text("The bootstrap process creates the initial database structure including hats (roles), permissions, the first admin user, and default settings. It only runs once on a fresh database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Database") {
                LabeledContent("Path", value: AppCore.databasePath())
                    .font(.caption2)
            }
        }
        .onAppear { loadCounts() }
    }

    private func loadCounts() {
        do {
            userCount = try appCore.db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL") ?? 0
            }
            hatCount = try appCore.db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hats") ?? 0
            }
            settingCount = try appCore.db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings") ?? 0
            }
        } catch {}
    }
}
