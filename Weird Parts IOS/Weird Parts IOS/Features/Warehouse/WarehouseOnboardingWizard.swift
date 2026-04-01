import SwiftUI
import WiredPartCore

/// Data about a single area, used across wizard steps 3-6.
struct WizardAreaInfo: Identifiable {
    let id: Int64
    let areaCode: String
    let fullLocationCode: String
    let unitName: String
    let levelCode: String
}

/// Load all areas for a floor plan with context info (unit name, level code).
func loadAllWizardAreas(floorPlanId: Int64, service: WarehouseService) throws -> [WizardAreaInfo] {
    let units = try service.listStorageUnits(floorPlanId: floorPlanId)
    var areas: [WizardAreaInfo] = []
    for unit in units {
        guard let unitId = unit.id else { continue }
        let levels = try service.listLevelsForUnit(unitId: unitId)
        for level in levels {
            guard let levelId = level.id else { continue }
            let levelAreas = try service.listAreasForLevel(levelId: levelId)
            for area in levelAreas {
                guard let areaId = area.id else { continue }
                areas.append(WizardAreaInfo(
                    id: areaId,
                    areaCode: area.areaCode,
                    fullLocationCode: area.fullLocationCode
                        ?? "\(unit.name)-\(level.levelCode)-\(area.areaCode)",
                    unitName: unit.name,
                    levelCode: level.levelCode
                ))
            }
        }
    }
    return areas
}

// MARK: - Main Wizard

/// 6-step guided warehouse setup wizard.
///
/// Step 1: Define Space — name + measurements
/// Step 2: Place Units — add storage units inline
/// Step 3: Number Everything — interactive sticker checklist
/// Step 4: Walk the Floor — per-area part assignment
/// Step 5: Count Everything — per-area counting (hidden system counts)
/// Step 6: Set Targets — MIN/TARGET/MAX per part
struct WarehouseOnboardingWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var progress: WarehouseOnboardingProgress?
    @State private var currentStep = 1
    @State private var floorPlanId: Int64?
    @State private var loadError: String?
    @State private var completedWizardSteps: Set<Int> = []

    // Step 1 state
    @State private var planName = "Main Warehouse"
    @State private var widthFeet = 40
    @State private var lengthFeet = 60

    private let totalSteps = 6
    private let stepLabels = [
        "Define Space", "Place Units", "Number Everything",
        "Walk the Floor", "Count Everything", "Set Targets"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                errorBanner

                TabView(selection: $currentStep) {
                    step1DefineSpace.tag(1)

                    if let fpId = floorPlanId {
                        WarehouseWizardStep2(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(2)

                        WarehouseWizardStep3(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(3)

                        WarehouseWizardStep4(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(4)

                        WarehouseWizardStep5(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(5)

                        WarehouseWizardStep6(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(6)
                    } else {
                        incompleteStepView.tag(2)
                        incompleteStepView.tag(3)
                        incompleteStepView.tag(4)
                        incompleteStepView.tag(5)
                        incompleteStepView.tag(6)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                navigationButtons
            }
            .navigationTitle(stepLabels[currentStep - 1])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save & Exit") { saveAndExit() }
                }
            }
            .task { loadProgress() }
        }
    }

    // MARK: - Incomplete Step Placeholder

    @ViewBuilder
    private var incompleteStepView: some View {
        ContentUnavailableView {
            Label("Complete Step 1 First", systemImage: "1.circle")
        } description: {
            Text("Create a floor plan before setting up storage units.")
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = loadError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { loadError = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private var progressBar: some View {
        VStack(spacing: 4) {
            // Clickable step dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step + 1 == currentStep ? .blue :
                              completedWizardSteps.contains(step + 1) ? .green :
                              .gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .onTapGesture {
                            if step + 1 <= currentStep || completedWizardSteps.contains(step + 1) {
                                withAnimation { currentStep = step + 1 }
                            }
                        }
                }
            }

            HStack {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stepLabels[currentStep - 1])
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Step 1: Define Space

    @ViewBuilder
    private var step1DefineSpace: some View {
        Form {
            Section("Warehouse Details") {
                TextField("Name", text: $planName)
                Stepper("Width: \(widthFeet) ft", value: $widthFeet, in: 10...500, step: 5)
                Stepper("Length: \(lengthFeet) ft", value: $lengthFeet, in: 10...500, step: 5)
            }

            Section {
                Text("Measure your warehouse — width and length in feet. Don't worry about being exact; you can adjust later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep > 1 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if currentStep < totalSteps {
                Button {
                    completeCurrentStep()
                } label: {
                    Label(
                        currentStep == 1 && floorPlanId == nil
                            ? "Create & Continue" : "Next",
                        systemImage: "chevron.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    finishOnboarding()
                } label: {
                    Label("Finish Setup", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            // Skip for Now (steps 2-5 only)
            if currentStep > 1 && currentStep < totalSteps {
                Button {
                    completedWizardSteps.insert(currentStep)
                    withAnimation { currentStep += 1 }
                } label: {
                    Text("Skip")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Actions

    private func loadProgress() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service unavailable"
            return
        }
        do {
            if let existing = try service.getOnboardingProgress() {
                progress = existing
                currentStep = existing.currentStep
                floorPlanId = existing.floorPlanId

                // Restore completed steps
                if existing.step1Complete { completedWizardSteps.insert(1) }
                if existing.step2Complete { completedWizardSteps.insert(2) }
                if existing.step3Complete { completedWizardSteps.insert(3) }
            }
        } catch {
            loadError = userFriendlyError(error, context: "load warehouse setup")
        }
    }

    private func completeCurrentStep() {
        guard let service = appCore.warehouseService else {
            loadError = "Service not available"
            return
        }

        // Step 1: Create floor plan if needed
        if currentStep == 1 && floorPlanId == nil {
            do {
                let plan = try service.createFloorPlan(
                    name: planName,
                    widthInches: widthFeet * 12,
                    lengthInches: lengthFeet * 12
                )
                floorPlanId = plan.id

                if progress == nil {
                    progress = try service.startOnboarding(floorPlanId: plan.id)
                } else if let id = progress?.id {
                    try service.updateOnboardingStep(
                        id: id, currentStep: 2,
                        step1Complete: true, floorPlanId: plan.id
                    )
                }
                completedWizardSteps.insert(1)
                withAnimation { currentStep = 2 }
            } catch {
                loadError = userFriendlyError(error, context: "create floor plan")
            }
            return
        }

        completedWizardSteps.insert(currentStep)

        // Save progress to the database
        guard let id = progress?.id else {
            withAnimation { currentStep = min(currentStep + 1, totalSteps) }
            return
        }
        do {
            let nextStep = min(currentStep + 1, totalSteps)
            switch currentStep {
            case 1:
                try service.updateOnboardingStep(id: id, currentStep: nextStep, step1Complete: true)
            case 2:
                try service.updateOnboardingStep(id: id, currentStep: nextStep, step2Complete: true)
            case 3:
                try service.updateOnboardingStep(id: id, currentStep: nextStep, step3Complete: true)
            default:
                try service.updateOnboardingStep(id: id, currentStep: nextStep)
            }
        } catch {
            loadError = userFriendlyError(error, context: "save progress")
        }
        withAnimation { currentStep = min(currentStep + 1, totalSteps) }
    }

    private func saveAndExit() {
        if let service = appCore.warehouseService, let id = progress?.id {
            try? service.updateOnboardingStep(id: id, currentStep: currentStep)
        }
        dismiss()
    }

    private func finishOnboarding() {
        if let service = appCore.warehouseService, let id = progress?.id {
            try? service.completeOnboarding(id: id)
        }
        dismiss()
    }
}

// MARK: - Quick Count Entry Point

/// Simplified entry point that skips Steps 1-3 (no floor plan).
struct WarehouseQuickCountWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "number.circle.fill")
                    .decorativeIconFont(64)
                    .foregroundStyle(.purple)

                Text("Quick Count")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Skip the floor plan setup and go straight to counting your inventory. You can set up the floor plan later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    quickCountStep("1", title: "Pick a location", desc: "Start with any shelf or area")
                    quickCountStep("2", title: "Identify parts", desc: "Scan or search for each part")
                    quickCountStep("3", title: "Enter counts", desc: "Count what you see")
                    quickCountStep("4", title: "Set targets", desc: "MIN/TARGET/MAX levels")
                }
                .padding(.horizontal)

                Button {
                    startQuickCount()
                } label: {
                    Label("Start Quick Count", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 30)
            .navigationTitle("Quick Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func quickCountStep(_ number: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.purple)
                .clipShape(Circle())
                .frame(minWidth: 44, minHeight: 44)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func startQuickCount() {
        dismiss()
        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": "warehouse-audit"]
        )
    }
}
