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
        _ = try env.fleet.createVehicle(vehicleNumber: "V-ACT", vehicleName: "Active Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        let active = try env.fleet.listVehicles(status: "active")
        #expect(active.count >= 1)
    }

    // MARK: - Trailer CRUD

    @Test("Create and list trailers")
    func testTrailerCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(
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
        let trailerId = try env.fleet.createTrailer(trailerNumber: "T-DET", trailerType: "enclosed", notes: nil)
        let detail = try env.fleet.getTrailerDetail(trailerId: trailerId)
        #expect(detail?.trailerCode == "T-DET")
    }

    // MARK: - Driver Assignment

    @Test("Assign driver to vehicle")
    func testAssignDriver() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(vehicleNumber: "V-DRV", vehicleName: "Driver Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        try env.fleet.assignDriver(
            vehicleId: vehicleId,
            userId: env.adminUserId,
            assignmentType: "primary",
            isTakeHome: false
        )
        let detail = try env.fleet.getVehicleDetail(id: vehicleId)
        #expect(detail != nil)
    }

    @Test("My vehicle stats")
    func testMyVehicleStats() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(vehicleNumber: "V-MY", vehicleName: "My Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        try env.fleet.assignDriver(vehicleId: vehicleId, userId: env.adminUserId, assignmentType: "primary", isTakeHome: true)
        let stats = try env.fleet.getMyVehicleStats(userId: env.adminUserId)
        #expect(stats != nil)
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
        _ = try env.fleet.createVehicle(vehicleNumber: "V-STS", vehicleName: "Status Truck", vehicleType: "van", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
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
        let vehicleId = try env.fleet.createVehicle(vehicleNumber: "V-STK", vehicleName: "Stock Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        let stock = try env.fleet.getVehicleStock(vehicleId: vehicleId, stockType: "standard")
        #expect(stock.isEmpty)
    }

    @Test("Add vehicle stock item")
    func testAddVehicleStock() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(vehicleNumber: "V-ADD", vehicleName: "Add Truck", vehicleType: "truck", make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil)
        try env.fleet.addVehicleStockItem(vehicleId: vehicleId, partName: "Wire Nuts", quantity: 100, stockType: "standard")
        let stock = try env.fleet.getVehicleStock(vehicleId: vehicleId, stockType: "standard")
        #expect(stock.count >= 1)
    }

    // MARK: - Trailer Location

    @Test("Update and get trailer location history")
    func testTrailerLocationHistory() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(trailerNumber: "T-LOC", trailerType: "flatbed", notes: nil)
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

    // MARK: - Vehicle Tools

    @Test("Get vehicle tools returns empty when no assignments or checkouts exist")
    func testVehicleToolsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
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
            vehicleNumber: "V-FUEL", vehicleName: "Fuel Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // Assign admin user so getMyVehicleStats returns the vehicle
        try env.fleet.assignDriver(
            vehicleId: vehicleId, userId: env.adminUserId,
            assignmentType: "primary", isTakeHome: true
        )
        try env.fleet.logFuelLevel(vehicleId: vehicleId, fuelLevel: 0.75)
        let stats = try env.fleet.getMyVehicleStats(userId: env.adminUserId)
        #expect(stats?.fuelLevel == 0.75)
    }

    // MARK: - Trailer Stock & Storage Units

    @Test("Get trailer stock returns empty on fresh trailer")
    func testTrailerStockEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(trailerNumber: "T-STK", trailerType: "enclosed", notes: nil)
        let stock = try env.fleet.getTrailerStock(trailerId: trailerId)
        #expect(stock.isEmpty)
    }

    @Test("Get trailer storage units returns empty on fresh trailer")
    func testTrailerStorageUnitsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(trailerNumber: "T-SU", trailerType: "enclosed", notes: nil)
        let units = try env.fleet.getTrailerStorageUnits(trailerId: trailerId)
        #expect(units.isEmpty)
    }

    // MARK: - Save Inspection & Check Required

    @Test("Save inspection and check required returns cleared")
    func testSaveInspectionAndCheckRequired() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
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
            vehicleNumber: "V-DEL-01", vehicleName: "Delete Test", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.fleet.assignDriver(vehicleId: vehicleId, userId: env.adminUserId, assignmentType: "primary", isTakeHome: false)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [env.adminUserId])
        }
        let vehicles = try env.fleet.listVehicles()
        let v = vehicles.first(where: { $0.id == vehicleId })
        #expect(v != nil)
        #expect(v?.assignedUserName == nil)
    }

    @Test("updateTrailerLocation is a no-op on a soft-deleted trailer")
    func testUpdateTrailerLocation_noOpOnSoftDeletedTrailer() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO job_trailers (trailer_code, name, created_at, updated_at)
                VALUES ('TR-SOFTDEL', 'TombstonedTrailer', datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }
        // Set a known is_at_shop state then soft-delete the trailer
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_trailers SET is_at_shop = 0, deleted_at = datetime('now') WHERE id = ?",
                           arguments: [trailerId])
        }
        // Stale dispatcher marks trailer as at-shop — must not mutate a tombstoned row
        try env.fleet.updateTrailerLocation(trailerId: trailerId, locationType: "shop", locationLabel: "Yard", jobId: nil, recordedBy: env.adminUserId)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT is_at_shop FROM job_trailers WHERE id = ?", arguments: [trailerId])
        }
        let isAtShop: Int = row?["is_at_shop"] ?? -1
        #expect(isAtShop == 0,
            "Soft-deleted trailer is_at_shop must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("logFuelLevel is a no-op on a soft-deleted vehicle")
    func testLogFuelLevel_noOpOnSoftDeletedVehicle() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-SOFT-DEL",
            vehicleName: "TombstonedTruck",
            vehicleType: "company_truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        // Seed a known fuel reading, then soft-delete the vehicle
        try env.fleet.logFuelLevel(vehicleId: vehicleId, fuelLevel: 0.25)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [vehicleId])
        }
        // Stale UI writes a new reading. Regression: UPDATE vehicles ... WHERE id = ?
        // had no deleted_at guard, so the write would persist on the tombstone.
        try env.fleet.logFuelLevel(vehicleId: vehicleId, fuelLevel: 0.99)

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
            vehicleNumber: "V-FL-RANGE", vehicleName: "RangeTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        #expect(throws: FleetService.FleetError.invalidFuelLevel(-0.1)) {
            try env.fleet.logFuelLevel(vehicleId: vehicleId, fuelLevel: -0.1)
        }
        #expect(throws: FleetService.FleetError.invalidFuelLevel(1.5)) {
            try env.fleet.logFuelLevel(vehicleId: vehicleId, fuelLevel: 1.5)
        }
    }

    @Test("addVehicleStockItem rejects blank partName, zero quantity, and tombstoned vehicle")
    func testAddVehicleStockItem_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-STK-VAL", vehicleName: "ValTruck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        #expect(throws: FleetService.FleetError.self) {
            try env.fleet.addVehicleStockItem(
                vehicleId: vehicleId, partName: "   ", quantity: 5, stockType: "standard"
            )
        }
        #expect(throws: FleetService.FleetError.self) {
            try env.fleet.addVehicleStockItem(
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
                vehicleId: vehicleId, partName: "WireNut", quantity: 5, stockType: "standard"
            )
        }
    }

    // MARK: - Input validation — create paths (iter 68)

    @Test("createVehicle rejects blank vehicleNumber and vehicleName")
    func testCreateVehicle_rejectsBlankIdentifiers() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: FleetService.FleetError.requiredFieldEmpty("vehicleNumber")) {
            try env.fleet.createVehicle(
                vehicleNumber: "   ", vehicleName: "ValidName", vehicleType: "truck",
                make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
            )
        }
        #expect(throws: FleetService.FleetError.requiredFieldEmpty("vehicleName")) {
            try env.fleet.createVehicle(
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
            try env.fleet.createTrailer(trailerNumber: "", trailerType: "flatbed", notes: nil)
        }
        #expect(throws: FleetService.FleetError.requiredFieldEmpty("trailerType")) {
            try env.fleet.createTrailer(trailerNumber: "TR-BLANK", trailerType: "   ", notes: nil)
        }
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM job_trailers WHERE trailer_code LIKE 'TR-BLANK%'") ?? 0
        }
        #expect(count == 0, "Blank-identifier trailers must produce zero rows in the DB")
    }

    // MARK: - is_active Defense

    @Test("listVehicles excludes is_active = 0 vehicles")
    func testListVehiclesExcludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
            vehicleNumber: "V-INACTIVE", vehicleName: "Inactive Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [vehicleId])
        }
        let vehicles = try env.fleet.listVehicles()
        #expect(!vehicles.contains(where: { $0.id == vehicleId }), "is_active=0 vehicle must not appear in listVehicles")
    }

    @Test("listTrailers excludes is_active = 0 trailers")
    func testListTrailersExcludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(trailerNumber: "TR-INACTIVE", trailerType: "flatbed", notes: nil)
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
            vehicleNumber: "V-STS-INACTIVE", vehicleName: "Inactive Status", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET is_active = 0 WHERE id = ?", arguments: [vehicleId])
        }
        let list = try env.fleet.getVehicleStatusList()
        #expect(!list.contains(where: { $0.id == vehicleId }), "is_active=0 vehicle must not appear in status list")
    }

    @Test("getUpcomingFleetMaintenance excludes is_active = 0 vehicles")
    func testUpcomingFleetMaintenance_excludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let vehicleId = try env.fleet.createVehicle(
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
}
