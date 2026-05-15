import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("Warehouse Walking Path Tests")
struct WarehouseWalkingPathTests {
    private func freshEnv() throws -> E2ETestHelpers.TestEnvironment {
        try E2ETestHelpers.setUp()
    }

    @Test("walking path migration creates schema and idempotent stop APIs")
    func walkingPathSchemaAndIdempotency() throws {
        let env = try freshEnv()

        try env.db.writer.read { db in
            let pathColumns = try db.columns(in: "warehouse_walking_paths").map(\.name)
            #expect(pathColumns.contains("deleted_at"))
            #expect(pathColumns.contains("is_active"))
            #expect(pathColumns.contains("is_default"))

            let stopColumns = try db.columns(in: "warehouse_walking_path_stops").map(\.name)
            #expect(stopColumns.contains("path_id"))
            #expect(stopColumns.contains("area_id"))
            #expect(stopColumns.contains("sort_order"))
            #expect(stopColumns.contains("deleted_at"))
            #expect(stopColumns.contains("is_active"))

            let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list('warehouse_walking_path_stops')")
            let indexNames = Set(indexes.compactMap { $0["name"] as String? })
            #expect(indexNames.contains("idx_walking_path_stops_path_order"))
            #expect(indexNames.contains("idx_walking_path_stops_unique_active_area"))
        }

        let fixture = try makeAreaFixture(env)
        let path = try env.warehouse.createWalkingPath(
            floorPlanId: fixture.floorPlanId,
            name: "Default",
            userId: env.adminUserId
        )
        let pathId = try #require(path.id)

        try env.warehouse.appendWalkingPathStop(pathId: pathId, areaId: fixture.areas[0])
        try env.warehouse.appendWalkingPathStop(pathId: pathId, areaId: fixture.areas[0])
        var loaded = try #require(try env.warehouse.getDefaultWalkingPath(floorPlanId: fixture.floorPlanId))
        #expect(loaded.stops.map(\.areaId) == [fixture.areas[0]])

        let originalStopId = try #require(loaded.stops.first?.id)
        try env.warehouse.setWalkingPathStops(pathId: pathId, areaIds: [fixture.areas[1], fixture.areas[0], fixture.areas[1]])
        loaded = try #require(try env.warehouse.getDefaultWalkingPath(floorPlanId: fixture.floorPlanId))
        #expect(loaded.stops.map(\.areaId) == [fixture.areas[1], fixture.areas[0]])
        #expect(loaded.stops.first(where: { $0.areaId == fixture.areas[0] })?.id == originalStopId)
    }

    @Test("suggestWalkingPath returns row-major area order")
    func suggestWalkingPathReturnsRowMajorOrder() throws {
        let env = try freshEnv()
        let fixture = try makeAreaFixture(env)

        let suggested = try env.warehouse.suggestWalkingPath(floorPlanId: fixture.floorPlanId)

        #expect(suggested == [
            fixture.byUnitName["North West"]![0],
            fixture.byUnitName["North West"]![1],
            fixture.byUnitName["North East"]![0],
            fixture.byUnitName["South West"]![0],
        ])
    }

    @Test("pruneOrphanedStops removes only soft-deleted and hard-deleted area stops")
    func pruneOrphanedStopsRemovesOnlyDeletedAreaStops() throws {
        let env = try freshEnv()
        let fixture = try makeAreaFixture(env)
        let path = try env.warehouse.createWalkingPath(
            floorPlanId: fixture.floorPlanId,
            name: "Default",
            userId: env.adminUserId
        )
        let pathId = try #require(path.id)

        try env.warehouse.setWalkingPathStops(pathId: pathId, areaIds: fixture.areas)
        try env.warehouse.deleteStorageArea(id: fixture.areas[1])
        try env.db.writer.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(
                sql: "DELETE FROM warehouse_storage_areas WHERE id = ?",
                arguments: [fixture.areas[2]]
            )
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let removed = try env.warehouse.pruneOrphanedStops(floorPlanId: fixture.floorPlanId)
        let loaded = try #require(try env.warehouse.getDefaultWalkingPath(floorPlanId: fixture.floorPlanId))

        #expect(removed == 2)
        #expect(loaded.stops.map(\.areaId) == [fixture.areas[0], fixture.areas[3]])
    }

    @Test("reloading default walking path prunes deleted area stops before save")
    func reloadingDefaultWalkingPathPrunesDeletedStopsBeforeSave() throws {
        let env = try freshEnv()
        let fixture = try makeAreaFixture(env)
        let path = try env.warehouse.createWalkingPath(
            floorPlanId: fixture.floorPlanId,
            name: "Default",
            userId: env.adminUserId
        )
        let pathId = try #require(path.id)

        try env.warehouse.setWalkingPathStops(pathId: pathId, areaIds: [fixture.areas[0], fixture.areas[1]])
        try env.warehouse.deleteStorageArea(id: fixture.areas[1])

        let reloaded = try #require(try env.warehouse.getDefaultWalkingPath(floorPlanId: fixture.floorPlanId))
        #expect(reloaded.stops.map(\.areaId) == [fixture.areas[0]])
        #expect(reloaded.stops.map(\.sortOrder) == [0])

        try env.warehouse.setWalkingPathStops(pathId: pathId, areaIds: reloaded.stops.map(\.areaId) + [fixture.areas[2]])
        let saved = try #require(try env.warehouse.getDefaultWalkingPath(floorPlanId: fixture.floorPlanId))

        #expect(saved.stops.map(\.areaId) == [fixture.areas[0], fixture.areas[2]])
        #expect(saved.stops.map(\.sortOrder) == [0, 1])
    }

    @Test("moveWalkingPathStop reorders active stops")
    func moveWalkingPathStopReordersStops() throws {
        let env = try freshEnv()
        let fixture = try makeAreaFixture(env)
        let path = try env.warehouse.createWalkingPath(
            floorPlanId: fixture.floorPlanId,
            name: "Default",
            userId: env.adminUserId
        )
        let pathId = try #require(path.id)

        try env.warehouse.setWalkingPathStops(pathId: pathId, areaIds: fixture.areas)
        let loaded = try #require(try env.warehouse.getDefaultWalkingPath(floorPlanId: fixture.floorPlanId))
        let lastStopId = try #require(loaded.stops.last?.id)

        try env.warehouse.moveWalkingPathStop(stopId: lastStopId, toIndex: 1)
        let moved = try #require(try env.warehouse.getDefaultWalkingPath(floorPlanId: fixture.floorPlanId))

        #expect(moved.stops.map(\.areaId) == [
            fixture.areas[0],
            fixture.areas[3],
            fixture.areas[1],
            fixture.areas[2],
        ])
        #expect(moved.stops.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("walking path stops must belong to the path floor plan")
    func walkingPathStopsRejectCrossFloorPlanAreas() throws {
        let env = try freshEnv()
        let fixture = try makeAreaFixture(env)
        let otherFixture = try makeAreaFixture(env)
        let path = try env.warehouse.createWalkingPath(
            floorPlanId: fixture.floorPlanId,
            name: "Default",
            userId: env.adminUserId
        )
        let pathId = try #require(path.id)

        #expect(throws: WarehouseService.WarehouseError.self) {
            try env.warehouse.appendWalkingPathStop(pathId: pathId, areaId: otherFixture.areas[0])
        }
        #expect(throws: WarehouseService.WarehouseError.self) {
            try env.warehouse.setWalkingPathStops(pathId: pathId, areaIds: [otherFixture.areas[0]])
        }
    }

    private func makeAreaFixture(_ env: E2ETestHelpers.TestEnvironment) throws -> (
        floorPlanId: Int64,
        areas: [Int64],
        byUnitName: [String: [Int64]]
    ) {
        let plan = try env.warehouse.createFloorPlan(name: "Walking Path WH", widthInches: 480, lengthInches: 360)
        let floorPlanId = try #require(plan.id)

        let southWest = try makeUnit(env, floorPlanId: floorPlanId, name: "South West", gridX: 0, gridY: 1, areas: 1)
        let northEast = try makeUnit(env, floorPlanId: floorPlanId, name: "North East", gridX: 1, gridY: 0, areas: 1)
        let northWest = try makeUnit(env, floorPlanId: floorPlanId, name: "North West", gridX: 0, gridY: 0, areas: 2)

        return (
            floorPlanId,
            northWest + northEast + southWest,
            [
                "North West": northWest,
                "North East": northEast,
                "South West": southWest,
            ]
        )
    }

    private func makeUnit(
        _ env: E2ETestHelpers.TestEnvironment,
        floorPlanId: Int64,
        name: String,
        gridX: Int,
        gridY: Int,
        areas: Int
    ) throws -> [Int64] {
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: floorPlanId,
            name: name,
            unitType: "shelf",
            rowNumber: name,
            unitNumber: name,
            gridX: gridX,
            gridY: gridY
        )
        let level = try env.warehouse.addStorageLevel(unitId: try #require(unit.id), levelCode: "L1", order: 0)
        var areaIds: [Int64] = []
        for areaNumber in 1...areas {
            let area = try env.warehouse.addStorageArea(levelId: try #require(level.id), areaNumber: areaNumber)
            areaIds.append(try #require(area.id))
        }
        return areaIds
    }
}
