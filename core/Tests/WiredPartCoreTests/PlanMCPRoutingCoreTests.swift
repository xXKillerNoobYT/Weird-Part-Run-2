import Foundation
import Testing
@testable import WiredPartCore

@Suite("PLAN MCP deterministic routing")
struct PlanMCPRoutingCoreTests {
    private func makeCapability() -> PlanMCPCapabilityDescriptor {
        PlanMCPCapabilityDescriptor(
            id: "execute_plan_step",
            requiredPermission: "plan.execute",
            riskLevel: .high,
            requiresApproval: true,
            estimatedCostCredits: 15,
            inputSchemaVersion: "plan.step.v1",
            outputSchemaVersion: "plan.result.v1",
            providers: [
                .init(providerId: "provider.primary", priority: 10),
                .init(providerId: "provider.backup", priority: 20),
                .init(providerId: "provider.zeta", priority: 20)
            ]
        )
    }

    @Test("denies unknown capability by default")
    func testUnknownCapabilityDenied() {
        let router = PlanMCPDeterministicRouter(registry: .init(capabilities: []))

        let decision = router.route(
            PlanMCPRouteRequest(
                capabilityId: "missing",
                grantedPermissions: ["plan.execute"],
                approvalGranted: true,
                maxAllowedRisk: .critical,
                providerAvailability: [:]
            )
        )

        #expect(decision.gateDecision == .denied(.unknownCapability))
        #expect(decision.selectedProviderId == nil)
    }

    @Test("denies unauthorized capability")
    func testUnauthorizedCapabilityDenied() {
        let router = PlanMCPDeterministicRouter(registry: .init(capabilities: [makeCapability()]))

        let decision = router.route(
            PlanMCPRouteRequest(
                capabilityId: "execute_plan_step",
                grantedPermissions: ["plan.view"],
                approvalGranted: true,
                maxAllowedRisk: .critical,
                providerAvailability: ["provider.primary": true]
            )
        )

        #expect(decision.gateDecision == .denied(.unauthorizedCapability))
        #expect(decision.selectedProviderId == nil)
    }

    @Test("risk gate transition denies until risk ceiling is raised")
    func testRiskGateTransition() {
        let router = PlanMCPDeterministicRouter(registry: .init(capabilities: [makeCapability()]))

        let denied = router.route(
            PlanMCPRouteRequest(
                capabilityId: "execute_plan_step",
                grantedPermissions: ["plan.execute"],
                approvalGranted: true,
                maxAllowedRisk: .medium,
                providerAvailability: ["provider.primary": true]
            )
        )
        #expect(denied.gateDecision == .denied(.riskExceeded))

        let allowed = router.route(
            PlanMCPRouteRequest(
                capabilityId: "execute_plan_step",
                grantedPermissions: ["plan.execute"],
                approvalGranted: true,
                maxAllowedRisk: .high,
                providerAvailability: ["provider.primary": true]
            )
        )
        #expect(allowed.gateDecision == .allowed)
        #expect(allowed.selectedProviderId == "provider.primary")
    }

    @Test("approval gate denies and then allows with explicit approval")
    func testApprovalGateTransition() {
        let router = PlanMCPDeterministicRouter(registry: .init(capabilities: [makeCapability()]))

        let denied = router.route(
            PlanMCPRouteRequest(
                capabilityId: "execute_plan_step",
                grantedPermissions: ["plan.execute"],
                approvalGranted: false,
                maxAllowedRisk: .critical,
                providerAvailability: ["provider.primary": true]
            )
        )
        #expect(denied.gateDecision == .denied(.approvalRequired))

        let allowed = router.route(
            PlanMCPRouteRequest(
                capabilityId: "execute_plan_step",
                grantedPermissions: ["plan.execute"],
                approvalGranted: true,
                maxAllowedRisk: .critical,
                providerAvailability: ["provider.primary": true]
            )
        )
        #expect(allowed.gateDecision == .allowed)
        #expect(allowed.selectedProviderId == "provider.primary")
    }

    @Test("fallback policy chooses next deterministic provider when preferred is unavailable")
    func testFallbackPolicy() {
        let router = PlanMCPDeterministicRouter(registry: .init(capabilities: [makeCapability()]))

        let decision = router.route(
            PlanMCPRouteRequest(
                capabilityId: "execute_plan_step",
                grantedPermissions: ["plan.execute"],
                approvalGranted: true,
                maxAllowedRisk: .critical,
                providerAvailability: [
                    "provider.primary": false,
                    "provider.backup": true,
                    "provider.zeta": true
                ],
                preferredProviderId: "provider.primary"
            )
        )

        #expect(decision.gateDecision == .allowed)
        #expect(decision.selectedProviderId == "provider.backup")
        #expect(decision.fallback.fallbackUsed == true)
        #expect(decision.fallback.fallbackReason == "preferred_provider_unavailable")
        #expect(decision.fallback.attemptedProviders == ["provider.primary", "provider.backup"])
        #expect(decision.fallback.unavailableProviders == ["provider.primary"])
    }

    @Test("denies when no providers are available")
    func testNoProviderAvailable() {
        let router = PlanMCPDeterministicRouter(registry: .init(capabilities: [makeCapability()]))

        let decision = router.route(
            PlanMCPRouteRequest(
                capabilityId: "execute_plan_step",
                grantedPermissions: ["plan.execute"],
                approvalGranted: true,
                maxAllowedRisk: .critical,
                providerAvailability: [
                    "provider.primary": false,
                    "provider.backup": false,
                    "provider.zeta": false
                ]
            )
        )

        #expect(decision.gateDecision == .denied(.noProviderAvailable))
        #expect(decision.selectedProviderId == nil)
        #expect(decision.fallback.attemptedProviders == ["provider.primary", "provider.backup", "provider.zeta"])
    }

    @Test("registry retains capability metadata fields")
    func testCapabilityMetadata() {
        let capability = makeCapability()
        let registry = PlanMCPCapabilityRegistry(capabilities: [capability])
        let loaded = registry.capability(id: "execute_plan_step")

        #expect(loaded?.riskLevel == .high)
        #expect(loaded?.requiresApproval == true)
        #expect(loaded?.estimatedCostCredits == 15)
        #expect(loaded?.inputSchemaVersion == "plan.step.v1")
        #expect(loaded?.outputSchemaVersion == "plan.result.v1")
    }
}
