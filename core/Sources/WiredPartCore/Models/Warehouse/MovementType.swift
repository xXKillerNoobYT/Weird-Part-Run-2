import Foundation

/// Canonical values for `stock_movements.movement_type`.
public enum WarehouseMovementType: String, CaseIterable, Codable, Sendable {
    case receive
    case consume
    case transfer
    case returnToStock = "return"
    case adjustment
    case receivingStaged = "receiving_staged"
    case writeOff = "write_off"
    case returnToSupplier = "return_to_supplier"

    /// Movement types that reduce available sellable stock for forecast usage.
    public var countsAsConsumption: Bool {
        switch self {
        case .consume, .returnToSupplier:
            return true
        case .receive, .transfer, .returnToStock, .adjustment, .receivingStaged, .writeOff:
            return false
        }
    }

    public static var consumptionRawValues: [String] {
        allCases.filter(\.countsAsConsumption).map(\.rawValue)
    }

    /// Safe SQL literal list for static queries built only from enum raw values.
    public static var consumptionSQLLiteralList: String {
        consumptionRawValues.map { "'\($0)'" }.joined(separator: ", ")
    }

    public static func from(sourceLocationType source: String, destinationLocationType destination: String) -> WarehouseMovementType {
        if source == "job" {
            return .returnToSupplier
        }
        if destination == "job" {
            return .consume
        }
        if destination == "warehouse", source == "truck" || source == "trailer" {
            return .returnToStock
        }
        return .transfer
    }
}
