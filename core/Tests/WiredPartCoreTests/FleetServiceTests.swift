import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("FleetService Tests")
struct FleetServiceTests {

    // MARK: - Vehicle CRUD

    @Test("Create and list vehicles")
    func testVehicleCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-TEST",
            vehicleName: "Test Truck",
            vehicleType: "truck",
            make: "Ford",
            model: "F-150",
            year: 2024,
            color: nil,
            vin: nil,
            licensePlate: nil,
            notes: nil
        )
        #expect(vehicleId > 0)

        let vehicles = try env.fleet.listVehicles()
        #expect(vehicles.contains(where: { $0.vehicleNumber == "V-TEST" }))
    }

    @Test("Get vehicle detail")
    func testVehicleDetail() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-DET",
            vehicleName: "Detail Truck",
            vehicleType: "truck",
            make: "Chevy",
            model: "Silverado",
            year: 2023,
            color: nil,
            vin: nil,
            licensePlate: nil,
            notes: nil
        )
        let detail = try env.fleet.getVehicleDetail(id: vehicleId)
        #expect(detail?.vehicleName == "Detail Truck")
        #expect(detail?.make == "Chevy")
    }

    @Test("Filter vehicles by status")
    func testFilterVehiclesByStatus() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.fleet.createVehicle(actorId: env.adminUserId, vehicleNumber: "V-ACT", vehicleName: "Active Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        let active = try env.fleet.listVehicles(status: "active")
        #expect(active.count >= 1)
    }

    @Test("Vehicle status counts aggregate in SQL and exclude inactive rows")
    func testVehicleStatusCounts() throws {
        let env = try E2ETestHelpers.setUp()
        let before = try env.fleet.getVehicleStatusCounts()

        let activeId = try env.fleet.createVehicle(
            vehicleNumber: "V-COUNT-ACT", vehicleName: "Count Active", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let inactiveId = try env.fleet.createVehicle(
            vehicleNumber: "V-COUNT-INACT", vehicleName: "Count Inactive", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let maintenanceId = try env.fleet.createVehicle(
            vehicleNumber: "V-COUNT-MAINT", vehicleName: "Count Maintenance", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let retiredId = try env.fleet.createVehicle(
            vehicleNumber: "V-COUNT-RET", vehicleName: "Count Retired", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let excludedId = try env.fleet.createVehicle(
            vehicleNumber: "V-COUNT-EXCL", vehicleName: "Count Excluded", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET status = 'inactive' WHERE id = ?", arguments: [inactiveId])
            try db.execute(sql: "UPDATE vehicles SET status = 'maintenance' WHERE id = ?", arguments: [maintenanceId])
            try db.execute(sql: "UPDATE vehicles SET status = 'retired' WHERE id = ?", arguments: [retiredId])
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [excludedId])
        }

        let after = try env.fleet.getVehicleStatusCounts()
        #expect(after.all == before.all + 4)
        #expect(after.active == before.active + 1)
        #expect(after.inactive == before.inactive + 1)
        #expect(after.maintenance == before.maintenance + 1)
        #expect(after.retired == before.retired + 1)
        #expect(after.count(for: "all") == after.all)
        #expect(after.count(for: "active") == after.active)
        #expect(after.count(for: "unknown") == 0)

        let visibleIds = Set(try env.fleet.listVehicles().map(\.id))
        #expect(visibleIds.contains(activeId))
        #expect(!visibleIds.contains(excludedId))
    }

    // MARK: - Trailer CRUD

    @Test("Create and list trailers")
    func testTrailerCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(
            actorId: env.adminUserId,
            trailerNumber: "T-001",
            trailerType: "flatbed",
            notes: "24ft flatbed"
        )
        #expect(trailerId > 0)

        let trailers = try env.fleet.listTrailers()
        #expect(trailers.count >= 1)
    }

    @Test("Get trailer detail")
    func testTrailerDetail() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "T-DET", trailerType: "enclosed", notes: nil)
        let detail = try env.fleet.getTrailerDetail(trailerId: trailerId)
        #expect(detail?.trailerCode == "T-DET")
    }

    // MARK: - Driver Assignment

    @Test("Assign driver to vehicle")
    func testAssignDriver() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(actorId: env.adminUserId, vehicleNumber: "V-DRV", vehicleName: "Driver Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        try env.fleet.assignDriver(
            actorId: env.adminUserId,
            vehicleId: vehicleId,
            userId: env.adminUserId,
            assignmentType: "primary",
            isTakeHome: false
        )
        let detail = try env.fleet.getVehicleDetail(id: vehicleId)
        #expect(detail != nil)
    }

    @Test("assignDriver deactivates previous active assignment for same vehicle")
    func testAssignDriverDeactivatesVehicleAssignment() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-REASSIGN", vehicleName: "Reassign Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let nextUserId = try env.auth.createUser(displayName: "Next Driver", pin: "5678")

        try env.fleet.assignDriver(
            vehicleId: vehicleId, userId: env.adminUserId,
            assignmentType: "primary", isTakeHome: false
        )
        try env.fleet.assignDriver(
            vehicleId: vehicleId, userId: nextUserId,
            assignmentType: "primary", isTakeHome: true
        )

        let rows = try env.db.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT user_id, is_active, end_date
                FROM vehicle_assignments
                WHERE vehicle_id = ? AND deleted_at IS NULL
                ORDER BY id ASC
                """, arguments: [vehicleId])
        }

        #expect(rows.count == 2)
        #expect((rows[0]["user_id"] as Int64?) == env.adminUserId)
        #expect((rows[0]["is_active"] as Int?) == 0)
        #expect((rows[0]["end_date"] as String?) != nil)
        #expect((rows[1]["user_id"] as Int64?) == nextUserId)
        #expect((rows[1]["is_active"] as Int?) == 1)
    }

    @Test("assignDriver deactivates previous active assignment for same driver")
    func testAssignDriverDeactivatesDriverAssignment() throws {
        let env = try E2ETestHelpers.setUp()
        let firstVehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-DRIVER-1", vehicleName: "First Driver Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let secondVehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-DRIVER-2", vehicleName: "Second Driver Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )

        try env.fleet.assignDriver(
            vehicleId: firstVehicleId, userId: env.adminUserId,
            assignmentType: "primary", isTakeHome: false
        )
        try env.fleet.assignDriver(
            vehicleId: secondVehicleId, userId: env.adminUserId,
            assignmentType: "primary", isTakeHome: true
        )

        let rows = try env.db.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT vehicle_id, is_active, end_date
                FROM vehicle_assignments
                WHERE user_id = ? AND deleted_at IS NULL
                ORDER BY id ASC
                """, arguments: [env.adminUserId])
        }

        #expect(rows.count == 2)
        #expect((rows[0]["vehicle_id"] as Int64?) == firstVehicleId)
        #expect((rows[0]["is_active"] as Int?) == 0)
        #expect((rows[0]["end_date"] as String?) != nil)
        #expect((rows[1]["vehicle_id"] as Int64?) == secondVehicleId)
        #expect((rows[1]["is_active"] as Int?) == 1)
    }

    @Test("My vehicle stats")
    func testMyVehicleStats() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(actorId: env.adminUserId, vehicleNumber: "V-MY", vehicleName: "My Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        try env.fleet.assignDriver(actorId: env.adminUserId, vehicleId: vehicleId, userId: env.adminUserId, assignmentType: "primary", isTakeHome: true)
        let stats = try env.fleet.getMyVehicleStats(userId: env.adminUserId)
        #expect(stats != nil)
    }

    @Test("My Truck dashboard batched load matches legacy service calls")
    func testMyTruckDashboardData() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-BATCH",
            vehicleName: "Batch Truck",
            vehicleType: "truck",
            make: "Ford",
            model: "Transit",
            year: 2025,
            color: nil,
            vin: nil,
            licensePlate: nil,
            notes: nil
        )
        try env.fleet.assignDriver(
            vehicleId: vehicleId,
            userId: env.adminUserId,
            assignmentType: "primary",
            isTakeHome: true
        )
        try env.fleet.logFuelLevel(vehicleId: vehicleId, fuelLevel: 0.5)
        try env.fleet.addVehicleStockItem(vehicleId: vehicleId, partName: "Wire Nuts", quantity: 12, stockType: "truck_stock")
        try env.fleet.addVehicleStockItem(vehicleId: vehicleId, partName: "Panel", quantity: 2, stockType: "transfer")

        let trailerId = try env.fleet.createTrailer(trailerNumber: "T-BATCH", trailerType: "enclosed", notes: nil)
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO trailer_attachments (vehicle_id, trailer_id, attached_by)
                    VALUES (?, ?, ?)
                    """,
                arguments: [vehicleId, trailerId, env.adminUserId]
            )
            try db.execute(
                sql: """
                    INSERT INTO mileage_logs (vehicle_id, user_id, log_date, total_miles, purpose)
                    VALUES (?, ?, '2026-05-02', 18.5, 'Service call'),
                           (?, ?, '2026-05-01', 11.0, 'Pickup')
                    """,
                arguments: [vehicleId, env.adminUserId, vehicleId, env.adminUserId]
            )
            try db.execute(
                sql: """
                    INSERT INTO fuel_logs (vehicle_id, user_id, log_date, gallons, total_cost, station)
                    VALUES (?, ?, '2026-05-03', 9.0, 36.0, 'Depot'),
                           (?, ?, '2026-05-01', 7.5, 30.0, 'Yard')
                    """,
                arguments: [vehicleId, env.adminUserId, vehicleId, env.adminUserId]
            )
        }

        let dashboard = try env.fleet.getMyTruckDashboardData(userId: env.adminUserId)
        let legacyStats = try env.fleet.getMyVehicleStats(userId: env.adminUserId)
        let legacyVehicle = try env.fleet.getVehicleDetail(id: vehicleId)
        let legacyTruckStock = try env.fleet.getVehicleStock(vehicleId: vehicleId, stockType: "truck_stock")
        let legacyTransferItems = try env.fleet.getVehicleStock(vehicleId: vehicleId, stockType: "transfer")
        let legacyMileage = try env.fleet.listMileageLogs(vehicleId: vehicleId, limit: 5)
        let legacyFuel = try env.fleet.listFuelLogs(vehicleId: vehicleId, limit: 5)

        #expect(dashboard.vehicleStats?.vehicleId == legacyStats?.vehicleId)
        #expect(dashboard.vehicleStats?.partCount == legacyStats?.partCount)
        #expect(dashboard.vehicleStats?.transferItems == legacyStats?.transferItems)
        #expect(dashboard.vehicleStats?.fuelLevel == legacyStats?.fuelLevel)
        #expect(dashboard.vehicleStats?.hasTrailer == legacyStats?.hasTrailer)
        #expect(dashboard.vehicleStats?.trailerId == legacyStats?.trailerId)
        #expect(dashboard.vehicle?.vehicleName == legacyVehicle?.vehicleName)
        #expect(dashboard.vehicle?.assignments.count == legacyVehicle?.assignments.count)
        #expect(dashboard.truckStock.map(\.partName) == legacyTruckStock.map(\.partName))
        #expect(dashboard.transferItems.map(\.partName) == legacyTransferItems.map(\.partName))
        #expect(dashboard.recentMileage.map(\.logDate) == legacyMileage.map(\.logDate))
        #expect(dashboard.recentFuel.map(\.logDate) == legacyFuel.map(\.logDate))
    }

    // MARK: - Fleet Stats & Dashboard

    @Test("Fleet stats aggregates")
    func testFleetStats() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.fleet.getFleetStats()
        #expect(stats.totalVehicles >= 0)
    }

    @Test("Fleet dashboard stats")
    func testFleetDashboardStats() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.fleet.getFleetDashboardStats()
        #expect(stats.activeVehicles >= 0)
    }

    @Test("Vehicle status list")
    func testVehicleStatusList() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.fleet.createVehicle(actorId: env.adminUserId, vehicleNumber: "V-STS", vehicleName: "Status Truck", vehicleType: "van", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        let statuses = try env.fleet.getVehicleStatusList()
        #expect(statuses.count >= 1)
    }

    // MARK: - Maintenance & Fuel

    @Test("List maintenance records empty on fresh DB")
    func testMaintenanceEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let records = try env.fleet.listMaintenanceRecords(vehicleId: nil, limit: 50)
        #expect(records.isEmpty)
    }

    @Test("List fuel logs empty on fresh DB")
    func testFuelLogsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let logs = try env.fleet.listFuelLogs(vehicleId: nil, limit: 50)
        #expect(logs.isEmpty)
    }

    @Test("List mileage logs empty on fresh DB")
    func testMileageLogsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let logs = try env.fleet.listMileageLogs(vehicleId: nil, userId: nil, limit: 50)
        #expect(logs.isEmpty)
    }

    // MARK: - Date Range Filtering (#276)

    @Test("listFuelLogs filters by start/end date range")
    func testListFuelLogsDateRange() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-FUEL-DR", vehicleName: "Fuel DR", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let userId = try env.auth.createUser(displayName: "Fuel DR User", pin: "1234")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO fuel_logs (vehicle_id, user_id, log_date, gallons, total_cost, station)
                VALUES (?, ?, '2026-01-15', 10.0, 35.00, 'Old Station')
                """, arguments: [vehicleId, userId])
            try db.execute(sql: """
                INSERT INTO fuel_logs (vehicle_id, user_id, log_date, gallons, total_cost, station)
                VALUES (?, ?, '2026-04-20', 12.0, 42.00, 'Recent Station')
                """, arguments: [vehicleId, userId])
        }
        let recent = try env.fleet.listFuelLogs(start: "2026-04-01", end: "2026-04-30")
        #expect(recent.count == 1, "Date filter should only include April logs")
        #expect(recent.first?.station == "Recent Station")
        let all = try env.fleet.listFuelLogs()
        #expect(all.count == 2, "No filter should return both logs")
    }

    @Test("listMileageLogs filters by start/end date range")
    func testListMileageLogsDateRange() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-MIL-DR", vehicleName: "Mileage DR", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let userId = try env.auth.createUser(displayName: "Mileage DR User", pin: "1234")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO mileage_logs (vehicle_id, user_id, log_date, total_miles, purpose)
                VALUES (?, ?, '2026-01-10', 100.0, 'Old trip')
                """, arguments: [vehicleId, userId])
            try db.execute(sql: """
                INSERT INTO mileage_logs (vehicle_id, user_id, log_date, total_miles, purpose)
                VALUES (?, ?, '2026-04-22', 50.0, 'Recent trip')
                """, arguments: [vehicleId, userId])
        }
        let recent = try env.fleet.listMileageLogs(start: "2026-04-01", end: "2026-04-30")
        #expect(recent.count == 1, "Date filter should only include April logs")
        #expect(recent.first?.purpose == "Recent trip")
    }

    @Test("listMaintenanceRecords filters by start/end date range")
    func testListMaintenanceRecordsDateRange() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-MNT-DR", vehicleName: "Maint DR", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO maintenance_records (vehicle_id, performed_at, cost, odometer_reading)
                VALUES (?, '2026-01-05', 150.0, 30000)
                """, arguments: [vehicleId])
            try db.execute(sql: """
                INSERT INTO maintenance_records (vehicle_id, performed_at, cost, odometer_reading)
                VALUES (?, '2026-04-18', 250.0, 32000)
                """, arguments: [vehicleId])
        }
        let recent = try env.fleet.listMaintenanceRecords(start: "2026-04-01", end: "2026-04-30")
        #expect(recent.count == 1, "Date filter should only include April records")
        #expect(recent.first?.cost == 250.0)
    }

    @Test("Upcoming fleet maintenance empty")
    func testUpcomingMaintenance() throws {
        let env = try E2ETestHelpers.setUp()
        let upcoming = try env.fleet.getUpcomingFleetMaintenance(limit: 10)
        #expect(upcoming.isEmpty)
    }

    // MARK: - Inspections

    @Test("List inspections empty on fresh DB")
    func testInspectionsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let inspections = try env.fleet.listInspections(limit: 50)
        #expect(inspections.isEmpty)
    }

    @Test("Inspection checklist returns template items")
    func testInspectionChecklist() throws {
        let env = try E2ETestHelpers.setUp()
        let checklist = try env.fleet.getInspectionChecklist(vehicleType: "truck", includeTrailer: false)
        // May be empty on fresh DB or have defaults
        #expect(checklist.count >= 0)
    }

    // MARK: - Vehicle Stock & Tools

    @Test("Vehicle stock empty on fresh DB")
    func testVehicleStockEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(actorId: env.adminUserId, vehicleNumber: "V-STK", vehicleName: "Stock Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        let stock = try env.fleet.getVehicleStock(vehicleId: vehicleId, stockType: "standard")
        #expect(stock.isEmpty)
    }

    @Test("Add vehicle stock item")
    func testAddVehicleStock() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(actorId: env.adminUserId, vehicleNumber: "V-ADD", vehicleName: "Add Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        try env.fleet.addVehicleStockItem(actorId: env.adminUserId, vehicleId: vehicleId, partName: "Wire Nuts", quantity: 100, stockType: "standard")
        let stock = try env.fleet.getVehicleStock(vehicleId: vehicleId, stockType: "standard")
        #expect(stock.count >= 1)
    }

    // MARK: - Trailer Location

    @Test("Update and get trailer location history")
    func testTrailerLocationHistory() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "T-LOC", trailerType: "flatbed", notes: nil)
        try env.fleet.updateTrailerLocation(
            trailerId: trailerId,
            locationType: "job",
            locationLabel: "Main St Project",
            jobId: nil,
            recordedBy: env.adminUserId
        )
        let history = try env.fleet.getTrailerLocationHistory(trailerId: trailerId, limit: 10)
        #expect(history.count >= 1)
    }

    // MARK: - Telematics

    @Test("List telematics data returns empty on fresh DB")
    func testTelematicsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let data = try env.fleet.listTelematicsData()
        #expect(data.isEmpty)
    }

    @Test("List telematics data returns latest live row per vehicle")
    func testTelematicsLatestLiveRows() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-GPS", vehicleName: "GPS Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO vehicle_location_logs
                    (vehicle_id, user_id, latitude, longitude, speed, status, recorded_at)
                VALUES
                    (?, ?, 41.1, -104.1, 12.0, 'moving', '2026-05-12T10:00:00Z'),
                    (?, ?, 41.2, -104.2, 0.0, 'parked', '2026-05-12T10:05:00Z')
                """, arguments: [vehicleId, env.adminUserId, vehicleId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO vehicle_location_logs
                    (vehicle_id, user_id, latitude, longitude, speed, status, recorded_at, deleted_at)
                VALUES (?, ?, 41.3, -104.3, 21.0, 'deleted', '2026-05-12T10:10:00Z', '2026-05-12T10:11:00Z')
                """, arguments: [vehicleId, env.adminUserId])
        }

        let data = try env.fleet.listTelematicsData()
        #expect(data.count == 1)
        #expect(data.first?.id == 2)
        #expect(data.first?.vehicleName == "GPS Truck")
        #expect(data.first?.driverName == env.adminUser.displayName)
        #expect(data.first?.status == "parked")
    }

    // MARK: - Vehicle Tools

    @Test("Get vehicle tools returns empty when no assignments or checkouts exist")
    func testVehicleToolsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-TOOL", vehicleName: "Tool Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let tools = try env.fleet.getVehicleTools(vehicleId: vehicleId)
        #expect(tools.isEmpty)
    }

    // MARK: - Fuel Level

    @Test("Log fuel level updates vehicle fuel_level via MyVehicleStats")
    func testLogFuelLevel() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-FUEL", vehicleName: "Fuel Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // Assign admin user so getMyVehicleStats returns the vehicle
        try env.fleet.assignDriver(
            actorId: env.adminUserId,
            vehicleId: vehicleId, userId: env.adminUserId,
            assignmentType: "primary", isTakeHome: true
        )
        try env.fleet.logFuelLevel(actorId: env.adminUserId, vehicleId: vehicleId, fuelLevel: 0.75)
        let stats = try env.fleet.getMyVehicleStats(userId: env.adminUserId)
        #expect(stats?.fuelLevel == 0.75)
    }

    // MARK: - Trailer Stock & Storage Units

    @Test("Get trailer stock returns empty on fresh trailer")
    func testTrailerStockEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "T-STK", trailerType: "enclosed", notes: nil)
        let stock = try env.fleet.getTrailerStock(trailerId: trailerId)
        #expect(stock.isEmpty)
    }

    @Test("Get trailer storage units returns empty on fresh trailer")
    func testTrailerStorageUnitsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "T-SU", trailerType: "enclosed", notes: nil)
        let units = try env.fleet.getTrailerStorageUnits(trailerId: trailerId)
        #expect(units.isEmpty)
    }

    // MARK: - Save Inspection & Check Required

    @Test("Save inspection and check required returns cleared")
    func testSaveInspectionAndCheckRequired() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-INSP", vehicleName: "Inspection Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )

        // Before any inspection, should be required
        let before = try env.fleet.checkInspectionRequired(vehicleId: vehicleId)
        if case .required = before { } else {
            Issue.record("Expected .required before any inspection")
        }

        // Save a passing inspection
        let inspectionId = try env.fleet.saveInspection(
            vehicleId: vehicleId,
            trailerId: nil,
            inspectorId: env.adminUserId,
            result: "pass",
            items: [],
            notes: "All clear",
            odometerReading: 10000,
            fuelLevel: 0.8
        )
        #expect(inspectionId > 0)

        // After passing inspection today, should be cleared
        let after = try env.fleet.checkInspectionRequired(vehicleId: vehicleId)
        if case .cleared = after { } else {
            Issue.record("Expected .cleared after passing inspection today")
        }
    }

    @Test("checkInspectionRequired returns blocked after failed inspection")
    func testInspectionRequiredBlockedOnFail() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-FAIL", vehicleName: "Failed Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )

        _ = try env.fleet.saveInspection(
            vehicleId: vehicleId,
            trailerId: nil,
            inspectorId: env.adminUserId,
            result: "fail",
            items: [],
            notes: "Brake issues",
            odometerReading: nil,
            fuelLevel: nil
        )

        let requirement = try env.fleet.checkInspectionRequired(vehicleId: vehicleId)
        if case .blocked = requirement { } else {
            Issue.record("Expected .blocked after failed inspection")
        }
    }

    @Test("getInspectionRecords returns records after saveInspection")
    func testGetInspectionRecords() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-IREC", vehicleName: "Record Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )

        _ = try env.fleet.saveInspection(
            vehicleId: vehicleId,
            trailerId: nil,
            inspectorId: env.adminUserId,
            result: "pass",
            items: [],
            notes: nil,
            odometerReading: 5000,
            fuelLevel: nil
        )

        let records = try env.fleet.getInspectionRecords(vehicleId: vehicleId, limit: 10)
        #expect(records.count == 1)
        #expect(records[0].result == "pass")
        #expect(records[0].odometerReading == 5000)
    }

    // MARK: - Fleet Reports

    @Test("getFuelCostReport returns empty on fresh DB")
    func testFuelCostReportEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let start = Date(timeIntervalSinceNow: -30 * 86400)
        let end = Date()
        let report = try env.fleet.getFuelCostReport(startDate: start, endDate: end)
        // No fuel logs yet — HAVING filters out zeros
        #expect(report.isEmpty)
    }

    @Test("getMaintenanceTrendsReport returns empty on fresh DB")
    func testMaintenanceTrendsReportEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let start = Date(timeIntervalSinceNow: -30 * 86400)
        let end = Date()
        let report = try env.fleet.getMaintenanceTrendsReport(startDate: start, endDate: end)
        #expect(report.isEmpty)
    }

    @Test("getMileageSummaryReport returns empty on fresh DB")
    func testMileageSummaryReportEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let start = Date(timeIntervalSinceNow: -30 * 86400)
        let end = Date()
        let report = try env.fleet.getMileageSummaryReport(startDate: start, endDate: end)
        // No mileage logs — HAVING total_miles > 0 filters out all rows
        #expect(report.isEmpty)
    }

    @Test("getVehicleUtilizationReport includes vehicle with zero activity")
    func testVehicleUtilizationReport() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-UTIL", vehicleName: "Util Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let start = Date(timeIntervalSinceNow: -7 * 86400)
        let end = Date()
        let report = try env.fleet.getVehicleUtilizationReport(startDate: start, endDate: end)
        // Utilization report includes all active vehicles (even those with 0 days active)
        #expect(report.count >= 1)
        let entry = report.first(where: { $0.vehicleName == "Util Truck" })
        #expect(entry != nil)
        #expect(entry?.daysActive == 0)
        #expect(entry?.utilization == 0.0)
    }

    @Test("getMaintenanceTrendsReport falls back to 'Unknown' when vehicle is soft-deleted")
    func testMaintenanceTrendHidesDeletedVehicleName() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-MT-DEL", vehicleName: "Trend Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // Insert a maintenance record directly (no public service API for this)
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO maintenance_records (vehicle_id, performed_at, cost)
                    VALUES (?, date('now'), 150.0)
                    """,
                arguments: [vehicleId]
            )
            try db.execute(sql: "UPDATE vehicles SET deleted_at = datetime('now') WHERE id = ?", arguments: [vehicleId])
        }

        let start = Date(timeIntervalSinceNow: -86400)
        let end = Date(timeIntervalSinceNow: 86400)
        let report = try env.fleet.getMaintenanceTrendsReport(startDate: start, endDate: end)
        let row = report.first(where: { $0.vehicleName == "Unknown" })
        #expect(row != nil)
        #expect(row?.cost == 150.0)
    }

    @Test("listVehicles hides assigned user name for soft-deleted user")
    func testListVehiclesHidesDeletedAssignedUserName() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-DEL-01", vehicleName: "Delete Test", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.fleet.assignDriver(actorId: env.adminUserId, vehicleId: vehicleId, userId: env.adminUserId, assignmentType: "primary", isTakeHome: false)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [env.adminUserId])
        }
        let vehicles = try env.fleet.listVehicles()
        let v = vehicles.first(where: { $0.id == vehicleId })
        #expect(v != nil)
        #expect(v?.assignedUserName == nil)
    }

    @Test("updateTrailerLocation throws trailerNotFound for a soft-deleted trailer")
    func testUpdateTrailerLocation_throwsForSoftDeletedTrailer() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO job_trailers (trailer_code, name, created_at, updated_at)
                VALUES ('TR-SOFTDEL', 'TombstonedTrailer', datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }
        // Soft-delete the trailer
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_trailers SET is_at_shop = 0, deleted_at = datetime('now') WHERE id = ?",
                           arguments: [trailerId])
        }
        // The guard must fire before any history row is inserted
        #expect(throws: FleetService.FleetError.trailerNotFound(trailerId)) {
            try env.fleet.updateTrailerLocation(trailerId: trailerId, locationType: "shop", locationLabel: "Yard", jobId: nil, recordedBy: env.adminUserId)
        }
        // No orphan audit row must have been inserted
        let historyCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trailer_location_history WHERE trailer_id = ?",
                             arguments: [trailerId]) ?? 0
        }
        #expect(historyCount == 0,
            "Soft-deleted trailer must not receive a history row — guard must fire before INSERT")
        // is_at_shop must remain unchanged (0)
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT is_at_shop FROM job_trailers WHERE id = ?", arguments: [trailerId])
        }
        let isAtShop: Int = row?["is_at_shop"] ?? -1
        #expect(isAtShop == 0,
            "Soft-deleted trailer is_at_shop must not change")
    }

    @Test("logFuelLevel is a no-op on a soft-deleted vehicle")
    func testLogFuelLevel_noOpOnSoftDeletedVehicle() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-SOFT-DEL",
            vehicleName: "TombstonedTruck",
            vehicleType: "company_truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // Seed a known fuel reading, then soft-delete the vehicle
        try env.fleet.logFuelLevel(actorId: env.adminUserId, vehicleId: vehicleId, fuelLevel: 0.25)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [vehicleId])
        }
        // Stale UI writes a new reading. Regression: UPDATE vehicles ... WHERE id = ?
        // had no deleted_at guard, so the write would persist on the tombstone.
        try env.fleet.logFuelLevel(actorId: env.adminUserId, vehicleId: vehicleId, fuelLevel: 0.99)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT fuel_level FROM vehicles WHERE id = ?", arguments: [vehicleId])
        }
        let fuel: Double = row?["fuel_level"] ?? -1
        #expect(fuel == 0.25,
            "Soft-deleted vehicle fuel_level must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("assignDriver creates no orphan vehicle_assignments row for a soft-deleted vehicle")
    func testAssignDriver_noOrphanForSoftDeletedVehicle() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-ASGN-SOFT", vehicleName: "TombstonedTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [vehicleId])
        }
        // Regression: INSERT INTO vehicle_assignments had no pre-check that the
        // target vehicle exists and isn't tombstoned — the FK constraint allows
        // the write against a soft-deleted parent.
        try env.fleet.assignDriver(
            actorId: env.adminUserId,
            vehicleId: vehicleId, userId: env.adminUserId,
            assignmentType: "primary", isTakeHome: false
        )
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM vehicle_assignments WHERE vehicle_id = ?
                """, arguments: [vehicleId]) ?? 0
        }
        #expect(count == 0,
            "Soft-deleted vehicle must not receive a new driver assignment — INSERT must be pre-checked")
    }

    // MARK: - Input validation (iter 73)

    @Test("logFuelLevel rejects fuel level outside [0.0, 1.0]")
    func testLogFuelLevel_rejectsOutOfRange() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-FL-RANGE", vehicleName: "RangeTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        #expect(throws: FleetService.FleetError.invalidFuelLevel(-0.1)) {
            try env.fleet.logFuelLevel(actorId: env.adminUserId, vehicleId: vehicleId, fuelLevel: -0.1)
        }
        #expect(throws: FleetService.FleetError.invalidFuelLevel(1.5)) {
            try env.fleet.logFuelLevel(actorId: env.adminUserId, vehicleId: vehicleId, fuelLevel: 1.5)
        }
    }

    @Test("addVehicleStockItem rejects blank partName, zero quantity, and tombstoned vehicle")
    func testAddVehicleStockItem_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-STK-VAL", vehicleName: "ValTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        #expect(throws: FleetService.FleetError.self) {
            try env.fleet.addVehicleStockItem(
                actorId: env.adminUserId,
                vehicleId: vehicleId, partName: "   ", quantity: 5, stockType: "standard"
            )
        }
        #expect(throws: FleetService.FleetError.self) {
            try env.fleet.addVehicleStockItem(
                actorId: env.adminUserId,
                vehicleId: vehicleId, partName: "WireNut", quantity: 0, stockType: "standard"
            )
        }
        // Tombstone vehicle, then retry with valid inputs
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [vehicleId])
        }
        #expect(throws: FleetService.FleetError.self) {
            try env.fleet.addVehicleStockItem(
                actorId: env.adminUserId,
                vehicleId: vehicleId, partName: "WireNut", quantity: 5, stockType: "standard"
            )
        }
    }

    // MARK: - Issue #282: Defense-in-depth hygiene fixes

    @Test("updateTrailerLocation throws userNotFound for non-existent recordedBy")
    func testUpdateTrailerLocation_throwsForNonExistentUser() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "T-FK-USER", trailerType: "flatbed", notes: nil)
        let bogusUserId: Int64 = 999_999
        #expect(throws: FleetService.FleetError.userNotFound(bogusUserId)) {
            try env.fleet.updateTrailerLocation(
                trailerId: trailerId,
                locationType: "shop",
                locationLabel: "Yard",
                jobId: nil,
                recordedBy: bogusUserId
            )
        }
        // No row must have been inserted
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trailer_location_history WHERE trailer_id = ?",
                             arguments: [trailerId]) ?? 0
        }
        #expect(count == 0, "No audit row must land when recordedBy is not a valid user")
    }

    @Test("updateTrailerLocation throws userNotFound for soft-deleted recordedBy")
    func testUpdateTrailerLocation_throwsForSoftDeletedUser() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "T-FK-SDEL", trailerType: "flatbed", notes: nil)
        // Soft-delete the admin user
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: FleetService.FleetError.userNotFound(env.adminUserId)) {
            try env.fleet.updateTrailerLocation(
                trailerId: trailerId,
                locationType: "job",
                locationLabel: nil,
                jobId: nil,
                recordedBy: env.adminUserId
            )
        }
    }

    @Test("addVehicleStockItem coerces empty/whitespace location strings to nil")
    func testAddVehicleStockItem_emptyLocationCoercedToNil() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-LOC-NIL", vehicleName: "LocNilTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.fleet.addVehicleStockItem(
            actorId: env.adminUserId,
            vehicleId: vehicleId, partName: "Bolt", quantity: 1, stockType: "standard",
            sourceLocation: "   ", destinationLocation: ""
        )
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT source_location, destination_location FROM vehicle_stock WHERE vehicle_id = ?",
                             arguments: [vehicleId])
        }
        #expect(row != nil)
        let src: String? = row?["source_location"]
        let dst: String? = row?["destination_location"]
        #expect(src == nil, "Whitespace-only sourceLocation must be stored as nil")
        #expect(dst == nil, "Empty destinationLocation must be stored as nil")
    }

    @Test("addVehicleStockItem caps location strings to 100 characters")
    func testAddVehicleStockItem_locationCappedAt100Chars() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-LOC-CAP", vehicleName: "LocCapTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let longString = String(repeating: "A", count: 150)
        let exactly100 = String(repeating: "B", count: 100)
        try env.fleet.addVehicleStockItem(
            actorId: env.adminUserId,
            vehicleId: vehicleId, partName: "Cap Test Part", quantity: 1, stockType: "standard",
            sourceLocation: longString, destinationLocation: exactly100
        )
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT source_location, destination_location FROM vehicle_stock WHERE vehicle_id = ?",
                             arguments: [vehicleId])
        }
        #expect(row != nil)
        let src: String? = row?["source_location"]
        let dst: String? = row?["destination_location"]
        #expect(src?.count == 100, "150-char sourceLocation must be truncated to 100")
        #expect(dst?.count == 100, "Exactly-100-char destinationLocation must be stored as-is")
    }

    @Test("addVehicleStockItem stores valid location strings unchanged")
    func testAddVehicleStockItem_validLocationStoredUnchanged() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-LOC-OK", vehicleName: "LocOkTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.fleet.addVehicleStockItem(
            actorId: env.adminUserId,
            vehicleId: vehicleId, partName: "Nut", quantity: 5, stockType: "standard",
            sourceLocation: "Warehouse A", destinationLocation: "Truck Bay 3"
        )
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT source_location, destination_location FROM vehicle_stock WHERE vehicle_id = ?",
                             arguments: [vehicleId])
        }
        #expect(row != nil)
        let src: String? = row?["source_location"]
        let dst: String? = row?["destination_location"]
        #expect(src == "Warehouse A")
        #expect(dst == "Truck Bay 3")
    }

    @Test("addVehicleStockItem caps transfer_reason to 100 characters")
    func testAddVehicleStockItem_transferReasonCappedAt100Chars() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-TR-CAP", vehicleName: "TrReasonTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let longReason = String(repeating: "X", count: 150)
        let exactReason = String(repeating: "Y", count: 100)
        // Insert with the long reason, then read back
        try env.fleet.addVehicleStockItem(
            actorId: env.adminUserId,
            vehicleId: vehicleId, partName: "Cap Test", quantity: 2, stockType: "standard",
            transferReason: longReason
        )
        // Insert a second item with exactly-100 reason
        try env.fleet.addVehicleStockItem(
            actorId: env.adminUserId,
            vehicleId: vehicleId, partName: "Cap Test 2", quantity: 1, stockType: "standard",
            transferReason: exactReason
        )
        let rows = try env.db.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT part_name, transfer_reason FROM vehicle_stock WHERE vehicle_id = ? ORDER BY id",
                             arguments: [vehicleId])
        }
        #expect(rows.count == 2)
        let r1: String? = rows[0]["transfer_reason"]
        let r2: String? = rows[1]["transfer_reason"]
        #expect(r1?.count == 100, "150-char transferReason must be truncated to 100")
        #expect(r2?.count == 100, "Exactly-100-char transferReason must be stored as-is")
    }

    // MARK: - Input validation — create paths (iter 68)

    @Test("createVehicle rejects blank vehicleNumber and vehicleName")
    func testCreateVehicle_rejectsBlankIdentifiers() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: FleetService.FleetError.requiredFieldEmpty("vehicleNumber")) {
            try env.fleet.createVehicle(
                actorId: env.adminUserId,
                vehicleNumber: "   ", vehicleName: "ValidName", vehicleType: "truck",
                make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
            )
        }
        #expect(throws: FleetService.FleetError.requiredFieldEmpty("vehicleName")) {
            try env.fleet.createVehicle(
                actorId: env.adminUserId,
                vehicleNumber: "V-BLANK-NAME", vehicleName: "", vehicleType: "truck",
                make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
            )
        }
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM vehicles WHERE vehicle_number LIKE 'V-BLANK%'") ?? 0
        }
        #expect(count == 0, "Blank-identifier vehicles must produce zero rows in the DB")
    }

    @Test("createTrailer rejects blank trailerNumber and trailerType")
    func testCreateTrailer_rejectsBlankIdentifiers() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: FleetService.FleetError.requiredFieldEmpty("trailerNumber")) {
            try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "", trailerType: "flatbed", notes: nil)
        }
        #expect(throws: FleetService.FleetError.requiredFieldEmpty("trailerType")) {
            try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "TR-BLANK", trailerType: "   ", notes: nil)
        }
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM job_trailers WHERE trailer_code LIKE 'TR-BLANK%'") ?? 0
        }
        #expect(count == 0, "Blank-identifier trailers must produce zero rows in the DB")
    }

    // MARK: - is_active Defense

    @Test("reportVehicleIssue persists row to vehicle_issue_reports with FK guards and validation")
    func testReportVehicleIssue() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-ISSUE-1", vehicleName: "Issue Test Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )

        // Happy path — write succeeds, returns rowid, row visible in DB.
        let rowId = try env.fleet.reportVehicleIssue(
            vehicleId: vehicleId, reportedBy: env.adminUserId,
            severity: "high", description: "  Brake pedal soft — needs immediate inspection.  "
        )
        #expect(rowId > 0)
        try env.db.writer.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM vehicle_issue_reports
                WHERE id = ? AND vehicle_id = ? AND reported_by = ?
                  AND severity = 'high' AND status = 'open'
                  AND description = 'Brake pedal soft — needs immediate inspection.'
                """, arguments: [rowId, vehicleId, env.adminUserId]) ?? 0
            #expect(count == 1, "row must persist with trimmed description and default status='open'")
        }

        // Validation: empty / whitespace-only description rejected.
        #expect(throws: FleetService.FleetError.invalidIssueReport("description cannot be empty")) {
            try env.fleet.reportVehicleIssue(
                vehicleId: vehicleId, reportedBy: env.adminUserId,
                severity: "low", description: "   \n  "
            )
        }

        // Validation: invalid severity rejected.
        #expect(throws: FleetService.FleetError.invalidIssueReport("invalid severity: bogus")) {
            try env.fleet.reportVehicleIssue(
                vehicleId: vehicleId, reportedBy: env.adminUserId,
                severity: "bogus", description: "anything"
            )
        }

        // FK guard: missing vehicle rejected.
        #expect(throws: FleetService.FleetError.vehicleNotFound(99_999)) {
            try env.fleet.reportVehicleIssue(
                vehicleId: 99_999, reportedBy: env.adminUserId,
                severity: "low", description: "fake vehicle"
            )
        }

        // FK guard: missing user rejected.
        #expect(throws: FleetService.FleetError.userNotFound(99_999)) {
            try env.fleet.reportVehicleIssue(
                vehicleId: vehicleId, reportedBy: 99_999,
                severity: "low", description: "fake reporter"
            )
        }

        // FK guard: tombstoned vehicle rejected.
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [vehicleId])
        }
        #expect(throws: FleetService.FleetError.vehicleNotFound(vehicleId)) {
            try env.fleet.reportVehicleIssue(
                vehicleId: vehicleId, reportedBy: env.adminUserId,
                severity: "low", description: "issue on deactivated vehicle"
            )
        }
    }

    @Test("listVehicles excludes is_active = 0 vehicles")
    func testListVehiclesExcludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-INACTIVE", vehicleName: "Inactive Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [vehicleId])
        }
        let vehicles = try env.fleet.listVehicles()
        #expect(!vehicles.contains(where: { $0.id == vehicleId }), "is_active=0 vehicle must not appear in listVehicles")
    }

    @Test("getVehicleDetail returns nil for is_active = 0 vehicles")
    func testGetVehicleDetailExcludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-DETAIL-INACTIVE", vehicleName: "Detail Inactive", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // Confirm visible while active.
        #expect(try env.fleet.getVehicleDetail(id: vehicleId) != nil, "Active vehicle should be retrievable by id")
        // Soft-deactivate.
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [vehicleId])
        }
        #expect(try env.fleet.getVehicleDetail(id: vehicleId) == nil, "is_active=0 vehicle must not be returned by getVehicleDetail")
    }

    @Test("getVehicleDetail hydrates isActive strictly (no silent default to 1)")
    func testGetVehicleDetailIsActiveStrictDefault() throws {
        // Regression for #275: previously `row["is_active"] ?? 1` would default
        // NULL to 1 (active). Now uses `(row["is_active"] as Int?) ?? 0` —
        // strict typed extraction with a safe default.
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-ISACTIVE-HYD", vehicleName: "Hydration Test", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let detail = try env.fleet.getVehicleDetail(id: vehicleId)
        #expect(detail != nil, "Active vehicle must be retrievable")
        #expect(detail?.isActive == 1, "Active vehicle must hydrate isActive = 1 (matches WHERE filter)")
    }

    @Test("listTrailers excludes is_active = 0 trailers")
    func testListTrailersExcludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "TR-INACTIVE", trailerType: "flatbed", notes: nil)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_trailers SET is_active = 0 WHERE id = ?", arguments: [trailerId])
        }
        let trailers = try env.fleet.listTrailers()
        #expect(!trailers.contains(where: { $0.id == trailerId }), "is_active=0 trailer must not appear in listTrailers")
    }

    @Test("getFleetStats excludes is_active = 0 vehicles from counts")
    func testFleetStatsExcludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-STATS-INACTIVE", vehicleName: "Stats Inactive", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let before = try env.fleet.getFleetStats()
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [vehicleId])
        }
        let after = try env.fleet.getFleetStats()
        #expect(after.totalVehicles == before.totalVehicles - 1, "is_active=0 vehicle must reduce totalVehicles count")
    }

    @Test("getVehicleStatusList excludes is_active = 0 vehicles")
    func testVehicleStatusList_excludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-STS-INACTIVE", vehicleName: "Inactive Status", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [vehicleId])
        }
        let list = try env.fleet.getVehicleStatusList()
        #expect(!list.contains(where: { $0.id == vehicleId }), "is_active=0 vehicle must not appear in status list")
    }

    @Test("getFleetDashboardStats regression – consolidated query matches expected values")
    func testFleetDashboardStatsRegression() throws {
        let env = try E2ETestHelpers.setUp()

        // Baseline – empty fleet
        let baseline = try env.fleet.getFleetDashboardStats()
        #expect(baseline.totalVehicles == 0)
        #expect(baseline.activeVehicles == 0)
        #expect(baseline.maintenanceDue == 0)
        #expect(baseline.overdueInspections == 0)
        #expect(baseline.totalTrailers == 0)

        // Create two vehicles: one active, one out-of-service
        let v1 = try env.fleet.createVehicle(
            vehicleNumber: "V-DASH-1", vehicleName: "Dash Active", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let v2 = try env.fleet.createVehicle(
            vehicleNumber: "V-DASH-2", vehicleName: "Dash OOS", vehicleType: "van",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET status = 'out_of_service' WHERE id = ?", arguments: [v2])
        }

        // Create a trailer
        _ = try env.fleet.createTrailer(trailerNumber: "TR-DASH-1", trailerType: "flatbed", notes: nil)

        // Insert MTD cost data (current month)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO fuel_logs (vehicle_id, user_id, log_date, gallons, total_cost, station)
                VALUES (?, ?, ?, 10.0, 45.50, 'Test Station')
                """, arguments: [v1, env.adminUserId, today])
            try db.execute(sql: """
                INSERT INTO mileage_logs (vehicle_id, user_id, log_date, total_miles, purpose)
                VALUES (?, ?, ?, 120.0, 'Service call')
                """, arguments: [v1, env.adminUserId, today])
            try db.execute(sql: """
                INSERT INTO maintenance_records (vehicle_id, performed_at, cost, odometer_reading)
                VALUES (?, ?, 250.00, 50000)
                """, arguments: [v1, today])
        }

        let stats = try env.fleet.getFleetDashboardStats()
        #expect(stats.totalVehicles == 2)
        #expect(stats.activeVehicles == 1)
        #expect(stats.totalTrailers == 1)
        #expect(stats.fuelCostMTD == 45.50)
        #expect(stats.milesMTD == 120)
        #expect(stats.maintenanceCostMTD == 250.00)

        // Deactivate a vehicle – should reduce counts
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [v2])
        }
        let afterDeactivate = try env.fleet.getFleetDashboardStats()
        #expect(afterDeactivate.totalVehicles == 1)
        #expect(afterDeactivate.activeVehicles == 1)
    }

    @Test("getFleetStats matches getFleetDashboardStats base counts")
    func testFleetStatsMatchesDashboardBaseCounts() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.fleet.createVehicle(
            vehicleNumber: "V-MATCH-1", vehicleName: "Match Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        _ = try env.fleet.createTrailer(trailerNumber: "TR-MATCH-1", trailerType: "enclosed", notes: nil)

        let basic = try env.fleet.getFleetStats()
        let dashboard = try env.fleet.getFleetDashboardStats()

        #expect(basic.totalVehicles == dashboard.totalVehicles)
        #expect(basic.activeVehicles == dashboard.activeVehicles)
        #expect(basic.maintenanceDue == dashboard.maintenanceDue)
        #expect(basic.totalTrailers == dashboard.totalTrailers)
    }

    @Test("getTrailersForJob returns job-scoped trailer dashboard summary")
    func testGetTrailersForJobSummary() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TR-SUM", name: "Trailer Summary Job")
        let otherJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TR-OTHER", name: "Other Job")
        let trailerId = try env.fleet.createTrailer(trailerNumber: "TR-JOB-1", trailerType: "Job Trailer", notes: nil)
        let otherTrailerId = try env.fleet.createTrailer(trailerNumber: "TR-JOB-2", trailerType: "Other Trailer", notes: nil)

        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE job_trailers
                SET current_job_id = ?, assigned_driver_user_id = ?, is_at_shop = 0
                WHERE id = ?
                """, arguments: [jobId, env.adminUserId, trailerId])
            try db.execute(sql: """
                UPDATE job_trailers SET current_job_id = ? WHERE id = ?
                """, arguments: [otherJobId, otherTrailerId])
            try db.execute(sql: """
                INSERT INTO trailer_stock (trailer_id, part_name, quantity, min_qty, created_at, updated_at)
                VALUES (?, 'Connector', 1, 2, datetime('now'), datetime('now')),
                       (?, 'Cable', 5, 2, datetime('now'), datetime('now'))
                """, arguments: [trailerId, trailerId])
            try db.execute(sql: """
                INSERT INTO trailer_location_history
                (trailer_id, location_type, location_label, job_id, arrived_at, recorded_by)
                VALUES (?, 'job_site', 'North gate', ?, '2026-05-13 08:00:00', ?)
                """, arguments: [trailerId, jobId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO trailer_location_events
                (trailer_id, event_type, location_kind, job_id, recorded_by, recorded_at, notes)
                VALUES (?, 'arrived', 'job_site', ?, ?, '2026-05-13 08:05:00', 'On site')
                """, arguments: [trailerId, jobId, env.adminUserId])
        }

        let summaries = try env.fleet.getTrailersForJob(jobId: jobId)

        #expect(summaries.count == 1)
        #expect(summaries[0].id == trailerId)
        #expect(summaries[0].trailerCode == "TR-JOB-1")
        #expect(summaries[0].isAtShop == false)
        #expect(summaries[0].currentJobId == jobId)
        #expect(summaries[0].currentJobName == "Trailer Summary Job")
        #expect(summaries[0].assignedDriverName == env.adminUser.displayName)
        #expect(summaries[0].stockCount == 2)
        #expect(summaries[0].belowMinCount == 1)
        #expect(summaries[0].lastLocationType == "job_site")
        #expect(summaries[0].lastLocationLabel == "North gate")
        #expect(summaries[0].lastEventType == "arrived")
    }

    @Test("getTrailersForJob returns empty when trailer summary tables are missing")
    func testGetTrailersForJobMissingTables() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TR-MISSING", name: "Missing Tables Job")
        let trailerId = try env.fleet.createTrailer(trailerNumber: "TR-MISSING", trailerType: "Job Trailer", notes: nil)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_trailers SET current_job_id = ? WHERE id = ?", arguments: [jobId, trailerId])
            try db.execute(sql: "DROP TABLE trailer_stock")
        }

        let summaries = try env.fleet.getTrailersForJob(jobId: jobId)

        #expect(summaries.isEmpty)
    }

    @Test("getUpcomingFleetMaintenance excludes is_active = 0 vehicles")
    func testUpcomingFleetMaintenance_excludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-MAINT-INACTIVE", vehicleName: "Inactive Maint", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE vehicles SET is_active = 0, next_maintenance_date = date('now', '+1 day')
                WHERE id = ?
                """, arguments: [vehicleId])
        }
        let upcoming = try env.fleet.getUpcomingFleetMaintenance(limit: 50)
        #expect(!upcoming.contains(where: { $0.id == vehicleId }), "is_active=0 vehicle must not appear in upcoming maintenance")
    }

    // MARK: - Permission enforcement

    @Test("createVehicle throws insufficientPermissions when actor lacks manage_fleet")
    func testCreateVehicle_insufficientPermissions() throws {
        let env = try E2ETestHelpers.setUp()
        // A freshly created user with no hat has no permissions
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")

        #expect(throws: FleetService.FleetError.insufficientPermissions(required: "manage_fleet")) {
            try env.fleet.createVehicle(
                actorId: unprivUserId,
                vehicleNumber: "V-NOPERM", vehicleName: "NoPerm Truck", vehicleType: "truck",
                make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
            )
        }
    }

    @Test("createTrailer throws insufficientPermissions when actor lacks manage_fleet")
    func testCreateTrailer_insufficientPermissions() throws {
        let env = try E2ETestHelpers.setUp()
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")

        #expect(throws: FleetService.FleetError.insufficientPermissions(required: "manage_fleet")) {
            try env.fleet.createTrailer(
                actorId: unprivUserId,
                trailerNumber: "T-NOPERM", trailerType: "flatbed", notes: nil
            )
        }
    }

    @Test("assignDriver throws insufficientPermissions when actor lacks manage_fleet")
    func testAssignDriver_insufficientPermissions() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-ASGN-NOPERM", vehicleName: "NoPerm Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")

        #expect(throws: FleetService.FleetError.insufficientPermissions(required: "manage_fleet")) {
            try env.fleet.assignDriver(
                actorId: unprivUserId,
                vehicleId: vehicleId,
                userId: unprivUserId,
                assignmentType: "primary",
                isTakeHome: false
            )
        }
    }

    @Test("logFuelLevel throws insufficientPermissions when actor lacks log_fleet")
    func testLogFuelLevel_insufficientPermissions() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-FUEL-NOPERM", vehicleName: "NoPerm Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // User with no hat has no permissions
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")

        #expect(throws: FleetService.FleetError.insufficientPermissions(required: "log_fleet")) {
            try env.fleet.logFuelLevel(actorId: unprivUserId, vehicleId: vehicleId, fuelLevel: 0.5)
        }
    }

    @Test("logFuelLevel succeeds for a user with the Worker hat (has log_fleet)")
    func testLogFuelLevel_workerCanLog() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-FUEL-WORKER", vehicleName: "Worker Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let workerId = try env.auth.createUser(displayName: "Worker User", pin: "5678")
        // Assign the Worker hat via direct SQL (Worker hat includes log_fleet)
        try env.db.writer.write { db in
            try db.execute(
                sql: "INSERT INTO user_hats (user_id, hat_id, is_active) SELECT ?, id, 1 FROM hats WHERE name = 'Worker'",
                arguments: [workerId]
            )
        }

        // Workers have log_fleet — this must not throw
        try env.fleet.logFuelLevel(actorId: workerId, vehicleId: vehicleId, fuelLevel: 0.6)
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT fuel_level FROM vehicles WHERE id = ?", arguments: [vehicleId])
        }
        let fuel: Double = row?["fuel_level"] ?? -1
        #expect(fuel == 0.6, "Worker must be able to update fuel_level with log_fleet permission")
    }

    @Test("addVehicleStockItem throws insufficientPermissions when actor lacks log_fleet")
    func testAddVehicleStockItem_insufficientPermissions() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-STK-NOPERM", vehicleName: "NoPerm Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // User with no hat has no permissions
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")

        #expect(throws: FleetService.FleetError.insufficientPermissions(required: "log_fleet")) {
            try env.fleet.addVehicleStockItem(
                actorId: unprivUserId,
                vehicleId: vehicleId, partName: "Wire Nut", quantity: 5, stockType: "standard"
            )
        }
    }

    @Test("addVehicleStockItem succeeds for a user with the Worker hat (has log_fleet)")
    func testAddVehicleStockItem_workerCanAdd() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-STK-WORKER", vehicleName: "Worker Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        let workerId = try env.auth.createUser(displayName: "Worker User", pin: "5678")
        // Assign the Worker hat via direct SQL (Worker hat includes log_fleet)
        try env.db.writer.write { db in
            try db.execute(
                sql: "INSERT INTO user_hats (user_id, hat_id, is_active) SELECT ?, id, 1 FROM hats WHERE name = 'Worker'",
                arguments: [workerId]
            )
        }

        // Workers have log_fleet — this must not throw
        try env.fleet.addVehicleStockItem(
            actorId: workerId,
            vehicleId: vehicleId, partName: "Bolt", quantity: 10, stockType: "truck_stock"
        )
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM vehicle_stock WHERE vehicle_id = ? AND part_name = 'Bolt'",
                             arguments: [vehicleId]) ?? 0
        }
        #expect(count == 1, "Worker must be able to add stock items with log_fleet permission")
    }
}
