import Foundation

/// Risk classification for PLAN MCP capabilities.
public enum PlanMCPRiskLevel: Int, Sendable, Codable, Comparable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    public static func < (lhs: PlanMCPRiskLevel, rhs: PlanMCPRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Static capability metadata used by deterministic PLAN MCP routing.
public struct PlanMCPCapabilityDescriptor: Sendable, Codable {
    public let id: String
    public let requiredPermission: String
    public let riskLevel: PlanMCPRiskLevel
    public let requiresApproval: Bool
    public let estimatedCostCredits: Int
    public let inputSchemaVersion: String
    public let outputSchemaVersion: String
    public let providers: [ProviderCandidate]

    public init(
        id: String,
        requiredPermission: String,
        riskLevel: PlanMCPRiskLevel,
        requiresApproval: Bool,
        estimatedCostCredits: Int,
        inputSchemaVersion: String,
        outputSchemaVersion: String,
        providers: [ProviderCandidate]
    ) {
        self.id = id
        self.requiredPermission = requiredPermission
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
        self.estimatedCostCredits = estimatedCostCredits
        self.inputSchemaVersion = inputSchemaVersion
        self.outputSchemaVersion = outputSchemaVersion
        self.providers = providers
    }

    /// Deterministic order used for routing and fallback.
    public var orderedProviders: [ProviderCandidate] {
        providers.sorted {
            if $0.priority == $1.priority {
                return $0.providerId < $1.providerId
            }
            return $0.priority < $1.priority
        }
    }

    public struct ProviderCandidate: Sendable, Codable, Equatable {
        public let providerId: String
        public let priority: Int

        public init(providerId: String, priority: Int) {
            self.providerId = providerId
            self.priority = priority
        }
    }
}

public struct PlanMCPCapabilityRegistry: Sendable {
    private let capabilitiesById: [String: PlanMCPCapabilityDescriptor]

    public init(capabilities: [PlanMCPCapabilityDescriptor]) {
        self.capabilitiesById = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.id, $0) })
    }

    public func capability(id: String) -> PlanMCPCapabilityDescriptor? {
        capabilitiesById[id]
    }
}

public struct PlanMCPRouteRequest: Sendable {
    public let capabilityId: String
    public let grantedPermissions: Set<String>
    public let approvalGranted: Bool
    public let maxAllowedRisk: PlanMCPRiskLevel
    public let providerAvailability: [String: Bool]
    public let preferredProviderId: String?

    public init(
        capabilityId: String,
        grantedPermissions: Set<String>,
        approvalGranted: Bool,
        maxAllowedRisk: PlanMCPRiskLevel,
        providerAvailability: [String: Bool],
        preferredProviderId: String? = nil
    ) {
        self.capabilityId = capabilityId
        self.grantedPermissions = grantedPermissions
        self.approvalGranted = approvalGranted
        self.maxAllowedRisk = maxAllowedRisk
        self.providerAvailability = providerAvailability
        self.preferredProviderId = preferredProviderId
    }
}

public enum PlanMCPGateDecision: Sendable, Equatable {
    case allowed
    case denied(PlanMCPDenyReason)

    public enum PlanMCPDenyReason: String, Sendable {
        case unknownCapability
        case unauthorizedCapability
        case approvalRequired
        case riskExceeded
        case noProviderAvailable
    }
}

public struct PlanMCPFallbackMetadata: Sendable, Equatable {
    public let attemptedProviders: [String]
    public let unavailableProviders: [String]
    public let fallbackUsed: Bool
    public let fallbackReason: String?

    public init(
        attemptedProviders: [String],
        unavailableProviders: [String],
        fallbackUsed: Bool,
        fallbackReason: String?
    ) {
        self.attemptedProviders = attemptedProviders
        self.unavailableProviders = unavailableProviders
        self.fallbackUsed = fallbackUsed
        self.fallbackReason = fallbackReason
    }
}

public struct PlanMCPRoutingDecision: Sendable, Equatable {
    public let gateDecision: PlanMCPGateDecision
    public let selectedProviderId: String?
    public let rationale: String
    public let fallback: PlanMCPFallbackMetadata

    public init(
        gateDecision: PlanMCPGateDecision,
        selectedProviderId: String?,
        rationale: String,
        fallback: PlanMCPFallbackMetadata
    ) {
        self.gateDecision = gateDecision
        self.selectedProviderId = selectedProviderId
        self.rationale = rationale
        self.fallback = fallback
    }
}

/// Deterministic gatekeeper + provider router for PLAN MCP capabilities.
public struct PlanMCPDeterministicRouter: Sendable {
    private let registry: PlanMCPCapabilityRegistry

    public init(registry: PlanMCPCapabilityRegistry) {
        self.registry = registry
    }

    public func route(_ request: PlanMCPRouteRequest) -> PlanMCPRoutingDecision {
        guard let capability = registry.capability(id: request.capabilityId) else {
            return denied(
                .unknownCapability,
                rationale: "Capability '\(request.capabilityId)' is not in registry"
            )
        }

        guard request.grantedPermissions.contains(capability.requiredPermission) else {
            return denied(
                .unauthorizedCapability,
                rationale: "Missing permission '\(capability.requiredPermission)'"
            )
        }

        guard request.maxAllowedRisk >= capability.riskLevel else {
            return denied(
                .riskExceeded,
                rationale: "Capability risk '\(capability.riskLevel)' exceeds current gate '\(request.maxAllowedRisk)'"
            )
        }

        guard !capability.requiresApproval || request.approvalGranted else {
            return denied(
                .approvalRequired,
                rationale: "Capability requires explicit approval"
            )
        }

        return selectProvider(capability: capability, request: request)
    }

    private func denied(_ reason: PlanMCPGateDecision.PlanMCPDenyReason, rationale: String) -> PlanMCPRoutingDecision {
        PlanMCPRoutingDecision(
            gateDecision: .denied(reason),
            selectedProviderId: nil,
            rationale: rationale,
            fallback: PlanMCPFallbackMetadata(
                attemptedProviders: [],
                unavailableProviders: [],
                fallbackUsed: false,
                fallbackReason: nil
            )
        )
    }

    private func selectProvider(
        capability: PlanMCPCapabilityDescriptor,
        request: PlanMCPRouteRequest
    ) -> PlanMCPRoutingDecision {
        let ordered = capability.orderedProviders
        var attempted: [String] = []
        var unavailable: [String] = []

        var preferred: PlanMCPCapabilityDescriptor.ProviderCandidate?
        if let preferredProviderId = request.preferredProviderId {
            preferred = ordered.first { $0.providerId == preferredProviderId }
        }

        var candidates = ordered
        if let preferred {
            candidates.removeAll { $0.providerId == preferred.providerId }
            candidates.insert(preferred, at: 0)
        }

        for candidate in candidates {
            attempted.append(candidate.providerId)
            if request.providerAvailability[candidate.providerId] ?? false {
                let fallbackUsed = request.preferredProviderId != nil && candidate.providerId != request.preferredProviderId
                let fallbackReason = fallbackUsed ? "preferred_provider_unavailable" : nil

                return PlanMCPRoutingDecision(
                    gateDecision: .allowed,
                    selectedProviderId: candidate.providerId,
                    rationale: "Selected provider '\(candidate.providerId)' for capability '\(capability.id)'",
                    fallback: PlanMCPFallbackMetadata(
                        attemptedProviders: attempted,
                        unavailableProviders: unavailable,
                        fallbackUsed: fallbackUsed,
                        fallbackReason: fallbackReason
                    )
                )
            }
            unavailable.append(candidate.providerId)
        }

        return PlanMCPRoutingDecision(
            gateDecision: .denied(.noProviderAvailable),
            selectedProviderId: nil,
            rationale: "No providers are currently available for capability '\(capability.id)'",
            fallback: PlanMCPFallbackMetadata(
                attemptedProviders: attempted,
                unavailableProviders: unavailable,
                fallbackUsed: false,
                fallbackReason: nil
            )
        )
    }
}
