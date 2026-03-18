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
                            Label(device["assigned_user"] ?? "Unassigned", systemImage: "person")
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
                    SELECT d.id, d.device_name, d.device_fingerprint, d.last_seen,
                           COALESCE(u.display_name, 'Unassigned') AS assigned_user
                    FROM devices d
                    LEFT JOIN users u ON u.id = d.assigned_user_id
                    WHERE d.deleted_at IS NULL
                    ORDER BY d.last_seen DESC
                """)
                return rows.map { row in
                    var dict: [String: String] = [:]
                    dict["id"] = "\(row["id"] as Int64? ?? 0)"
                    dict["name"] = row["device_name"] as? String ?? "Unknown"
                    dict["device_type"] = row["device_fingerprint"] as? String ?? "unknown"
                    dict["assigned_user"] = row["assigned_user"] as? String ?? "Unassigned"
                    // Determine online status from last_seen recency
                    let lastSeen = row["last_seen"] as? String
                    dict["last_seen_at"] = lastSeen
                    dict["status"] = Self.isRecentlyOnline(lastSeen) ? "online" : "offline"
                    return dict
                }
            }
            // Show trusted devices from device registry
            sessions = try db.writer.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT dr.rowid AS id, dr.device_id, dr.created_at,
                           COALESCE(dr.device_name, 'Unknown') AS user_name
                    FROM _device_registry dr
                    WHERE dr.is_trusted = 1 AND dr.is_deactivated = 0
                    ORDER BY dr.last_seen_at DESC
                """)
                return rows.map { row in
                    var dict: [String: String] = [:]
                    dict["id"] = "\(row["id"] as Int64? ?? 0)"
                    dict["user_id"] = "\(row["device_id"] as Int64? ?? 0)"
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

    /// Check if a last_seen timestamp is within the last 5 minutes
    private static func isRecentlyOnline(_ lastSeen: String?) -> Bool {
        guard let lastSeen, !lastSeen.isEmpty else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: lastSeen) {
            return Date().timeIntervalSince(date) < 300 // 5 minutes
        }
        // Try simpler format
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = simple.date(from: lastSeen) {
            return Date().timeIntervalSince(date) < 300
        }
        return false
    }

    // MARK: - Force Logout

    private func forceLogout() {
        guard let db = appCore.db, let sessionId = selectedSessionId else { return }
        do {
            try db.writer.write { db in
                try db.execute(sql: "UPDATE _device_registry SET is_deactivated = 1 WHERE rowid = ?", arguments: [sessionId])
            }
            selectedSessionId = nil
            Task { loadData() }
        } catch {
            errorMessage = "Force logout failed: \(error.localizedDescription)"
        }
    }
}
