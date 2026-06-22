import SwiftUI
import CoreLocation
@preconcurrency import UserNotifications
import WiredPartCore
import os.log

/// Clock in/out page for iOS.
///
/// Shows an inline GPS-sorted job list for clocking in, or current clock
/// status when already clocked in. "Shop / Warehouse" is always pinned first.
/// When clocked into Shop, an optional collapsible section lets the user link
/// time to a specific job without clocking out/in.
struct IOSClockPage: View {
    @EnvironmentObject private var appCore: AppCore
    @StateObject private var locationManager = LocationManager()
    @StateObject private var geofenceManager = GeofenceManager()

    private let logger = Logger(subsystem: "com.wiredpart", category: "ClockPage")

    // MARK: - State

    @State private var activeEntry: JobsService.LaborEntryRow?
    @State private var todayEntries: [JobsService.LaborEntryRow] = []
    @State private var todayHours: Double = 0.0
    @State private var isLoading = true
    @State private var errorMessage: String?

    // GPS + job list
    @State private var userLocation: CLLocation?
    @State private var sortedJobs: [JobWithDistance] = []
    @State private var isShopClockIn = false
    @State private var linkedJobId: Int64?
    @State private var linkedJobName: String?

    // Activity status (working, supply_run, break, lunch_paid, lunch_unpaid)
    @State private var activityStatus: String = "working"
    @State private var activeSupplyRunStartedAt: Date?
    @State private var supplyRunElapsedText: String = ""

    // Break/lunch tracking
    @State private var activeBreakRecord: BreakRecord?
    @State private var breakElapsedText: String = ""
    /// Break duration timer. Fix #216: Timer is a reference type but @State
    /// works correctly here because we never OBSERVE the timer itself — we just
    /// hold the reference to invalidate it. All view updates come from @State
    /// strings (breakElapsedText) written inside the timer closure, which do
    /// trigger SwiftUI updates correctly. Every code path that dismisses or
    /// navigates away calls `.invalidate()` and sets to nil. A future refactor
    /// could wrap this in AnyCancellable via Timer.publish() for stylistic
    /// consistency with DashboardView (#214), but behavior is correct today.
    @State private var breakTimer: Timer?
    @State private var breakBudgetMinutes: Int = 15
    @State private var lunchPaidMinutes: Int = 30
    @State private var showLunchUnpaidPrompt = false
    @State private var showRecoveredTimerBanner = false
    @State private var recoveredBannerDismissed = false
    @State private var isSwitchingJob = false

    // To-do integration
    @State private var activeTodos: [JobsService.ClockTodoItem] = []
    @State private var currentTodo: JobsService.ClockTodoItem?
    @State private var workType: String = "new_work"

    // Live elapsed timer — see breakTimer doc above (#216) for why @State is safe here.
    @State private var elapsedTimer: Timer?
    @State private var elapsedText: String = "0h 0m"

    // Today's grouped breakdown
    @State private var todayJobGroups: [JobsService.JobClockGroup] = []

    // Sheets
    @State private var activeSheet: ActiveSheet?
    @State private var lastLaborEntryId: Int64?

    // Flex Pool — shown when user has no dispatch for today
    @State private var hasDispatchToday = false
    @State private var flexPoolJobs: [JobsService.ClockJobRow] = []
    @State private var showSelfAssignConfirmation = false
    @State private var selectedFlexJob: (id: Int64, name: String)?

    // Confirmation dialogs
    @State private var showClockOutConfirmation = false
    @State private var pendingClockOutEntryId: Int64?

    // Location permission
    @State private var showLocationDeniedAlert = false

    // alreadyClockedIn recovery
    @State private var showAlreadyClockedInAlert = false
    @State private var pendingClockInJobId: Int64?
    @State private var pendingClockInIsShop = false
    @State private var danglingEntryJobName: String?

    // notClockedIn recovery
    @State private var showNotClockedInAlert = false

    /// True when location permission has not been decided yet (first launch).
    private var needsLocationPermission: Bool {
        locationManager.authorizationStatus == .notDetermined
    }

    // Date filter
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    private enum ActiveSheet: Identifiable {
        case questionnaire(Int64)
        case jobScanner
        case help
        case todoPicker
        case switchJobPicker
        case lunchUnpaidPrompt
        case breakStatePicker

        var id: String {
            switch self {
            case .questionnaire(let id): "questionnaire-\(id)"
            case .jobScanner: "jobScanner"
            case .help: "help"
            case .todoPicker: "todoPicker"
            case .switchJobPicker: "switchJobPicker"
            case .lunchUnpaidPrompt: "lunchUnpaidPrompt"
            case .breakStatePicker: "breakStatePicker"
            }
        }
    }

    fileprivate enum BreakStateOption: String, CaseIterable, Identifiable {
        case paidBreak
        case paidLunch
        case unpaidLunch

        var id: String { rawValue }

        var breakType: String {
            switch self {
            case .paidBreak: return "break"
            case .paidLunch: return "lunch_paid"
            case .unpaidLunch: return "lunch_unpaid"
            }
        }

        var title: String {
            switch self {
            case .paidBreak: return "Paid Break"
            case .paidLunch: return "Paid Lunch"
            case .unpaidLunch: return "Unpaid Lunch / Clocked-Out"
            }
        }

        var subtitle: String {
            switch self {
            case .paidBreak: return "State-required paid rest break; clock stays running."
            case .paidLunch: return "Paid meal/rest period; clock stays running until the paid timer ends."
            case .unpaidLunch: return "Unpaid lunch or offered extra break; shows a paused/clocked-out state."
            }
        }

        var icon: String {
            switch self {
            case .paidBreak: return "cup.and.saucer.fill"
            case .paidLunch: return "fork.knife"
            case .unpaidLunch: return "pause.circle.fill"
            }
        }
    }

    struct JobWithDistance: Identifiable {
        let id: Int64
        let jobName: String
        let jobNumber: String
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let distanceMiles: Double?
        let status: String

        var distanceText: String {
            guard let d = distanceMiles else { return "" }
            if d < 0.1 { return "Nearby" }
            return String(format: "%.1f mi", d)
        }
    }

    var body: some View {
        clockContent
            .navigationTitle("Clock In / Out")
            .toolbar {
                if activeEntry == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { activeSheet = .jobScanner } label: {
                            Label("Scan Job", systemImage: "qrcode.viewfinder")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .refreshable { loadData() }
            .task { appCore.onboardingManager?.markCompleted("clock-in") }
            .task {
                // Don't auto-request permission — let the banner explain first.
                // Only reload denied state in case user returned from Settings.
                if locationManager.permissionDenied {
                    showLocationDeniedAlert = true
                }
                loadData()
            }
            .onChange(of: dateRange) { loadData() }
            .onChange(of: customStart) { loadData() }
            .onChange(of: customEnd) { loadData() }
            .onAppear {
                let clockedIn = activeEntry != nil
                let jobName = activeEntry?.jobName ?? "none"
                NotificationCenter.default.post(
                    name: .clockPageActive,
                    object: nil,
                    userInfo: [
                        "context": "Clock Page: \(clockedIn ? "Clocked in to \(jobName), elapsed \(elapsedText), activity: \(activityStatus)" : "Not clocked in"). Today: \(todayJobGroups.count) job entries, \(String(format: "%.1f", todayHours))h total."
                    ]
                )
            }
            .onDisappear {
                elapsedTimer?.invalidate(); elapsedTimer = nil
                breakTimer?.invalidate(); breakTimer = nil
                NotificationCenter.default.post(name: .clockPageInactive, object: nil)
            }
            .fullScreenCover(isPresented: $geofenceManager.didExitJobRegion) {
                GeofenceAlertView(
                    geofenceManager: geofenceManager,
                    onResolved: { loadData() }
                )
                .environmentObject(appCore)
                .interactiveDismissDisabled(true)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .questionnaire(let entryId):
                    IOSQuestionnairePage(laborEntryId: entryId, onComplete: { loadData() })
                case .jobScanner:
                    QRScanSheet(expectedType: .job) { result in
                        if let jobId = result.entityId, result.isFound {
                            clockIn(jobId: jobId, isShop: false)
                        }
                    }
                    .environmentObject(appCore)
                case .help:
                    PageHelpSheet(
                        title: "Clock In/Out Help",
                        sections: [
                            ("Clocking In", "Select a job from the GPS-sorted list to clock in. Jobs closest to you appear first. 'Shop / Warehouse' is always pinned at the top."),
                            ("Clocking Out", "When clocked in, tap the Clock Out button. You may be prompted to answer clock-out questions before the entry is saved."),
                            ("Elapsed Timer", "The large timer shows how long you've been on the current job. It updates every minute automatically."),
                            ("Switch Job", "Use the Switch Job button to clock out of the current job and immediately clock into a different one — no need to find the job list again."),
                            ("To-Do Tracking", "After clocking in, you can optionally pick a to-do to track what you're working on. Use 'Mark Done' to complete it and pick the next one."),
                            ("Today's Hours", "The hours breakdown shows your total time per job with optional per-to-do detail. Warranty entries are marked with a 'W' badge."),
                            ("QR Scan", "Use the QR scanner button in the toolbar to scan a job QR code and clock in directly.")
                        ]
                    )
                case .todoPicker:
                    TodoPickerSheet(todos: activeTodos) { todo in
                        selectTodo(todo)
                        activeSheet = nil
                    }
                case .switchJobPicker:
                    SwitchJobPickerSheet(
                        currentJobName: activeEntry?.jobName ?? "current job",
                        jobs: sortedJobs,
                        isSwitching: isSwitchingJob
                    ) { job in
                        Task { await switchToJob(job) }
                    }
                    .environmentObject(appCore)
                case .lunchUnpaidPrompt:
                    LunchUnpaidPromptSheet(
                        onContinueUnpaid: {
                            Task { await continueUnpaidLunch() }
                        },
                        onEndLunch: {
                            activeSheet = nil
                            showLunchUnpaidPrompt = false
                            Task { await endCurrentBreak() }
                        }
                    )
                case .breakStatePicker:
                    BreakStatePickerSheet(
                        isOnSupplyRun: activityStatus == "supply_run",
                        onStartTimedState: { option, minutes in
                            activeSheet = nil
                            guard let entryId = activeEntry?.id else { return }
                            Task {
                                switch option {
                                case .paidBreak:
                                    await startPaidBreak(entryId: entryId, minutes: minutes)
                                case .paidLunch:
                                    await startLunchBreak(entryId: entryId, minutes: minutes)
                                case .unpaidLunch:
                                    await startUnpaidLunch(entryId: entryId, minutes: minutes)
                                }
                            }
                        },
                        onToggleSupplyRun: {
                            activeSheet = nil
                            guard let entryId = activeEntry?.id else { return }
                            Task { await toggleSupplyRun(entryId: entryId) }
                        }
                    )
                }
            }
            .alert("Join Job?", isPresented: $showSelfAssignConfirmation) {
                Button("Assign & Clock In") {
                    Task { await selfAssignAndClockIn() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Assign yourself to \(selectedFlexJob?.name ?? "this job") and clock in?")
            }
            .alert("Location Permission Required", isPresented: $showLocationDeniedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Location is required for clock in/out. Please enable it in Settings \u{2192} Privacy & Security \u{2192} Location Services.")
            }
            .alert("You Are Already Clocked In", isPresented: $showAlreadyClockedInAlert) {
                Button("Clock Out Previous Entry", role: .destructive) {
                    clockOutDanglingAndRetry()
                }
                Button("Cancel", role: .cancel) {
                    pendingClockInJobId = nil
                    pendingClockInIsShop = false
                }
            } message: {
                Text("You have an active clock entry for \(danglingEntryJobName ?? "a previous job"). Would you like to clock out of it first?")
            }
            .alert("Unexpected Clock State", isPresented: $showNotClockedInAlert) {
                Button("Refresh") { loadData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The clock state is out of sync. Tap Refresh to reload.")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var clockContent: some View {
        if isLoading {
            ProgressView("Loading clock status...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                FirstVisitHint(pageId: "clock", message: "Tap a job to clock in. Use the GPS-sorted list to find nearby jobs quickly.")

                OnboardingBanner(pageId: "dashboard-clock")

                SkippedModuleHint(moduleId: "clock")

                // Error banner — prominent, top-of-view, dismissable
                if let errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.white)
                                .accessibilityHidden(true)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                self.errorMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss error")
                        }
                        .padding(10)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }

                // Location permission banners
                if needsLocationPermission && activeEntry == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Location Required")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("This company requires GPS check-in for clock entries.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.orange)
                            }

                            Button {
                                locationManager.requestPermission()
                            } label: {
                                Label("Allow Location Access", systemImage: "location.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.regular)
                        }
                        .padding(.vertical, 4)
                    }
                } else if locationManager.permissionDenied && activeEntry == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Location Access Denied")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("Go to Settings to allow location access for clock-in.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "location.slash.fill")
                                    .foregroundStyle(.red)
                            }

                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gear")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.regular)
                        }
                        .padding(.vertical, 4)
                    }
                }

                StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)

                if let entry = activeEntry {
                    // CLOCKED IN — show status + clock out button
                    clockRecoverySection(entry)
                    clockedInSection(entry)
                    currentTaskSection(entry)
                    shopJobLinkSection
                    todayHoursSection
                } else {
                    // NOT CLOCKED IN — show inline job picker
                    jobPickerSection
                    flexPoolSection
                    todayHoursSection
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Clocked-In Section

    private func clockedInSection(_ entry: JobsService.LaborEntryRow) -> some View {
        Section("Current Status") {
            VStack(alignment: .leading, spacing: 8) {
                // Status label
                Label(statusLabel, systemImage: statusIcon)
                    .font(.headline)
                    .foregroundStyle(statusColor)

                // Live elapsed timer — large, readable display
                VStack(spacing: 2) {
                    Text(elapsedText)
                        .font(.system(.largeTitle, design: .rounded)).bold()
                        .monospacedDigit()
                    Text("Job: \(entry.jobName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                HStack {
                    Text("Since:")
                        .foregroundStyle(.secondary)
                    Text(formatTime(entry.clockIn))
                        .font(.system(.subheadline, design: .monospaced))
                }
                Label("Saved on this device · waiting to sync", systemImage: "icloud.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)

                if let supplyRunStart = activeSupplyRunStartedAt, activityStatus == "supply_run" {
                    activeSupplyRunCard(startedAt: supplyRunStart)
                }

                // Active break/lunch indicator
                if let breakRecord = activeBreakRecord {
                    activeBreakBanner(breakRecord)
                }

                // Clock Out + Switch Job (disabled during active break)
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        pendingClockOutEntryId = entry.id
                        showClockOutConfirmation = true
                    } label: {
                        Label("Clock Out", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .actionRing(.red)
                    .disabled(activeBreakRecord != nil)
                    .opacity(activeBreakRecord != nil ? 0.4 : 1.0)
                    .accessibilityLabel("Clock Out — action required")
                    .confirmationDialog("Clock Out?", isPresented: $showClockOutConfirmation, titleVisibility: .visible) {
                        Button("Clock Out", role: .destructive) {
                            if let entryId = pendingClockOutEntryId {
                                clockOut(entryId: entryId)
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("You'll be prompted to answer clock-out questions.")
                    }

                    Button {
                        switchJob(entryId: entry.id)
                    } label: {
                        Label("Switch Job", systemImage: "arrow.triangle.swap")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(activeBreakRecord != nil)
                    .opacity(activeBreakRecord != nil ? 0.4 : 1.0)
                }
                .padding(.top, 4)

                // Break explanation when clock out is disabled
                if activeBreakRecord != nil {
                    Label("End your break before switching jobs or clocking out.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Divider()

                // Lunch / Break / Supply Run buttons
                if activeBreakRecord != nil {
                    // Show end break button when on break — prominent orange to draw attention
                    Button {
                        Task { await endCurrentBreak() }
                    } label: {
                        Label(activeBreakRecord?.breakType == "lunch_unpaid" ? "Resume Work" : "End \(activeBreakRecord?.breakType == "break" ? "Break" : "Lunch")",
                              systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                } else {
                    Button {
                        activeSheet = .breakStatePicker
                    } label: {
                        Label(
                            activityStatus == "supply_run" ? "Break / Lunch / End Supply Run" : "Break / Lunch / Supply Run",
                            systemImage: activityStatus == "supply_run" ? "checkmark.circle" : "timer"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(activityStatus == "supply_run" ? .green : .orange)
                    .controlSize(.large)
                    .accessibilityLabel("Open break, lunch, and supply run state picker")
                    .accessibilityHint("Choose paid break, paid lunch, unpaid lunch, or supply run with duration options.")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Status Helpers

    private var statusLabel: String {
        switch activityStatus {
        case "supply_run": return "On Supply Run"
        case "break": return "On Paid Break"
        case "lunch_paid": return "On Paid Lunch"
        case "lunch_unpaid": return "On Unpaid Lunch"
        default: return "Clocked In"
        }
    }

    private var statusIcon: String {
        switch activityStatus {
        case "supply_run": return "car.fill"
        case "break": return "cup.and.saucer.fill"
        case "lunch_paid", "lunch_unpaid": return "fork.knife"
        default: return "clock.fill"
        }
    }

    private var statusColor: Color {
        switch activityStatus {
        case "supply_run": return .orange
        case "break": return .purple
        case "lunch_paid": return .blue
        case "lunch_unpaid": return .red
        default: return .green
        }
    }

    // MARK: - Active Break Banner

    private func activeSupplyRunCard(startedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Supply Run Active", systemImage: "car.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatClockTime(startedAt))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(supplyRunElapsedText)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
            }

            Text("You stay clocked in and billable while this supply run is active.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Supply Run Active. Started \(formatClockTime(startedAt)). Duration \(supplyRunElapsedText). You stay clocked in and billable while this supply run is active.")
        .accessibilityIdentifier("clock-active-supply-run-card")
    }

    private func activeBreakBanner(_ breakRecord: BreakRecord) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: breakRecord.breakType == "break" ? "cup.and.saucer.fill" : "fork.knife")
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text(activeBreakTitle(breakRecord))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
                Text(breakElapsedText)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            // Budget bar
            if breakRecord.breakType == "break" {
                let budget = activeBreakTargetMinutes(breakRecord)
                let elapsed = breakElapsedMinutes(breakRecord)
                let progress = min(1.0, Double(elapsed) / Double(max(1, budget)))
                ProgressView(value: progress)
                    .tint(progress >= 1.0 ? .red : .white)
                Text("\(elapsed)/\(budget) min")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            } else if breakRecord.breakType == "lunch_paid" {
                let paidMin = activeBreakTargetMinutes(breakRecord)
                let elapsed = breakElapsedMinutes(breakRecord)
                let progress = min(1.0, Double(elapsed) / Double(max(1, paidMin)))
                ProgressView(value: progress)
                    .tint(progress >= 1.0 ? .red : .white)
                if elapsed < paidMin {
                    Text("\(elapsed)/\(paidMin) min paid")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("Paid portion complete — \(elapsed - paidMin) min unpaid")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            } else {
                Text("\(breakElapsedText) unpaid lunch")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Timer paused for unpaid lunch. Resume work to continue this job.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(activeBreakColor(breakRecord))
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func clockRecoverySection(_ entry: JobsService.LaborEntryRow) -> some View {
        if showRecoveredTimerBanner && !recoveredBannerDismissed {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Active timer recovered", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text("You are still clocked into \(entry.jobName) since \(formatTime(entry.clockIn)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Active timer recovered. You are still clocked into \(entry.jobName) since \(formatTime(entry.clockIn)).")
                    HStack {
                        Button {
                            recoveredBannerDismissed = true
                        } label: {
                            Label("Continue Timer", systemImage: "play.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Continue Timer")
                        .accessibilityHint("Dismisses the recovered timer banner and keeps the active timer running.")
                        .accessibilityIdentifier("clock-recovered-continue-timer-button")

                        Button(role: .destructive) {
                            pendingClockOutEntryId = entry.id
                            showClockOutConfirmation = true
                        } label: {
                            Label("Clock Out", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Clock Out")
                        .accessibilityHint("Opens confirmation to clock out of \(entry.jobName).")
                        .accessibilityIdentifier("clock-recovered-clock-out-button")
                    }
                }
            }
        }
    }

    private func activeBreakTitle(_ record: BreakRecord) -> String {
        switch record.breakType {
        case "break": return "Paid Break"
        case "lunch_unpaid": return "Unpaid Lunch"
        default: return "Paid Lunch"
        }
    }

    private func activeBreakColor(_ record: BreakRecord) -> Color {
        switch record.breakType {
        case "break": return .purple
        case "lunch_unpaid": return .red
        default: return .blue
        }
    }

    private func breakElapsedMinutes(_ record: BreakRecord) -> Int {
        let formatter = Formatters.iso8601Fractional
        let basic = Formatters.iso8601Basic
        let local = Formatters.localDateTimeFormatter

        guard let start = formatter.date(from: record.startedAt)
                ?? basic.date(from: record.startedAt)
                ?? local.date(from: record.startedAt) else { return 0 }
        return Int(Date().timeIntervalSince(start) / 60)
    }

    // MARK: - Job Picker (inline, no sheet)

    /// Whether clock-in buttons should be disabled (no location permission).
    private var clockInDisabled: Bool {
        needsLocationPermission || locationManager.permissionDenied
    }

    @ViewBuilder
    private var jobPickerSection: some View {
        Section {
            // Shop / Warehouse — always first, pinned
            Button {
                clockIn(jobId: nil, isShop: true)
            } label: {
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "building.fill")
                        .font(.title3)
                        .foregroundStyle(clockInDisabled ? .gray : .blue)
                        .frame(width: 40, height: 40)
                        .background((clockInDisabled ? Color.gray : Color.blue).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shop / Warehouse")
                            .font(.body)
                            .fontWeight(.semibold)
                        Text("Office, ordering, design work")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "clock.badge.checkmark.fill")
                        .foregroundStyle(clockInDisabled ? .gray : .green)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(clockInDisabled)
            .opacity(clockInDisabled ? 0.5 : 1.0)
        } header: {
            Text("Clock In To")
        }

        // Active Jobs sorted by distance
        if !sortedJobs.isEmpty {
            Section {
                ForEach(sortedJobs) { job in
                    Button {
                        clockIn(jobId: job.id, isShop: false)
                    } label: {
                        HStack(spacing: DS.Space.md) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .frame(width: 40, height: 40)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.jobName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                HStack(spacing: 8) {
                                    if !job.jobNumber.isEmpty {
                                        Text("#\(job.jobNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let addr = job.address, !addr.isEmpty {
                                        Text(addr)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            if !job.distanceText.isEmpty {
                                Text(job.distanceText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(
                                        (job.distanceMiles ?? 999) < 1 ? .green : .secondary
                                    )
                            }

                            Image(systemName: "clock.badge.checkmark.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(clockInDisabled)
                    .opacity(clockInDisabled ? 0.5 : 1.0)
                }
            } header: {
                HStack {
                    Text("Job Sites")
                    Spacer()
                    if userLocation != nil {
                        Label("Sorted by distance", systemImage: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Flex Pool Section

    /// Shows available jobs for self-assignment when the worker has no dispatch today.
    @ViewBuilder
    private var flexPoolSection: some View {
        if !hasDispatchToday && activeEntry == nil {
            Section {
                if flexPoolJobs.isEmpty {
                    Label {
                        Text("No available jobs for today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(flexPoolJobs) { job in
                        Button {
                            selectedFlexJob = (job.id, job.jobName)
                            showSelfAssignConfirmation = true
                        } label: {
                            HStack(spacing: DS.Space.md) {
                                Image(systemName: "briefcase.fill")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                    .frame(width: 40, height: 40)
                                    .background(Color.green.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.jobName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    if !job.jobNumber.isEmpty {
                                        Text("#\(job.jobNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                ActionDot(isOverdue: false)

                                Text("Join")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("Flex Pool")
                    Spacer()
                    Label("No dispatch today", systemImage: "person.badge.clock")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Shop Job Link

    @ViewBuilder
    private var shopJobLinkSection: some View {
        if isShopClockIn {
            Section {
                DisclosureGroup("Link time to a job (optional)") {
                    if let linkedName = linkedJobName {
                        // Currently linked
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text("Linked to: \(linkedName)")
                                .font(.subheadline)
                            Spacer()
                            Button("End Link") {
                                endJobLink()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.vertical, 4)

                        Button("Change Job") {
                            linkedJobId = nil
                            linkedJobName = nil
                        }
                        .font(.caption)
                    } else {
                        // Not linked — show job list
                        ForEach(sortedJobs) { job in
                            Button {
                                startJobLink(jobId: job.id, jobName: job.jobName)
                            } label: {
                                HStack {
                                    Text(job.jobName)
                                        .font(.subheadline)
                                    if !job.distanceText.isEmpty {
                                        Spacer()
                                        Text(job.distanceText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Job Link")
            }
        }
    }

    // MARK: - Today's Hours (Per-Job + Per-Todo Breakdown)

    private var todayHoursSection: some View {
        Section {
            if todayJobGroups.isEmpty {
                Text("No hours logged today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Per-job breakdown
                ForEach(todayJobGroups) { jobGroup in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(jobGroup.jobName).font(.headline)
                            Spacer()
                            Text(formatDuration(jobGroup.totalDuration))
                                .font(.headline).monospacedDigit()
                        }
                        // Per-entry breakdown within job (shows to-do if linked)
                        ForEach(jobGroup.entries) { entry in
                            HStack {
                                if let todo = entry.todoName {
                                    Text("  \(todo)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("  General")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                if entry.workType == "warranty" {
                                    Text("W")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text(formatDuration(entry.duration))
                                    .font(.caption).monospacedDigit()
                                    .foregroundStyle(.secondary)
                                statusDot(entry.endTime == nil)
                            }
                        }
                    }
                }

                // Total
                HStack {
                    Text("Today Total").font(.headline).bold()
                    Spacer()
                    Text(formatDuration(todaysTotal))
                        .font(.headline).bold().monospacedDigit()
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Today's Hours")
        }
    }

    /// Total duration across all today's entries.
    private var todaysTotal: TimeInterval {
        todayJobGroups.reduce(0) { $0 + $1.totalDuration }
    }

    // MARK: - Status Dot

    private func statusDot(_ isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
            .accessibilityLabel(isActive ? "Status: active" : "Status: completed")
    }

    // MARK: - Current Task Section

    @ViewBuilder
    private func currentTaskSection(_ entry: JobsService.LaborEntryRow) -> some View {
        // Only show if this job has to-dos
        if !activeTodos.isEmpty || currentTodo != nil {
            Section {
                // Work type picker
                Picker("Work Type", selection: $workType) {
                    Text("New Work").tag("new_work")
                    Text("Warranty").tag("warranty")
                }
                .pickerStyle(.segmented)
                .onChange(of: workType) { _, newValue in
                    guard let service = appCore.jobsService else {
                        errorMessage = "Service not available"
                        return
                    }
                    do {
                        try service.setClockEntryWorkType(clockEntryId: entry.id, workType: newValue)
                    } catch {
                        errorMessage = userFriendlyError(error, context: "update work type")
                    }
                }

                if let todo = currentTodo {
                    // Current to-do display
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(todo.title)
                                    .font(.headline)
                                Text("Working on this")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task { await markTodoDoneAndPickNext(entry: entry) }
                            } label: {
                                Label("Mark Done", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)

                            Button {
                                activeSheet = .todoPicker
                            } label: {
                                Label("Switch", systemImage: "arrow.triangle.swap")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else {
                    // No to-do selected
                    Button {
                        activeSheet = .todoPicker
                    } label: {
                        Label("Pick a To-Do", systemImage: "checklist")
                    }
                }
            } header: {
                Text("Current Task")
            }
        }
    }

    // MARK: - Flex Pool Actions

    /// Check if the current user has a dispatch assignment for today.
    /// If not, load the flex pool (active jobs they can self-assign to).
    private func checkDispatchStatus() {
        guard let userId = appCore.currentUser?.id else { return }

        let today = Formatters.localDateFormatter.string(from: Date())

        // Check for dispatch entries via SchedulingService
        if let schedulingService = appCore.schedulingService {
            do {
                let dispatches = try schedulingService.getMySchedule(
                    userId: userId,
                    startDate: today,
                    endDate: today
                )
                hasDispatchToday = !dispatches.isEmpty
            } catch {
                // If table doesn't exist or other error, assume no dispatch
                hasDispatchToday = false
            }
        } else {
            // Scheduling service unavailable — assume no dispatch
            hasDispatchToday = false
        }

        // If no dispatch today, load flex pool jobs
        if !hasDispatchToday {
            if let jobsService = appCore.jobsService {
                do {
                    flexPoolJobs = try jobsService.listActiveJobsForClock()
                } catch {
                    flexPoolJobs = []
                }
            } else {
                flexPoolJobs = []
            }
        } else {
            flexPoolJobs = []
        }
    }

    /// Self-assign the user to the selected flex pool job and clock in.
    private func selfAssignAndClockIn() async {
        guard let flexJob = selectedFlexJob,
              let userId = appCore.currentUser?.id else {
            await MainActor.run {
                errorMessage = "Not logged in"
            }
            return
        }

        let today = Formatters.localDateFormatter.string(from: Date())

        // Create a dispatch entry so the assignment is tracked
        if let schedulingService = appCore.schedulingService {
            do {
                try schedulingService.createDispatch(
                    jobId: flexJob.id,
                    userId: userId,
                    date: today,
                    notes: "Self-assigned from Flex Pool"
                )
            } catch {
                // Non-fatal: clock-in still works even if dispatch creation fails.
                // Show a subtle warning so the dispatcher knows.
                await MainActor.run {
                    errorMessage = "Clocked in, but dispatch record could not be created."
                }
            }
        }

        // Clock in to the selected job
        await MainActor.run {
            clockIn(jobId: flexJob.id, isShop: false)
        }
    }

    // MARK: - Actions

    private func clockIn(jobId: Int64?, isShop: Bool) {
        // Check location permission before attempting clock-in
        if needsLocationPermission {
            logger.warning("ClockIn blocked — location permission not determined yet")
            locationManager.requestPermission()
            return
        }
        if locationManager.permissionDenied {
            logger.warning("ClockIn blocked — location permission denied")
            showLocationDeniedAlert = true
            return
        }

        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Not logged in"
            return
        }

        logger.info("ClockIn tapped — permissionStatus=\(self.locationManager.authorizationStatus.rawValue) userId=\(userId) jobId=\(jobId ?? -1) isShop=\(isShop)")

        Task {
            let location = await locationManager.getCurrentLocation()
            let lat = location?.coordinate.latitude
            let lng = location?.coordinate.longitude
            logger.info("GPS result: lat=\(lat ?? 0) lng=\(lng ?? 0)")

            do {
                // Check payment hold before allowing clock-in
                if !isShop, let jid = jobId {
                    let isHeld = try service.isJobOnPaymentHold(jobId: jid)
                    if isHeld {
                        errorMessage = "This job is on payment hold. Contact your manager."
                        return
                    }
                }

                logger.info("Calling service.clockIn(userId: \(userId), jobId: \(jobId ?? 0))")

                if isShop {
                    // Clock in to Shop/Warehouse through the internal warehouse time bucket.
                    try service.clockInToWarehouse(userId: userId, gpsLat: lat, gpsLng: lng)
                    isShopClockIn = true
                    geofenceManager.stopMonitoring()
                } else if let jid = jobId {
                    try service.clockIn(userId: userId, jobId: jid, gpsLat: lat, gpsLng: lng)
                    isShopClockIn = false
                    // Start geofence monitoring if job has coordinates
                    if let job = sortedJobs.first(where: { $0.id == jid }),
                       let jobLat = job.latitude, let jobLng = job.longitude,
                       jobLat != 0, jobLng != 0 {
                        geofenceManager.startMonitoring(jobId: jid, jobName: job.jobName, latitude: jobLat, longitude: jobLng)
                    }
                }
                logger.info("ClockIn success")
                errorMessage = nil
                appCore.onboardingManager?.markCompleted("clock-in")
                loadData()
            } catch let error as JobsService.JobsError {
                switch error {
                case .alreadyClockedIn(_, _):
                    logger.warning("ClockIn error: alreadyClockedIn — showing recovery alert")
                    // Find the active entry to show the job name
                    let activeJobName = try? service.getActiveClockEntry(userId: userId)?.jobName
                    danglingEntryJobName = activeJobName
                    pendingClockInJobId = jobId
                    pendingClockInIsShop = isShop
                    showAlreadyClockedInAlert = true
                case .notClockedIn(_):
                    logger.warning("ClockIn got notClockedIn unexpectedly — showing refresh alert")
                    showNotClockedInAlert = true
                default:
                    logger.error("ClockIn JobsError: \(error)")
                    errorMessage = userFriendlyError(error, context: "clock in")
                }
            } catch {
                logger.error("ClockIn error: \(error.localizedDescription)")
                errorMessage = userFriendlyError(error, context: "clock in")
            }
        }
    }

    /// Clock out the dangling entry and retry the pending clock-in.
    private func clockOutDanglingAndRetry() {
        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Not logged in"
            return
        }

        logger.info("Clocking out dangling entry for userId=\(userId)")

        Task {
            let location = await locationManager.getCurrentLocation()

            do {
                // Find and clock out the active entry
                guard let active = try service.getActiveClockEntry(userId: userId) else {
                    logger.warning("No active entry found — refreshing")
                    loadData()
                    return
                }
                _ = try service.clockOut(
                    laborEntryId: active.id,
                    gpsLat: location?.coordinate.latitude,
                    gpsLng: location?.coordinate.longitude
                )
                geofenceManager.stopMonitoring()
                logger.info("Dangling entry clocked out — retrying clock-in")

                // Brief pause then retry the original clock-in
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    clockIn(jobId: pendingClockInJobId, isShop: pendingClockInIsShop)
                    pendingClockInJobId = nil
                    pendingClockInIsShop = false
                }
            } catch {
                logger.error("ClockOut dangling error: \(error.localizedDescription)")
                errorMessage = userFriendlyError(error, context: "clock out previous entry")
            }
        }
    }

    private func clockOut(entryId: Int64) {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }

        Task {
            let location = await locationManager.getCurrentLocation()

            do {
                try service.clockOut(
                    laborEntryId: entryId,
                    gpsLat: location?.coordinate.latitude,
                    gpsLng: location?.coordinate.longitude
                )
                geofenceManager.stopMonitoring()
                errorMessage = nil
                linkedJobId = nil
                linkedJobName = nil
                isShopClockIn = false
                lastLaborEntryId = entryId
                appCore.onboardingManager?.markCompleted("clock-out")
                activeSheet = .questionnaire(entryId)
                loadData()
            } catch {
                errorMessage = userFriendlyError(error, context: "clock out")
            }
        }
    }

    /// Start a paid break — stays clocked in, starts break timer.
    private func startPaidBreak(entryId: Int64, minutes: Int = 15) async {
        guard let breakSvc = appCore.breakService,
              let userId = appCore.currentUser?.id else {
            await MainActor.run { errorMessage = "Break service unavailable" }
            return
        }

        do {
            let record = try breakSvc.startBreak(
                userId: userId,
                breakType: "break",
                laborEntryId: entryId,
                timerMinutes: minutes
            )
            await MainActor.run {
                activeBreakRecord = record
                activityStatus = "break"
                breakBudgetMinutes = minutes
                errorMessage = nil
                appCore.onboardingManager?.markCompleted("clock-break")
                startBreakTimer()
                scheduleBreakNotifications(for: record, durationMinutes: minutes)
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "start break")
            }
        }
    }

    /// Start a lunch — first portion is paid, after paid portion prompts for unpaid.
    private func startLunchBreak(entryId: Int64, minutes: Int? = nil) async {
        guard let breakSvc = appCore.breakService,
              let userId = appCore.currentUser?.id else {
            await MainActor.run { errorMessage = "Break service unavailable" }
            return
        }

        do {
            let settings = try breakSvc.getCompanyBreakSettings()
            let policies = try breakSvc.getBreakPolicy(stateCode: settings.stateCode)
            let lunchPolicy = policies.first { $0.policyType == "state_required_paid" }
            let paidMin = minutes ?? lunchPolicy?.lunchMinutes ?? 30

            let record = try breakSvc.startBreak(
                userId: userId,
                breakType: "lunch_paid",
                laborEntryId: entryId,
                timerMinutes: paidMin
            )
            await MainActor.run {
                activeBreakRecord = record
                activityStatus = "lunch_paid"
                lunchPaidMinutes = paidMin
                errorMessage = nil
                startBreakTimer()
                scheduleBreakNotifications(for: record, durationMinutes: paidMin)
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "start lunch")
            }
        }
    }

    /// Start an unpaid lunch directly. It remains anchored to the active labor entry.
    private func startUnpaidLunch(entryId: Int64, minutes: Int? = nil) async {
        guard let breakSvc = appCore.breakService,
              let userId = appCore.currentUser?.id else {
            await MainActor.run { errorMessage = "Break service unavailable" }
            return
        }

        do {
            let record = try breakSvc.startBreak(
                userId: userId,
                breakType: "lunch_unpaid",
                laborEntryId: entryId,
                timerMinutes: minutes
            )
            await MainActor.run {
                activeBreakRecord = record
                activityStatus = "lunch_unpaid"
                if let minutes { lunchPaidMinutes = minutes }
                errorMessage = nil
                startBreakTimer()
                if let minutes { scheduleBreakNotifications(for: record, durationMinutes: minutes) }
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "start unpaid lunch")
            }
        }
    }

    /// Close paid lunch and continue the same active labor entry on unpaid lunch.
    private func continueUnpaidLunch() async {
        guard let breakSvc = appCore.breakService,
              let userId = appCore.currentUser?.id,
              let entryId = activeEntry?.id else {
            await MainActor.run { errorMessage = "Break service unavailable" }
            return
        }

        do {
            if let paidRecord = activeBreakRecord, let paidRecordId = paidRecord.id {
                try breakSvc.endBreak(recordId: paidRecordId)
                cancelBreakNotifications(for: paidRecord)
            }
            let unpaidRecord = try breakSvc.startBreak(
                userId: userId,
                breakType: "lunch_unpaid",
                laborEntryId: entryId,
                timerMinutes: nil
            )
            await MainActor.run {
                activeSheet = nil
                showLunchUnpaidPrompt = false
                activeBreakRecord = unpaidRecord
                activityStatus = "lunch_unpaid"
                errorMessage = nil
                startBreakTimer()
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "continue unpaid lunch")
            }
        }
    }

    /// End the currently active break/lunch.
    private func endCurrentBreak() async {
        guard let breakSvc = appCore.breakService,
              let record = activeBreakRecord,
              let recordId = record.id else {
            errorMessage = "Break service not available"
            return
        }

        do {
            try breakSvc.endBreak(recordId: recordId)
            cancelBreakNotifications(for: record)
            await MainActor.run {
                breakTimer?.invalidate()
                breakTimer = nil
                activeBreakRecord = nil
                activityStatus = "working"
                activeSupplyRunStartedAt = nil
                supplyRunElapsedText = ""
                breakElapsedText = ""
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "end break")
            }
        }
    }

    // MARK: - Break Timer

    private func activeBreakTargetMinutes(_ record: BreakRecord) -> Int {
        if let timer = record.timerDurationMinutes, timer > 0 { return timer }
        switch record.breakType {
        case "break": return breakBudgetMinutes
        case "lunch_paid", "lunch_unpaid": return lunchPaidMinutes
        default: return breakBudgetMinutes
        }
    }

    private func scheduleBreakNotifications(for record: BreakRecord, durationMinutes: Int) {
        guard durationMinutes > 0 else { return }
        let title = activeBreakTitle(record)
        let fiveMinuteIdentifier = breakNotificationIdentifier(record, suffix: "five-minute")
        let timeReachedIdentifier = breakNotificationIdentifier(record, suffix: "time-reached")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            var requests: [UNNotificationRequest] = []

            if durationMinutes > 5 {
                let content = UNMutableNotificationContent()
                content.title = "\(title): 5 min remaining"
                content.body = "Wrap up and head back when this timer ends."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval((durationMinutes - 5) * 60), repeats: false)
                requests.append(UNNotificationRequest(identifier: fiveMinuteIdentifier, content: content, trigger: trigger))
            }

            let endContent = UNMutableNotificationContent()
            endContent.title = "\(title): \(durationMinutes) min reached"
            endContent.body = record.breakType == "lunch_paid" ? "Paid lunch is complete. Continue unpaid lunch or resume work." : "Your timer is complete."
            endContent.sound = .default
            let endTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(durationMinutes * 60), repeats: false)
            requests.append(UNNotificationRequest(identifier: timeReachedIdentifier, content: endContent, trigger: endTrigger))

            for request in requests {
                UNUserNotificationCenter.current().add(request) { error in
                    if let error {
                        logger.error("Failed to schedule break notification \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    private func cancelBreakNotifications(for record: BreakRecord) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            breakNotificationIdentifier(record, suffix: "five-minute"),
            breakNotificationIdentifier(record, suffix: "time-reached")
        ])
    }

    private func breakNotificationIdentifier(_ record: BreakRecord, suffix: String) -> String {
        "clock-break-\(record.id ?? record.laborEntryId ?? 0)-\(record.breakType)-\(suffix)"
    }

    private func startBreakTimer() {
        breakTimer?.invalidate()
        updateBreakElapsedText()
        breakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                updateBreakElapsedText()
                checkBreakBudget()
            }
        }
    }

    private func updateBreakElapsedText() {
        guard let record = activeBreakRecord else {
            breakElapsedText = ""
            return
        }
        let elapsed = breakElapsedMinutes(record)
        let seconds = breakElapsedSeconds(record) % 60
        breakElapsedText = String(format: "%d:%02d", elapsed, seconds)
    }

    private func breakElapsedSeconds(_ record: BreakRecord) -> Int {
        let formatter = Formatters.iso8601Fractional
        let basic = Formatters.iso8601Basic
        let local = Formatters.localDateTimeFormatter

        guard let start = formatter.date(from: record.startedAt)
                ?? basic.date(from: record.startedAt)
                ?? local.date(from: record.startedAt) else { return 0 }
        return Int(Date().timeIntervalSince(start))
    }

    private func checkBreakBudget() {
        guard let record = activeBreakRecord else { return }
        let elapsed = breakElapsedMinutes(record)

        let target = activeBreakTargetMinutes(record)
        if record.breakType == "break" && elapsed >= target {
            // Auto-end break at budget limit
            Task { await endCurrentBreak() }
        } else if record.breakType == "lunch_paid" && elapsed >= target {
            // Paid lunch portion complete — prompt for unpaid continuation
            if !showLunchUnpaidPrompt {
                showLunchUnpaidPrompt = true
                activeSheet = .lunchUnpaidPrompt
            }
        }
    }

    /// Toggle supply run status — keeps the user clocked in, changes activity status.
    private func toggleSupplyRun(entryId: Int64) async {
        guard let service = appCore.jobsService else {
            await MainActor.run { errorMessage = "Service not available" }
            return
        }

        do {
            let newStatus = try service.toggleSupplyRun(laborEntryId: entryId)
            let notes = try? service.getLaborEntryNotes(laborEntryId: entryId)
            let supplyRunStart = JobsService.activeSupplyRunStart(notes: notes)
            await MainActor.run {
                activityStatus = newStatus
                activeSupplyRunStartedAt = newStatus == "supply_run" ? supplyRunStart : nil
                updateSupplyRunElapsedText()
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "toggle supply run")
            }
        }
    }

    private func startJobLink(jobId: Int64, jobName: String) {
        linkedJobId = jobId
        linkedJobName = jobName
    }

    private func endJobLink() {
        linkedJobId = nil
        linkedJobName = nil
    }

    // MARK: - Switch Job

    /// Open the atomic job switch picker. The current entry remains active until confirmation.
    private func switchJob(entryId: Int64) {
        activeSheet = .switchJobPicker
    }

    private func switchToJob(_ job: JobWithDistance) async {
        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else {
            await MainActor.run { errorMessage = "Service not available" }
            return
        }

        await MainActor.run { isSwitchingJob = true }
        let location = await locationManager.getCurrentLocation()

        do {
            if try service.isJobOnPaymentHold(jobId: job.id) {
                await MainActor.run {
                    errorMessage = "This job is on payment hold. Contact your manager."
                    isSwitchingJob = false
                }
                return
            }

            try service.switchClockedInJob(
                userId: userId,
                nextJobId: job.id,
                at: Date(),
                clockOutGpsLat: location?.coordinate.latitude,
                clockOutGpsLng: location?.coordinate.longitude,
                clockInGpsLat: location?.coordinate.latitude,
                clockInGpsLng: location?.coordinate.longitude
            )
            geofenceManager.stopMonitoring()
            if let jobLat = job.latitude, let jobLng = job.longitude, jobLat != 0, jobLng != 0 {
                geofenceManager.startMonitoring(jobId: job.id, jobName: job.jobName, latitude: jobLat, longitude: jobLng)
            }
            await MainActor.run {
                activeSheet = nil
                isSwitchingJob = false
                errorMessage = nil
                linkedJobId = nil
                linkedJobName = nil
                isShopClockIn = false
                currentTodo = nil
                recoveredBannerDismissed = false
            }
            loadData()
        } catch let error as JobsService.JobsError {
            await MainActor.run {
                isSwitchingJob = false
                switch error {
                case .notClockedIn:
                    showNotClockedInAlert = true
                default:
                    errorMessage = "Could not switch jobs. Your current timer is still running. Try again."
                }
            }
        } catch {
            await MainActor.run {
                isSwitchingJob = false
                errorMessage = "Could not switch jobs. Your current timer is still running. Try again."
            }
        }
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer(clockInISO: String) {
        updateElapsedText(clockInISO: clockInISO)
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                updateElapsedText(clockInISO: clockInISO)
                updateSupplyRunElapsedText()
            }
        }
    }

    private func updateElapsedText(clockInISO: String) {
        let isoFormatter = Formatters.iso8601Fractional
        let isoBasic = Formatters.iso8601Basic

        guard let clockInDate = isoFormatter.date(from: clockInISO)
                ?? isoBasic.date(from: clockInISO) else {
            elapsedText = "0h 0m"
            return
        }
        let elapsed = Date().timeIntervalSince(clockInDate)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        elapsedText = "\(hours)h \(minutes)m"
    }

    private func updateSupplyRunElapsedText() {
        guard let activeSupplyRunStartedAt else {
            supplyRunElapsedText = ""
            return
        }
        supplyRunElapsedText = formatDuration(max(0, Date().timeIntervalSince(activeSupplyRunStartedAt)))
    }

    // MARK: - To-Do Actions

    private func selectTodo(_ todo: JobsService.ClockTodoItem) {
        guard let service = appCore.jobsService,
              let entry = activeEntry else {
            errorMessage = "Jobs service not available"
            return
        }
        currentTodo = todo
        do {
            try service.linkClockEntryToTodo(clockEntryId: entry.id, todoId: todo.id)
        } catch {
            logger.warning("linkClockEntryToTodo failed (select): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func markTodoDoneAndPickNext(entry: JobsService.LaborEntryRow) async {
        guard let todo = currentTodo,
              let notebooksService = appCore.notebooksService,
              let jobsService = appCore.jobsService else { return }

        do {
            try notebooksService.completeEntry(entryId: todo.id)
            let remaining = try jobsService.getActiveJobTodos(jobId: entry.jobId)

            await MainActor.run {
                activeTodos = remaining
                currentTodo = nil
                do {
                    try jobsService.linkClockEntryToTodo(clockEntryId: entry.id, todoId: nil)
                } catch {
                    self.logger.warning("linkClockEntryToTodo failed (unlink): \(error.localizedDescription, privacy: .public)")
                }
            }

            if !remaining.isEmpty {
                await MainActor.run {
                    activeSheet = .todoPicker
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "complete to-do")
            }
        }
    }

    private func loadTodosForJob(jobId: Int64) {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }
        do {
            activeTodos = try service.getActiveJobTodos(jobId: jobId)
        } catch {
            activeTodos = []
        }
    }

    // MARK: - Helpers

    private func formatTime(_ iso: String) -> String {
        guard iso.count >= 16 else { return iso }
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(iso.startIndex, offsetBy: 16)
        return String(iso[start..<end])
    }

    private func formatClockTime(_ date: Date) -> String {
        Formatters.timeFormatter.string(from: date)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = activeEntry == nil && todayEntries.isEmpty
        // Don't clear errorMessage here — let it persist until the load
        // succeeds so users can read the error during a refresh attempt.

        Task {
            userLocation = await locationManager.getCurrentLocation()
            await loadJobsAndClockStatus()
        }
    }

    private func loadJobsAndClockStatus() async {
        guard let userId = appCore.currentUser?.id else {
            await MainActor.run {
                isLoading = false
                errorMessage = "Not logged in"
            }
            return
        }

        do {
            guard let service = appCore.jobsService else {
                await MainActor.run {
                    errorMessage = "Service not available"
                    isLoading = false
                }
                return
            }

            // Load active clock entry
            let entry = try service.getActiveClockEntry(userId: userId)

            // Load today's entries
            let entries = try service.listLaborEntries(userId: userId, limit: 50)
            let todayPrefix = Formatters.localDateFormatter.string(from: Date())
            let todayE = entries.filter { $0.clockIn.hasPrefix(String(todayPrefix)) }
            let todayH = todayE.reduce(0.0) { $0 + $1.regularHours + $1.overtimeHours }

            // Load active jobs via JobsService (avoids raw SQL column issues)
            let clockJobs = try service.listActiveJobsForClock()

            // Calculate distances and sort
            let userLoc = userLocation
            var jobsWithDist: [JobWithDistance] = clockJobs.map { job in
                let lat = job.latitude
                let lng = job.longitude
                var dist: Double? = nil

                if let userLoc, let lat, let lng,
                   lat != 0, lng != 0 {
                    let jobLoc = CLLocation(latitude: lat, longitude: lng)
                    dist = userLoc.distance(from: jobLoc) / 1609.34
                }

                return JobWithDistance(
                    id: job.id,
                    jobName: job.jobName,
                    jobNumber: job.jobNumber,
                    address: job.address,
                    latitude: lat,
                    longitude: lng,
                    distanceMiles: dist,
                    status: job.status
                )
            }

            // Sort: jobs with distance first (nearest first), then jobs without distance
            jobsWithDist.sort { a, b in
                switch (a.distanceMiles, b.distanceMiles) {
                case let (ad?, bd?): return ad < bd
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.jobName < b.jobName
                }
            }

            // Check activity status from notes (supply_run tracking)
            var currentActivity = "working"
            var supplyRunStart: Date?
            if let entry {
                let notes = try? service.getLaborEntryNotes(laborEntryId: entry.id)
                if JobsService.isOnSupplyRun(notes: notes) {
                    currentActivity = "supply_run"
                    supplyRunStart = JobsService.activeSupplyRunStart(notes: notes)
                }
            }

            // Load active break record if any
            var currentBreak: BreakRecord?
            let breakBudget = 15
            var lunchPaid = 30
            if let breakSvc = appCore.breakService {
                currentBreak = try? breakSvc.getActiveBreak(userId: userId)
                if let settings = try? breakSvc.getCompanyBreakSettings() {
                    let policies = try? breakSvc.getBreakPolicy(stateCode: settings.stateCode)
                    let lunchPolicy = policies?.first { $0.policyType == "state_required_paid" }
                    lunchPaid = lunchPolicy?.lunchMinutes ?? 30
                }
            }

            // Load to-dos for the active job
            var todos: [JobsService.ClockTodoItem] = []
            var linkedTodo: JobsService.ClockTodoItem?
            var currentWorkType = "new_work"
            if let entry {
                todos = try service.getActiveJobTodos(jobId: entry.jobId)
                currentWorkType = entry.workType ?? "new_work"
                if let todoId = entry.linkedTodoId {
                    linkedTodo = todos.first(where: { $0.id == todoId })
                }
            }

            // Load today's grouped clock entries
            let groups = try service.getTodaysClockEntries(userId: userId)

            await MainActor.run {
                activeEntry = entry
                todayEntries = todayE
                todayHours = todayH
                todayJobGroups = groups
                sortedJobs = jobsWithDist
                activeTodos = todos
                currentTodo = linkedTodo
                workType = currentWorkType
                isLoading = false
                errorMessage = nil  // Clear errors on successful load

                // Apply break state
                activeBreakRecord = currentBreak
                breakBudgetMinutes = breakBudget
                lunchPaidMinutes = lunchPaid
                if let brk = currentBreak {
                    activityStatus = brk.breakType
                    activeSupplyRunStartedAt = nil
                    supplyRunElapsedText = ""
                    if let timer = brk.timerDurationMinutes, timer > 0 {
                        switch brk.breakType {
                        case "break": breakBudgetMinutes = timer
                        case "lunch_paid", "lunch_unpaid": lunchPaidMinutes = timer
                        default: break
                        }
                    }
                    startBreakTimer()
                } else {
                    activityStatus = currentActivity
                    activeSupplyRunStartedAt = supplyRunStart
                    updateSupplyRunElapsedText()
                    breakTimer?.invalidate()
                    breakTimer = nil
                    breakElapsedText = ""
                }

                // Start/stop elapsed timer based on clock-in state
                if let entry {
                    startElapsedTimer(clockInISO: entry.clockIn)
                    if !recoveredBannerDismissed {
                        showRecoveredTimerBanner = true
                    }
                } else {
                    elapsedTimer?.invalidate()
                    elapsedTimer = nil
                    elapsedText = "0h 0m"
                    activeSupplyRunStartedAt = nil
                    supplyRunElapsedText = ""
                    showRecoveredTimerBanner = false
                    recoveredBannerDismissed = false
                }

                // Check if current clock-in is to shop
                if let entry, entry.jobName.lowercased().contains("shop") || entry.jobName.lowercased().contains("warehouse") {
                    isShopClockIn = true
                } else {
                    isShopClockIn = false
                }

                // Check dispatch status and load flex pool if needed
                checkDispatchStatus()
            }
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "update clock")
                isLoading = false
            }
        }
    }
}

// MARK: - Switch Job Picker Sheet

private struct SwitchJobPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentJobName: String
    let jobs: [IOSClockPage.JobWithDistance]
    let isSwitching: Bool
    let onConfirm: (IOSClockPage.JobWithDistance) -> Void
    @State private var selectedJob: IOSClockPage.JobWithDistance?
    @State private var searchText = ""

    private var filteredJobs: [IOSClockPage.JobWithDistance] {
        guard !searchText.isEmpty else { return jobs }
        let query = searchText.lowercased()
        return jobs.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.jobNumber.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Clock out of \(currentJobName) and clock into another job.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Job Sites") {
                    if filteredJobs.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No Jobs Found",
                            message: "No clockable jobs match this search."
                        )
                    } else {
                        ForEach(filteredJobs) { job in
                            Button {
                                selectedJob = job
                            } label: {
                                HStack(spacing: DS.Space.md) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.orange)
                                        .frame(width: 36, height: 36)
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .frame(minWidth: 44, minHeight: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(job.jobName).font(.body).fontWeight(.medium)
                                        HStack(spacing: 8) {
                                            if !job.jobNumber.isEmpty {
                                                Text("#\(job.jobNumber)").font(.caption).foregroundStyle(.secondary)
                                            }
                                            if let address = job.address, !address.isEmpty {
                                                Text(address).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                                            }
                                        }
                                    }
                                    Spacer()
                                    if !job.distanceText.isEmpty {
                                        Text(job.distanceText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Switch Job")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search jobs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                selectedJob.map { "Switch from \(currentJobName) to \($0.jobName)?" } ?? "Switch Job?",
                isPresented: Binding(
                    get: { selectedJob != nil },
                    set: { if !$0 { selectedJob = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Switch Job") {
                    if let selectedJob {
                        onConfirm(selectedJob)
                    }
                }
                .disabled(isSwitching)
                Button("Cancel", role: .cancel) { selectedJob = nil }
            }
        }
    }
}

// MARK: - To-Do Picker Sheet

private struct TodoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let todos: [JobsService.ClockTodoItem]
    let onSelect: (JobsService.ClockTodoItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                if todos.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "No To-Dos",
                        message: "This job has no active to-dos. Add to-dos in the job's notebook."
                    )
                } else {
                    ForEach(todos) { todo in
                        Button {
                            onSelect(todo)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(todo.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let content = todo.content, !content.isEmpty {
                                    Text(content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                if let status = todo.taskStatus, status != "pending" {
                                    Text(status.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("What are you working on?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Break State Picker Sheet

private struct BreakStatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isOnSupplyRun: Bool
    let onStartTimedState: (IOSClockPage.BreakStateOption, Int) -> Void
    let onToggleSupplyRun: () -> Void

    private let durations = [15, 30, 45, 60]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose the field time state before stepping away from the job.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Paid break and paid lunch keep the job clock running. Unpaid lunch is shown as a paused/clocked-out state for audit visibility. Supply runs keep the job clock running and can be ended from this same picker.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Timed break / lunch") {
                    ForEach(IOSClockPage.BreakStateOption.allCases) { option in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(option.title, systemImage: option.icon)
                                .font(.headline)
                            Text(option.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(durations, id: \.self) { minutes in
                                    Button("\(minutes)m") {
                                        onStartTimedState(option, minutes)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityLabel("Start \(option.title) for \(minutes) minutes")
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .opacity(isOnSupplyRun ? 0.45 : 1)
                        .disabled(isOnSupplyRun)
                    }
                }

                Section("Supply run") {
                    Button {
                        onToggleSupplyRun()
                    } label: {
                        Label(isOnSupplyRun ? "End Supply Run" : "Start Supply Run", systemImage: isOnSupplyRun ? "checkmark.circle.fill" : "car.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isOnSupplyRun ? .green : .orange)

                    Text("Supply runs are billable/clocked-in travel for parts or supplies. End the run when you return to normal work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Break / Lunch State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Lunch Unpaid Prompt Sheet

private struct LunchUnpaidPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onContinueUnpaid: () -> Void
    let onEndLunch: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "fork.knife")
                    .decorativeIconFont(48)
                    .foregroundStyle(.blue)

                Text("Paid Lunch Complete")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your paid lunch period has ended. Would you like to continue on an unpaid lunch break, or return to work?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        onContinueUnpaid()
                    } label: {
                        Label("Continue Unpaid Lunch", systemImage: "clock.badge.exclamationmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.orange)

                    Button {
                        onEndLunch()
                    } label: {
                        Label("End Lunch — Back to Work", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Lunch Time")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
