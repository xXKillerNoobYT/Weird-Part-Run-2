import SwiftUI
import WiredPartCore

/// Security and device administration page.
///
/// Shows registered devices, active auth sessions, and provides force-logout
/// capability. Uses AuthService methods to read device and session data.
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
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-security-help-button")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Security Help", sections: [
                ("What This Page Does", "Shows registered device status and active user auth sessions. Administrators can force-logout sessions from this page."),
                ("How to Use It", "Review device status and active sessions. To end a session, tap the red X button next to it (admin permission required)."),
            ])
        }
        .task { loadData() }
        .confirmDestruction(
            ofRecordNamed: selectedSessionUserName,
            noun: "session",
            actionLabel: "Force Logout",
            actionVerb: "immediately ends",
            isPresented: $showForceLogoutConfirm,
            messageSuffix: "They will need to log in again."
        ) {
            forceLogout()
        }
    }

    /// Name of the user whose session is pending force-logout, so the
    /// confirmation names whose access is being cut. Empty when the session
    /// can't be resolved — the helper then renders "Force Logout this session?".
    private var selectedSessionUserName: String {
        guard let selectedSessionId else { return "" }
        return sessions.first(where: { $0.id == selectedSessionId })?.userName ?? ""
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
                    .rowAccessibility(
                        label: "Device \(device.name), assigned to \(device.assignedUser)",
                        value: deviceAccessibilityValue(device),
                        id: "settings-security-device-\(device.id)"
                    )
                }
            }
        }
    }

    /// "Online, last seen 2026-07-06" — mirrors the visible status + last-seen
    /// caption for VoiceOver.
    private func deviceAccessibilityValue(_ device: AuthService.RegisteredDevice) -> String {
        let status = device.status == "online" ? "Online" : device.status.capitalized
        guard let lastSeen = device.lastSeenAt else { return status }
        return "\(status), last seen \(lastSeen)"
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
                        .rowAccessibility(
                            label: "Session for \(session.userName)",
                            value: "Started \(session.createdAt)",
                            id: "settings-security-session-\(session.id)"
                        )
                        Spacer()
                        if appCore.hasPermission("manage_devices") {
                            Button {
                                selectedSessionId = session.id
                                showForceLogoutConfirm = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .dsMinTapTarget()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Force logout \(session.userName)")
                            .accessibilityHint("Ends this session immediately. The user will need to log in again.")
                            .accessibilityIdentifier("settings-security-force-logout-\(session.id)")
                        }
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        if appCore.hasPermission("manage_devices") {
                            Button(role: .destructive) {
                                selectedSessionId = session.id
                                showForceLogoutConfirm = true
                            } label: {
                                Label("Force Logout", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Info Section

    private var securityInfoSection: some View {
        Section {
            Text("Registered devices show sync status. Active sessions are revocable login sessions; force logout invalidates the selected session tokens.")
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
