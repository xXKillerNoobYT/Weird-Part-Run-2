import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("PartsService Permission Gate Tests")
struct PartsServicePermissionGateTests {
    @discardableResult
    private func insertPendingRecommendation(
        _ env: E2ETestHelpers.TestEnvironment,
        partId: Int64,
        recommendationType: String = "adjust",
        recommendedMin: Int = 2,
        recommendedTarget: Int = 5,
        recommendedMax: Int = 10
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO target_recommendations
                    (part_id, location_type, location_id, recommendation_type,
                     current_min, current_target, current_max,
                     recommended_min, recommended_target, recommended_max,
                     usage_value, usage_unit, data_days, impact_score,
                     reason, cooldown_until, status)
                VALUES (?, 'warehouse', 1, ?, 0, 0, 0, ?, ?, ?,
                        1.0, 'daily', 90, 5.0,
                        'Test recommendation', datetime('now', '+60 days'), 'pending')
                """,
                arguments: [partId, recommendationType, recommendedMin, recommendedTarget, recommendedMax])
            return db.lastInsertedRowID
        }
    }

    private func seedWorkerUser(_ env: E2ETestHelpers.TestEnvironment) throws -> Int64 {
        let userId = try env.auth.createUser(displayName: "Parts Worker", pin: "2468")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO user_hats (user_id, hat_id, is_active)
                SELECT ?, id, 1 FROM hats WHERE name = 'Worker'
                """, arguments: [userId])
        }
        return userId
    }

    private func seedRecommendationFixture(
        _ env: E2ETestHelpers.TestEnvironment,
        categoryName: String,
        partName: String
    ) throws -> Int64 {
        let catId = try E2ETestHelpers.seedCategory(env, name: categoryName)
        let partId = try E2ETestHelpers.seedPart(env, name: partName, categoryId: catId)
        try env.parts.setLocationStockTarget(
            partId: partId,
            locationType: "warehouse",
            locationId: 1,
            minStock: 0,
            targetStock: 0,
            maxStock: 0
        )
        return try insertPendingRecommendation(env, partId: partId)
    }

    @Test("approveRecommendation rejects users without recommendation approval permission")
    func approveRecommendationRejectsWithoutPermission() throws {
        let env = try E2ETestHelpers.setUp()
        let workerUserId = try seedWorkerUser(env)
        let recId = try seedRecommendationFixture(
            env,
            categoryName: "ApproveDeniedCat",
            partName: "ApproveDeniedPart"
        )

        do {
            try env.parts.approveRecommendation(id: recId, userId: workerUserId)
            Issue.record("approveRecommendation should reject users without parts.approve_recommendation")
        } catch PartsService.PartsError.insufficientPermissions(let required) {
            #expect(required == "parts.approve_recommendation")
        } catch {
            Issue.record("Expected insufficientPermissions, got \(error)")
        }

        let row = try env.db.writer.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT status, approved_by FROM target_recommendations WHERE id = ?",
                arguments: [recId]
            )
        }
        let result = try #require(row)
        #expect((result["status"] as String) == "pending")
        #expect((result["approved_by"] as Int64?) == nil)
    }

    @Test("dismissRecommendation rejects users without recommendation dismissal permission")
    func dismissRecommendationRejectsWithoutPermission() throws {
        let env = try E2ETestHelpers.setUp()
        let workerUserId = try seedWorkerUser(env)
        let recId = try seedRecommendationFixture(
            env,
            categoryName: "DismissDeniedCat",
            partName: "DismissDeniedPart"
        )

        do {
            try env.parts.dismissRecommendation(id: recId, userId: workerUserId, reason: "Not needed")
            Issue.record("dismissRecommendation should reject users without parts.dismiss_recommendation")
        } catch PartsService.PartsError.insufficientPermissions(let required) {
            #expect(required == "parts.dismiss_recommendation")
        } catch {
            Issue.record("Expected insufficientPermissions, got \(error)")
        }

        let row = try env.db.writer.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT status, dismissed_by, dismissed_reason FROM target_recommendations WHERE id = ?",
                arguments: [recId]
            )
        }
        let result = try #require(row)
        #expect((result["status"] as String) == "pending")
        #expect((result["dismissed_by"] as Int64?) == nil)
        #expect((result["dismissed_reason"] as String?) == nil)
    }
}
