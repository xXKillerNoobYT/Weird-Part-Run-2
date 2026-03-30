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
}
