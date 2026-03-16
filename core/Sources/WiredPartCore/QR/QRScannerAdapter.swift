import Foundation
import GRDB

// MARK: - QR Scanner Adapter Protocol

/// Platform-specific QR/barcode scanner interface.
///
/// Implementations:
/// - macOS: `AVCaptureSession` + `VNDetectBarcodesRequest`
/// - iOS: `DataScannerViewController` (VisionKit)
///
/// The adapter provides continuous scanning via `AsyncStream<QRScanEvent>`.
/// The core layer decodes payloads via `QRCodec` — the adapter only
/// delivers raw string content.
@MainActor
public protocol QRScannerAdapter: AnyObject, Sendable {
    /// Whether camera/scanner hardware is available on this device.
    var isAvailable: Bool { get }

    /// Start continuous QR scanning. Returns an async stream of scan events.
    ///
    /// The stream emits `.detected` events as QR codes are found,
    /// `.error` if scanning fails, and `.permissionDenied` if the user
    /// denies camera access.
    ///
    /// Call `stopScanning()` to end the stream.
    func startScanning() async throws -> AsyncStream<QRScanEvent>

    /// Stop an active scanning session.
    func stopScanning()
}

// MARK: - Scan Format

/// Format of a scanned barcode/QR code.
public enum ScanFormat: String, Sendable {
    case qr
    case barcode
    case code128
    case code39
    case ean8
    case ean13
    case upce
    case unknown
}

// MARK: - Single Scan Result

/// Result of a single QR/barcode scan (legacy compatibility).
public struct ScanResult: Sendable {
    public let value: String
    public let format: ScanFormat

    public init(value: String, format: ScanFormat = .qr) {
        self.value = value
        self.format = format
    }
}

// MARK: - Legacy Scanner Adapter

/// Simple single-scan interface (backward compatibility with Phase 3.5).
public protocol ScannerAdapter: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func scan() async throws -> ScanResult
}

// MARK: - QR Auto-Fill Service

/// Processes QR scan results and returns auto-fill data for forms.
///
/// This service sits between the scanner adapter (platform) and the UI.
/// It decodes the QR payload, looks up the entity in the database,
/// and returns the field values to populate.
public final class QRAutoFillService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    /// Process a raw QR scan string and return auto-fill data.
    ///
    /// - Parameter rawString: The raw text from the QR scanner.
    /// - Returns: Auto-fill result with entity data and field mappings.
    public func processQRScan(_ rawString: String) throws -> QRAutoFillResult {
        let decoded = QRCodec.decode(rawString)

        switch decoded {
        case .wiredPartV2(let payload):
            let fields = try lookupEntity(type: payload.type, id: payload.id)
            return QRAutoFillResult(
                source: .wiredPartV2,
                entityType: payload.type,
                entityId: payload.id,
                code: payload.code,
                fields: fields,
                meta: payload.meta ?? [:]
            )

        case .wiredPartV1(let id, let code):
            // V1 codes are always parts
            let fields = try lookupEntity(type: .part, id: id)
            return QRAutoFillResult(
                source: .wiredPartV1,
                entityType: .part,
                entityId: id,
                code: code,
                fields: fields,
                meta: [:]
            )

        case .externalCode(let text):
            // Search the parts catalog for this code
            let fields = try searchCatalog(code: text)
            return QRAutoFillResult(
                source: .external,
                entityType: nil,
                entityId: nil,
                code: text,
                fields: fields,
                meta: [:]
            )

        case .invalid(let reason):
            return QRAutoFillResult(
                source: .invalid,
                entityType: nil,
                entityId: nil,
                code: rawString,
                fields: [:],
                meta: ["error": reason]
            )
        }
    }

    // MARK: - Private Lookups

    private func lookupEntity(type: QREntityType, id: Int64) throws -> [String: String] {
        try db.writer.read { dbConnection in
            let tableName = Self.tableForEntityType(type)
            guard let row = try Row.fetchOne(
                dbConnection,
                sql: "SELECT * FROM \(tableName) WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            ) else {
                return ["_status": "not_found"]
            }

            var fields: [String: String] = [:]
            for column in row.columnNames {
                if let value = row[column] as? String {
                    fields[column] = value
                } else if let value = row[column] as? Int64 {
                    fields[column] = String(value)
                } else if let value = row[column] as? Double {
                    fields[column] = String(value)
                }
            }
            fields["_status"] = "found"
            return fields
        }
    }

    private func searchCatalog(code: String) throws -> [String: String] {
        try db.writer.read { dbConnection in
            // Search parts by code, SKU, or barcode
            guard let row = try Row.fetchOne(
                dbConnection,
                sql: """
                    SELECT * FROM parts
                    WHERE (code = ? OR sku = ? OR barcode = ?)
                    AND deleted_at IS NULL
                    LIMIT 1
                    """,
                arguments: [code, code, code]
            ) else {
                return ["_status": "not_found"]
            }

            var fields: [String: String] = [:]
            for column in row.columnNames {
                if let value = row[column] as? String {
                    fields[column] = value
                } else if let value = row[column] as? Int64 {
                    fields[column] = String(value)
                } else if let value = row[column] as? Double {
                    fields[column] = String(value)
                }
            }
            fields["_status"] = "found"
            return fields
        }
    }

    private static func tableForEntityType(_ type: QREntityType) -> String {
        switch type {
        case .part: return "parts"
        case .job: return "jobs"
        case .supplier: return "suppliers"
        case .bin: return "bin_locations"
        case .vehicle: return "vehicles"
        case .tool: return "tools"
        case .employee: return "users"
        case .po: return "purchase_orders"
        }
    }
}

// MARK: - QR Auto-Fill Result

/// Result of processing a QR scan for form auto-fill.
public struct QRAutoFillResult: Sendable {
    public enum Source: String, Sendable {
        case wiredPartV2
        case wiredPartV1
        case external
        case invalid
    }

    public let source: Source
    public let entityType: QREntityType?
    public let entityId: Int64?
    public let code: String
    public let fields: [String: String]
    public let meta: [String: String]

    /// Whether the entity was found in the local database.
    public var isFound: Bool {
        fields["_status"] == "found"
    }
}
