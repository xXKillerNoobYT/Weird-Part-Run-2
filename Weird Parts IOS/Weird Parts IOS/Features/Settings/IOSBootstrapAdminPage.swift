import SwiftUI
import WiredPartCore

/// Device bootstrap administration page for iOS.
///
/// Shows devices that have been registered through the bootstrap
/// process, their current enrollment status, and last check-in time.
/// Full bootstrap management (approve/reject) requires the desktop app.
struct IOSBootstrapAdminPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var bootstrapDevices: [SettingsService.BootstrapDeviceRow] = []
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading devices...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if bootstrapDevices.isEmpty {
                ContentUnavailableView(
                    "No Bootstrap Devices",
                    systemImage: "iphone.and.arrow.forward",
                    description: Text("No devices have been registered through the bootstrap process yet.")
                )
            } else {
                List {
                    Section("Registered Devices (\(bootstrapDevices.count))") {
                        ForEach(bootstrapDevices) { device in
                            deviceRow(device)
                        }
                    }

                    adminInfoSection
                }
            }
        }
        .navigationTitle("Bootstrap Admin")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Bootstrap Admin Help", sections: [
                ("What This Page Does", "Lists devices that registered through the bootstrap process. Shows each device's enrollment status, type, app version, and last check-in time."),
                ("How to Use It", "Review registered devices and their statuses here. Device approval and rejection must be performed from the desktop application. Pull down to refresh the list."),
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .overlay {
            if let errorMessage {
                VStack {
                    Spacer()
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.white)
                        .padding()
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                        .padding()
                }
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Device Row

    private func deviceRow(_ device: SettingsService.BootstrapDeviceRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.name)
                    .font(.body.weight(.medium))
                Spacer()
                statusBadge(device.status)
            }
            HStack(spacing: 12) {
                Label(device.deviceType, systemImage: iconForType(device.deviceType))
                if let version = device.appVersion {
                    Label(version, systemImage: "app.badge")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let lastCheckin = device.lastCheckin {
                Text("Last check-in: \(lastCheckin)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colorForStatus(status).opacity(0.15))
            .foregroundStyle(colorForStatus(status))
            .clipShape(Capsule())
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved", "active":  return .green
        case "pending":             return .orange
        case "rejected", "revoked": return .red
        default:                    return .secondary
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "iphone", "phone":   return "iphone"
        case "ipad", "tablet":    return "ipad"
        case "mac", "desktop":    return "desktopcomputer"
        case "windows", "pc":     return "pc"
        default:                  return "laptopcomputer"
        }
    }

    // MARK: - Info Section

    private var adminInfoSection: some View {
        Section {
            Text("Device approval and rejection must be performed from the desktop application. This page provides a read-only view of registered bootstrap devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let settingsService = appCore.settingsService else {
            errorMessage = "Settings service not available."
            isLoading = false
            return
        }
        do {
            bootstrapDevices = try settingsService.listBootstrapDevices()
        } catch {
            errorMessage = userFriendlyError(error, context: "load")
            bootstrapDevices = []
        }
        isLoading = false
    }
}
