import Foundation

@MainActor
final class BootstrapCoordinator {
    struct TimeoutError: LocalizedError {
        let seconds: TimeInterval

        var errorDescription: String? {
            "Bootstrap exceeded \(Int(seconds))s timeout"
        }
    }

    struct Failure {
        let incidentID: String
        let title: String
        let details: String
        let technicalDetails: String
        let errorType: String
        let errorCode: String
        let errorMessage: String
        let elapsed: TimeInterval
        let timeout: TimeInterval
    }

    enum State {
        case loading
        case ready
        case failed(Failure)
    }

    private let timeout: TimeInterval
    private let bootstrapWork: @Sendable () async throws -> Void
    private let now: () -> Date

    private var task: Task<Void, Never>?

    var onStateChange: ((State) -> Void)?

    init(
        timeout: TimeInterval,
        now: @escaping () -> Date = Date.init,
        bootstrapWork: @escaping @Sendable () async throws -> Void
    ) {
        self.timeout = timeout
        self.now = now
        self.bootstrapWork = bootstrapWork
    }

    func start() {
        runBootstrap()
    }

    func retry() {
        runBootstrap()
    }

    private func runBootstrap() {
        task?.cancel()
        onStateChange?(.loading)

        task = Task { [timeout, now, bootstrapWork] in
            let startedAt = now()
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await bootstrapWork()
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(timeout))
                        throw TimeoutError(seconds: timeout)
                    }

                    _ = try await group.next()
                    group.cancelAll()
                }

                guard !Task.isCancelled else { return }
                onStateChange?(.ready)
            } catch {
                guard !Task.isCancelled else { return }
                let elapsed = now().timeIntervalSince(startedAt)
                let failure = Self.makeFailure(error: error, elapsed: elapsed, timeout: timeout)
                onStateChange?(.failed(failure))
            }
        }
    }

    private static func makeFailure(error: Error, elapsed: TimeInterval, timeout: TimeInterval) -> Failure {
        let incidentID = String(UUID().uuidString.prefix(8))
        let context = ErrorContext.from(error: error)
        if let timeoutError = error as? TimeoutError {
            return Failure(
                incidentID: incidentID,
                title: "Startup Timed Out",
                details: "The app stayed in loading for over \(Int(timeoutError.seconds)) seconds. Check network availability, then retry. If this repeats, copy diagnostics and share them with engineering.",
                technicalDetails: timeoutError.localizedDescription,
                errorType: context.errorType,
                errorCode: context.errorCode,
                errorMessage: context.errorMessage,
                elapsed: elapsed,
                timeout: timeout
            )
        }

        return Failure(
            incidentID: incidentID,
            title: "Startup Failed",
            details: "Bootstrap failed with error: \(error.localizedDescription). Retry once. If it fails again, copy diagnostics and report the failure.",
            technicalDetails: error.localizedDescription,
            errorType: context.errorType,
            errorCode: context.errorCode,
            errorMessage: context.errorMessage,
            elapsed: elapsed,
            timeout: timeout
        )
    }
}

private struct ErrorContext {
    let errorType: String
    let errorCode: String
    let errorMessage: String

    static func from(error: Error) -> Self {
        let nsError = error as NSError
        let typeName = String(reflecting: type(of: error))
        let message = nsError.localizedDescription
        return Self(errorType: typeName, errorCode: "\(nsError.code)", errorMessage: message)
    }
}
