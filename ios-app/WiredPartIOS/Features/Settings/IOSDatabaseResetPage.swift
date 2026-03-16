import SwiftUI
import WiredPartCore

/// iOS settings page for resetting the local database.
///
/// Any user can navigate here to request a reset, but an Admin
/// (with `manage_devices` permission) must approve it by entering their PIN.
/// Touch-optimized layout for iPhone and iPad.
struct IOSDatabaseResetPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var resetPhase: ResetPhase = .idle
    @State private var adminUsers: [User] = []
    @State private var selectedAdminId: Int64? = nil
    @State private var adminPin: String = ""
    @State private var errorMessage: String? = nil
    @State private var hasOtherDevices = false

    private var isCurrentUserAdmin: Bool {
        appCore.hasPermission("manage_devices")
    }

    // MARK: - Body

    var body: some View {
        List {
            warningSection
            dataCategoriesSection
            deviceStatusSection

            switch resetPhase {
            case .idle:
                initiateSection
            case .awaitingApproval:
                approvalSection
            case .resetting:
                progressSection
            case .complete:
                EmptyView()
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Database Reset")
        .task {
            loadDeviceStatus()
        }
    }

    // MARK: - Warning Section

    private var warningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Destructive Action", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("This will permanently delete ALL data on this device and return it to the first-run setup screen. This action cannot be undone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Data Categories

    private var dataCategoriesSection: some View {
        Section("Data That Will Be Deleted") {
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
    }

    private func dataRow(_ text: String) -> some View {
        Label(text, systemImage: "xmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .tint(.red.opacity(0.7))
    }

    // MARK: - Device Status

    private var deviceStatusSection: some View {
        Section("Device Status") {
            Label(
                hasOtherDevices
                    ? "Other devices detected. They will be notified before reset."
                    : "No other devices detected.",
                systemImage: hasOtherDevices ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
            )
            .foregroundStyle(hasOtherDevices ? .orange : .green)
            .font(.callout)
        }
    }

    // MARK: - Initiate Section

    private var initiateSection: some View {
        Section("Reset Database") {
            Text("After reset, this device will behave as if it's brand new. You'll need to create a new admin account or sync with another device.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                beginReset()
            } label: {
                Label("Request Database Reset", systemImage: "arrow.counterclockwise.circle")
            }
        }
    }

    // MARK: - Approval Section

    private var approvalSection: some View {
        Section("Admin Approval Required") {
            if isCurrentUserAdmin {
                Text("You have admin privileges. Enter your PIN to confirm.")
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
                }
            }

            SecureField("Enter 4-digit PIN", text: $adminPin)
                .keyboardType(.numberPad)
                .onChange(of: adminPin) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(4))
                    if filtered != newValue { adminPin = filtered }
                }

            Button(role: .destructive) {
                confirmReset()
            } label: {
                Text("Confirm Reset")
            }
            .disabled(!canConfirm)

            Button("Cancel", role: .cancel) {
                cancelReset()
            }
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
        Section("Resetting...") {
            HStack(spacing: 12) {
                ProgressView()
                Text("Deleting all local data...")
                    .font(.callout)
            }
        }
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
