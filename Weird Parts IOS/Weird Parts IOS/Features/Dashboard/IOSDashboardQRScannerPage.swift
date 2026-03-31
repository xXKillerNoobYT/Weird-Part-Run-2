import SwiftUI
import WiredPartCore
#if os(iOS) && !targetEnvironment(macCatalyst)
import VisionKit
#endif

/// Fast continuous QR scanner — camera opens immediately, shows live item info.
///
/// Features:
/// - Camera starts on appear, scans continuously
/// - Info overlay shows the current scanned item (updates as you point at different codes)
/// - Lock button freezes the current scan for details/actions
/// - Quick actions auto-lock the camera until action completes
/// - Last scan remembered if QR goes out of frame
/// - Manual entry fallback below the camera
struct IOSDashboardQRScannerPage: View {
    @EnvironmentObject private var appCore: AppCore

    // Scanner state
    @State private var isScanning = false
    @State private var isLocked = false
    @State private var currentResult: ScanResultData?
    @State private var lastResult: ScanResultData? // Remembered
    @State private var scanError: String?
    @State private var isProcessing = false

    // Location navigation state
    @State private var currentLocationInfo: WarehouseService.LocationScanInfo?
    @State private var directionResult: WarehouseService.DirectionResult?
    @State private var userPositionAreaId: Int64?

    // Manual entry
    @State private var manualCode = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        case scannedDetail
        var id: String {
            switch self {
            case .help: return "help"
            case .scannedDetail: return "scannedDetail"
            }
        }
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @State private var scanner: IOSQRScanner?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "dashboard-scanner")

            #if os(iOS) && !targetEnvironment(macCatalyst)
            if DataScannerViewController.isSupported {
                // Camera viewfinder (top half)
                cameraSection
                    .frame(maxHeight: .infinity)

                // Info overlay + controls (bottom half)
                bottomSection
            } else {
                noCameraFallback
            }
            #else
            noCameraFallback
            #endif
        }
        .background(Color.black)
        .task { appCore.onboardingManager?.markCompleted("scanner-open") }
        .navigationTitle("QR Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "QR Scanner Help",
                    sections: [
                        ("Scanning", "Point the camera at any WiredPart QR code. The scanner runs continuously and shows item info in real time as you scan."),
                        ("Lock & Actions", "Tap the lock button to freeze on a result and see quick actions. Tap Resume Scanning to continue. Quick actions auto-lock the camera."),
                        ("Manual Entry", "No camera? Type or paste a code in the manual entry field below the camera view to look up items directly.")
                    ]
                )
            case .scannedDetail:
                NavigationStack {
                    if let result = currentResult {
                        List {
                            Section("Scanned Item") {
                                LabeledContent("Code", value: result.code)
                                if let type = result.entityType {
                                    LabeledContent("Type", value: type.rawValue.capitalized)
                                }
                                if !result.entityTitle.isEmpty {
                                    LabeledContent("Name", value: result.entityTitle)
                                }
                            }
                            if !result.detailFields.isEmpty {
                                Section("Details") {
                                    ForEach(result.detailFields, id: \.key) { field in
                                        LabeledContent(field.key, value: field.value)
                                    }
                                }
                            }
                            if let locations = result.stockLocations, !locations.isEmpty {
                                Section("Stock Locations") {
                                    ForEach(locations, id: \.label) { loc in
                                        LabeledContent(loc.label, value: "\(loc.qty)")
                                    }
                                }
                            }
                        }
                        .navigationTitle("Item Details")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { activeSheet = nil }
                            }
                        }
                    } else {
                        Text("No scanned item")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            #if os(iOS) && !targetEnvironment(macCatalyst)
            if DataScannerViewController.isSupported {
                startContinuousScanning()
            }
            #endif
            // Load user's last known warehouse position for direction guidance
            if let service = appCore.warehouseService {
                userPositionAreaId = try? service.getUserCurrentPosition(userId: 1)
            }
        }
        .onDisappear {
            #if os(iOS) && !targetEnvironment(macCatalyst)
            scanner?.stopScanning()
            #endif
        }
    }

    // MARK: - Camera Section

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @ViewBuilder
    private var cameraSection: some View {
        ZStack {
            // Camera preview placeholder
            // In production, embed the DataScannerViewController view here
            Rectangle()
                .fill(Color.black)
                .overlay(
                    VStack {
                        if isLocked {
                            HStack {
                                Spacer()
                                Label("Locked", systemImage: "lock.fill")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(.orange))
                                    .padding()
                            }
                        }
                        Spacer()
                    }
                )

            // Scanning frame overlay
            if !isLocked {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 250, height: 250)
            }

            // Processing indicator
            if isProcessing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
    }
    #endif

    // MARK: - Bottom Section (Info + Controls)

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 0) {
            // Result card or empty state
            resultOverlay
                .frame(minHeight: 120)

            Divider()

            // Controls bar
            controlsBar
                .padding(DS.Space.md)

            // Manual entry
            manualEntryBar
                .padding(.horizontal, DS.Space.md)
                .padding(.bottom, DS.Space.md)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Result Overlay

    @ViewBuilder
    private var resultOverlay: some View {
        let displayResult = currentResult ?? lastResult

        if let result = displayResult {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                // Header row
                HStack(spacing: DS.Space.md) {
                    Image(systemName: result.isLocation ? "mappin.circle.fill" : (result.isFound ? "checkmark.circle.fill" : "questionmark.circle.fill"))
                        .font(.title2)
                        .foregroundStyle(result.isLocation ? .blue : (result.isFound ? .green : .orange))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.isFound ? result.entityTitle : "Not Found")
                            .font(.headline)
                            .lineLimit(1)
                        Text(result.isLocation ? "Warehouse Location" : (result.entityType?.rawValue.capitalized ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Lock/Unlock button
                    Button {
                        toggleLock()
                    } label: {
                        Image(systemName: isLocked ? "lock.fill" : "lock.open")
                            .font(.title3)
                            .foregroundStyle(isLocked ? .orange : .secondary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(isLocked
                                    ? Color.orange.opacity(0.15)
                                    : Color(.secondarySystemGroupedBackground))
                            )
                    }
                    .accessibilityLabel(isLocked ? "Unlock scanner" : "Lock scanner")
                }

                // Location contents (warehouse locations)
                if result.isLocation, let locInfo = currentLocationInfo {
                    locationContentsSection(locInfo)
                }

                // Direction guidance
                if let direction = directionResult {
                    directionGuidanceRow(direction)
                }

                // Stock locations (parts)
                if !result.isLocation, result.isFound, let stockLocs = result.stockLocations, !stockLocs.isEmpty {
                    HStack(spacing: DS.Space.md) {
                        ForEach(stockLocs, id: \.label) { loc in
                            VStack(spacing: 2) {
                                Text("\(loc.qty)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                Text(loc.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Detail fields
                if !result.detailFields.isEmpty {
                    HStack(spacing: DS.Space.lg) {
                        ForEach(result.detailFields.prefix(3), id: \.key) { field in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(field.key)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(field.value)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                // Quick actions (only when locked)
                if isLocked && result.isFound {
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.md) {
                            quickActions(for: result)
                        }
                    }
                }
            }
            .padding(DS.Space.md)
        } else if let error = scanError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            .padding(DS.Space.md)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Point camera at a QR code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Space.md)
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: DS.Space.lg) {
            if isLocked {
                Button {
                    unlockAndResume()
                } label: {
                    Label("Resume Scanning", systemImage: "play.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            Spacer()

            if currentResult != nil || lastResult != nil {
                Button {
                    currentResult = nil
                    lastResult = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Manual Entry

    private var manualEntryBar: some View {
        HStack(spacing: DS.Space.sm) {
            TextField("Type code manually...", text: $manualCode)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { processManualCode() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button("Look Up") { processManualCode() }
                .buttonStyle(.bordered)
                .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
        }
    }

    // MARK: - No Camera Fallback

    private var noCameraFallback: some View {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                Image(systemName: "camera.badge.ellipsis")
                    .decorativeIconFont(48)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                    .padding(.top, DS.Space.jumbo)

                Text("Camera not available")
                    .font(.title3)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Manual Entry")
                        .dsStyle(.sectionTitle)

                    HStack(spacing: DS.Space.sm) {
                        TextField("Type or paste code...", text: $manualCode)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { processManualCode() }

                        Button("Look Up") { processManualCode() }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualCode.isEmpty || isProcessing)
                    }
                }
                .padding(.horizontal, DS.Space.lg)

                if currentResult != nil {
                    resultOverlay
                        .dsCard()
                        .padding(.horizontal, DS.Space.lg)
                }
            }
        }
        .background(DS.Background.page)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private func quickActions(for result: ScanResultData) -> some View {
        if result.isLocation {
            DSQuickActionButton(title: "Quick Audit", icon: "checklist", color: .orange) {
                autoLockAction { navigateToModule("warehouse") }
            }
            DSQuickActionButton(title: "Assign Part", icon: "plus.circle", color: .green) {
                autoLockAction { navigateToModule("warehouse") }
            }
            DSQuickActionButton(title: "Floor Plan", icon: "map", color: .blue) {
                autoLockAction { navigateToModule("warehouse") }
            }
        } else {
            switch result.entityType {
            case .part:
                DSQuickActionButton(title: "Move Stock", icon: "arrow.left.arrow.right", color: .orange) {
                    autoLockAction { navigateToModule("warehouse") }
                }
                DSQuickActionButton(title: "View Part", icon: "info.circle", color: .blue) {
                    autoLockAction { navigateToModule("parts") }
                }
            case .tool:
                DSQuickActionButton(title: "Check Status", icon: "wrench.and.screwdriver", color: .blue) {
                    autoLockAction { navigateToModule("tools") }
                }
            case .job:
                DSQuickActionButton(title: "View Job", icon: "hammer", color: .orange) {
                    autoLockAction { navigateToModule("jobs") }
                }
            case .vehicle:
                DSQuickActionButton(title: "View Fleet", icon: "car", color: .green) {
                    autoLockAction { navigateToModule("fleet") }
                }
            default:
                DSQuickActionButton(title: "Details", icon: "info.circle", color: .blue) {
                    autoLockAction { activeSheet = .scannedDetail }
                }
            }
        }

        DSQuickActionButton(title: "Scan Next", icon: "qrcode.viewfinder", color: .purple) {
            unlockAndResume()
        }
    }

    // MARK: - Lock / Unlock

    private func toggleLock() {
        if isLocked {
            unlockAndResume()
        } else {
            isLocked = true
            #if os(iOS) && !targetEnvironment(macCatalyst)
            scanner?.stopScanning()
            #endif
        }
    }

    private func unlockAndResume() {
        isLocked = false
        currentResult = nil
        #if os(iOS) && !targetEnvironment(macCatalyst)
        startContinuousScanning()
        #endif
    }

    private func autoLockAction(_ action: @escaping () -> Void) {
        isLocked = true
        action()
    }

    // MARK: - Continuous Scanning

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func startContinuousScanning() {
        guard !isLocked else { return }
        let newScanner = IOSQRScanner()
        scanner = newScanner

        guard newScanner.isAvailable else {
            scanError = "Camera scanner not available."
            return
        }

        isScanning = true
        scanError = nil

        Task {
            do {
                let stream = try await newScanner.startScanning()
                for await event in stream {
                    guard !isLocked else { continue }

                    switch event {
                    case .detected(let payload, _):
                        // Don't stop scanning — process and update overlay
                        await processCode(payload, autoLock: false)
                    case .error(let msg):
                        scanError = msg
                    case .permissionDenied:
                        scanError = "Camera permission denied. Enable in Settings."
                        isScanning = false
                        return
                    }
                }
            } catch {
                scanError = userFriendlyError(error, context: "scan item")
                isScanning = false
            }
        }
    }
    #endif

    // MARK: - Process Code

    private func processManualCode() {
        let code = manualCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        Task {
            await processCode(code, autoLock: true)
            await MainActor.run { manualCode = "" }
        }
    }

    private func processCode(_ code: String, autoLock: Bool) async {
        guard let dashboardService = appCore.dashboardService else {
            scanError = "Service not available"
            return
        }

        // Skip if we just scanned the same code
        if let current = currentResult, current.code == code { return }

        await MainActor.run {
            isProcessing = true
            scanError = nil
        }

        do {
            // Check if this is a warehouse location code first
            if let locationInfo = try processLocationCode(code) {
                let scanData = ScanResultData(
                    code: code,
                    isFound: true,
                    entityType: .bin,
                    entityId: locationInfo.areaId,
                    entityTitle: locationInfo.fullLocationCode,
                    stockLocations: nil,
                    detailFields: [
                        DetailField(key: "Unit", value: locationInfo.unitName),
                        DetailField(key: "Level", value: locationInfo.levelName),
                        DetailField(key: "Area", value: locationInfo.areaCode)
                    ],
                    isLocation: true
                )

                // Compute directions from user's last known position
                var directions: WarehouseService.DirectionResult?
                if let fromAreaId = userPositionAreaId, let service = appCore.warehouseService {
                    directions = try? service.getDirections(fromAreaId: fromAreaId, toAreaId: locationInfo.areaId)
                }

                // Update user position to this scanned location
                if let service = appCore.warehouseService {
                    try? service.setUserCurrentPosition(userId: 1, areaId: locationInfo.areaId)
                }

                await MainActor.run {
                    currentLocationInfo = locationInfo
                    directionResult = directions
                    userPositionAreaId = locationInfo.areaId
                    currentResult = scanData
                    lastResult = scanData
                    isProcessing = false
                    if autoLock { isLocked = true }
                }
                return
            }

            // Standard QR processing for non-location codes
            let result = try dashboardService.processQRScan(code)

            var stockLocations: [StockLocation]?
            if result.entityType == .part, let partId = result.entityId {
                stockLocations = try loadPartStockLocations(partId: partId)
            }

            let title = buildEntityTitle(result: result)
            let detailFields = buildDetailFields(result: result)

            let scanData = ScanResultData(
                code: code,
                isFound: result.isFound,
                entityType: result.entityType,
                entityId: result.entityId,
                entityTitle: title,
                stockLocations: stockLocations,
                detailFields: detailFields
            )

            await MainActor.run {
                currentLocationInfo = nil
                directionResult = nil
                currentResult = scanData
                lastResult = scanData // Remember it
                isProcessing = false
                if autoLock { isLocked = true }
            }
        } catch {
            await MainActor.run {
                scanError = userFriendlyError(error, context: "scan item")
                isProcessing = false
            }
        }
    }

    // MARK: - Helpers

    private func loadPartStockLocations(partId: Int64) throws -> [StockLocation] {
        guard let service = appCore.warehouseService else {
            scanError = "Warehouse service not available"
            return []
        }
        let stockByType = try service.getPartStockByLocationType(partId: partId)
        return stockByType.map { entry in
            let label = switch entry.locationType {
            case "warehouse": "Warehouse"
            case "pulled", "staging": "Staging"
            case "truck": "Truck"
            case "trailer": "Trailer"
            case "job": "Job Site"
            default: entry.locationType.capitalized
            }
            return StockLocation(label: label, qty: entry.totalQty)
        }
    }

    private func buildEntityTitle(result: QRAutoFillResult) -> String {
        guard result.isFound else { return "Unknown" }
        let fields = result.fields
        switch result.entityType {
        case .part: return fields["name"] ?? fields["code"] ?? "Part"
        case .job: return fields["job_name"] ?? fields["job_number"] ?? "Job"
        case .tool: return fields["tool_name"] ?? fields["serial_number"] ?? "Tool"
        case .vehicle: return fields["vehicle_name"] ?? fields["vehicle_number"] ?? "Vehicle"
        case .supplier: return fields["name"] ?? "Supplier"
        case .employee: return fields["display_name"] ?? "Employee"
        case .bin: return fields["label"] ?? fields["code"] ?? "Bin"
        case .po: return fields["po_number"] ?? "Purchase Order"
        case .none: return fields["name"] ?? fields["code"] ?? "Entity"
        }
    }

    private func buildDetailFields(result: QRAutoFillResult) -> [DetailField] {
        guard result.isFound else { return [] }
        let fields = result.fields
        var details: [DetailField] = []
        switch result.entityType {
        case .part:
            if let code = fields["code"] { details.append(DetailField(key: "Code", value: code)) }
            if let sku = fields["sku"], !sku.isEmpty { details.append(DetailField(key: "SKU", value: sku)) }
            if let unit = fields["unit_of_measure"] { details.append(DetailField(key: "Unit", value: unit)) }
        case .job:
            if let num = fields["job_number"] { details.append(DetailField(key: "Number", value: num)) }
            if let status = fields["status"] { details.append(DetailField(key: "Status", value: status.capitalized)) }
            if let customer = fields["customer_name"] { details.append(DetailField(key: "Customer", value: customer)) }
        case .tool:
            if let serial = fields["serial_number"] { details.append(DetailField(key: "Serial #", value: serial)) }
            if let status = fields["status"] { details.append(DetailField(key: "Status", value: status.capitalized)) }
            if let condition = fields["condition_status"] { details.append(DetailField(key: "Condition", value: condition.capitalized)) }
        case .vehicle:
            if let num = fields["vehicle_number"] { details.append(DetailField(key: "Number", value: num)) }
            if let status = fields["status"] { details.append(DetailField(key: "Status", value: status.capitalized)) }
        default: break
        }
        return details
    }

    // MARK: - Location Processing

    /// Check if the code matches a warehouse location and return its info.
    private func processLocationCode(_ code: String) throws -> WarehouseService.LocationScanInfo? {
        guard let service = appCore.warehouseService else { scanError = "Warehouse service not available"; return nil }
        // Try looking up the code as a full_location_code
        return try service.getLocationByQR(qrCode: code)
    }

    // MARK: - Location Contents Section

    @ViewBuilder
    private func locationContentsSection(_ locInfo: WarehouseService.LocationScanInfo) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if locInfo.parts.isEmpty {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Empty location — no parts assigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Contents (\(locInfo.parts.count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(locInfo.parts.prefix(5), id: \.partId) { item in
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: item.isHome ? "house.fill" : "shippingbox")
                            .font(.caption2)
                            .foregroundStyle(item.isHome ? .green : .blue)
                            .frame(width: 16)
                            .accessibilityLabel(item.isHome ? "Home location" : "Stored here")

                        Text(item.partName)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        if let pn = item.partNumber, !pn.isEmpty {
                            Text(pn)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if locInfo.parts.count > 5 {
                    Text("+\(locInfo.parts.count - 5) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Direction Guidance

    @ViewBuilder
    private func directionGuidanceRow(_ direction: WarehouseService.DirectionResult) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "location.fill")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text(direction.instructions)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func navigateToModule(_ moduleId: String) {
        NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["moduleId": moduleId])
    }
}

// MARK: - Local Types

private struct ScanResultData {
    let code: String
    let isFound: Bool
    let entityType: QREntityType?
    let entityId: Int64?
    let entityTitle: String
    let stockLocations: [StockLocation]?
    let detailFields: [DetailField]
    var isLocation: Bool = false
}

private struct StockLocation {
    let label: String
    let qty: Int
}

private struct DetailField {
    let key: String
    let value: String
}
