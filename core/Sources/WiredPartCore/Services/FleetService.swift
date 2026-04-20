import Foundation
import GRDB

/// Fleet & Vehicle Management Service — read queries for vehicles, maintenance,
/// mileage logs, fuel logs, trailers, and fleet dashboard stats.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Fleet & Vehicle Management feature area (Phase 6)
public final class FleetService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum FleetError: Error, Sendable, Equatable {
        case vehicleNotFound(Int64)
        case userNotFound(Int64)
        case trailerNotFound(Int64)
        case invalidQuantity(Int)
        case invalidFuelLevel(Double)
        case requiredFieldEmpty(String)
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A vehicle row for list views with assigned user name.
    public struct VehicleListItem: Sendable, Identifiable {
        public let id: Int64
        public let vehicleNumber: String
        public let vehicleName: String
        public let vehicleType: String
        public let status: String
        public let make: String?
        public let model: String?
        public let year: Int?
        public let currentOdometer: Int?
        public let assignedUserName: String?
        public let assignedUserId: Int64?

        public init(
            id: Int64, vehicleNumber: String, vehicleName: String, vehicleType: String,
            status: String, make: String?, model: String?, year: Int?,
            currentOdometer: Int?, assignedUserName: String?, assignedUserId: Int64? = nil
        ) {
            self.id = id
            self.vehicleNumber = vehicleNumber
            self.vehicleName = vehicleName
            self.vehicleType = vehicleType
            self.status = status
            self.make = make
            self.model = model
            self.year = year
            self.currentOdometer = currentOdometer
            self.assignedUserName = assignedUserName
            self.assignedUserId = assignedUserId
        }
    }

    /// Full vehicle detail including all fields and active assignments.
    public struct VehicleDetail: Sendable {
        public let id: Int64
        public let vehicleNumber: String
        public let vehicleName: String
        public let vehicleType: String
        public let status: String
        public let make: String?
        public let model: String?
        public let year: Int?
        public let color: String?
        public let vin: String?
        public let licensePlate: String?
        public let insurancePolicy: String?
        public let insuranceExpiry: String?
        public let registrationExpiry: String?
        public let currentOdometer: Int?
        public let ownerUserId: Int64?
        public let notes: String?
        public let photoPath: String?
        public let isActive: Int
        public let deletedAt: String?
        public let createdAt: String?
        public let updatedAt: String?
        public let assignments: [AssignmentRow]

        public init(
            id: Int64, vehicleNumber: String, vehicleName: String, vehicleType: String,
            status: String, make: String?, model: String?, year: Int?,
            color: String?, vin: String?, licensePlate: String?,
            insurancePolicy: String?, insuranceExpiry: String?, registrationExpiry: String?,
            currentOdometer: Int?, ownerUserId: Int64?, notes: String?, photoPath: String?,
            isActive: Int, deletedAt: String?, createdAt: String?, updatedAt: String?,
            assignments: [AssignmentRow]
        ) {
            self.id = id
            self.vehicleNumber = vehicleNumber
            self.vehicleName = vehicleName
            self.vehicleType = vehicleType
            self.status = status
            self.make = make
            self.model = model
            self.year = year
            self.color = color
            self.vin = vin
            self.licensePlate = licensePlate
            self.insurancePolicy = insurancePolicy
            self.insuranceExpiry = insuranceExpiry
            self.registrationExpiry = registrationExpiry
            self.currentOdometer = currentOdometer
            self.ownerUserId = ownerUserId
            self.notes = notes
            self.photoPath = photoPath
            self.isActive = isActive
            self.deletedAt = deletedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.assignments = assignments
        }
    }

    /// A vehicle assignment row with user name.
    public struct AssignmentRow: Sendable, Identifiable {
        public let id: Int64
        public let userId: Int64
        public let userName: String
        public let assignmentType: String
        public let isTakeHome: Bool
        public let startDate: String
        public let endDate: String?
        public let isActive: Bool

        public init(
            id: Int64, userId: Int64, userName: String, assignmentType: String,
            isTakeHome: Bool, startDate: String, endDate: String?, isActive: Bool
        ) {
            self.id = id
            self.userId = userId
            self.userName = userName
            self.assignmentType = assignmentType
            self.isTakeHome = isTakeHome
            self.startDate = startDate
            self.endDate = endDate
            self.isActive = isActive
        }
    }

    /// A maintenance record row with vehicle and type names.
    public struct MaintenanceRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let maintenanceTypeName: String?
        public let performedAt: String
        public let performedByName: String?
        public let cost: Double?
        public let odometerReading: Int?

        public init(
            id: Int64, vehicleName: String, maintenanceTypeName: String?,
            performedAt: String, performedByName: String?,
            cost: Double?, odometerReading: Int?
        ) {
            self.id = id
            self.vehicleName = vehicleName
            self.maintenanceTypeName = maintenanceTypeName
            self.performedAt = performedAt
            self.performedByName = performedByName
            self.cost = cost
            self.odometerReading = odometerReading
        }
    }

    /// A mileage log row with vehicle and user names.
    public struct MileageRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let userName: String
        public let logDate: String
        public let totalMiles: Double?
        public let purpose: String?

        public init(
            id: Int64, vehicleName: String, userName: String,
            logDate: String, totalMiles: Double?, purpose: String?
        ) {
            self.id = id
            self.vehicleName = vehicleName
            self.userName = userName
            self.logDate = logDate
            self.totalMiles = totalMiles
            self.purpose = purpose
        }
    }

    /// A fuel log row with vehicle and user names.
    public struct FuelRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let userName: String
        public let logDate: String
        public let gallons: Double?
        public let totalCost: Double?
        public let station: String?

        public init(
            id: Int64, vehicleName: String, userName: String,
            logDate: String, gallons: Double?, totalCost: Double?, station: String?
        ) {
            self.id = id
            self.vehicleName = vehicleName
            self.userName = userName
            self.logDate = logDate
            self.gallons = gallons
            self.totalCost = totalCost
            self.station = station
        }
    }

    /// A trailer row for list views with current job and assigned vehicle names.
    public struct TrailerListItem: Sendable, Identifiable {
        public let id: Int64
        public let trailerNumber: String
        public let trailerType: String
        public let status: String
        public let currentJobName: String?
        public let assignedVehicleName: String?

        public init(
            id: Int64, trailerNumber: String, trailerType: String, status: String,
            currentJobName: String?, assignedVehicleName: String?
        ) {
            self.id = id
            self.trailerNumber = trailerNumber
            self.trailerType = trailerType
            self.status = status
            self.currentJobName = currentJobName
            self.assignedVehicleName = assignedVehicleName
        }
    }

    /// Fleet-wide dashboard statistics.
    public struct FleetStats: Sendable {
        public let totalVehicles: Int
        public let activeVehicles: Int
        public let maintenanceDue: Int
        public let totalTrailers: Int

        public init(totalVehicles: Int, activeVehicles: Int, maintenanceDue: Int, totalTrailers: Int) {
            self.totalVehicles = totalVehicles
            self.activeVehicles = activeVehicles
            self.maintenanceDue = maintenanceDue
            self.totalTrailers = totalTrailers
        }
    }

    // =========================================================================
    // MARK: - 1. Vehicles
    // =========================================================================

    /// List vehicles with optional status filter. Includes the primary assigned user name.
    public func listVehicles(status: String? = nil) throws -> [VehicleListItem] {
        do {
            return try db.writer.read { dbConn -> [VehicleListItem] in
                var whereClauses = ["v.deleted_at IS NULL", "v.is_active = 1"]
                var args: [(any DatabaseValueConvertible)?] = []

                if let status, !status.isEmpty {
                    whereClauses.append("v.status = ?")
                    args.append(status)
                }

                let sql = """
                    SELECT v.id, v.vehicle_number, v.vehicle_name, v.vehicle_type,
                           v.status, v.make, v.model, v.year, v.current_odometer,
                           COALESCE(u.display_name, u.email) AS assigned_user_name,
                           va.user_id AS assigned_user_id
                    FROM vehicles v
                    LEFT JOIN vehicle_assignments va
                        ON va.vehicle_id = v.id AND va.is_active = 1 AND va.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = va.user_id AND u.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    GROUP BY v.id
                    ORDER BY v.vehicle_number ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    VehicleListItem(
                        id: row["id"] ?? 0,
                        vehicleNumber: row["vehicle_number"] ?? "",
                        vehicleName: row["vehicle_name"] ?? "",
                        vehicleType: row["vehicle_type"] ?? "truck",
                        status: row["status"] ?? "active",
                        make: row["make"] as String?,
                        model: row["model"] as String?,
                        year: row["year"] as Int?,
                        currentOdometer: row["current_odometer"] as Int?,
                        assignedUserName: row["assigned_user_name"] as String?,
                        assignedUserId: row["assigned_user_id"] as Int64?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single vehicle by ID with full detail and active assignments.
    public func getVehicleDetail(id: Int64) throws -> VehicleDetail? {
        do {
            return try db.writer.read { dbConn -> VehicleDetail? in
                guard let row = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT v.*
                        FROM vehicles v
                        WHERE v.id = ? AND v.deleted_at IS NULL
                        """,
                    arguments: [id]
                ) else { return nil }

                // Fetch active assignments for this vehicle
                let assignmentRows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT va.id, va.user_id, va.assignment_type, va.is_take_home,
                               va.start_date, va.end_date, va.is_active,
                               COALESCE(u.display_name, u.email, 'Unknown') AS user_name
                        FROM vehicle_assignments va
                        LEFT JOIN users u ON u.id = va.user_id AND u.deleted_at IS NULL
                        WHERE va.vehicle_id = ? AND va.deleted_at IS NULL
                        ORDER BY va.is_active DESC, va.start_date DESC
                        """,
                    arguments: [id]
                )

                let assignments = assignmentRows.map { aRow in
                    AssignmentRow(
                        id: aRow["id"] ?? 0,
                        userId: aRow["user_id"] ?? 0,
                        userName: aRow["user_name"] ?? "Unknown",
                        assignmentType: aRow["assignment_type"] ?? "primary",
                        isTakeHome: (aRow["is_take_home"] as Int?) == 1,
                        startDate: aRow["start_date"] ?? "",
                        endDate: aRow["end_date"] as String?,
                        isActive: (aRow["is_active"] as Int?) == 1
                    )
                }

                return VehicleDetail(
                    id: row["id"] ?? 0,
                    vehicleNumber: row["vehicle_number"] ?? "",
                    vehicleName: row["vehicle_name"] ?? "",
                    vehicleType: row["vehicle_type"] ?? "truck",
                    status: row["status"] ?? "active",
                    make: row["make"] as String?,
                    model: row["model"] as String?,
                    year: row["year"] as Int?,
                    color: row["color"] as String?,
                    vin: row["vin"] as String?,
                    licensePlate: row["license_plate"] as String?,
                    insurancePolicy: row["insurance_policy"] as String?,
                    insuranceExpiry: row["insurance_expiry"] as String?,
                    registrationExpiry: row["registration_expiry"] as String?,
                    currentOdometer: row["current_odometer"] as Int?,
                    ownerUserId: row["owner_user_id"] as Int64?,
                    notes: row["notes"] as String?,
                    photoPath: row["photo_path"] as String?,
                    isActive: row["is_active"] ?? 1,
                    deletedAt: row["deleted_at"] as String?,
                    createdAt: row["created_at"] as String?,
                    updatedAt: row["updated_at"] as String?,
                    assignments: assignments
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Maintenance Records
    // =========================================================================

    /// List maintenance records, optionally filtered by vehicle.
    public func listMaintenanceRecords(vehicleId: Int64? = nil, limit: Int = 50) throws -> [MaintenanceRow] {
        do {
            return try db.writer.read { dbConn -> [MaintenanceRow] in
                var whereClauses = ["mr.deleted_at IS NULL"]
                var args: [(any DatabaseValueConvertible)?] = []

                if let vehicleId {
                    whereClauses.append("mr.vehicle_id = ?")
                    args.append(vehicleId)
                }

                args.append(limit)

                let sql = """
                    SELECT mr.id, mr.performed_at, mr.cost, mr.odometer_reading,
                           v.vehicle_name,
                           mt.name AS maintenance_type_name,
                           COALESCE(u.display_name, u.email) AS performed_by_name
                    FROM maintenance_records mr
                    LEFT JOIN vehicles v ON v.id = mr.vehicle_id AND v.deleted_at IS NULL AND v.is_active = 1
                    LEFT JOIN maintenance_types mt ON mt.id = mr.maintenance_type_id
                    LEFT JOIN users u ON u.id = mr.performed_by AND u.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY mr.performed_at DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    MaintenanceRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "",
                        maintenanceTypeName: row["maintenance_type_name"] as String?,
                        performedAt: row["performed_at"] ?? "",
                        performedByName: row["performed_by_name"] as String?,
                        cost: row["cost"] as Double?,
                        odometerReading: row["odometer_reading"] as Int?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3. Mileage Logs
    // =========================================================================

    /// List mileage logs, optionally filtered by vehicle and/or user.
    public func listMileageLogs(vehicleId: Int64? = nil, userId: Int64? = nil, limit: Int = 50) throws -> [MileageRow] {
        do {
            return try db.writer.read { dbConn -> [MileageRow] in
                var whereClauses = ["ml.deleted_at IS NULL"]
                var args: [(any DatabaseValueConvertible)?] = []

                if let vehicleId {
                    whereClauses.append("ml.vehicle_id = ?")
                    args.append(vehicleId)
                }
                if let userId {
                    whereClauses.append("ml.user_id = ?")
                    args.append(userId)
                }

                args.append(limit)

                let sql = """
                    SELECT ml.id, ml.log_date, ml.total_miles, ml.purpose,
                           v.vehicle_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name
                    FROM mileage_logs ml
                    LEFT JOIN vehicles v ON v.id = ml.vehicle_id AND v.deleted_at IS NULL AND v.is_active = 1
                    LEFT JOIN users u ON u.id = ml.user_id AND u.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY ml.log_date DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    MileageRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "",
                        userName: row["user_name"] ?? "Unknown",
                        logDate: row["log_date"] ?? "",
                        totalMiles: row["total_miles"] as Double?,
                        purpose: row["purpose"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 4. Fuel Logs
    // =========================================================================

    /// List fuel logs, optionally filtered by vehicle.
    public func listFuelLogs(vehicleId: Int64? = nil, limit: Int = 50) throws -> [FuelRow] {
        do {
            return try db.writer.read { dbConn -> [FuelRow] in
                var whereClauses = ["fl.deleted_at IS NULL"]
                var args: [(any DatabaseValueConvertible)?] = []

                if let vehicleId {
                    whereClauses.append("fl.vehicle_id = ?")
                    args.append(vehicleId)
                }

                args.append(limit)

                let sql = """
                    SELECT fl.id, fl.log_date, fl.gallons, fl.total_cost, fl.station,
                           v.vehicle_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name
                    FROM fuel_logs fl
                    LEFT JOIN vehicles v ON v.id = fl.vehicle_id AND v.deleted_at IS NULL AND v.is_active = 1
                    LEFT JOIN users u ON u.id = fl.user_id AND u.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY fl.log_date DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    FuelRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "",
                        userName: row["user_name"] ?? "Unknown",
                        logDate: row["log_date"] ?? "",
                        gallons: row["gallons"] as Double?,
                        totalCost: row["total_cost"] as Double?,
                        station: row["station"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5. Trailers
    // =========================================================================

    /// List trailers with optional status filter. Includes current job and assigned vehicle names.
    public func listTrailers(status: String? = nil) throws -> [TrailerListItem] {
        do {
            return try db.writer.read { dbConn -> [TrailerListItem] in
                var whereClauses = ["jt.deleted_at IS NULL", "jt.is_active = 1"]
                var args: [(any DatabaseValueConvertible)?] = []

                if let status, !status.isEmpty {
                    whereClauses.append("jt.status = ?")
                    args.append(status)
                }

                let sql = """
                    SELECT jt.id, jt.trailer_code AS trailer_number, jt.name AS trailer_type, jt.status,
                           j.job_name AS current_job_name,
                           u.display_name AS assigned_driver_name
                    FROM job_trailers jt
                    LEFT JOIN jobs j ON j.id = jt.current_job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jt.assigned_driver_user_id AND u.deleted_at IS NULL
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY jt.trailer_code ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    TrailerListItem(
                        id: row["id"] ?? 0,
                        trailerNumber: row["trailer_number"] ?? "",
                        trailerType: row["trailer_type"] ?? "",
                        status: row["status"] ?? "available",
                        currentJobName: row["current_job_name"] as String?,
                        assignedVehicleName: row["assigned_driver_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 6. Fleet Stats
    // =========================================================================

    /// Get fleet-wide dashboard statistics.
    public func getFleetStats() throws -> FleetStats {
        let totalVehicles = try safeCount(
            sql: "SELECT COUNT(*) FROM vehicles WHERE deleted_at IS NULL AND is_active = 1"
        )

        let activeVehicles = try safeCount(
            sql: "SELECT COUNT(*) FROM vehicles WHERE status = 'active' AND deleted_at IS NULL AND is_active = 1"
        )

        // Maintenance due: schedules where next_due_date <= today or next_due_miles <= current odometer
        let maintenanceDue = try safeCount(
            sql: """
                SELECT COUNT(*) FROM maintenance_schedules ms
                JOIN vehicles v ON v.id = ms.vehicle_id AND v.deleted_at IS NULL AND v.is_active = 1
                WHERE ms.deleted_at IS NULL
                  AND (
                    (ms.next_due_date IS NOT NULL AND date(ms.next_due_date) <= date('now'))
                    OR (ms.next_due_miles IS NOT NULL AND v.current_odometer IS NOT NULL
                        AND ms.next_due_miles <= v.current_odometer)
                  )
                """
        )

        let totalTrailers = try safeCount(
            sql: "SELECT COUNT(*) FROM job_trailers WHERE deleted_at IS NULL AND is_active = 1"
        )

        return FleetStats(
            totalVehicles: totalVehicles,
            activeVehicles: activeVehicles,
            maintenanceDue: maintenanceDue,
            totalTrailers: totalTrailers
        )
    }

    // =========================================================================
    // MARK: - 6b. Fleet Dashboard KPIs
    // =========================================================================

    /// Extended fleet dashboard statistics with cost data and inspection status.
    public struct FleetDashboardStats: Sendable {
        public let totalVehicles: Int
        public let activeVehicles: Int
        public let maintenanceDue: Int
        public let overdueInspections: Int
        public let totalTrailers: Int
        // Cost stats (month-to-date)
        public let fuelCostMTD: Double?
        public let milesMTD: Int?
        public let maintenanceCostMTD: Double?

        public init(
            totalVehicles: Int, activeVehicles: Int, maintenanceDue: Int,
            overdueInspections: Int, totalTrailers: Int,
            fuelCostMTD: Double?, milesMTD: Int?, maintenanceCostMTD: Double?
        ) {
            self.totalVehicles = totalVehicles
            self.activeVehicles = activeVehicles
            self.maintenanceDue = maintenanceDue
            self.overdueInspections = overdueInspections
            self.totalTrailers = totalTrailers
            self.fuelCostMTD = fuelCostMTD
            self.milesMTD = milesMTD
            self.maintenanceCostMTD = maintenanceCostMTD
        }
    }

    /// Vehicle status item for the dashboard vehicle list.
    public struct VehicleStatusItem: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let vehicleType: String
        public let status: String
        public let driverName: String?
        public let lastInspectionDate: String?
        public let nextMaintenanceDate: String?

        public init(
            id: Int64, vehicleName: String, vehicleType: String,
            status: String, driverName: String?,
            lastInspectionDate: String?, nextMaintenanceDate: String?
        ) {
            self.id = id
            self.vehicleName = vehicleName
            self.vehicleType = vehicleType
            self.status = status
            self.driverName = driverName
            self.lastInspectionDate = lastInspectionDate
            self.nextMaintenanceDate = nextMaintenanceDate
        }
    }

    /// Upcoming maintenance item for the dashboard.
    public struct FleetMaintenanceItem: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let nextMaintenanceDate: String
        public let daysUntil: Double

        public init(id: Int64, vehicleName: String, nextMaintenanceDate: String, daysUntil: Double) {
            self.id = id
            self.vehicleName = vehicleName
            self.nextMaintenanceDate = nextMaintenanceDate
            self.daysUntil = daysUntil
        }
    }

    /// Get full fleet dashboard statistics including overdue inspections and cost data.
    public func getFleetDashboardStats() throws -> FleetDashboardStats {
        let basic = try getFleetStats()

        // Overdue inspections: active vehicles with no inspection today
        let overdueInspections = try safeCount(sql: """
            SELECT COUNT(*) FROM vehicles v
            WHERE v.status = 'active' AND v.deleted_at IS NULL AND v.is_active = 1
              AND v.id IN (SELECT vehicle_id FROM vehicle_assignments WHERE is_active = 1 AND deleted_at IS NULL)
              AND v.id NOT IN (
                  SELECT vehicle_id FROM inspection_records
                  WHERE deleted_at IS NULL AND date(performed_at) = date('now')
              )
            """)

        // Month-to-date cost stats
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let monthStr = fmt.string(from: startOfMonth)

        let fuelCostMTD: Double? = try {
            do {
                return try db.writer.read { dbConn in
                    try Double.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(total_cost), 0) FROM fuel_logs
                        WHERE log_date >= ? AND deleted_at IS NULL
                        """, arguments: [monthStr])
                }
            } catch {
                if isTableNotFoundError(error) { return 0 }
                throw error
            }
        }()

        let milesMTD: Int? = try {
            do {
                return try db.writer.read { dbConn in
                    try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(CAST(SUM(total_miles) AS INTEGER), 0) FROM mileage_logs
                        WHERE log_date >= ? AND deleted_at IS NULL
                        """, arguments: [monthStr])
                }
            } catch {
                if isTableNotFoundError(error) { return 0 }
                throw error
            }
        }()

        let maintenanceCostMTD: Double? = try {
            do {
                return try db.writer.read { dbConn in
                    try Double.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(cost), 0) FROM maintenance_records
                        WHERE performed_at >= ? AND deleted_at IS NULL
                        """, arguments: [monthStr])
                }
            } catch {
                if isTableNotFoundError(error) { return 0 }
                throw error
            }
        }()

        return FleetDashboardStats(
            totalVehicles: basic.totalVehicles,
            activeVehicles: basic.activeVehicles,
            maintenanceDue: basic.maintenanceDue,
            overdueInspections: overdueInspections,
            totalTrailers: basic.totalTrailers,
            fuelCostMTD: fuelCostMTD,
            milesMTD: milesMTD,
            maintenanceCostMTD: maintenanceCostMTD
        )
    }

    /// Get all vehicles with their current assignment and inspection status.
    public func getVehicleStatusList() throws -> [VehicleStatusItem] {
        do {
            return try db.writer.read { dbConn -> [VehicleStatusItem] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT v.id, v.vehicle_name, v.vehicle_type, v.status,
                           v.next_maintenance_date,
                           COALESCE(u.display_name, u.email) AS driver_name,
                           (SELECT MAX(ir.performed_at) FROM inspection_records ir
                            WHERE ir.vehicle_id = v.id AND ir.deleted_at IS NULL) AS last_inspection_date
                    FROM vehicles v
                    LEFT JOIN vehicle_assignments va ON v.id = va.vehicle_id AND va.is_active = 1 AND va.deleted_at IS NULL
                    LEFT JOIN users u ON va.user_id = u.id AND u.deleted_at IS NULL
                    WHERE v.status != 'retired' AND v.deleted_at IS NULL AND v.is_active = 1
                    ORDER BY v.vehicle_name
                    """)

                return rows.map { row in
                    VehicleStatusItem(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        vehicleType: row["vehicle_type"] ?? "truck",
                        status: row["status"] ?? "active",
                        driverName: row["driver_name"] as String?,
                        lastInspectionDate: row["last_inspection_date"] as String?,
                        nextMaintenanceDate: row["next_maintenance_date"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get upcoming fleet maintenance sorted by earliest due date.
    public func getUpcomingFleetMaintenance(limit: Int = 10) throws -> [FleetMaintenanceItem] {
        do {
            return try db.writer.read { dbConn -> [FleetMaintenanceItem] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT v.id, COALESCE(v.vehicle_name, v.vehicle_number) AS vehicle_name,
                           v.next_maintenance_date,
                           julianday(v.next_maintenance_date) - julianday('now') AS days_until
                    FROM vehicles v
                    WHERE v.next_maintenance_date IS NOT NULL
                      AND v.status != 'retired' AND v.deleted_at IS NULL AND v.is_active = 1
                    ORDER BY v.next_maintenance_date ASC
                    LIMIT ?
                    """, arguments: [limit])

                return rows.map { row in
                    FleetMaintenanceItem(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        nextMaintenanceDate: row["next_maintenance_date"] ?? "",
                        daysUntil: row["days_until"] ?? 0.0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7. Inspections
    // =========================================================================

    /// An inspection record row with vehicle and inspector names.
    public struct InspectionRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let inspectorName: String
        public let inspectionDate: String
        public let result: String
        public let odometerReading: Int?
        public let notes: String?

        public init(
            id: Int64, vehicleName: String, inspectorName: String,
            inspectionDate: String, result: String,
            odometerReading: Int?, notes: String?
        ) {
            self.id = id
            self.vehicleName = vehicleName
            self.inspectorName = inspectorName
            self.inspectionDate = inspectionDate
            self.result = result
            self.odometerReading = odometerReading
            self.notes = notes
        }
    }

    /// List vehicle inspections, most recent first.
    public func listInspections(limit: Int = 100) throws -> [InspectionRow] {
        do {
            return try db.writer.read { dbConn -> [InspectionRow] in
                let sql = """
                    SELECT ir.id, ir.performed_at AS inspection_date, ir.result, ir.notes, ir.odometer_reading,
                           COALESCE(v.vehicle_name, v.vehicle_number, 'Unknown') AS vehicle_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS inspector_name
                    FROM inspection_records ir
                    LEFT JOIN vehicles v ON v.id = ir.vehicle_id AND v.deleted_at IS NULL AND v.is_active = 1
                    LEFT JOIN users u ON u.id = ir.inspector_id AND u.deleted_at IS NULL
                    WHERE ir.deleted_at IS NULL
                    ORDER BY ir.performed_at DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [limit])
                return rows.map { row in
                    InspectionRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        inspectorName: row["inspector_name"] ?? "Unknown",
                        inspectionDate: row["inspection_date"] ?? "",
                        result: row["result"] ?? "pending",
                        odometerReading: row["odometer_reading"] as Int?,
                        notes: row["notes"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 8. Telematics / GPS
    // =========================================================================

    /// A vehicle location row for telematics display.
    public struct VehicleLocationRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let driverName: String
        public let latitude: Double?
        public let longitude: Double?
        public let speed: Double?
        public let status: String
        public let lastUpdated: String

        public init(
            id: Int64, vehicleName: String, driverName: String,
            latitude: Double?, longitude: Double?, speed: Double?,
            status: String, lastUpdated: String
        ) {
            self.id = id
            self.vehicleName = vehicleName
            self.driverName = driverName
            self.latitude = latitude
            self.longitude = longitude
            self.speed = speed
            self.status = status
            self.lastUpdated = lastUpdated
        }
    }

    /// List latest GPS/telematics data — one row per vehicle, most recent position.
    public func listTelematicsData() throws -> [VehicleLocationRow] {
        do {
            return try db.writer.read { dbConn -> [VehicleLocationRow] in
                let sql = """
                    SELECT vll.id, vll.latitude, vll.longitude, vll.speed,
                           vll.status, vll.recorded_at,
                           COALESCE(v.vehicle_name, v.vehicle_number, 'Unknown') AS vehicle_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS driver_name
                    FROM vehicle_location_logs vll
                    LEFT JOIN vehicles v ON v.id = vll.vehicle_id AND v.deleted_at IS NULL AND v.is_active = 1
                    LEFT JOIN users u ON u.id = vll.user_id AND u.deleted_at IS NULL
                    WHERE vll.id IN (
                        SELECT MAX(id) FROM vehicle_location_logs
                        WHERE deleted_at IS NULL
                        GROUP BY vehicle_id
                    )
                    ORDER BY vll.recorded_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    VehicleLocationRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        driverName: row["driver_name"] ?? "Unknown",
                        latitude: row["latitude"] as Double?,
                        longitude: row["longitude"] as Double?,
                        speed: row["speed"] as Double?,
                        status: row["status"] ?? "unknown",
                        lastUpdated: row["recorded_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 9. Create / Mutate
    // =========================================================================

    /// Create a new vehicle. Returns the inserted row ID.
    public func createVehicle(
        vehicleNumber: String,
        vehicleName: String,
        vehicleType: String,
        make: String?,
        model: String?,
        year: Int?,
        color: String?,
        vin: String?,
        licensePlate: String?,
        notes: String?
    ) throws -> Int64 {
        guard !vehicleNumber.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FleetError.requiredFieldEmpty("vehicleNumber")
        }
        guard !vehicleName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FleetError.requiredFieldEmpty("vehicleName")
        }
        return try db.writer.write { dbConn in
            let now = CoreFormatters.nowISO()
            try dbConn.execute(
                sql: """
                    INSERT INTO vehicles (vehicle_number, vehicle_name, vehicle_type,
                        make, model, year, color, vin, license_plate, notes,
                        status, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', 1, ?, ?)
                    """,
                arguments: [vehicleNumber, vehicleName, vehicleType,
                            make, model, year, color, vin, licensePlate, notes,
                            now, now]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Create a new trailer. Returns the inserted row ID.
    public func createTrailer(
        trailerNumber: String,
        trailerType: String,
        notes: String?
    ) throws -> Int64 {
        guard !trailerNumber.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FleetError.requiredFieldEmpty("trailerNumber")
        }
        guard !trailerType.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FleetError.requiredFieldEmpty("trailerType")
        }
        return try db.writer.write { dbConn in
            let now = CoreFormatters.nowISO()
            try dbConn.execute(
                sql: """
                    INSERT INTO job_trailers (trailer_code, name, status, notes, created_at, updated_at)
                    VALUES (?, ?, 'available', ?, ?, ?)
                    """,
                arguments: [trailerNumber, trailerType, notes, now, now]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Assign a driver (user) to a vehicle.
    public func assignDriver(
        vehicleId: Int64,
        userId: Int64,
        assignmentType: String,
        isTakeHome: Bool
    ) throws {
        try db.writer.write { dbConn in
            // Guard: both vehicle and user must exist and not be tombstoned —
            // otherwise the INSERT INTO vehicle_assignments would orphan-link
            // to a soft-deleted parent (the FK constraint allows the write).
            let vehicleExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM vehicles WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [vehicleId]) ?? 0) > 0
            guard vehicleExists else { return }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL
                """, arguments: [userId]) ?? 0) > 0
            guard userExists else { return }

            try dbConn.execute(
                sql: """
                    INSERT INTO vehicle_assignments
                        (vehicle_id, user_id, assignment_type, is_take_home, is_active)
                    VALUES (?, ?, ?, ?, 1)
                    """,
                arguments: [vehicleId, userId, assignmentType, isTakeHome ? 1 : 0]
            )
        }
    }

    // =========================================================================
    // MARK: - 10. My Vehicle Stats
    // =========================================================================

    /// Stats for the "My Vehicle" smart cards dashboard.
    public struct MyVehicleStats: Sendable {
        public let vehicleId: Int64
        public let toolCount: Int
        public let partCount: Int
        public let fuelLevel: Double?     // 0.0–1.0, nil if not tracked
        public let maintenanceDue: Int
        public let transferItems: Int     // items in transfer area
        public let hasTrailer: Bool
        public let trailerName: String?
        public let trailerId: Int64?

        public init(
            vehicleId: Int64, toolCount: Int, partCount: Int, fuelLevel: Double?,
            maintenanceDue: Int, transferItems: Int,
            hasTrailer: Bool, trailerName: String?, trailerId: Int64?
        ) {
            self.vehicleId = vehicleId
            self.toolCount = toolCount
            self.partCount = partCount
            self.fuelLevel = fuelLevel
            self.maintenanceDue = maintenanceDue
            self.transferItems = transferItems
            self.hasTrailer = hasTrailer
            self.trailerName = trailerName
            self.trailerId = trailerId
        }
    }

    /// Get aggregated stats for the current user's assigned vehicle.
    public func getMyVehicleStats(userId: Int64) throws -> MyVehicleStats? {
        do {
            return try db.writer.read { dbConn -> MyVehicleStats? in
                // Find assigned vehicle
                guard let assignment = try Row.fetchOne(dbConn, sql: """
                    SELECT va.vehicle_id, v.vehicle_name, v.fuel_level
                    FROM vehicle_assignments va
                    JOIN vehicles v ON va.vehicle_id = v.id AND v.deleted_at IS NULL AND v.is_active = 1
                    WHERE va.user_id = ? AND va.is_active = 1 AND va.deleted_at IS NULL
                    ORDER BY va.start_date DESC LIMIT 1
                    """, arguments: [userId]) else {
                    return nil
                }

                let vehicleId: Int64 = assignment["vehicle_id"] ?? 0

                // Tools checked out to this user that are on the vehicle
                let toolCount = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM tool_checkouts tc
                    JOIN tools t ON tc.tool_id = t.id
                    WHERE tc.checked_out_by = ? AND tc.checked_in_at IS NULL
                    AND t.deleted_at IS NULL
                    """, arguments: [userId]) ?? 0

                // Truck stock (permanent parts)
                let partCount = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(quantity), 0) FROM vehicle_stock
                    WHERE vehicle_id = ? AND stock_type = 'truck_stock' AND deleted_at IS NULL
                    """, arguments: [vehicleId]) ?? 0

                // Maintenance due within 7 days
                let maintenanceDue = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM maintenance_schedules ms
                    WHERE ms.vehicle_id = ? AND ms.deleted_at IS NULL
                    AND ms.next_due_date IS NOT NULL
                    AND date(ms.next_due_date) <= date('now', '+7 days')
                    """, arguments: [vehicleId]) ?? 0

                // Transfer items
                let transferItems = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(quantity), 0) FROM vehicle_stock
                    WHERE vehicle_id = ? AND stock_type = 'transfer' AND deleted_at IS NULL
                    """, arguments: [vehicleId]) ?? 0

                // Attached trailer
                let trailer = try Row.fetchOne(dbConn, sql: """
                    SELECT ta.trailer_id, jt.name
                    FROM trailer_attachments ta
                    JOIN job_trailers jt ON ta.trailer_id = jt.id AND jt.deleted_at IS NULL AND jt.is_active = 1
                    WHERE ta.vehicle_id = ? AND ta.detached_at IS NULL AND ta.deleted_at IS NULL
                    """, arguments: [vehicleId])

                let fuelLevel: Double? = assignment["fuel_level"]

                return MyVehicleStats(
                    vehicleId: vehicleId,
                    toolCount: toolCount,
                    partCount: partCount,
                    fuelLevel: fuelLevel,
                    maintenanceDue: maintenanceDue,
                    transferItems: transferItems,
                    hasTrailer: trailer != nil,
                    trailerName: trailer?["name"] as String?,
                    trailerId: trailer?["trailer_id"] as Int64?
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 11. Vehicle Stock
    // =========================================================================

    /// A vehicle stock item for inventory display.
    public struct VehicleStockItem: Sendable, Identifiable {
        public let id: Int64
        public let partName: String
        public let quantity: Int
        public let stockType: String
        public let minQty: Int?
        public let targetQty: Int?
        public let maxQty: Int?
        public let sourceLocation: String?
        public let destinationLocation: String?
        public let transferReason: String?

        public init(
            id: Int64, partName: String, quantity: Int, stockType: String,
            minQty: Int?, targetQty: Int?, maxQty: Int?,
            sourceLocation: String?, destinationLocation: String?,
            transferReason: String?
        ) {
            self.id = id
            self.partName = partName
            self.quantity = quantity
            self.stockType = stockType
            self.minQty = minQty
            self.targetQty = targetQty
            self.maxQty = maxQty
            self.sourceLocation = sourceLocation
            self.destinationLocation = destinationLocation
            self.transferReason = transferReason
        }
    }

    /// List vehicle stock items by type (truck_stock or transfer).
    public func getVehicleStock(vehicleId: Int64, stockType: String) throws -> [VehicleStockItem] {
        do {
            return try db.writer.read { dbConn -> [VehicleStockItem] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, part_name, quantity, stock_type,
                           min_qty, target_qty, max_qty,
                           source_location, destination_location, transfer_reason
                    FROM vehicle_stock
                    WHERE vehicle_id = ? AND stock_type = ? AND deleted_at IS NULL
                    ORDER BY part_name ASC
                    """, arguments: [vehicleId, stockType])

                return rows.map { row in
                    VehicleStockItem(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "",
                        quantity: row["quantity"] ?? 0,
                        stockType: row["stock_type"] ?? stockType,
                        minQty: row["min_qty"] as Int?,
                        targetQty: row["target_qty"] as Int?,
                        maxQty: row["max_qty"] as Int?,
                        sourceLocation: row["source_location"] as String?,
                        destinationLocation: row["destination_location"] as String?,
                        transferReason: row["transfer_reason"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 12. Vehicle Tools
    // =========================================================================

    /// A tool currently checked out to a vehicle's assigned driver.
    public struct VehicleToolItem: Sendable, Identifiable {
        public let id: Int64
        public let toolName: String
        public let toolNumber: String
        public let checkedOutBy: String
        public let condition: String
        public let checkedOutAt: String

        public init(
            id: Int64, toolName: String, toolNumber: String,
            checkedOutBy: String, condition: String, checkedOutAt: String
        ) {
            self.id = id
            self.toolName = toolName
            self.toolNumber = toolNumber
            self.checkedOutBy = checkedOutBy
            self.condition = condition
            self.checkedOutAt = checkedOutAt
        }
    }

    /// Get tools checked out to users assigned to a specific vehicle.
    public func getVehicleTools(vehicleId: Int64) throws -> [VehicleToolItem] {
        do {
            return try db.writer.read { dbConn -> [VehicleToolItem] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT tc.id, t.name AS tool_name, t.tool_number,
                           COALESCE(u.display_name, u.email, 'Unknown') AS checked_out_by,
                           COALESCE(tc.checkout_condition, 'good') AS condition,
                           tc.checked_out_at
                    FROM tool_checkouts tc
                    JOIN tools t ON tc.tool_id = t.id
                    LEFT JOIN users u ON tc.checked_out_by = u.id AND u.deleted_at IS NULL
                    WHERE tc.checked_in_at IS NULL
                    AND tc.checked_out_by IN (
                        SELECT user_id FROM vehicle_assignments
                        WHERE vehicle_id = ? AND is_active = 1 AND deleted_at IS NULL
                    )
                    ORDER BY t.name ASC
                    """, arguments: [vehicleId])

                return rows.map { row in
                    VehicleToolItem(
                        id: row["id"] ?? 0,
                        toolName: row["tool_name"] ?? "",
                        toolNumber: row["tool_number"] ?? "",
                        checkedOutBy: row["checked_out_by"] ?? "Unknown",
                        condition: row["condition"] ?? "good",
                        checkedOutAt: row["checked_out_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 13. Vehicle Stock Mutations
    // =========================================================================

    /// Add a stock item (truck_stock or transfer) to a vehicle.
    public func addVehicleStockItem(
        vehicleId: Int64,
        partName: String,
        quantity: Int,
        stockType: String,
        partId: Int64? = nil,
        minQty: Int? = nil,
        targetQty: Int? = nil,
        maxQty: Int? = nil,
        sourceLocation: String? = nil,
        destinationLocation: String? = nil,
        transferReason: String? = nil
    ) throws {
        guard !partName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FleetError.requiredFieldEmpty("partName")
        }
        guard quantity > 0 else { throw FleetError.invalidQuantity(quantity) }

        try db.writer.write { dbConn in
            // Guard: vehicle must exist and not be tombstoned — otherwise the INSERT
            // would create an orphan vehicle_stock row against a decommissioned truck.
            let vehicleExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM vehicles WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [vehicleId]) ?? 0) > 0
            guard vehicleExists else { throw FleetError.vehicleNotFound(vehicleId) }

            try dbConn.execute(
                sql: """
                    INSERT INTO vehicle_stock
                    (vehicle_id, part_id, part_name, quantity, stock_type,
                     min_qty, target_qty, max_qty,
                     source_location, destination_location, transfer_reason)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [vehicleId, partId, partName, quantity, stockType,
                            minQty, targetQty, maxQty,
                            sourceLocation, destinationLocation, transferReason]
            )
        }
    }

    /// Log a fuel fill-up and update the vehicle's fuel_level.
    /// fuelLevel must be in [0.0, 1.0] — a fraction of a full tank.
    public func logFuelLevel(vehicleId: Int64, fuelLevel: Double) throws {
        guard fuelLevel >= 0.0 && fuelLevel <= 1.0 else {
            throw FleetError.invalidFuelLevel(fuelLevel)
        }
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE vehicles SET fuel_level = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [fuelLevel, vehicleId]
            )
        }
    }

    // =========================================================================
    // MARK: - 14. Trailer Detail
    // =========================================================================

    /// Full trailer detail including location status.
    public struct TrailerDetail: Sendable {
        public let id: Int64
        public let trailerCode: String
        public let name: String
        public let status: String
        public let isAtShop: Bool
        public let linkedWarehouseId: Int64?
        public let currentJobName: String?
        public let assignedDriverName: String?

        public init(
            id: Int64, trailerCode: String, name: String, status: String,
            isAtShop: Bool, linkedWarehouseId: Int64?,
            currentJobName: String?, assignedDriverName: String?
        ) {
            self.id = id
            self.trailerCode = trailerCode
            self.name = name
            self.status = status
            self.isAtShop = isAtShop
            self.linkedWarehouseId = linkedWarehouseId
            self.currentJobName = currentJobName
            self.assignedDriverName = assignedDriverName
        }
    }

    /// Get a trailer's full detail by ID.
    public func getTrailerDetail(trailerId: Int64) throws -> TrailerDetail? {
        do {
            return try db.writer.read { dbConn -> TrailerDetail? in
                guard let row = try Row.fetchOne(dbConn, sql: """
                    SELECT jt.*, j.job_name AS current_job_name,
                           COALESCE(u.display_name, u.email) AS assigned_driver_name
                    FROM job_trailers jt
                    LEFT JOIN jobs j ON j.id = jt.current_job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jt.assigned_driver_user_id AND u.deleted_at IS NULL
                    WHERE jt.id = ? AND jt.deleted_at IS NULL AND jt.is_active = 1
                    """, arguments: [trailerId]) else {
                    return nil
                }

                return TrailerDetail(
                    id: row["id"] ?? 0,
                    trailerCode: row["trailer_code"] ?? "",
                    name: row["name"] ?? "",
                    status: row["status"] ?? "available",
                    isAtShop: (row["is_at_shop"] as Int?) == 1,
                    linkedWarehouseId: row["linked_warehouse_id"] as Int64?,
                    currentJobName: row["current_job_name"] as String?,
                    assignedDriverName: row["assigned_driver_name"] as String?
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 15. Trailer Stock
    // =========================================================================

    /// A stock item in a trailer's inventory.
    public struct TrailerStockItem: Sendable, Identifiable {
        public let id: Int64
        public let partName: String
        public let quantity: Int
        public let minQty: Int?
        public let targetQty: Int?
        public let maxQty: Int?
        public let storageUnitId: Int64?
        public let storageUnitName: String?

        public init(
            id: Int64, partName: String, quantity: Int,
            minQty: Int?, targetQty: Int?, maxQty: Int?,
            storageUnitId: Int64?, storageUnitName: String?
        ) {
            self.id = id
            self.partName = partName
            self.quantity = quantity
            self.minQty = minQty
            self.targetQty = targetQty
            self.maxQty = maxQty
            self.storageUnitId = storageUnitId
            self.storageUnitName = storageUnitName
        }
    }

    /// Get all stock items for a trailer.
    public func getTrailerStock(trailerId: Int64) throws -> [TrailerStockItem] {
        do {
            return try db.writer.read { dbConn -> [TrailerStockItem] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT ts.id, ts.part_name, ts.quantity,
                           ts.min_qty, ts.target_qty, ts.max_qty,
                           ts.storage_unit_id, tsu.name AS storage_unit_name
                    FROM trailer_stock ts
                    LEFT JOIN trailer_storage_units tsu ON ts.storage_unit_id = tsu.id
                    WHERE ts.trailer_id = ? AND ts.deleted_at IS NULL
                    ORDER BY tsu.sort_order, ts.part_name
                    """, arguments: [trailerId])

                return rows.map { row in
                    TrailerStockItem(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "",
                        quantity: row["quantity"] ?? 0,
                        minQty: row["min_qty"] as Int?,
                        targetQty: row["target_qty"] as Int?,
                        maxQty: row["max_qty"] as Int?,
                        storageUnitId: row["storage_unit_id"] as Int64?,
                        storageUnitName: row["storage_unit_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 16. Trailer Storage Units
    // =========================================================================

    /// A physical storage unit in a trailer (shelf, drawer, bin, etc.).
    public struct TrailerStorageUnit: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let unitType: String
        public let capacitySlots: Int?
        public let sortOrder: Int

        public init(id: Int64, name: String, unitType: String, capacitySlots: Int?, sortOrder: Int) {
            self.id = id
            self.name = name
            self.unitType = unitType
            self.capacitySlots = capacitySlots
            self.sortOrder = sortOrder
        }
    }

    /// Get storage units for a trailer.
    public func getTrailerStorageUnits(trailerId: Int64) throws -> [TrailerStorageUnit] {
        do {
            return try db.writer.read { dbConn -> [TrailerStorageUnit] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, name, unit_type, capacity_slots, sort_order
                    FROM trailer_storage_units
                    WHERE trailer_id = ? AND deleted_at IS NULL
                    ORDER BY sort_order
                    """, arguments: [trailerId])

                return rows.map { row in
                    TrailerStorageUnit(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        unitType: row["unit_type"] ?? "shelf",
                        capacitySlots: row["capacity_slots"] as Int?,
                        sortOrder: row["sort_order"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 17. Trailer Location History
    // =========================================================================

    /// A location history record for a trailer.
    public struct TrailerLocationRecord: Sendable, Identifiable {
        public let id: Int64
        public let locationType: String
        public let locationLabel: String?
        public let arrivedAt: String
        public let departedAt: String?
        public let recordedByName: String?

        public init(
            id: Int64, locationType: String, locationLabel: String?,
            arrivedAt: String, departedAt: String?, recordedByName: String?
        ) {
            self.id = id
            self.locationType = locationType
            self.locationLabel = locationLabel
            self.arrivedAt = arrivedAt
            self.departedAt = departedAt
            self.recordedByName = recordedByName
        }
    }

    /// Get location history for a trailer.
    public func getTrailerLocationHistory(trailerId: Int64, limit: Int = 20) throws -> [TrailerLocationRecord] {
        do {
            return try db.writer.read { dbConn -> [TrailerLocationRecord] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT tlh.id, tlh.location_type, tlh.location_label,
                           tlh.arrived_at, tlh.departed_at,
                           COALESCE(u.display_name, u.email) AS recorded_by_name
                    FROM trailer_location_history tlh
                    LEFT JOIN users u ON u.id = tlh.recorded_by AND u.deleted_at IS NULL
                    WHERE tlh.trailer_id = ? AND tlh.deleted_at IS NULL
                    ORDER BY tlh.arrived_at DESC
                    LIMIT ?
                    """, arguments: [trailerId, limit])

                return rows.map { row in
                    TrailerLocationRecord(
                        id: row["id"] ?? 0,
                        locationType: row["location_type"] ?? "",
                        locationLabel: row["location_label"] as String?,
                        arrivedAt: row["arrived_at"] ?? "",
                        departedAt: row["departed_at"] as String?,
                        recordedByName: row["recorded_by_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Update trailer location (close previous, open new).
    public func updateTrailerLocation(
        trailerId: Int64, locationType: String, locationLabel: String?,
        jobId: Int64? = nil, recordedBy: Int64
    ) throws {
        try db.writer.write { dbConn in
            // Close previous location
            try dbConn.execute(sql: """
                UPDATE trailer_location_history SET departed_at = datetime('now')
                WHERE trailer_id = ? AND departed_at IS NULL
                """, arguments: [trailerId])

            // Insert new location
            try dbConn.execute(sql: """
                INSERT INTO trailer_location_history
                (trailer_id, location_type, location_label, job_id, recorded_by)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [trailerId, locationType, locationLabel, jobId, recordedBy])

            // Update is_at_shop flag
            let isAtShop = locationType == "shop" ? 1 : 0
            try dbConn.execute(sql: """
                UPDATE job_trailers SET is_at_shop = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [isAtShop, trailerId])
        }
    }

    // =========================================================================
    // MARK: - 18. Pre-Trip Inspection Checklist
    // =========================================================================

    /// A template checklist item returned by getInspectionChecklist.
    public struct InspectionTemplateItem: Sendable, Identifiable {
        public let id: Int64
        public let vehicleType: String
        public let section: String
        public let itemName: String
        public let itemDescription: String?
        public let isCritical: Bool
        public let sortOrder: Int

        public init(
            id: Int64, vehicleType: String, section: String,
            itemName: String, itemDescription: String?,
            isCritical: Bool, sortOrder: Int
        ) {
            self.id = id
            self.vehicleType = vehicleType
            self.section = section
            self.itemName = itemName
            self.itemDescription = itemDescription
            self.isCritical = isCritical
            self.sortOrder = sortOrder
        }
    }

    /// Result payload for a single item when saving an inspection.
    public struct InspectionItemResult: Sendable {
        public let templateItemId: Int64
        public let status: String   // "ok", "issue", "na"
        public let notes: String?

        public init(templateItemId: Int64, status: String, notes: String? = nil) {
            self.templateItemId = templateItemId
            self.status = status
            self.notes = notes
        }
    }

    /// Inspection requirement for clock-in integration.
    public enum InspectionRequirement: Sendable {
        case cleared
        case required(reason: String)
        case blocked(reason: String)
    }

    /// A saved inspection record for history display.
    public struct InspectionRecordRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let inspectorName: String
        public let result: String
        public let performedAt: String
        public let odometerReading: Int?
        public let fuelLevel: Double?
        public let notes: String?

        public init(
            id: Int64, vehicleName: String, inspectorName: String,
            result: String, performedAt: String,
            odometerReading: Int?, fuelLevel: Double?, notes: String?
        ) {
            self.id = id
            self.vehicleName = vehicleName
            self.inspectorName = inspectorName
            self.result = result
            self.performedAt = performedAt
            self.odometerReading = odometerReading
            self.fuelLevel = fuelLevel
            self.notes = notes
        }
    }

    /// Get the inspection checklist for a vehicle type, optionally including trailer items.
    public func getInspectionChecklist(vehicleType: String, includeTrailer: Bool = false) throws -> [InspectionTemplateItem] {
        do {
            return try db.writer.read { dbConn -> [InspectionTemplateItem] in
                var types = [vehicleType.lowercased()]
                if includeTrailer { types.append("trailer") }

                let placeholders = types.map { _ in "?" }.joined(separator: ", ")
                let sql = """
                    SELECT id, vehicle_type, section, item_name, item_description, is_critical, sort_order
                    FROM inspection_templates
                    WHERE vehicle_type IN (\(placeholders))
                      AND is_active = 1 AND deleted_at IS NULL
                    ORDER BY
                        CASE section
                            WHEN 'exterior' THEN 1
                            WHEN 'interior' THEN 2
                            WHEN 'equipment' THEN 3
                            ELSE 4
                        END,
                        sort_order ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(types))
                return rows.map { row in
                    InspectionTemplateItem(
                        id: row["id"] ?? 0,
                        vehicleType: row["vehicle_type"] ?? "",
                        section: row["section"] ?? "",
                        itemName: row["item_name"] ?? "",
                        itemDescription: row["item_description"] as String?,
                        isCritical: row["is_critical"] as Bool? ?? false,
                        sortOrder: row["sort_order"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Save a completed inspection with all item results.
    @discardableResult
    public func saveInspection(
        vehicleId: Int64, trailerId: Int64?, inspectorId: Int64,
        result: String, items: [InspectionItemResult],
        notes: String?, odometerReading: Int?, fuelLevel: Double?
    ) throws -> Int64 {
        // Validate fuel level bounds when supplied.
        if let fl = fuelLevel, fl < 0.0 || fl > 1.0 {
            throw FleetError.invalidFuelLevel(fl)
        }
        return try db.writer.write { dbConn -> Int64 in
            // Guard: vehicle + inspector must exist and not be tombstoned.
            // The inspection is an audit-grade record — orphan FK parents here
            // would corrupt the pre-trip compliance audit trail.
            let vehicleExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM vehicles WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [vehicleId]) ?? 0) > 0
            guard vehicleExists else { throw FleetError.vehicleNotFound(vehicleId) }
            let inspectorExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL
                """, arguments: [inspectorId]) ?? 0) > 0
            guard inspectorExists else { throw FleetError.userNotFound(inspectorId) }
            if let tid = trailerId {
                let trailerExists = (try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM job_trailers WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [tid]) ?? 0) > 0
                guard trailerExists else { throw FleetError.trailerNotFound(tid) }
            }

            // Insert the inspection record
            try dbConn.execute(sql: """
                INSERT INTO inspection_records
                (vehicle_id, trailer_id, inspector_id, result, notes, odometer_reading, fuel_level)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [vehicleId, trailerId, inspectorId, result, notes,
                                odometerReading, fuelLevel])

            let inspectionId = dbConn.lastInsertedRowID

            // Insert each item result
            for item in items {
                try dbConn.execute(sql: """
                    INSERT INTO inspection_results
                    (inspection_id, template_item_id, status, notes)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [inspectionId, item.templateItemId, item.status, item.notes])
            }

            // Update vehicle readings if provided
            if let odometer = odometerReading {
                try dbConn.execute(sql: """
                    UPDATE vehicles SET current_odometer = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [odometer, vehicleId])
            }
            if let fuel = fuelLevel {
                try dbConn.execute(sql: """
                    UPDATE vehicles SET fuel_level = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [fuel, vehicleId])
            }

            return inspectionId
        }
    }

    /// Check if a pre-trip inspection is required before clock-in.
    public func checkInspectionRequired(vehicleId: Int64) throws -> InspectionRequirement {
        do {
            return try db.writer.read { dbConn -> InspectionRequirement in
                let row = try Row.fetchOne(dbConn, sql: """
                    SELECT result, performed_at FROM inspection_records
                    WHERE vehicle_id = ? AND deleted_at IS NULL
                    ORDER BY performed_at DESC LIMIT 1
                    """, arguments: [vehicleId])

                guard let inspection = row else {
                    return .required(reason: "No inspection on record")
                }

                let result: String = inspection["result"] ?? "unknown"
                let performedAtStr: String = inspection["performed_at"] ?? ""

                if result == "fail" {
                    return .blocked(reason: "Vehicle failed last inspection")
                }

                // Check if inspection was performed today
                // SQLite datetime('now') stores UTC, so compare against UTC date
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.timeZone = TimeZone(identifier: "UTC")
                let todayStr = fmt.string(from: Date())
                let isToday = performedAtStr.hasPrefix(todayStr)

                if !isToday {
                    return .required(reason: "No inspection today")
                }
                return .cleared
            }
        } catch {
            if isTableNotFoundError(error) { return .required(reason: "Inspection system not available") }
            throw error
        }
    }

    /// Get inspection history for a vehicle.
    public func getInspectionRecords(vehicleId: Int64, limit: Int = 20) throws -> [InspectionRecordRow] {
        do {
            return try db.writer.read { dbConn -> [InspectionRecordRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT ir.id, ir.result, ir.performed_at, ir.odometer_reading,
                           ir.fuel_level, ir.notes,
                           COALESCE(v.vehicle_name, v.vehicle_number, 'Unknown') AS vehicle_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS inspector_name
                    FROM inspection_records ir
                    LEFT JOIN vehicles v ON v.id = ir.vehicle_id AND v.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = ir.inspector_id AND u.deleted_at IS NULL
                    WHERE ir.vehicle_id = ? AND ir.deleted_at IS NULL
                    ORDER BY ir.performed_at DESC
                    LIMIT ?
                    """, arguments: [vehicleId, limit])

                return rows.map { row in
                    InspectionRecordRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        inspectorName: row["inspector_name"] ?? "Unknown",
                        result: row["result"] ?? "unknown",
                        performedAt: row["performed_at"] ?? "",
                        odometerReading: row["odometer_reading"] as Int?,
                        fuelLevel: row["fuel_level"] as Double?,
                        notes: row["notes"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 19. Report Queries
    // =========================================================================

    /// Fuel cost breakdown by vehicle for a date range.
    public struct FuelReportRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let gallons: Double
        public let totalCost: Double
        public let costPerGallon: Double
    }

    /// Maintenance trend row — cost per month/vehicle.
    public struct MaintenanceTrendRow: Sendable, Identifiable {
        public let id: String
        public let vehicleName: String
        public let maintenanceType: String
        public let cost: Double
        public let performedAt: String
    }

    /// Mileage summary per vehicle.
    public struct MileageSummaryRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let totalMiles: Double
        public let tripCount: Int
        public let avgMilesPerTrip: Double
    }

    /// Vehicle utilization row — days active vs total days.
    public struct VehicleUtilizationRow: Sendable, Identifiable {
        public let id: Int64
        public let vehicleName: String
        public let daysActive: Int
        public let totalDays: Int
        public let utilization: Double
    }

    /// Get fuel cost report grouped by vehicle for a date range.
    public func getFuelCostReport(startDate: Date, endDate: Date) throws -> [FuelReportRow] {
        let startStr = Self.formatDateOnly(startDate)
        let endStr = Self.formatDateOnly(endDate)
        do {
            return try db.writer.read { dbConn -> [FuelReportRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT v.id, COALESCE(v.vehicle_name, v.vehicle_number) AS vehicle_name,
                           COALESCE(SUM(f.gallons), 0) AS total_gallons,
                           COALESCE(SUM(f.total_cost), 0) AS total_cost
                    FROM vehicles v
                    LEFT JOIN fuel_logs f ON f.vehicle_id = v.id
                        AND f.deleted_at IS NULL
                        AND f.log_date >= ? AND f.log_date <= ?
                    WHERE v.deleted_at IS NULL AND v.is_active = 1
                    GROUP BY v.id
                    HAVING total_gallons > 0 OR total_cost > 0
                    ORDER BY total_cost DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    let gallons: Double = row["total_gallons"] ?? 0
                    let cost: Double = row["total_cost"] ?? 0
                    return FuelReportRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        gallons: gallons,
                        totalCost: cost,
                        costPerGallon: gallons > 0 ? cost / gallons : 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get maintenance records for trend analysis in a date range.
    public func getMaintenanceTrendsReport(startDate: Date, endDate: Date) throws -> [MaintenanceTrendRow] {
        let startStr = Self.formatDateOnly(startDate)
        let endStr = Self.formatDateOnly(endDate)
        do {
            return try db.writer.read { dbConn -> [MaintenanceTrendRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT mr.id, COALESCE(v.vehicle_name, v.vehicle_number) AS vehicle_name,
                           COALESCE(mt.name, 'General') AS maintenance_type,
                           COALESCE(mr.cost, 0) AS cost,
                           COALESCE(mr.performed_at, mr.created_at, '') AS performed_at
                    FROM maintenance_records mr
                    LEFT JOIN vehicles v ON v.id = mr.vehicle_id AND v.deleted_at IS NULL
                    LEFT JOIN maintenance_types mt ON mt.id = mr.maintenance_type_id
                    WHERE mr.deleted_at IS NULL
                      AND mr.performed_at >= ? AND mr.performed_at <= ?
                    ORDER BY mr.performed_at DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    MaintenanceTrendRow(
                        id: "\(row["id"] as Int64? ?? 0)",
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        maintenanceType: row["maintenance_type"] ?? "General",
                        cost: row["cost"] ?? 0,
                        performedAt: row["performed_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get mileage summary per vehicle for a date range.
    public func getMileageSummaryReport(startDate: Date, endDate: Date) throws -> [MileageSummaryRow] {
        let startStr = Self.formatDateOnly(startDate)
        let endStr = Self.formatDateOnly(endDate)
        do {
            return try db.writer.read { dbConn -> [MileageSummaryRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT v.id, COALESCE(v.vehicle_name, v.vehicle_number) AS vehicle_name,
                           COALESCE(SUM(m.total_miles), 0) AS total_miles,
                           COUNT(m.id) AS trip_count
                    FROM vehicles v
                    LEFT JOIN mileage_logs m ON m.vehicle_id = v.id
                        AND m.deleted_at IS NULL
                        AND m.log_date >= ? AND m.log_date <= ?
                    WHERE v.deleted_at IS NULL AND v.is_active = 1
                    GROUP BY v.id
                    HAVING total_miles > 0
                    ORDER BY total_miles DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    let miles: Double = row["total_miles"] ?? 0
                    let trips: Int = row["trip_count"] ?? 0
                    return MileageSummaryRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        totalMiles: miles,
                        tripCount: trips,
                        avgMilesPerTrip: trips > 0 ? miles / Double(trips) : 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get vehicle utilization (days with mileage or dispatch activity) for a date range.
    public func getVehicleUtilizationReport(startDate: Date, endDate: Date) throws -> [VehicleUtilizationRow] {
        let startStr = Self.formatDateOnly(startDate)
        let endStr = Self.formatDateOnly(endDate)
        let totalDays = max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        do {
            return try db.writer.read { dbConn -> [VehicleUtilizationRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT v.id, COALESCE(v.vehicle_name, v.vehicle_number) AS vehicle_name,
                           COUNT(DISTINCT m.log_date) AS days_active
                    FROM vehicles v
                    LEFT JOIN mileage_logs m ON m.vehicle_id = v.id
                        AND m.deleted_at IS NULL
                        AND m.log_date >= ? AND m.log_date <= ?
                    WHERE v.deleted_at IS NULL AND v.is_active = 1
                    GROUP BY v.id
                    ORDER BY days_active DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    let daysActive: Int = row["days_active"] ?? 0
                    return VehicleUtilizationRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        daysActive: daysActive,
                        totalDays: totalDays,
                        utilization: Double(daysActive) / Double(totalDays)
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Format a Date as "yyyy-MM-dd".
    private static func formatDateOnly(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) query returning an Int.
    /// Returns 0 if the table does not exist.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
