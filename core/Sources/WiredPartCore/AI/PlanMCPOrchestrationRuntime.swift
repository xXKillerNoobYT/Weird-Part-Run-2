import Foundation

public struct PlanMCPRetryPolicy: Sendable, Equatable {
    public let maxAttempts: Int

    public init(maxAttempts: Int) {
        self.maxAttempts = max(1, maxAttempts)
    }
}

public struct PlanMCPExecutionStep: Sendable, Equatable {
    public let id: String
    public let capabilityId: String
    public let preferredProviderId: String?
    public let timeoutNanoseconds: UInt64?

    public init(
        id: String,
        capabilityId: String,
        preferredProviderId: String? = nil,
        timeoutNanoseconds: UInt64? = nil
    ) {
        self.id = id
        self.capabilityId = capabilityId
        self.preferredProviderId = preferredProviderId
        self.timeoutNanoseconds = timeoutNanoseconds
    }
}

public struct PlanMCPExecutionPhase: Sendable, Equatable {
    public let id: String
    public let steps: [PlanMCPExecutionStep]

    public init(id: String, steps: [PlanMCPExecutionStep]) {
        self.id = id
        self.steps = steps
    }
}

public struct PlanMCPExecutionGraph: Sendable, Equatable {
    public let phases: [PlanMCPExecutionPhase]

    public init(phases: [PlanMCPExecutionPhase]) {
        self.phases = phases
    }
}

public struct PlanMCPRuntimeRequest: Sendable {
    public let graph: PlanMCPExecutionGraph
    public let idempotencyKey: String
    public let grantedPermissions: Set<String>
    public let approvalGranted: Bool
    public let maxAllowedRisk: PlanMCPRiskLevel
    public let providerAvailability: [String: Bool]
    public let retryPolicy: PlanMCPRetryPolicy
    public let defaultStepTimeoutNanoseconds: UInt64?

    public init(
        graph: PlanMCPExecutionGraph,
        idempotencyKey: String,
        grantedPermissions: Set<String>,
        approvalGranted: Bool,
        maxAllowedRisk: PlanMCPRiskLevel,
        providerAvailability: [String: Bool],
        retryPolicy: PlanMCPRetryPolicy,
        defaultStepTimeoutNanoseconds: UInt64? = nil
    ) {
        self.graph = graph
        self.idempotencyKey = idempotencyKey
        self.grantedPermissions = grantedPermissions
        self.approvalGranted = approvalGranted
        self.maxAllowedRisk = maxAllowedRisk
        self.providerAvailability = providerAvailability
        self.retryPolicy = retryPolicy
        self.defaultStepTimeoutNanoseconds = defaultStepTimeoutNanoseconds
    }
}

public protocol PlanMCPProviderExecutor: Sendable {
    func execute(step: PlanMCPExecutionStep, providerId: String) async throws -> String
}

public struct PlanMCPStepExecutionResult: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case success
        case denied(PlanMCPGateDecision.PlanMCPDenyReason)
        case failed
    }

    public let stepId: String
    public let status: Status
    public let attempts: Int
    public let selectedProviderId: String?
    public let timedOut: Bool
    public let output: String?
    public let errorMessage: String?

    public init(
        stepId: String,
        status: Status,
        attempts: Int,
        selectedProviderId: String?,
        timedOut: Bool,
        output: String?,
        errorMessage: String?
    ) {
        self.stepId = stepId
        self.status = status
        self.attempts = attempts
        self.selectedProviderId = selectedProviderId
        self.timedOut = timedOut
        self.output = output
        self.errorMessage = errorMessage
    }
}

public struct PlanMCPPhaseExecutionResult: Sendable, Equatable {
    public let phaseId: String
    public let stepResults: [PlanMCPStepExecutionResult]

    public init(phaseId: String, stepResults: [PlanMCPStepExecutionResult]) {
        self.phaseId = phaseId
        self.stepResults = stepResults
    }
}

public struct PlanMCPRuntimeExecutionResult: Sendable, Equatable {
    public let idempotencyKey: String
    public let phaseResults: [PlanMCPPhaseExecutionResult]
    public let completed: Bool

    public init(idempotencyKey: String, phaseResults: [PlanMCPPhaseExecutionResult], completed: Bool) {
        self.idempotencyKey = idempotencyKey
        self.phaseResults = phaseResults
        self.completed = completed
    }
}

public actor PlanMCPIdempotencyStore {
    private var cached: [String: PlanMCPRuntimeExecutionResult] = [:]

    public init() {}

    public func result(for key: String) -> PlanMCPRuntimeExecutionResult? {
        cached[key]
    }

    public func save(_ result: PlanMCPRuntimeExecutionResult, for key: String) {
        cached[key] = result
    }
}

public struct PlanMCPOrchestrationRuntime: Sendable {
    private let router: PlanMCPDeterministicRouter
    private let providerExecutor: any PlanMCPProviderExecutor
    private let idempotencyStore: PlanMCPIdempotencyStore

    public init(
        router: PlanMCPDeterministicRouter,
        providerExecutor: any PlanMCPProviderExecutor,
        idempotencyStore: PlanMCPIdempotencyStore = PlanMCPIdempotencyStore()
    ) {
        self.router = router
        self.providerExecutor = providerExecutor
        self.idempotencyStore = idempotencyStore
    }

    public func execute(_ request: PlanMCPRuntimeRequest) async -> PlanMCPRuntimeExecutionResult {
        if let existing = await idempotencyStore.result(for: request.idempotencyKey) {
            return existing
        }

        var phaseResults: [PlanMCPPhaseExecutionResult] = []
        var completed = true

        for phase in request.graph.phases {
            let phaseResult = await executePhase(phase, request: request)
            phaseResults.append(phaseResult)

            if phaseResult.stepResults.contains(where: { step in
                if case .success = step.status { return false }
                return true
            }) {
                completed = false
                break
            }
        }

        let result = PlanMCPRuntimeExecutionResult(
            idempotencyKey: request.idempotencyKey,
            phaseResults: phaseResults,
            completed: completed
        )
        await idempotencyStore.save(result, for: request.idempotencyKey)
        return result
    }

    private func executePhase(
        _ phase: PlanMCPExecutionPhase,
        request: PlanMCPRuntimeRequest
    ) async -> PlanMCPPhaseExecutionResult {
        let indexed = await withTaskGroup(of: (Int, PlanMCPStepExecutionResult).self) { group in
            for (index, step) in phase.steps.enumerated() {
                group.addTask {
                    let result = await executeStep(step, request: request)
                    return (index, result)
                }
            }

            var collected: [(Int, PlanMCPStepExecutionResult)] = []
            for await item in group {
                collected.append(item)
            }
            return collected.sorted { $0.0 < $1.0 }
        }

        return PlanMCPPhaseExecutionResult(
            phaseId: phase.id,
            stepResults: indexed.map(\.1)
        )
    }

    private func executeStep(
        _ step: PlanMCPExecutionStep,
        request: PlanMCPRuntimeRequest
    ) async -> PlanMCPStepExecutionResult {
        let routeDecision = router.route(
            PlanMCPRouteRequest(
                capabilityId: step.capabilityId,
                grantedPermissions: request.grantedPermissions,
                approvalGranted: request.approvalGranted,
                maxAllowedRisk: request.maxAllowedRisk,
                providerAvailability: request.providerAvailability,
                preferredProviderId: step.preferredProviderId
            )
        )

        guard routeDecision.gateDecision == .allowed, let providerId = routeDecision.selectedProviderId else {
            if case .denied(let reason) = routeDecision.gateDecision {
                return PlanMCPStepExecutionResult(
                    stepId: step.id,
                    status: .denied(reason),
                    attempts: 0,
                    selectedProviderId: nil,
                    timedOut: false,
                    output: nil,
                    errorMessage: routeDecision.rationale
                )
            }

            return PlanMCPStepExecutionResult(
                stepId: step.id,
                status: .failed,
                attempts: 0,
                selectedProviderId: nil,
                timedOut: false,
                output: nil,
                errorMessage: "Routing was allowed but no provider was selected"
            )
        }

        let timeout = step.timeoutNanoseconds ?? request.defaultStepTimeoutNanoseconds
        var attempt = 0
        var lastError: String?
        var timedOut = false

        while attempt < request.retryPolicy.maxAttempts {
            attempt += 1

            do {
                let output = try await executeWithTimeout(step: step, providerId: providerId, timeoutNanoseconds: timeout)
                return PlanMCPStepExecutionResult(
                    stepId: step.id,
                    status: .success,
                    attempts: attempt,
                    selectedProviderId: providerId,
                    timedOut: false,
                    output: output,
                    errorMessage: nil
                )
            } catch is PlanMCPRuntimeTimeoutError {
                timedOut = true
                lastError = "step_timeout"
            } catch {
                lastError = String(describing: error)
            }
        }

        return PlanMCPStepExecutionResult(
            stepId: step.id,
            status: .failed,
            attempts: attempt,
            selectedProviderId: providerId,
            timedOut: timedOut,
            output: nil,
            errorMessage: lastError
        )
    }

    private func executeWithTimeout(
        step: PlanMCPExecutionStep,
        providerId: String,
        timeoutNanoseconds: UInt64?
    ) async throws -> String {
        guard let timeoutNanoseconds else {
            return try await providerExecutor.execute(step: step, providerId: providerId)
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await providerExecutor.execute(step: step, providerId: providerId)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PlanMCPRuntimeTimeoutError()
            }

            guard let first = try await group.next() else {
                throw PlanMCPRuntimeTimeoutError()
            }
            group.cancelAll()
            return first
        }
    }
}

private struct PlanMCPRuntimeTimeoutError: Error {}
