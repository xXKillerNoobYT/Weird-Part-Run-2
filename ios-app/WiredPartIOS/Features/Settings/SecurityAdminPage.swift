import SwiftUI
import GRDB
import WiredPartCore

/// Security and device administration page.
///
/// Shows registered devices, active sessions, and provides force-logout
/// capability. Reads directly from `devices` and `sessions` tables via
/// raw SQL. On mobile this is primarily a view-only status page; full
/// administration is expected on desktop.
struct SecurityAdminPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var devices: [[String: String]] = []
    @State private var sessions: [[String: String]] = []
    @State private var errorMessage: String?
    @State private var showForceLogoutConfirm = false
    @State private var selectedSessionId: String?

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading security data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    devicesSection
                    sessionsSection
                    securityInfoSection

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle("Security & Devices")
        .task { loadData() }
        .alert("Force Logout", isPresented: $showForceLogoutConfirm) {
            Button("Cancel", role: .cancel) { selectedSessionId = nil }
            Button("Force Logout", role: .destructive) { forceLogout() }
        } message: {
            Text("This will immediately end the selected session. The user will need to log in again.")
        }
    }

    // MARK: - Devices Section

    private var devicesSection: some View {
        Section("Registered Devices") {
            if devices.isEmpty {
                Text("No registered devices found.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(devices, id: \.self) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device["name"] ?? "Unknown Device")
                            .font(.body.weight(.medium))
                        HStack(spacing: 12) {
                            Label(device["device_type"] ?? "unknown", systemImage: "desktopcomputer")
                            Label(device["status"] ?? "offline", systemImage:
                                (device["status"] == "online") ? "circle.fill" : "circle")
                                .foregroundStyle((device["status"] == "online") ? .green : .secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let lastSeen = device["last_seen_at"] {
                            Text("Last seen: \(lastSeen)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Sessions Section

    private var sessionsSection: some View {
        Section("Active Sessions") {
            if sessions.isEmpty {
                Text("No active sessions.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(sessions, id: \.self) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session["user_name"] ?? "User #\(session["user_id"] ?? "?")")
                                .font(.body)
                            Text("Started: \(session["created_at"] ?? "Unknown")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appCore.hasPermission("manage_devices") {
                            Button {
                                selectedSessionId = session["id"]
                                showForceLogoutConfirm = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Info Section

    private var securityInfoSection: some View {
        Section {
            Text("Full device and session management is available on the desktop application. This page provides a read-only view of the current security state.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else {
            errorMessage = "Database not available."
            isLoading = false
            return
        }
        do {
            devices = try db.writer.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, name, device_type, status, last_seen_at
                    FROM devices ORDER BY last_seen_at DESC
                """)
                return rows.map { row in
                    var dict: [String: String] = [:]
                    dict["id"] = "\(row["id"] as Int64? ?? 0)"
                    dict["name"] = row["name"] as? String ?? "Unknown"
                    dict["device_type"] = row["device_type"] as? String ?? "unknown"
                    dict["status"] = row["status"] as? String ?? "offline"
                    dict["last_seen_at"] = row["last_seen_at"] as? String
                    return dict
                }
            }
            sessions = try db.writer.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT s.id, s.user_id, s.created_at,
                           COALESCE(u.display_name, u.username) AS user_name
                    FROM sessions s
                    LEFT JOIN users u ON u.id = s.user_id
                    WHERE s.is_active = 1
                    ORDER BY s.created_at DESC
                """)
                return rows.map { row in
                    var dict: [String: String] = [:]
                    dict["id"] = "\(row["id"] as Int64? ?? 0)"
                    dict["user_id"] = "\(row["user_id"] as Int64? ?? 0)"
                    dict["user_name"] = row["user_name"] as? String ?? "Unknown"
                    dict["created_at"] = row["created_at"] as? String ?? "Unknown"
                    return dict
                }
            }
        } catch {
            // Gracefully handle missing tables
            if error.localizedDescription.contains("no such table") {
                devices = []
                sessions = []
            } else {
                errorMessage = "Failed to load: \(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    // MARK: - Force Logout

    private func forceLogout() {
        guard let db = appCore.db, let sessionId = selectedSessionId else { return }
        do {
            try db.writer.write { db in
                try db.execute(sql: "UPDATE sessions SET is_active = 0 WHERE id = ?", arguments: [sessionId])
            }
            selectedSessionId = nil
            Task { loadData() }
        } catch {
            errorMessage = "Force logout failed: \(error.localizedDescription)"
        }
    }
}
