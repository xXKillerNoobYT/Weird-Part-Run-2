import Foundation
import GRDB

// MARK: - StockMovement

/// Represents a single inventory movement from one location to another.
/// Tracks the full journey of parts: Supplier → Warehouse → Staging → Truck → Job.
public struct StockMovement: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "stock_movements"

    /// Canonical values stored in `stock_movements.movement_type`.
    ///
    /// Keep movement producers and SQL consumers on this enum instead of
    /// open-coded strings so forecasting/reporting do not silently drift when a
    /// writer uses a synonym such as `consumed` or `job_pull`.
    public enum MovementType: String, Codable, CaseIterable, Sendable {
        case transfer
        case receive
        case receiving
        case receivingStaged = "receiving_staged"
        case receipt
        case stockReturn = "return"
        case returnToSupplier = "return_to_supplier"
        case adjustment
        case addStock = "add_stock"
        case writeOff = "write_off"
        case consume
        case pull
        case usage
        case jobPull = "job_pull"
        case restockFromShop = "restock_from_shop"

        /// Movement types that remove stock from normal availability and should
        /// contribute to demand/forecast calculations. Return-to-supplier stays
        /// included to preserve the pre-existing 30/90-day consumption stats
        /// behavior while making every forecast query use the same definition.
        public static let forecastConsumptionTypes: [MovementType] = [
            .consume, .pull, .usage, .jobPull, .returnToSupplier
        ]

        /// Movement types shown as material usage in reports.
        public static let materialUsageTypes: [MovementType] = [
            .consume, .pull, .usage, .jobPull
        ]

        /// Accept legacy/synonym values at write/filter boundaries, but persist
        /// the canonical raw value for all new stock movements.
        public var aliases: [String] {
            switch self {
            case .transfer:
                return ["transfer"]
            case .receive:
                return ["receive", "received", "receiving", "receipt"]
            case .receiving:
                return ["receiving"]
            case .receivingStaged:
                return ["receiving_staged"]
            case .receipt:
                return ["receipt"]
            case .stockReturn:
                return ["return", "returned", "stock_return"]
            case .returnToSupplier:
                return ["return_to_supplier"]
            case .adjustment:
                return ["adjustment", "adjust"]
            case .addStock:
                return ["add_stock"]
            case .writeOff:
                return ["write_off"]
            case .consume:
                return ["consume", "consumed", "consumption"]
            case .pull:
                return ["pull"]
            case .usage:
                return ["usage"]
            case .jobPull:
                return ["job_pull"]
            case .restockFromShop:
                return ["restock_from_shop"]
            }
        }

        public static func normalize(_ movementType: String) -> String {
            let normalized = movementType
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            for type in Self.allCases where type.aliases.contains(normalized) {
                return type.rawValue
            }
            return normalized
        }

        /// SQL literal list for static movement-type `IN (...)` clauses.
        /// Empty input deliberately produces a no-match list instead of invalid
        /// `IN ()` SQL so callers can safely compose from filtered type arrays.
        public static func sqlList(_ types: [MovementType]) -> String {
            guard !types.isEmpty else { return "(NULL)" }
            return "(" + types.map { "'\($0.rawValue)'" }.joined(separator: ", ") + ")"
        }
    }
    public var id: Int64?
    public var partId: Int64
    public var qty: Int
    public var fromLocationType: String?
    public var fromLocationId: Int64?
    public var toLocationType: String?
    public var toLocationId: Int64?
    public var supplierId: Int64?
    public var movementType: String
    public var reason: String?
    public var referenceNumber: String?
    public var notes: String?
    public var jobId: Int64?
    public var performedBy: Int64
    public var verifiedBy: Int64?
    public var photoPath: String?
    public var scanConfirmed: Int
    public var gpsLat: Double?
    public var gpsLng: Double?
    public var unitCostAtMove: Double?
    public var unitSellAtMove: Double?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, qty, reason, notes
        case partId = "part_id"
        case fromLocationType = "from_location_type"
        case fromLocationId = "from_location_id"
        case toLocationType = "to_location_type"
        case toLocationId = "to_location_id"
        case supplierId = "supplier_id"
        case movementType = "movement_type"
        case referenceNumber = "reference_number"
        case jobId = "job_id"
        case performedBy = "performed_by"
        case verifiedBy = "verified_by"
        case photoPath = "photo_path"
        case scanConfirmed = "scan_confirmed"
        case gpsLat = "gps_lat"
        case gpsLng = "gps_lng"
        case unitCostAtMove = "unit_cost_at_move"
        case unitSellAtMove = "unit_sell_at_move"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    /// Human-readable description of the movement direction
    public var movementDescription: String {
        let from = fromLocationType?.capitalized ?? "Unknown"
        let to = toLocationType?.capitalized ?? "Unknown"
        return "\(from) → \(to)"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
