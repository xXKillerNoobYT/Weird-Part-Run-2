//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Testing
import os.log
@testable import Weird_Parts

private enum BootstrapAuditTestError: Error {
    case start
    case complete
    case operation
}

private final class MockBootstrapTaskAuditor: AppCoreBackgroundTaskAuditing, @unchecked Sendable {
    var startedNames: [String] = []
    var completedIds: [Int64] = []
    var failedIds: [Int64] = []
    var startError: Error?
    var completeError: Error?

    func startTask(name: String, type: String, deviceId: String?) throws -> Int64 {
        if let startError {
            throw startError
        }
        startedNames.append(name)
        return 42
    }

    func completeTask(id: Int64, summary: String?, itemsProcessed: Int) throws {
        if let completeError {
            throw completeError
        }
        completedIds.append(id)
    }

    func failTask(id: Int64, error: String) throws {
        failedIds.append(id)
    }
}

private final class OperationProbe: @unchecked Sendable {
    var ran = false
}

struct Weird_Parts_IOSTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test func qaResolvedStatusBucketIncludesServiceResolvedStatus() async throws {
        #expect(QAThreadStatusBuckets.isResolved("resolved"))
        #expect(QAThreadStatusBuckets.isResolved("answered"))
        #expect(QAThreadStatusBuckets.isResolved("closed"))
        #expect(!QAThreadStatusBuckets.isResolved("open"))
        #expect(!QAThreadStatusBuckets.isResolved("escalated"))
    }

    @Test func auditedBootstrapTaskStillRunsWhenAuditStartFails() throws {
        let auditor = MockBootstrapTaskAuditor()
        auditor.startError = BootstrapAuditTestError.start
        let operation = OperationProbe()

        AppCore.runAuditedBootstrapTask(
            name: "Test Bootstrap Task",
            type: "test",
            successSummary: "Test complete",
            backgroundTaskService: auditor,
            logger: Logger(subsystem: "com.wiredpart.tests", category: "AppCore")
        ) {
            operation.ran = true
        }

        #expect(operation.ran)
        #expect(auditor.completedIds.isEmpty)
        #expect(auditor.failedIds.isEmpty)
    }

    @Test func auditedBootstrapTaskDoesNotThrowWhenAuditCompletionFails() throws {
        let auditor = MockBootstrapTaskAuditor()
        auditor.completeError = BootstrapAuditTestError.complete
        let operation = OperationProbe()

        AppCore.runAuditedBootstrapTask(
            name: "Test Bootstrap Task",
            type: "test",
            successSummary: "Test complete",
            backgroundTaskService: auditor,
            logger: Logger(subsystem: "com.wiredpart.tests", category: "AppCore")
        ) {
            operation.ran = true
        }

        #expect(operation.ran)
        #expect(auditor.startedNames == ["Test Bootstrap Task"])
        #expect(auditor.failedIds.isEmpty)
    }

    @Test func auditedBootstrapTaskRecordsOperationFailureWhenPossible() throws {
        let auditor = MockBootstrapTaskAuditor()

        AppCore.runAuditedBootstrapTask(
            name: "Test Bootstrap Task",
            type: "test",
            successSummary: "Test complete",
            backgroundTaskService: auditor,
            logger: Logger(subsystem: "com.wiredpart.tests", category: "AppCore")
        ) {
            throw BootstrapAuditTestError.operation
        }

        #expect(auditor.completedIds.isEmpty)
        #expect(auditor.failedIds == [42])
    }
}
