import SwiftUI
import WiredPartCore

/// Fleet diagnostics viewer (#1745) — the read side of `DeviceLogService`.
///
/// Until 2026-08-15 nothing in the app displayed `device_logs` at all, so a
/// field failure reached the developer as a screenshot and a recollection.
///
/// Two properties of this page are load-bearing rather than cosmetic:
///
/// 1. **It works with sync completely down.** Tracker trap 9: the diagnostic
///    channel must not depend on the thing it diagnoses. Logs replicate over
///    the same Bluetooth path that breaks, so a viewer that only showed
///    synced-in entries would go blank exactly when it is needed. This reads
///    the local table directly and offers Copy/Share so a field device's log
///    can reach the developer with no connectivity at all.
/// 2. **Verbose entries are local by design.** `debug`/`trace` never leave the
///    device (migration 126 gates the replication triggers), so the fleet view
///    on the shop Mac shows warn-and-above from other devices while this
///    device shows everything it recorded.
struct IOSDeviceLogsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var entries: [DeviceLogService.Entry] = []
    @State private var summary: [DeviceSummaryRow] = []
    @State private var minLevel: DeviceLogService.Level = .info
    @State private var selectedDeviceId: String?
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var verboseEnabled = UserDefaults.standard.bool(forKey: Self.verboseDefaultsKey)
    @State private var contextAnchor: DeviceLogService.Entry?

    /// Read by `AppCore.makeDeviceLogService` at launch — keep the two in sync.
    static let verboseDefaultsKey = "wp_verbose_device_logging"

    /// `deviceSummary()` returns a tuple; SwiftUI needs something identifiable.
    struct DeviceSummaryRow: Identifiable {
        let id: String
        let name: String?
        let errors: Int
        let total: Int
        let lastSeen: String?
    }

    var body: some View {
        List {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            filtersSection
            devicesSection
            entriesSection
        }
        .navigationTitle("Device Logs")
        .searchable(text: $searchText, prompt: "Search messages and detail")
        .onChange(of: searchText) { _, _ in reload() }
        .onChange(of: minLevel) { _, _ in reload() }
        .onChange(of: selectedDeviceId) { _, _ in reload() }
        .refreshable { reload() }
        .task { reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share logs")
                .accessibilityHint("Exports the visible log entries, so they can be sent without sync.")
            }
        }
        .sheet(item: $contextAnchor) { anchor in
            NavigationStack {
                DeviceLogContextView(anchor: anchor)
                    .environmentObject(appCore)
            }
        }
    }

    // MARK: - Sections

    private var filtersSection: some View {
        Section("Filters") {
            Picker("Minimum level", selection: $minLevel) {
                // Ordered worst-first so the common case (show me errors) is
                // the shortest reach.
                ForEach(DeviceLogService.Level.allCases.reversed(), id: \.self) { level in
                    Text(label(for: level)).tag(level)
                }
            }

            Toggle("Developer logging", isOn: $verboseEnabled)
                .onChange(of: verboseEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Self.verboseDefaultsKey)
                }
            Text("Records debug and trace detail on this device. Stays local — verbose entries are never sent to other devices. Takes effect next launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var devicesSection: some View {
        if !summary.isEmpty {
            Section("Devices") {
                Button {
                    selectedDeviceId = nil
                } label: {
                    HStack {
                        Text("All devices")
                        Spacer()
                        if selectedDeviceId == nil {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                ForEach(summary) { row in
                    Button {
                        // Tapping the selected device clears the filter rather
                        // than stranding the user on an empty list (#1740).
                        selectedDeviceId = (selectedDeviceId == row.id) ? nil : row.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name ?? row.id).lineLimit(1)
                                Text("\(row.total) entries · \(row.errors) errors")
                                    .font(.caption)
                                    .foregroundStyle(row.errors > 0 ? .red : .secondary)
                            }
                            Spacer()
                            if selectedDeviceId == row.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        Section(entries.isEmpty ? "Entries" : "Entries (\(entries.count))") {
            if isLoading && entries.isEmpty {
                ProgressView()
            } else if entries.isEmpty {
                // Never a bare empty state: say which filter is responsible and
                // offer the way out (#1740's lesson, applied here up front).
                VStack(alignment: .leading, spacing: 8) {
                    Text(emptyStateMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if isFiltered {
                        Button("Clear filters") {
                            minLevel = .trace
                            selectedDeviceId = nil
                            searchText = ""
                        }
                        .frame(minHeight: 44)
                    }
                }
            } else {
                ForEach(entries, id: \.id) { entry in
                    Button { contextAnchor = entry } label: {
                        DeviceLogRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Data

    private var isFiltered: Bool {
        minLevel != .trace || selectedDeviceId != nil || !searchText.isEmpty
    }

    private var emptyStateMessage: String {
        guard isFiltered else {
            return "No entries recorded yet. Diagnostics are written as the app runs — sync, pairing and startup activity all appear here."
        }
        var parts: [String] = ["level \(label(for: minLevel)) or worse"]
        if let selectedDeviceId {
            parts.append("device \(summary.first { $0.id == selectedDeviceId }?.name ?? selectedDeviceId)")
        }
        if !searchText.isEmpty { parts.append("matching “\(searchText)”") }
        return "No entries for \(parts.joined(separator: ", "))."
    }

    private func reload() {
        guard let service = appCore.deviceLogService else {
            loadError = "Diagnostics are unavailable — the database is not open."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let filter = DeviceLogService.Filter(
                minLevel: minLevel,
                deviceIds: selectedDeviceId.map { [$0] } ?? [],
                search: searchText.isEmpty ? nil : searchText
            )
            entries = try service.recent(limit: 500, filter: filter)
            summary = try service.deviceSummary().map {
                DeviceSummaryRow(
                    id: $0.deviceId, name: $0.deviceName,
                    errors: $0.errors, total: $0.total, lastSeen: $0.lastSeen
                )
            }
            loadError = nil
        } catch {
            // Surfaced, not swallowed: a diagnostics page that fails silently
            // is worse than none.
            loadError = "Could not read the log: \(error.localizedDescription)"
        }
    }

    /// Plain text so it can leave the device by any route — mail, Messages,
    /// AirDrop — with no working sync.
    private func exportText() -> String {
        entries.map { e in
            let device = e.deviceName ?? e.deviceId
            let build = e.buildNumber.map { " (build \($0))" } ?? ""
            return "\(e.createdAt) [\(e.level.rawValue.uppercased())] \(device)\(build) \(e.category): \(e.message)"
                + (e.detail.map { "\n    \($0)" } ?? "")
        }.joined(separator: "\n")
    }

    private func label(for level: DeviceLogService.Level) -> String {
        level.rawValue.capitalized
    }
}

/// One log line. Kept separate so the context sheet can reuse it.
struct DeviceLogRow: View {
    let entry: DeviceLogService.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(entry.category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(entry.createdAt)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(entry.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = entry.detail {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(deviceLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue) in \(entry.category): \(entry.message)")
    }

    private var deviceLine: String {
        var bits = [entry.deviceName ?? entry.deviceId]
        if let model = entry.deviceModel { bits.append(model) }
        if let os = entry.osVersion { bits.append(os) }
        if let build = entry.buildNumber { bits.append("build \(build)") }
        return bits.joined(separator: " · ")
    }

    private var tint: Color {
        switch entry.level {
        case .critical, .error: return .red
        case .warn: return .orange
        case .info: return .secondary
        case .debug, .trace: return .blue
        }
    }

    private var icon: String {
        switch entry.level {
        case .critical: return "exclamationmark.octagon.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .warn: return "exclamationmark.circle"
        case .info: return "info.circle"
        case .debug, .trace: return "ladybug"
        }
    }
}

/// Owner 2026-08-15: *"filters so we can find the info then work are way out
/// if needed"* — pick a line, then read what surrounded it.
struct DeviceLogContextView: View {
    @EnvironmentObject private var appCore: AppCore
    let anchor: DeviceLogService.Entry

    @State private var window: [DeviceLogService.Entry] = []
    @State private var acrossDevices = false
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                Picker("Scope", selection: $acrossDevices) {
                    Text("This device").tag(false)
                    Text("All devices").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: acrossDevices) { _, _ in load() }
            }

            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section(acrossDevices ? "Fleet timeline" : "Surrounding entries") {
                ForEach(window, id: \.id) { entry in
                    DeviceLogRow(entry: entry)
                        .listRowBackground(
                            entry.id == anchor.id
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                }
            }
        }
        .navigationTitle("Context")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        guard let service = appCore.deviceLogService else {
            loadError = "Diagnostics are unavailable."
            return
        }
        do {
            window = acrossDevices
                ? try service.contextAcrossDevices(around: anchor.id, seconds: 30)
                : try service.context(around: anchor.id, before: 50, after: 50)
            loadError = nil
        } catch {
            loadError = "Could not load context: \(error.localizedDescription)"
        }
    }
}
