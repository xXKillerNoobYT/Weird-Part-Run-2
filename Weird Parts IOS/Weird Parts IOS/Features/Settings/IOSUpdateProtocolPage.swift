import SwiftUI
import WiredPartCore

/// Update protocol settings page for iOS.
///
/// Shows the current app version, available updates, and update channel
/// configuration. On iOS, updates come through the App Store or the
/// bootstrap server; this page provides version visibility and channel
/// selection.
struct IOSUpdateProtocolPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var currentVersion = "1.0.0"
    @State private var buildNumber = "1"
    @State private var updateChannel = "stable"
    @State private var lastCheckTime: String?
    @State private var availableVersion: String?
    @State private var isCheckingUpdate = false
    @State private var errorMessage: String?
    @State private var saved = false

    private let channels = ["stable", "beta", "nightly"]

    // MARK: - Body

    var body: some View {
        Form {
            currentVersionSection
            updateStatusSection
            channelSection
            updateHistorySection
            infoSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Updates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-updates-help-button")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Updates Help", sections: [
                ("What This Page Does", "Shows the current app version, checks for available updates, and lets you choose an update channel (stable, beta, or nightly)."),
                ("How to Use It", "Tap 'Check for Updates' to see if a new version is available. Select an update channel to control which releases you receive. Updates are delivered from the shop server via the bootstrap process."),
            ])
        }
        .task { loadData() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Current Version

    private var currentVersionSection: some View {
        Section("Current Version") {
            LabeledContent("Version", value: currentVersion)
            LabeledContent("Build", value: buildNumber)
            LabeledContent("Platform", value: "iOS")
        }
    }

    // MARK: - Update Status

    private var updateStatusSection: some View {
        Section("Update Status") {
            if let available = availableVersion {
                HStack {
                    Label("Update Available: v\(available)", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Spacer()
                }
            } else {
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            LabeledContent("Last Checked") {
                Text(lastCheckTime ?? "Never")
                    .foregroundStyle(lastCheckTime != nil ? .primary : .secondary)
            }

            Button {
                checkForUpdates()
            } label: {
                HStack {
                    if isCheckingUpdate {
                        ProgressView()
                            .padding(.trailing, 4)
                    }
                    Text(isCheckingUpdate ? "Checking..." : "Check for Updates")
                }
            }
            .disabled(isCheckingUpdate)
        }
    }

    // MARK: - Channel Section

    private var channelSection: some View {
        Section("Update Channel") {
            Picker("Channel", selection: $updateChannel) {
                ForEach(channels, id: \.self) { channel in
                    Text(channel.capitalized).tag(channel)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: updateChannel) { _, _ in
                saveChannel()
            }

            Text(channelDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var channelDescription: String {
        switch updateChannel {
        case "beta":
            return "Receive beta releases with new features before they are stable. May contain bugs."
        case "nightly":
            return "Receive nightly builds with the latest changes. Not recommended for production use."
        default:
            return "Receive only stable, tested releases. Recommended for production use."
        }
    }

    // MARK: - History Section

    private var updateHistorySection: some View {
        Section("How Updates Work") {
            VStack(alignment: .leading, spacing: 6) {
                Label("iOS updates are delivered via the bootstrap server", systemImage: "arrow.down.app")
                Label("The shop server checks for new versions automatically", systemImage: "server.rack")
                Label("Devices download updates when connected to the shop", systemImage: "wifi")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            Text("Update protocol settings control how this device receives application updates. The shop server acts as the distribution point for all connected devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        // Read version from bundle
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        guard let settingsService = appCore.settingsService else {
            errorMessage = "Service not available"
            return
        }
        do {
            let settings = try settingsService.getUpdateSettings()
            lastCheckTime = settings.lastCheckTime
            availableVersion = settings.availableVersion
            updateChannel = settings.updateChannel
        } catch {
            if !userFriendlyError(error, context: "save settings").contains("no such table") {
                errorMessage = userFriendlyError(error, context: "load update settings")
            }
        }
    }

    // MARK: - Actions

    private func checkForUpdates() {
        isCheckingUpdate = true
        errorMessage = nil

        guard let settingsService = appCore.settingsService else {
            errorMessage = "Settings service not available."
            isCheckingUpdate = false
            return
        }

        do {
            // Update last check timestamp
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let now = formatter.string(from: Date())
            try settingsService.upsertSetting(key: "last_update_check", value: now, category: "updates")

            // Compare current version against stored latest
            let latestKnown = try settingsService.getSettingValue("latest_known_version")
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

            if let latest = latestKnown, latest.compare(current, options: .numeric) == .orderedDescending {
                availableVersion = latest
            } else {
                availableVersion = nil
            }
            lastCheckTime = now
        } catch {
            errorMessage = userFriendlyError(error, context: "save settings")
        }
        isCheckingUpdate = false
    }

    private func saveChannel() {
        guard let settingsService = appCore.settingsService else {
            errorMessage = "Service not available"
            return
        }
        do {
            try settingsService.saveUpdateChannel(updateChannel)
        } catch {
            errorMessage = userFriendlyError(error, context: "save channel")
        }
    }
}
