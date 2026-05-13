import SwiftUI
import WiredPartCore

/// Security and device administration page.
///
/// Shows registered devices, active sessions, and provides force-logout
/// capability. Uses AuthService methods to read device and session data.
/// On mobile this is primarily a view-only status page; full
/// administration is expected on desktop.
struct SecurityAdminPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var devices: [AuthService.RegisteredDevice] = []
    @State private var sessions: [AuthService.ActiveSession] = []
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            Group {
                PageHelpSheet(title: "Security Help", sections: [
                    ("What This Page Does", "Shows registered devices and active user sessions. Administrators can force-logout sessions from this page."),
                    ("How to Use It", "Review device status and active sessions. To end a session, tap the red X button next to it (admin permission required). Full device and session management is available on the desktop application."),
                ])
            }
            .presentationDetents([.medium, .large])
        }
        .task { loadData() }
        .alert("Force Logout", isPresented: $showForceLogoutConfirm) {
            Button("Cancel", role: .cancel) { selectedSessionId = nil }
            Button("Force Logout", role: .destructive) { forceLogout() }
        } message: {
            Text("This will immediately end the selected session. The user will need to log in again.")
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Devices Section

    private var devicesSection: some View {
        Section("Registered Devices") {
            if devices.isEmpty {
                Text("No registered devices found.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(devices, id: \.id) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.body.weight(.medium))
                        HStack(spacing: 12) {
                            Label(device.assignedUser, systemImage: "person")
                            Label(device.status, systemImage:
                                (device.status == "online") ? "circle.fill" : "circle")
                                .foregroundStyle((device.status == "online") ? .green : .secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let lastSeen = device.lastSeenAt {
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
                ForEach(sessions, id: \.id) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.userName)
                                .font(.body)
                            Text("Started: \(session.createdAt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appCore.hasPermission("manage_devices") {
                            Button {
                                selectedSessionId = session.id
                                showForceLogoutConfirm = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Force logout")
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
        guard let authService = appCore.authService else {
            errorMessage = "Auth service not available."
            isLoading = false
            return
        }
        do {
            devices = try authService.listRegisteredDevices()
            sessions = try authService.listActiveSessions()
        } catch {
            errorMessage = userFriendlyError(error, context: "load")
        }
        isLoading = false
    }

    // MARK: - Force Logout

    private func forceLogout() {
        guard let authService = appCore.authService, let sessionId = selectedSessionId else {
            if appCore.authService == nil { errorMessage = "Service not available" }
            return
        }
        do {
            try authService.deactivateSession(sessionId: sessionId)
            selectedSessionId = nil
            Task { loadData() }
        } catch {
            errorMessage = userFriendlyError(error, context: "load security settings")
        }
    }
}
