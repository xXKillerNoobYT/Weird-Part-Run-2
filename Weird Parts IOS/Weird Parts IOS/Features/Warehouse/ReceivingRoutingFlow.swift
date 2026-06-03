import SwiftUI
import WiredPartCore

// MARK: - Receiving Routing Flow

/// Step-by-step inline routing flow shown after a user confirms receiving a part.
///
/// Implements the condition-check and smart-routing logic:
/// 1. Condition picker: Good / Used / Damaged
///    - Used -> shelf if below target, write off if not
///    - Damaged -> return to supplier (replacement or refund)
///    - Good -> continue to step 2
/// 2. Wrong part check
/// 3. Job link check (PO -> JPO) -> direct staging if linked
/// 4. Cross-job JPO demand check -> suggest staging
/// 5. Stock level check -> restock / recommend return / force return
///
/// Key rules:
/// - Staging parts do NOT count toward shelf inventory
/// - Parts for a job go to staging directly
/// - Used parts cannot be returned to supplier
/// - Damaged parts cannot go on shelf
enum ReceivingRoutingValidation {
    static let missingLinkedPartRouteError = "This receiving item is no longer linked to an active part. Mark it as a wrong part or fix the PO line before routing damaged or used inventory."

    static func missingLinkedPartError(partId: Int64?) -> String? {
        partId == nil ? missingLinkedPartRouteError : nil
    }
}

struct ReceivingRoutingFlow: View {
    @EnvironmentObject private var appCore: AppCore

    /// The receiving session item being routed.
    let item: WarehouseService.ReceivingItemInfo
    /// The PO line ID for this item (used to check job links).
    let poLineId: Int64
    /// Quantity actually received for this item.
    let receivedQty: Int
    /// Called when routing is complete with the chosen route and any action already taken.
    let onRouteComplete: (WarehouseService.ReceivingRoute) -> Void
    /// Called when the user dismisses/cancels the routing flow.
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentStep: RoutingStep = .conditionCheck
    @State private var selectedCondition: PartCondition?
    @State private var isWrongPart = false
    @State private var isProcessing = false
    @State private var routingError: String?

    // Loaded data
    @State private var jobLink: WarehouseService.POLineJobLink?
    @State private var jpoDemands: [WarehouseService.ActiveJPODemand] = []
    @State private var stockLevels: WarehouseService.PartStockLevels?

    // Damaged sub-choice
    @State private var selectedDamageAction: DamageAction?

    enum RoutingStep: Int, CaseIterable {
        case conditionCheck = 1
        case wrongPartCheck = 2
        case jobLinkCheck = 3
        case jpoDemandCheck = 4
        case stockLevelCheck = 5
        case routeConfirmed = 6
    }

    enum PartCondition: String, CaseIterable {
        case good = "Good"
        case used = "Used"
        case damaged = "Damaged"

        var icon: String {
            switch self {
            case .good: "checkmark.circle.fill"
            case .used: "wrench.and.screwdriver"
            case .damaged: "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .good: .green
            case .used: .orange
            case .damaged: .red
            }
        }
    }

    enum DamageAction: String, CaseIterable {
        case replacement = "Replacement"
        case refund = "Refund"

        var icon: String {
            switch self {
            case .replacement: "arrow.triangle.2.circlepath"
            case .refund: "dollarsign.arrow.circlepath"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            stepProgressBar

            ScrollView {
                VStack(spacing: 16) {
                    // Item header
                    itemHeader

                    // Current step content
                    stepContent

                    // Error display
                    if let error = routingError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .padding()
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .refreshable {
                await refreshCurrentStep()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    // MARK: - Step Progress Bar

    private var stepProgressBar: some View {
        HStack(spacing: 4) {
            ForEach(1...totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var totalSteps: Int {
        // Condition always shown. Further steps depend on condition.
        switch selectedCondition {
        case .damaged: 2  // condition + damage action
        case .used: 2     // condition + used routing
        case .good, .none: 5   // full routing pipeline
        }
    }

    // MARK: - Item Header

    private var itemHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.partName)
                    .font(.headline)
                if let code = item.partCode {
                    Text(code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("Qty: \(receivedQty)")
                    .font(.title3)
                    .fontWeight(.semibold)
                if let condition = selectedCondition {
                    StatusBadge(text: condition.rawValue, color: condition.color)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Step Content Router

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .conditionCheck:
            conditionCheckStep
        case .wrongPartCheck:
            wrongPartCheckStep
        case .jobLinkCheck:
            jobLinkCheckStep
        case .jpoDemandCheck:
            jpoDemandCheckStep
        case .stockLevelCheck:
            stockLevelCheckStep
        case .routeConfirmed:
            routeConfirmedStep
        }
    }

    // MARK: - Step 1: Condition Check

    private var conditionCheckStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                step: 1,
                title: "Condition Check",
                subtitle: "What condition is this part in?"
            )

            ForEach(PartCondition.allCases, id: \.self) { condition in
                conditionButton(condition)
            }

            // Show damage action sub-choices when damaged is selected
            if selectedCondition == .damaged {
                Divider()
                damagedSubChoices
            }

            // Show used routing when used is selected
            if selectedCondition == .used {
                Divider()
                usedRoutingView
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func conditionButton(_ condition: PartCondition) -> some View {
        let isSelected = selectedCondition == condition
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCondition = condition
                routingError = nil
                // Reset sub-choices when condition changes
                selectedDamageAction = nil
            }
            // For Good condition, auto-advance after a brief delay
            if condition == .good {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    await advanceFromCondition()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: condition.icon)
                    .font(.title3)
                    .foregroundStyle(condition.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(condition.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(conditionDescription(condition))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(condition.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? condition.color.opacity(0.1) : Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? condition.color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func conditionDescription(_ condition: PartCondition) -> String {
        switch condition {
        case .good: "Part is new and in perfect condition"
        case .used: "Part has been used but may still be functional"
        case .damaged: "Part is damaged and cannot be used as-is"
        }
    }

    // MARK: - Damaged Sub-choices

    private var damagedSubChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Return to Supplier")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Damaged parts cannot go on shelf. Choose a return action:")
                .font(.caption)
                .foregroundStyle(.tertiary)

            ForEach(DamageAction.allCases, id: \.self) { action in
                damageActionButton(action)
            }

            if selectedDamageAction != nil {
                confirmButton(
                    title: "Confirm Return",
                    icon: "arrow.uturn.backward.circle.fill",
                    color: .red
                ) {
                    await processDamagedReturn()
                }
            }
        }
    }

    private func damageActionButton(_ action: DamageAction) -> some View {
        let isSelected = selectedDamageAction == action
        return Button {
            withAnimation { selectedDamageAction = action }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.body)
                    .frame(width: 28)

                Text(action.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.red.opacity(0.1) : Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.red : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Used Routing View

    private var usedRoutingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Used Part Routing")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Used parts cannot be returned to supplier.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if isProcessing {
                ProgressView("Checking stock levels...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let levels = stockLevels {
                usedPartDecision(levels)
            } else {
                confirmButton(
                    title: "Check Stock Levels",
                    icon: "chart.bar.fill",
                    color: .orange
                ) {
                    await loadStockLevels()
                }
            }
        }
    }

    @ViewBuilder
    private func usedPartDecision(_ levels: WarehouseService.PartStockLevels) -> some View {
        if levels.isBelowTarget {
            // Below target -> shelf it
            routingCard(
                icon: "arrow.down.to.line",
                title: "Put on Shelf",
                subtitle: "Stock is below target (\(levels.currentShelfQty)/\(levels.targetStock)). This used part can help fill the gap.",
                color: .green
            )
            confirmButton(
                title: "Shelf This Part",
                icon: "archivebox.fill",
                color: .green
            ) {
                onRouteComplete(.usedToShelf(levels: levels))
            }
        } else {
            // Not needed -> write off
            routingCard(
                icon: "xmark.bin.fill",
                title: "Write Off",
                subtitle: "Stock is at or above target (\(levels.currentShelfQty)/\(levels.targetStock)). This used part is not needed.",
                color: .orange
            )
            confirmButton(
                title: "Write Off",
                icon: "xmark.bin.fill",
                color: .orange
            ) {
                await processWriteOff()
            }
        }
    }

    // MARK: - Step 2: Wrong Part Check

    private var wrongPartCheckStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                step: 2,
                title: "Part Verification",
                subtitle: "Is this the correct part?"
            )

            HStack(spacing: 12) {
                // Correct part button
                Button {
                    withAnimation {
                        isWrongPart = false
                    }
                    Task { await advanceFromWrongPartCheck() }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Correct Part")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Wrong part button
                Button {
                    withAnimation {
                        isWrongPart = true
                        currentStep = .routeConfirmed
                    }
                    onRouteComplete(.wrongPart)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text("Wrong Part")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if isProcessing {
                ProgressView("Checking job links...")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Step 3: Job Link Check

    private var jobLinkCheckStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                step: 3,
                title: "Job Assignment",
                subtitle: "Checking if this part is ordered for a job..."
            )

            if isProcessing {
                ProgressView("Checking PO-to-JPO links...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let link = jobLink {
                // Linked to a job -> stage directly
                routingCard(
                    icon: "arrow.right.circle.fill",
                    title: "Stage for \(link.jobName)",
                    subtitle: "This part was ordered for a specific job (JPO #\(link.jpoId)). It will go directly to staging — not the shelf.",
                    color: .purple
                )

                confirmButton(
                    title: "Stage for Job",
                    icon: "tray.and.arrow.down.fill",
                    color: .purple
                ) {
                    await stageForJob(link)
                }
            } else {
                // No job link found, auto-advance
                ProgressView("No job link found. Checking other demands...")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .task {
                        await advanceFromJobLinkCheck()
                    }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await checkJobLink()
        }
    }

    // MARK: - Step 4: JPO Demand Check

    private var jpoDemandCheckStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                step: 4,
                title: "Other Job Demands",
                subtitle: "Checking if any active jobs need this part..."
            )

            if isProcessing {
                ProgressView("Searching active JPOs...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if !jpoDemands.isEmpty {
                routingCard(
                    icon: "person.2.fill",
                    title: "\(jpoDemands.count) Job(s) Want This Part",
                    subtitle: "Active job orders are waiting for this part. You can stage it directly.",
                    color: .indigo
                )

                ForEach(jpoDemands, id: \.jpoLineId) { demand in
                    jpoDemandRow(demand)
                }

                // Option to skip and shelve instead
                HStack(spacing: 12) {
                    confirmButton(
                        title: "Skip, Put on Shelf",
                        icon: "archivebox",
                        color: .secondary
                    ) {
                        await advanceToStockLevelCheck()
                    }
                }
            } else {
                ProgressView("No active demands found. Checking stock levels...")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .task {
                        await advanceToStockLevelCheck()
                    }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await checkJPODemand()
        }
    }

    private func jpoDemandRow(_ demand: WarehouseService.ActiveJPODemand) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(demand.jobName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("JPO #\(demand.jpoId) -- Needs \(demand.qtyNeeded)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await stageForJPODemand(demand)
                }
            } label: {
                Label("Stage", systemImage: "tray.and.arrow.down.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.15))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    // MARK: - Step 5: Stock Level Check

    private var stockLevelCheckStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                step: 5,
                title: "Stock Level Routing",
                subtitle: "Determining where this part should go..."
            )

            if isProcessing {
                ProgressView("Loading stock levels...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let levels = stockLevels {
                stockLevelDecision(levels)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await loadStockLevels()
        }
    }

    @ViewBuilder
    private func stockLevelDecision(_ levels: WarehouseService.PartStockLevels) -> some View {
        // Stock bar visualization
        stockLevelBar(levels)

        if levels.isBelowTarget {
            // Below target -> restock
            routingCard(
                icon: "arrow.down.to.line",
                title: "Restock Shelf",
                subtitle: "Stock is below target (\(levels.currentShelfQty)/\(levels.targetStock)). Needs \(levels.qtyToTarget) more to reach target.",
                color: .green
            )
            confirmButton(
                title: "Put on Shelf",
                icon: "archivebox.fill",
                color: .green
            ) {
                onRouteComplete(.restockShelf(levels: levels))
            }
        } else if levels.isAtOrAboveMax {
            // At/above max -> return
            routingCard(
                icon: "arrow.uturn.backward.circle.fill",
                title: "Return to Supplier",
                subtitle: "Stock is at or above maximum (\(levels.currentShelfQty)/\(levels.maxStock)). This part should be returned.",
                color: .red
            )
            confirmButton(
                title: "Return to Supplier",
                icon: "arrow.uturn.backward.circle.fill",
                color: .red
            ) {
                onRouteComplete(.returnOverstock(levels: levels))
            }
        } else {
            // Above target, below max -> recommend return
            routingCard(
                icon: "exclamationmark.circle",
                title: "Recommend Return",
                subtitle: "Stock is above target (\(levels.currentShelfQty)/\(levels.targetStock)) but below max (\(levels.maxStock)). Consider returning.",
                color: .orange
            )
            HStack(spacing: 12) {
                confirmButton(
                    title: "Shelf Anyway",
                    icon: "archivebox",
                    color: .secondary
                ) {
                    onRouteComplete(.restockShelf(levels: levels))
                }

                confirmButton(
                    title: "Return",
                    icon: "arrow.uturn.backward",
                    color: .orange
                ) {
                    onRouteComplete(.recommendReturn(levels: levels))
                }
            }
        }
    }

    private func stockLevelBar(_ levels: WarehouseService.PartStockLevels) -> some View {
        let maxVal = max(levels.maxStock, levels.currentShelfQty + receivedQty, levels.targetStock, 1)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Stock Levels")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))

                    // Current stock
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stockBarColor(levels))
                        .frame(width: max(4, width * CGFloat(levels.currentShelfQty) / CGFloat(maxVal)))

                    // Target marker
                    if levels.targetStock > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 2)
                            .offset(x: width * CGFloat(levels.targetStock) / CGFloat(maxVal))
                    }

                    // Max marker
                    if levels.maxStock > 0 {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2)
                            .offset(x: min(width - 2, width * CGFloat(levels.maxStock) / CGFloat(maxVal)))
                    }
                }
            }
            .frame(height: 12)

            HStack {
                Label("\(levels.currentShelfQty) current", systemImage: "cube.box")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if levels.targetStock > 0 {
                    Text("Target: \(levels.targetStock)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                if levels.maxStock > 0 {
                    Text("Max: \(levels.maxStock)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stockBarColor(_ levels: WarehouseService.PartStockLevels) -> Color {
        if levels.isAtOrAboveMax { return .red }
        if levels.isAboveTargetBelowMax { return .orange }
        return .green
    }

    // MARK: - Step 6: Route Confirmed

    private var routeConfirmedStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .decorativeIconFont(48)
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Routing Complete")
                .font(.headline)

            Text("This item has been routed successfully.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                onDismiss()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared Components

    private func stepHeader(step: Int, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Step \(step)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())

                Text(title)
                    .font(.headline)
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func routingCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    private func confirmButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(isProcessing)
    }

    // MARK: - Flow Logic

    @MainActor
    private func advanceFromCondition() async {
        guard let condition = selectedCondition else { return }
        switch condition {
        case .good:
            // Advance to wrong part check
            withAnimation { currentStep = .wrongPartCheck }
        case .used:
            // Used routing is handled inline in the condition step
            break
        case .damaged:
            // Damaged routing is handled inline in the condition step
            break
        }
    }

    @MainActor
    private func advanceFromWrongPartCheck() async {
        isProcessing = true
        // Move to job link check
        withAnimation { currentStep = .jobLinkCheck }
        isProcessing = false
    }

    @MainActor
    private func checkJobLink() async {
        guard item.partId != nil else {
            // No part ID, skip to stock levels
            await advanceToStockLevelCheck()
            return
        }
        isProcessing = true
        routingError = nil

        do {
            guard let service = appCore.warehouseService else {
                routingError = "Warehouse service unavailable"
                isProcessing = false
                return
            }
            jobLink = try service.getJobLinkForPOLine(poLineId: poLineId)
            isProcessing = false
        } catch {
            routingError = userFriendlyError(error, context: "route receiving")
            isProcessing = false
        }
    }

    @MainActor
    private func advanceFromJobLinkCheck() async {
        // No job link, check for cross-job demands
        withAnimation { currentStep = .jpoDemandCheck }
    }

    @MainActor
    private func checkJPODemand() async {
        guard let partId = item.partId else {
            await advanceToStockLevelCheck()
            return
        }
        isProcessing = true
        routingError = nil

        do {
            guard let service = appCore.warehouseService else {
                routingError = "Warehouse service unavailable"
                isProcessing = false
                return
            }
            let excludeJPOId = jobLink?.jpoId
            jpoDemands = try service.getActiveJPODemandForPart(
                partId: partId,
                excludeJPOId: excludeJPOId
            )
            isProcessing = false

            // If no demands, auto-advance after brief pause
            if jpoDemands.isEmpty {
                // Will auto-advance via .task modifier in the view
            }
        } catch {
            routingError = userFriendlyError(error, context: "route receiving")
            isProcessing = false
        }
    }

    @MainActor
    private func advanceToStockLevelCheck() async {
        withAnimation { currentStep = .stockLevelCheck }
    }

    @MainActor
    private func loadStockLevels() async {
        guard let partId = item.partId else {
            // No part ID, default to shelf
            stockLevels = WarehouseService.PartStockLevels(
                partId: 0, partName: item.partName,
                currentShelfQty: 0, minStock: 0, targetStock: 0, maxStock: 0
            )
            return
        }
        isProcessing = true
        routingError = nil

        do {
            guard let service = appCore.warehouseService else {
                routingError = "Warehouse service unavailable"
                isProcessing = false
                return
            }
            stockLevels = try service.getPartStockLevels(partId: partId)
            isProcessing = false
        } catch {
            routingError = userFriendlyError(error, context: "route receiving")
            isProcessing = false
        }
    }

    @MainActor
    private func refreshCurrentStep() async {
        switch currentStep {
        case .conditionCheck, .wrongPartCheck, .routeConfirmed:
            routingError = nil
        case .jobLinkCheck:
            await checkJobLink()
        case .jpoDemandCheck:
            await checkJPODemand()
        case .stockLevelCheck:
            await loadStockLevels()
        }
    }

    // MARK: - Actions

    @MainActor
    private func stageForJob(_ link: WarehouseService.POLineJobLink) async {
        guard let partId = item.partId else {
            routingError = ReceivingRoutingValidation.missingLinkedPartRouteError
            isProcessing = false
            return
        }
        isProcessing = true
        routingError = nil

        do {
            guard let service = appCore.warehouseService,
                  let userId = appCore.currentUser?.id else {
                routingError = appCore.currentUser == nil ? "Not logged in. Please log in and try again." : "Warehouse service unavailable"
                isProcessing = false
                return
            }
            try service.stageReceivedPartsForJob(
                partId: partId,
                qty: receivedQty,
                jobId: link.jobId,
                performedBy: userId,
                notes: "Received via PO, staged for \(link.jobName)"
            )
            try service.markReceivingSessionItemRouted(
                itemId: item.id,
                disposition: .staged,
                routedQty: receivedQty,
                routedBy: userId
            )
            isProcessing = false
            withAnimation { currentStep = .routeConfirmed }
            onRouteComplete(.stageForJob(jobId: link.jobId, jobName: link.jobName, jpoId: link.jpoId))
        } catch {
            routingError = userFriendlyError(error, context: "route receiving")
            isProcessing = false
        }
    }

    @MainActor
    private func stageForJPODemand(_ demand: WarehouseService.ActiveJPODemand) async {
        guard let partId = item.partId else {
            routingError = ReceivingRoutingValidation.missingLinkedPartRouteError
            isProcessing = false
            return
        }
        isProcessing = true
        routingError = nil

        do {
            guard let service = appCore.warehouseService,
                  let userId = appCore.currentUser?.id else {
                routingError = appCore.currentUser == nil ? "Not logged in. Please log in and try again." : "Warehouse service unavailable"
                isProcessing = false
                return
            }
            let qtyToStage = min(receivedQty, demand.qtyNeeded)
            try service.stageReceivedPartsForJob(
                partId: partId,
                qty: qtyToStage,
                jobId: demand.jobId,
                performedBy: userId,
                notes: "Cross-job staging from receiving for \(demand.jobName)"
            )
            try service.markReceivingSessionItemRouted(
                itemId: item.id,
                disposition: .staged,
                routedQty: qtyToStage,
                routedBy: userId
            )
            isProcessing = false
            withAnimation { currentStep = .routeConfirmed }
            onRouteComplete(.suggestStaging(demands: [demand]))
        } catch {
            routingError = userFriendlyError(error, context: "route receiving")
            isProcessing = false
        }
    }

    @MainActor
    private func processDamagedReturn() async {
        guard let partId = item.partId else {
            routingError = ReceivingRoutingValidation.missingLinkedPartRouteError
            isProcessing = false
            return
        }
        guard let action = selectedDamageAction else { return }
        isProcessing = true
        routingError = nil

        do {
            guard let service = appCore.warehouseService,
                  let userId = appCore.currentUser?.id else {
                routingError = appCore.currentUser == nil ? "Not logged in. Please log in and try again." : "Warehouse service unavailable"
                isProcessing = false
                return
            }
            try service.returnDamagedToSupplier(
                partId: partId,
                qty: receivedQty,
                returnType: action.rawValue.lowercased(),
                performedBy: userId,
                notes: "Damaged on arrival, requesting \(action.rawValue.lowercased())"
            )
            try service.markReceivingSessionItemRouted(
                itemId: item.id,
                disposition: .supplierReturn,
                routedQty: receivedQty,
                routedBy: userId
            )
            isProcessing = false
            withAnimation { currentStep = .routeConfirmed }
            onRouteComplete(.damagedReturn)
        } catch {
            routingError = userFriendlyError(error, context: "route receiving")
            isProcessing = false
        }
    }

    @MainActor
    private func processWriteOff() async {
        guard let partId = item.partId else {
            routingError = ReceivingRoutingValidation.missingLinkedPartRouteError
            isProcessing = false
            return
        }
        isProcessing = true
        routingError = nil

        do {
            guard let service = appCore.warehouseService,
                  let userId = appCore.currentUser?.id else {
                routingError = appCore.currentUser == nil ? "Not logged in. Please log in and try again." : "Warehouse service unavailable"
                isProcessing = false
                return
            }
            try service.writeOffReceivedPart(
                partId: partId,
                qty: receivedQty,
                reason: "Used part, stock at target",
                performedBy: userId,
                notes: "Used part received, not needed for stock"
            )
            try service.markReceivingSessionItemRouted(
                itemId: item.id,
                disposition: .writeOff,
                routedQty: receivedQty,
                routedBy: userId
            )
            isProcessing = false
            withAnimation { currentStep = .routeConfirmed }
            if let levels = stockLevels {
                onRouteComplete(.usedWriteOff(levels: levels))
            }
        } catch {
            routingError = userFriendlyError(error, context: "route receiving")
            isProcessing = false
        }
    }
}
