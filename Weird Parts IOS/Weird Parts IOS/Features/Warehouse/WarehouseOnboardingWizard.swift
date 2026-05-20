import SwiftUI
import WiredPartCore

/// Data about a single area, used across wizard steps 3-9.
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

/// 10-step guided warehouse setup wizard (progressive, resumable).
///
/// Step 1: Define Warehouse Size — name + width × length
/// Step 2: Define Zones — zone types for functional areas
/// Step 3: Define Storage Units — shelves, racks, cabinets
/// Step 4: Place Units — visual drag-and-drop on grid
/// Step 5: Define Shelves — levels within each unit
/// Step 6: Define Areas — sections within each shelf
/// Step 7: Bin Numbers — numbered bins for bin-type areas
/// Step 8: Walking Path — define audit walking order
/// Step 9: Part Assignment — assign catalog parts to bins/areas
/// Step 10: Count Verification — confirm physical counts and targets
struct WarehouseOnboardingWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var progress: WarehouseOnboardingProgress?
    @State private var currentStep = 1
    @State private var floorPlanId: Int64?
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var completedWizardSteps: Set<Int> = []

    // Step 1 state
    @State private var planName = "Main Warehouse"
    @State private var widthFeet = 40
    @State private var lengthFeet = 60

    private let totalSteps = 10
    private let stepLabels = [
        "Phase 1 · Define Size",
        "Phase 1 · Define Zones",
        "Phase 2 · Storage Units",
        "Phase 2 · Place Units",
        "Phase 3 · Shelves",
        "Phase 3 · Areas",
        "Phase 3 · Bin Numbers",
        "Phase 4 · Walking Path",
        "Phase 5 · Assign Parts",
        "Phase 5/6 · Verify Counts & Targets"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                errorBanner

                TabView(selection: $currentStep) {
                    step1DefineSpace.tag(1)

                    if let fpId = floorPlanId {
                        WizardStepZones(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(2)

                        WarehouseWizardStep2(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(3)

                        WizardStepPlacement(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(4)

                        WizardStepShelves(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(5)

                        WizardStepAreas(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(6)

                        WizardStepBins(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(7)

                        walkingPathStep.tag(8)

                        WarehouseWizardStep4(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(9)

                        WarehouseWizardStep5(
                            floorPlanId: fpId,
                            stepError: $loadError
                        ).tag(10)
                    } else {
                        ForEach(2...totalSteps, id: \.self) { step in
                            incompleteStepView.tag(step)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                navigationButtons
            }
            .navigationTitle(stepLabels[currentStep - 1])
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save & Exit") { saveAndExit() }
                        .disabled(isSaving)
                }
            }
            .task { loadProgress() }
        }
    }

    // MARK: - Incomplete Step Placeholder

    @ViewBuilder
    private var incompleteStepView: some View {
        EmptyStateView(
            icon: "1.circle",
            title: "Complete Step 1 First",
            message: "Create a floor plan before setting up storage units."
        )
    }

    @ViewBuilder
    private var walkingPathStep: some View {
        if let floorPlanId {
            WizardStepWalkingPath(
                floorPlanId: floorPlanId,
                stepError: $loadError
            )
        } else {
            incompleteStepView
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = loadError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { loadError = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(1...totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? .blue :
                                  completedWizardSteps.contains(step) ? .green :
                                  .gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                            .onTapGesture {
                                if step <= currentStep || completedWizardSteps.contains(step) {
                                    withAnimation { currentStep = step }
                                }
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
        .scrollDismissesKeyboard(.interactively)
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
                .disabled(isSaving)
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
                .disabled(isSaving)
            } else {
                Button {
                    finishOnboarding()
                } label: {
                    Label("Finish Setup", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSaving)
            }

            // Skip for Now (steps 2-9 only)
            if currentStep > 1 && currentStep < totalSteps {
                Button {
                    completedWizardSteps.insert(currentStep)
                    saveProgressToDb()
                    withAnimation { currentStep += 1 }
                } label: {
                    Text("Skip")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isSaving)
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
                currentStep = min(existing.currentStep, totalSteps)
                floorPlanId = existing.floorPlanId

                // Restore legacy completed steps
                if existing.step1Complete { completedWizardSteps.insert(1) }
                if existing.step2Complete { completedWizardSteps.insert(2) }
                if existing.step3Complete { completedWizardSteps.insert(3) }

                // Restore completed steps from canonical JSON, falling back to
                // the legacy step4_progress payload for in-progress sessions.
                let completedStepsJSON = existing.completedSteps ?? existing.step4Progress
                if let completedStepsJSON,
                   let data = completedStepsJSON.data(using: .utf8),
                   let steps = try? JSONDecoder().decode([Int].self, from: data) {
                    completedWizardSteps.formUnion(steps)
                }
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
                }

                if let id = progress?.id {
                    try service.updateOnboardingStep(
                        id: id,
                        currentStep: 2,
                        step1Complete: true,
                        completedSteps: completedStepsJSON([1]),
                        floorPlanId: plan.id
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
        saveProgressToDb()
        withAnimation { currentStep = min(currentStep + 1, totalSteps) }
    }

    private func saveProgressToDb(currentStepForResume: Int? = nil) {
        guard let service = appCore.warehouseService, let id = progress?.id else { return }
        do {
            let savedStep = currentStepForResume ?? min(currentStep + 1, totalSteps)
            try service.updateOnboardingStep(
                id: id,
                currentStep: savedStep,
                step1Complete: completedWizardSteps.contains(1),
                step2Complete: completedWizardSteps.contains(2),
                step3Complete: completedWizardSteps.contains(3),
                completedSteps: completedStepsJSON(completedWizardSteps)
            )
        } catch {
            loadError = userFriendlyError(error, context: "save progress")
        }
    }

    private func saveAndExit() {
        isSaving = true
        saveProgressToDb(currentStepForResume: currentStep)
        isSaving = false
        // Only dismiss if save succeeded (loadError is set by saveProgressToDb on failure)
        if loadError == nil {
            dismiss()
        }
    }

    private func finishOnboarding() {
        guard let service = appCore.warehouseService, let id = progress?.id else {
            dismiss()
            return
        }
        isSaving = true
        do {
            try service.completeOnboarding(id: id)
        } catch {
            isSaving = false
            loadError = userFriendlyError(error, context: "complete setup")
            return  // Don't dismiss — let user see the error and retry
        }
        isSaving = false
        dismiss()
    }

    private func completedStepsJSON(_ steps: Set<Int>) -> String {
        let boundedSteps = steps.filter { (1...totalSteps).contains($0) }.sorted()
        let data = (try? JSONEncoder().encode(boundedSteps)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
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
                .contentShape(Rectangle())

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
