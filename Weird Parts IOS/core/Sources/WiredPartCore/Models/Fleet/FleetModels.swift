import Foundation
import GRDB

// MARK: - WarehouseLocation

public struct WarehouseLocation: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "warehouse_locations"
    public var id: Int64?
    public var name: String
    public var address: String?
    public var locationType: String
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, address
        case locationType = "location_type"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Vehicle

public struct Vehicle: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "vehicles"
    public var id: Int64?
    public var vehicleNumber: String
    public var vehicleName: String
    public var vehicleType: String
    public var status: String
    public var make: String?
    public var model: String?
    public var year: Int?
    public var color: String?
    public var vin: String?
    public var licensePlate: String?
    public var insurancePolicy: String?
    public var insuranceExpiry: String?
    public var registrationExpiry: String?
    public var currentOdometer: Int?
    public var ownerUserId: Int64?
    public var notes: String?
    public var photoPath: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, make, model, year, color, vin, status, notes
        case vehicleNumber = "vehicle_number"
        case vehicleName = "vehicle_name"
        case vehicleType = "vehicle_type"
        case licensePlate = "license_plate"
        case insurancePolicy = "insurance_policy"
        case insuranceExpiry = "insurance_expiry"
        case registrationExpiry = "registration_expiry"
        case currentOdometer = "current_odometer"
        case ownerUserId = "owner_user_id"
        case photoPath = "photo_path"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - VehicleAssignment

public struct VehicleAssignment: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "vehicle_assignments"
    public var id: Int64?
    public var vehicleId: Int64
    public var userId: Int64
    public var assignmentType: String
    public var isTakeHome: Int
    public var homeToShopMiles: Double?
    public var startDate: String
    public var endDate: String?
    public var isActive: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case vehicleId = "vehicle_id"
        case userId = "user_id"
        case assignmentType = "assignment_type"
        case isTakeHome = "is_take_home"
        case homeToShopMiles = "home_to_shop_miles"
        case startDate = "start_date"
        case endDate = "end_date"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - VehicleDeliveryItem

public struct VehicleDeliveryItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "vehicle_delivery_items"
    public var id: Int64?
    public var vehicleId: Int64
    public var jobId: Int64?
    public var poId: Int64?
    public var description: String?
    public var quantity: Int
    public var status: String
    public var loadedBy: Int64?
    public var deliveredBy: Int64?
    public var loadedAt: String?
    public var deliveredAt: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, quantity, status, notes
        case vehicleId = "vehicle_id"
        case jobId = "job_id"
        case poId = "po_id"
        case loadedBy = "loaded_by"
        case deliveredBy = "delivered_by"
        case loadedAt = "loaded_at"
        case deliveredAt = "delivered_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - MaintenanceType

public struct MaintenanceType: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "maintenance_types"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - MaintenanceSchedule

public struct MaintenanceSchedule: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "maintenance_schedules"
    public var id: Int64?
    public var vehicleId: Int64
    public var maintenanceTypeId: Int64
    public var intervalMiles: Int?
    public var intervalDays: Int?
    public var lastPerformedAt: String?
    public var lastPerformedMiles: Int?
    public var nextDueDate: String?
    public var nextDueMiles: Int?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case vehicleId = "vehicle_id"
        case maintenanceTypeId = "maintenance_type_id"
        case intervalMiles = "interval_miles"
        case intervalDays = "interval_days"
        case lastPerformedAt = "last_performed_at"
        case lastPerformedMiles = "last_performed_miles"
        case nextDueDate = "next_due_date"
        case nextDueMiles = "next_due_miles"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - MaintenanceRecord

public struct MaintenanceRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "maintenance_records"
    public var id: Int64?
    public var vehicleId: Int64
    public var maintenanceTypeId: Int64?
    public var performedAt: String
    public var performedBy: Int64?
    public var odometerReading: Int?
    public var cost: Double?
    public var vendor: String?
    public var description: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, cost, vendor, description, notes
        case vehicleId = "vehicle_id"
        case maintenanceTypeId = "maintenance_type_id"
        case performedAt = "performed_at"
        case performedBy = "performed_by"
        case odometerReading = "odometer_reading"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - MileageLog

public struct MileageLog: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "mileage_logs"
    public var id: Int64?
    public var vehicleId: Int64
    public var userId: Int64
    public var logDate: String
    public var startOdometer: Int?
    public var endOdometer: Int?
    public var totalMiles: Double?
    public var purpose: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, purpose, notes
        case vehicleId = "vehicle_id"
        case userId = "user_id"
        case logDate = "log_date"
        case startOdometer = "start_odometer"
        case endOdometer = "end_odometer"
        case totalMiles = "total_miles"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TripLeg

public struct TripLeg: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "trip_legs"
    public var id: Int64?
    public var mileageLogId: Int64
    public var legType: String
    public var fromLocation: String?
    public var toLocation: String?
    public var miles: Double?
    public var jobId: Int64?
    public var notes: String?
    public var sortOrder: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, miles, notes
        case mileageLogId = "mileage_log_id"
        case legType = "leg_type"
        case fromLocation = "from_location"
        case toLocation = "to_location"
        case jobId = "job_id"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - MileageReimbursement

public struct MileageReimbursement: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "mileage_reimbursements"
    public var id: Int64?
    public var userId: Int64
    public var mileageLogId: Int64?
    public var miles: Double
    public var ratePerMile: Double
    public var amount: Double
    public var status: String
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, miles, amount, status, notes
        case userId = "user_id"
        case mileageLogId = "mileage_log_id"
        case ratePerMile = "rate_per_mile"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - FuelLog

public struct FuelLog: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "fuel_logs"
    public var id: Int64?
    public var vehicleId: Int64
    public var userId: Int64
    public var logDate: String
    public var gallons: Double?
    public var costPerGallon: Double?
    public var totalCost: Double?
    public var odometerReading: Int?
    public var station: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, gallons, station, notes
        case vehicleId = "vehicle_id"
        case userId = "user_id"
        case logDate = "log_date"
        case costPerGallon = "cost_per_gallon"
        case totalCost = "total_cost"
        case odometerReading = "odometer_reading"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - JobTrailer

public struct JobTrailer: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_trailers"
    public var id: Int64?
    public var trailerNumber: String
    public var trailerType: String
    public var status: String
    public var homeWarehouseId: Int64?
    public var currentJobId: Int64?
    public var assignedVehicleId: Int64?
    public var capacityNotes: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case trailerNumber = "trailer_number"
        case trailerType = "trailer_type"
        case homeWarehouseId = "home_warehouse_id"
        case currentJobId = "current_job_id"
        case assignedVehicleId = "assigned_vehicle_id"
        case capacityNotes = "capacity_notes"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TrailerLocationEvent

public struct TrailerLocationEvent: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "trailer_location_events"
    public var id: Int64?
    public var trailerId: Int64
    public var eventType: String
    public var locationKind: String
    public var locationId: Int64?
    public var locationName: String?
    public var movedBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case trailerId = "trailer_id"
        case eventType = "event_type"
        case locationKind = "location_kind"
        case locationId = "location_id"
        case locationName = "location_name"
        case movedBy = "moved_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TrailerStockTemplate

public struct TrailerStockTemplate: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "trailer_stock_templates"
    public var id: Int64?
    public var trailerId: Int64
    public var name: String
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case trailerId = "trailer_id"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TrailerStockTemplateLine

public struct TrailerStockTemplateLine: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "trailer_stock_template_lines"
    public var id: Int64?
    public var templateId: Int64
    public var partId: Int64
    public var targetQty: Int
    public var sortOrder: Int
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case templateId = "template_id"
        case partId = "part_id"
        case targetQty = "target_qty"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - OrderAttachment

public struct OrderAttachment: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "order_attachments"
    public var id: Int64?
    public var entityType: String
    public var entityId: Int64
    public var fileName: String
    public var filePath: String
    public var fileSize: Int?
    public var mimeType: String?
    public var uploadedBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case entityType = "entity_type"
        case entityId = "entity_id"
        case fileName = "file_name"
        case filePath = "file_path"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case uploadedBy = "uploaded_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
