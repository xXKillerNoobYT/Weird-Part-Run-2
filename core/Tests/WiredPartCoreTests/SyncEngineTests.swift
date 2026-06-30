import Testing
import Foundation
import Network
@testable import WiredPartCore

@Suite("SyncEngine Tests")
struct SyncEngineTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    @Test("Initial state is idle with zero pending")
    func testInitialState() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        let state = await engine.getState()
        #expect(state.status == .idle)
        #expect(state.pendingCount == 0)
        #expect(state.consecutiveFailures == 0)
        #expect(state.lastSyncAt == nil)
        #expect(state.error == nil)
    }

    @Test("Sync with empty shop URL returns error")
    func testEmptyShopUrl() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "",
            authToken: nil
        )
        #expect(result == false)
        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.error == "Shop URL not configured")
    }

    @Test("Sync with unreachable URL increments failure counter")
    func testUnreachableUrl() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        // Use a URL that will fail quickly (connection refused)
        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:1",
            authToken: nil
        )
        #expect(result == false)
        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.consecutiveFailures == 1)
    }

    @Test("Multiple failures increment counter")
    func testMultipleFailures() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let state = await engine.getState()
        #expect(state.consecutiveFailures == 2)
    }

    @Test("Manual sync resets failure counter")
    func testManualSyncResets() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        // First, cause a failure
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let stateBefore = await engine.getState()
        #expect(stateBefore.consecutiveFailures == 1)

        // Manual sync resets counter (even if it fails)
        _ = await engine.manualSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        // Counter was reset to 0 before the sync attempt, then incremented to 1 by the failure
        let stateAfter = await engine.getState()
        #expect(stateAfter.consecutiveFailures == 1)
    }

    @Test("Backoff calculation follows exponential pattern")
    func testBackoffCalculation() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        // 0 failures → normal interval
        let delay0 = await engine.getBackoffDelay()
        #expect(delay0 == SyncEngine.syncInterval)

        // Cause failures and check backoff
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let delay1 = await engine.getBackoffDelay()
        #expect(delay1 == SyncEngine.minBackoff) // 30s × 2^0 = 30s

        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let delay2 = await engine.getBackoffDelay()
        #expect(delay2 == SyncEngine.minBackoff * 2) // 30s × 2^1 = 60s

        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let delay3 = await engine.getBackoffDelay()
        #expect(delay3 == SyncEngine.minBackoff * 4) // 30s × 2^2 = 120s
    }

    @Test("Periodic sync lifecycle starts and stops")
    func testPeriodicLifecycle() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        await engine.startPeriodicSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:1"
        )
        // Should be running — calling start again is a no-op
        await engine.startPeriodicSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:1"
        )

        await engine.stopPeriodicSync()
        // State should still be accessible after stop
        let state = await engine.getState()
        #expect(state.status == .idle || state.status == .error || state.status == .syncing)
    }

    @Test("State change callback fires")
    func testStateChangeCallback() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        let expectation = Mutex(false)
        await engine.setOnStateChanged { _ in
            expectation.withLock { $0 = true }
        }

        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "")
        // Give main actor a moment to dispatch
        try await Task.sleep(for: .milliseconds(100))
        let fired = expectation.withLock { $0 }
        #expect(fired == true)
    }

    @Test("Sync ack failure is retryable and does not mark changes synced")
    func testAckFailureDoesNotReportSynced() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "dev-001"
        )
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let server = try SyncEngineHTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                return SyncEngineHTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch-ack-fails","shop_changes":[]}}"#
                )
            case "/api/sync/ack":
                return SyncEngineHTTPStubResponse(
                    statusCode: 500,
                    body: #"{"error":"ack failed"}"#
                )
            default:
                return SyncEngineHTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:\(port)",
            authToken: nil
        )

        #expect(result == false)
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.pendingCount == 1)
        #expect(state.error == "Ack failed: 500")
        #expect(state.consecutiveFailures == 1)
    }
}

// Simple thread-safe wrapper for test assertions
private final class Mutex<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private struct SyncEngineHTTPStubRequest: Sendable {
    let path: String
}

private struct SyncEngineHTTPStubResponse: Sendable {
    let statusCode: Int
    let body: String
}

private final class SyncEngineHTTPStubServer: @unchecked Sendable {
    private let listener: NWListener
    private let handler: @Sendable (SyncEngineHTTPStubRequest) -> SyncEngineHTTPStubResponse
    private let queue = DispatchQueue(label: "com.wiredpart.tests.syncengine.httpstub")

    init(handler: @escaping @Sendable (SyncEngineHTTPStubRequest) -> SyncEngineHTTPStubResponse) throws {
        self.listener = try NWListener(using: .tcp, on: .any)
        self.handler = handler
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let continuationBox = SyncEngineOneShotContinuationBox(continuation)

            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        continuationBox.resume(.success(port.rawValue))
                    } else {
                        continuationBox.resume(.failure(URLError(.badServerResponse)))
                    }
                case .failed(let error):
                    continuationBox.resume(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [handler, queue] connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                    let rawRequest = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let requestLine = rawRequest.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                    let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                    let stubResponse = handler(SyncEngineHTTPStubRequest(path: path))
                    let statusText = (200..<300).contains(stubResponse.statusCode) ? "OK" : "Error"
                    let response = """
                    HTTP/1.1 \(stubResponse.statusCode) \(statusText)\r
                    Content-Type: application/json\r
                    Content-Length: \(stubResponse.body.utf8.count)\r
                    Connection: close\r
                    \r
                    \(stubResponse.body)
                    """
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }
}

private final class SyncEngineOneShotContinuationBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<UInt16, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

// Extension to allow setting callback from outside actor
extension SyncEngine {
    func setOnStateChanged(_ callback: @escaping @Sendable (SyncState) -> Void) {
        self.onStateChanged = callback
    }
}
