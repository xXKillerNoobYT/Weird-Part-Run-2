import SwiftUI
import GRDB
import WiredPartCore

/// Dashboard QR Scanner sub-page.
///
/// Uses the existing `IOSQRScanner` (VisionKit DataScannerViewController)
/// for camera-based scanning, with a manual code entry fallback.
/// After a scan, shows entity info + contextual quick actions.
struct IOSDashboardQRScannerPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var manualCode = ""
    @State private var isScanning = false
    @State private var scanResult: ScanResultData?
    @State private var scanError: String?
    @State private var isProcessing = false

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @State private var scanner: IOSQRScanner?
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                // Camera scan section
                cameraScanSection
                    .padding(.horizontal, DS.Space.lg)

                // Manual entry section
                manualEntrySection
                    .padding(.horizontal, DS.Space.lg)

                // Error display
                if let error = scanError {
                    DSAlertBanner(severity: .error, title: "Scan Error", message: error)
                        .padding(.horizontal, DS.Space.lg)
                }

                // Processing indicator
                if isProcessing {
                    ProgressView("Looking up code...")
                        .padding()
                }

                // Result card
                if let result = scanResult {
                    resultCard(result)
                        .padding(.horizontal, DS.Space.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.vertical, DS.Space.lg)
        }
        .background(DS.Background.page)
        .navigationTitle("QR Scanner")
        .animation(.easeInOut(duration: 0.3), value: scanResult != nil)
    }

    // MARK: - Camera Scan Section

    private var cameraScanSection: some View {
        VStack(spacing: DS.Space.md) {
            #if os(iOS) && !targetEnvironment(macCatalyst)
            if DataScannerViewController.isSupported {
                Button {
                    startCameraScanning()
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Scan with Camera")
                                .dsStyle(.label)
                                .fontWeight(.semibold)
                            Text("Point camera at a QR code or barcode")
                                .dsStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(DS.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .dsElevatedCard()
            } else {
                // No camera available
                VStack(spacing: DS.Space.sm) {
                    Image(systemName: "camera.badge.ellipsis")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Camera not available")
                        .dsStyle(.label)
                        .foregroundStyle(.secondary)
                    Text("Use manual entry below to look up a code")
                        .dsStyle(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity)
                .dsCard()
            }
            #else
            VStack(spacing: DS.Space.sm) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Camera scanning is available on iOS devices")
                    .dsStyle(.label)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity)
            .dsCard()
            #endif
        }
    }

    // MARK: - Manual Entry

    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Manual Entry")
                .dsStyle(.sectionTitle)

            HStack(spacing: DS.Space.sm) {
                TextField("Type or paste code...", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { processManualCode() }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Look Up") {
                    processManualCode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
            }
        }
    }

    // MARK: - Result Card

    @ViewBuilder
    private func resultCard(_ result: ScanResultData) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // Header
            HStack(spacing: DS.Space.md) {
                Image(systemName: result.isFound ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(result.isFound ? DS.SemanticColor.success : DS.SemanticColor.warning)
                VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                    Text(result.isFound ? result.entityTitle : "Not Found")
                        .dsStyle(.label)
                        .fontWeight(.semibold)
                    Text(result.code)
                        .dsStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let type = result.entityType {
                    Text(type.rawValue.capitalized)
                        .dsStyle(.caption)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xxxs)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
            }

            if result.isFound {
                Divider()

                // Stock locations (for parts)
                if let stockLocations = result.stockLocations, !stockLocations.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Label("Stock Locations", systemImage: "mappin.and.ellipse")
                            .dsStyle(.label)
                            .foregroundStyle(.secondary)

                        ForEach(stockLocations, id: \.label) { loc in
                            HStack {
                                Text(loc.label)
                                    .dsStyle(.detail)
                                Spacer()
                                Text("\(loc.qty) units")
                                    .dsStyle(.detail)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // Detail fields
                if !result.detailFields.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(result.detailFields, id: \.key) { field in
                            LabeledContent(field.key, value: field.value)
                                .dsStyle(.detail)
                        }
                    }
                }

                Divider()

                // Quick actions
                quickActions(for: result)
            } else {
                Text("The scanned code was not recognized in the system.")
                    .dsStyle(.detail)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Space.lg)
        .dsElevatedCard()
    }

    @ViewBuilder
    private func quickActions(for result: ScanResultData) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Quick Actions")
                .dsStyle(.label)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.md) {
                    switch result.entityType {
                    case .part:
                        DSQuickActionButton(title: "Move Stock", icon: "arrow.left.arrow.right", color: .orange) {
                            navigateToModule("warehouse")
                        }
                        DSQuickActionButton(title: "View Details", icon: "info.circle", color: .blue) {
                            navigateToModule("parts")
                        }
                    case .tool:
                        DSQuickActionButton(title: "Check Status", icon: "wrench.and.screwdriver", color: .blue) {
                            navigateToModule("tools")
                        }
                    case .job:
                        DSQuickActionButton(title: "View Job", icon: "hammer", color: .orange) {
                            navigateToModule("jobs")
                        }
                    case .vehicle:
                        DSQuickActionButton(title: "View Fleet", icon: "car", color: .green) {
                            navigateToModule("fleet")
                        }
                    default:
                        DSQuickActionButton(title: "View Details", icon: "info.circle", color: .blue) {}
                    }

                    // Scan another
                    DSQuickActionButton(title: "Scan Again", icon: "qrcode.viewfinder", color: .purple) {
                        scanResult = nil
                        scanError = nil
                    }
                }
            }
        }
    }

    // MARK: - Scanning Logic

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func startCameraScanning() {
        let newScanner = IOSQRScanner()
        scanner = newScanner

        guard newScanner.isAvailable else {
            scanError = "Camera scanner is not available on this device."
            return
        }

        isScanning = true
        scanError = nil

        Task {
            do {
                let stream = try await newScanner.startScanning()
                for await event in stream {
                    switch event {
                    case .detected(let payload, _):
                        newScanner.stopScanning()
                        isScanning = false
                        await processCode(payload)
                        return
                    case .error(let msg):
                        newScanner.stopScanning()
                        isScanning = false
                        scanError = msg
                        return
                    case .permissionDenied:
                        newScanner.stopScanning()
                        isScanning = false
                        scanError = "Camera permission denied. Please enable camera access in Settings."
                        return
                    }
                }
            } catch {
                isScanning = false
                scanError = error.localizedDescription
            }
        }
    }
    #endif

    private func processManualCode() {
        let code = manualCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        Task {
            await processCode(code)
        }
    }

    private func processCode(_ code: String) async {
        guard let db = appCore.db else {
            scanError = "Database not available"
            return
        }

        await MainActor.run {
            isProcessing = true
            scanError = nil
            scanResult = nil
        }

        do {
            let autoFill = QRAutoFillService(db: db)
            let result = try autoFill.processQRScan(code)

            var stockLocations: [StockLocation]?

            // If it's a part, load stock locations
            if result.entityType == .part, let partId = result.entityId {
                stockLocations = try await loadPartStockLocations(db: db, partId: partId)
            }

            let title = buildEntityTitle(result: result)
            let detailFields = buildDetailFields(result: result)

            await MainActor.run {
                scanResult = ScanResultData(
                    code: code,
                    isFound: result.isFound,
                    entityType: result.entityType,
                    entityId: result.entityId,
                    entityTitle: title,
                    stockLocations: stockLocations,
                    detailFields: detailFields
                )
                isProcessing = false
                manualCode = ""
            }
        } catch {
            await MainActor.run {
                scanError = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func loadPartStockLocations(db: AppDatabase, partId: Int64) async throws -> [StockLocation] {
        try await db.writer.read { conn in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT s.location_type, SUM(s.qty) AS total_qty
                FROM stock s
                WHERE s.part_id = ? AND s.qty > 0 AND s.deleted_at IS NULL
                GROUP BY s.location_type
                ORDER BY total_qty DESC
                """, arguments: [partId])
            return rows.map { row in
                let locType: String = row["location_type"] ?? "unknown"
                let qty: Int = row["total_qty"] ?? 0
                let label = switch locType {
                case "warehouse": "Warehouse"
                case "pulled", "staging": "Staging"
                case "truck": "Truck"
                case "trailer": "Trailer"
                case "job": "Job Site"
                default: locType.capitalized
                }
                return StockLocation(label: label, qty: qty)
            }
        }
    }

    private func buildEntityTitle(result: QRAutoFillResult) -> String {
        guard result.isFound else { return "Unknown" }
        let fields = result.fields

        switch result.entityType {
        case .part:
            return fields["name"] ?? fields["code"] ?? "Part"
        case .job:
            return fields["job_name"] ?? fields["job_number"] ?? "Job"
        case .tool:
            return fields["tool_name"] ?? fields["serial_number"] ?? "Tool"
        case .vehicle:
            return fields["vehicle_name"] ?? fields["vehicle_number"] ?? "Vehicle"
        case .supplier:
            return fields["name"] ?? "Supplier"
        case .employee:
            return fields["display_name"] ?? "Employee"
        case .bin:
            return fields["label"] ?? fields["code"] ?? "Bin"
        case .po:
            return fields["po_number"] ?? "Purchase Order"
        case .none:
            return fields["name"] ?? fields["code"] ?? "Entity"
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
        default:
            break
        }

        return details
    }

    private func navigateToModule(_ moduleId: String) {
        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": moduleId]
        )
    }
}

// MARK: - Local Model Types

private struct ScanResultData {
    let code: String
    let isFound: Bool
    let entityType: QREntityType?
    let entityId: Int64?
    let entityTitle: String
    let stockLocations: [StockLocation]?
    let detailFields: [DetailField]
}

private struct StockLocation {
    let label: String
    let qty: Int
}

private struct DetailField {
    let key: String
    let value: String
}

#if os(iOS) && !targetEnvironment(macCatalyst)
import VisionKit
#endif
