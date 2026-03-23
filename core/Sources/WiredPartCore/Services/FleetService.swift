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
                var whereClauses = ["v.deleted_at IS NULL"]
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
                    LEFT JOIN users u ON u.id = va.user_id
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
                        LEFT JOIN users u ON u.id = va.user_id
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
                    LEFT JOIN vehicles v ON v.id = mr.vehicle_id
                    LEFT JOIN maintenance_types mt ON mt.id = mr.maintenance_type_id
                    LEFT JOIN users u ON u.id = mr.performed_by
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
                    LEFT JOIN vehicles v ON v.id = ml.vehicle_id
                    LEFT JOIN users u ON u.id = ml.user_id
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
                    LEFT JOIN vehicles v ON v.id = fl.vehicle_id
                    LEFT JOIN users u ON u.id = fl.user_id
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
                var whereClauses = ["jt.deleted_at IS NULL"]
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
                    LEFT JOIN jobs j ON j.id = jt.current_job_id
                    LEFT JOIN users u ON u.id = jt.assigned_driver_user_id
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
            sql: "SELECT COUNT(*) FROM vehicles WHERE deleted_at IS NULL"
        )

        let activeVehicles = try safeCount(
            sql: "SELECT COUNT(*) FROM vehicles WHERE status = 'active' AND deleted_at IS NULL"
        )

        // Maintenance due: schedules where next_due_date <= today or next_due_miles <= current odometer
        let maintenanceDue = try safeCount(
            sql: """
                SELECT COUNT(*) FROM maintenance_schedules ms
                JOIN vehicles v ON v.id = ms.vehicle_id AND v.deleted_at IS NULL
                WHERE ms.deleted_at IS NULL
                  AND (
                    (ms.next_due_date IS NOT NULL AND date(ms.next_due_date) <= date('now'))
                    OR (ms.next_due_miles IS NOT NULL AND v.current_odometer IS NOT NULL
                        AND ms.next_due_miles <= v.current_odometer)
                  )
                """
        )

        let totalTrailers = try safeCount(
            sql: "SELECT COUNT(*) FROM job_trailers WHERE deleted_at IS NULL"
        )

        return FleetStats(
            totalVehicles: totalVehicles,
            activeVehicles: activeVehicles,
            maintenanceDue: maintenanceDue,
            totalTrailers: totalTrailers
        )
    }

    // =========================================================================
    // MARK: - 7. Create / Mutate
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
        try db.writer.write { dbConn in
            let now = ISO8601DateFormatter().string(from: Date())
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
        try db.writer.write { dbConn in
            let now = ISO8601DateFormatter().string(from: Date())
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
        return message.contains("no such table")
    }
}
