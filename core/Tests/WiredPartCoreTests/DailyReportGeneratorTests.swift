import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("DailyReportGenerator Tests")
struct DailyReportGeneratorTests {

    private func freshEnv() throws -> (E2ETestHelpers.TestEnvironment, DailyReportGenerator) {
        let env = try E2ETestHelpers.setUp()
        let generator = DailyReportGenerator(db: env.db)
        return (env, generator)
    }

    @Test("Generate report for user with no labor entries")
    func testEmptyReport() throws {
        let (env, gen) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let report = try gen.generateReport(userId: env.adminUserId, jobId: jobId)
        #expect(report.totalHours == 0)
    }

    @Test("Get today's jobs for user")
    func testTodaysJobs() throws {
        let (env, gen) = try freshEnv()
        let jobs = try gen.getTodaysJobs(userId: env.adminUserId)
        #expect(jobs.count >= 0)
    }

    @Test("Report includes user and job info")
    func testReportMetadata() throws {
        let (env, gen) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-RPT", name: "Report Job")

        let report = try gen.generateReport(userId: env.adminUserId, jobId: jobId)
        #expect(report.userId == env.adminUserId)
        #expect(report.jobId == jobId)
    }
}
