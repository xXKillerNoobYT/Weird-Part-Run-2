import Foundation
import Testing
@testable import WiredPartCore

@Suite("PLAN MCP orchestration runtime")
struct PlanMCPOrchestrationRuntimeTests {
    actor StubExecutor: PlanMCPProviderExecutor {
        private(set) var attemptsByStep: [String: Int] = [:]

        func execute(step: PlanMCPExecutionStep, providerId: String) async throws -> String {
            let current = (attemptsByStep[step.id] ?? 0) + 1
            attemptsByStep[step.id] = current

            switch step.id {
            case "discover":
                return "discover:\(providerId)"
            case "fanout_a":
                return "fanout_a:\(providerId)"
            case "fanout_b":
                if current == 1 {
                    try await Task.sleep(nanoseconds: 30_000_000)
                }
                return "fanout_b:\(providerId):attempt\(current)"
            default:
                return "ok:\(step.id)"
            }
        }

        func attemptCount(for stepId: String) -> Int {
            attemptsByStep[stepId] ?? 0
        }
    }

    private func makeRuntime(executor: StubExecutor) -> PlanMCPOrchestrationRuntime {
        let capability = PlanMCPCapabilityDescriptor(
            id: "execute_plan_step",
            requiredPermission: "plan.execute",
            riskLevel: .high,
            requiresApproval: true,
            estimatedCostCredits: 15,
            inputSchemaVersion: "plan.step.v1",
            outputSchemaVersion: "plan.result.v1",
            providers: [
                .init(providerId: "provider.primary", priority: 10),
                .init(providerId: "provider.backup", priority: 20)
            ]
        )

        let router = PlanMCPDeterministicRouter(
            registry: PlanMCPCapabilityRegistry(capabilities: [capability])
        )
        return PlanMCPOrchestrationRuntime(router: router, providerExecutor: executor)
    }

    @Test("executes serial+parallel phases with retry timeout policy and idempotency")
    func testRuntimeExecutionFlow() async {
        let executor = StubExecutor()
        let runtime = makeRuntime(executor: executor)

        let request = PlanMCPRuntimeRequest(
            graph: PlanMCPExecutionGraph(
                phases: [
                    .init(
                        id: "phase_1",
                        steps: [.init(id: "discover", capabilityId: "execute_plan_step")]
                    ),
                    .init(
                        id: "phase_2",
                        steps: [
                            .init(id: "fanout_a", capabilityId: "execute_plan_step"),
                            .init(id: "fanout_b", capabilityId: "execute_plan_step", timeoutNanoseconds: 10_000_000)
                        ]
                    )
                ]
            ),
            idempotencyKey: "idem-001",
            grantedPermissions: ["plan.execute"],
            approvalGranted: true,
            maxAllowedRisk: .high,
            providerAvailability: ["provider.primary": true, "provider.backup": true],
            retryPolicy: .init(maxAttempts: 2)
        )

        let first = await runtime.execute(request)
        #expect(first.completed == true)
        #expect(first.phaseResults.count == 2)
        #expect(first.phaseResults[0].stepResults.count == 1)
        #expect(first.phaseResults[1].stepResults.count == 2)

        let fanoutB = first.phaseResults[1].stepResults.first { $0.stepId == "fanout_b" }
        #expect(fanoutB?.status == .success)
        #expect(fanoutB?.attempts == 2)

        let second = await runtime.execute(request)
        #expect(second == first)

        #expect(await executor.attemptCount(for: "discover") == 1)
        #expect(await executor.attemptCount(for: "fanout_a") == 1)
        #expect(await executor.attemptCount(for: "fanout_b") == 2)
    }
}
