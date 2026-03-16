import SwiftUI
import WiredPartCore

/// Settings page for resetting the local database.
///
/// Any user can navigate here to request a reset, but an Admin
/// (with `manage_devices` permission) must approve it by entering their PIN.
/// If the current user is already an Admin, they approve directly.
///
/// Before wiping, the device is deactivated in `_device_registry` so
/// connected peers stop syncing with it.
struct DatabaseResetPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var showConfirmation = false
    @State private var resetPhase: ResetPhase = .idle
    @State private var adminUsers: [User] = []
    @State private var selectedAdminId: Int64? = nil
    @State private var adminPin: String = ""
    @State private var errorMessage: String? = nil
    @State private var hasOtherDevices = false
    @State private var peersNotified = false

    private var isCurrentUserAdmin: Bool {
        appCore.hasPermission("manage_devices")
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Database Reset")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                warningSection
                dataCategories
                deviceStatusSection

                switch resetPhase {
                case .idle:
                    initiateSection
                case .awaitingApproval:
                    approvalSection
                case .resetting:
                    progressSection
                case .complete:
                    EmptyView() // App will navigate to bootstrap
                }

                if let errorMessage {
                    errorCard(errorMessage)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            loadDeviceStatus()
        }
    }

    // MARK: - Warning Section

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Destructive Action", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("This will permanently delete ALL data on this device and return it to the first-run setup screen. This action cannot be undone.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
    }

    // MARK: - Data Categories

    private var dataCategories: some View {
        GroupBox("Data That Will Be Deleted") {
            VStack(alignment: .leading, spacing: 8) {
                dataRow("Users, hats, and permissions")
                dataRow("Parts catalog and pricing")
                dataRow("Warehouse stock and movements")
                dataRow("Jobs, labor entries, and notebooks")
                dataRow("Orders and procurement history")
                dataRow("Fleet vehicles and assignments")
                dataRow("Scheduling and dispatch records")
                dataRow("Chat messages and Q&A")
                dataRow("Reports and audit logs")
                dataRow("Tools, kits, and checkout history")
                dataRow("All settings and company profiles")
                dataRow("Device identity and sync history")
            }
            .padding(.vertical, 4)
        }
    }

    private func dataRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red.opacity(0.7))
            Text(text)
                .font(.callout)
        }
    }

    // MARK: - Device Status

    private var deviceStatusSection: some View {
        GroupBox("Device Status") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: hasOtherDevices ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(hasOtherDevices ? .orange : .green)
                    Text(hasOtherDevices
                         ? "Other devices detected on the network. They will be notified before reset."
                         : "No other devices detected. Reset can proceed directly.")
                        .font(.callout)
                }

                if hasOtherDevices && peersNotified {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Peers have been notified of this device's deactivation.")
                            .font(.callout)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Initiate Section

    private var initiateSection: some View {
        GroupBox("Reset Database") {
            VStack(alignment: .leading, spacing: 12) {
                Text("After reset, this device will behave as if it's brand new. You'll need to create a new admin account or sync with another device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    beginReset()
                } label: {
                    Label("Request Database Reset", systemImage: "arrow.counterclockwise.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Admin Approval Section

    private var approvalSection: some View {
        GroupBox("Admin Approval Required") {
            VStack(alignment: .leading, spacing: 16) {
                if isCurrentUserAdmin {
                    Text("You have admin privileges. Enter your PIN to confirm the reset.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("An administrator must enter their PIN to authorize this reset.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if !adminUsers.isEmpty {
                        Picker("Admin User", selection: $selectedAdminId) {
                            Text("Select an admin...").tag(nil as Int64?)
                            ForEach(adminUsers, id: \.id) { user in
                                Text(user.displayName).tag(user.id as Int64?)
                            }
                        }
                        .frame(maxWidth: 280)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Admin PIN")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Enter 4-digit PIN", text: $adminPin)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onChange(of: adminPin) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(4))
                            if filtered != newValue { adminPin = filtered }
                        }
                }

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        confirmReset()
                    } label: {
                        Text("Confirm Reset")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!canConfirm)

                    Button("Cancel") {
                        cancelReset()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var canConfirm: Bool {
        let pinReady = adminPin.count == 4 && adminPin.allSatisfy(\.isNumber)
        if isCurrentUserAdmin {
            return pinReady
        } else {
            return pinReady && selectedAdminId != nil
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        GroupBox("Resetting...") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Deleting all local data and resetting the device...")
                        .font(.callout)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.05)))
    }

    // MARK: - Actions

    private func loadDeviceStatus() {
        guard let database = appCore.db else { return }
        let resetService = DeviceResetService(db: database)
        do {
            hasOtherDevices = try resetService.hasOtherActiveDevices()
            if !isCurrentUserAdmin {
                adminUsers = try resetService.getAdminUsers()
            }
        } catch {
            errorMessage = "Failed to check device status: \(error.localizedDescription)"
        }
    }

    private func beginReset() {
        errorMessage = nil
        adminPin = ""
        selectedAdminId = nil
        resetPhase = .awaitingApproval
    }

    private func cancelReset() {
        resetPhase = .idle
        adminPin = ""
        selectedAdminId = nil
        errorMessage = nil
    }

    private func confirmReset() {
        guard let database = appCore.db else { return }
        errorMessage = nil

        let resetService = DeviceResetService(db: database)
        let approvalUserId: Int64

        if isCurrentUserAdmin {
            guard let uid = appCore.currentUser?.id else { return }
            approvalUserId = uid
        } else {
            guard let uid = selectedAdminId else { return }
            approvalUserId = uid
        }

        // Verify admin PIN
        do {
            let approved = try resetService.verifyAdminApproval(userId: approvalUserId, pin: adminPin)
            guard approved else {
                errorMessage = "Invalid PIN or user does not have admin privileges."
                return
            }
        } catch {
            errorMessage = "Authentication failed: \(error.localizedDescription)"
            return
        }

        // Proceed with reset
        resetPhase = .resetting

        Task {
            do {
                try await appCore.performDatabaseReset()
                resetPhase = .complete
            } catch {
                resetPhase = .idle
                errorMessage = "Reset failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Phase Enum

    private enum ResetPhase {
        case idle
        case awaitingApproval
        case resetting
        case complete
    }
}
