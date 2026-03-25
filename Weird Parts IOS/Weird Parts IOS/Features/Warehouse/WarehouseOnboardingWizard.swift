import SwiftUI
import WiredPartCore

/// 6-step guided warehouse setup wizard.
///
/// Step 1: Define Space — name + measurements + features
/// Step 2: Place Units — add storage units to the floor plan
/// Step 3: Number Everything — sticker checklist
/// Step 4: Walk the Floor — identify parts per area
/// Step 5: Count Everything — enter counts
/// Step 6: Set Targets — MIN/TARGET/MAX per part
struct WarehouseOnboardingWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var progress: WarehouseOnboardingProgress?
    @State private var currentStep = 1
    @State private var floorPlanId: Int64?
    @State private var loadError: String?
    @State private var isQuickCount = false

    // Step 1 state
    @State private var planName = "Main Warehouse"
    @State private var widthFeet = 40
    @State private var lengthFeet = 60

    // Step tracking
    @State private var step4AreasWalked: Set<Int64> = []
    @State private var step5PartsCounted: Set<Int64> = []
    @State private var step6TargetsSet: Set<Int64> = []

    private let totalSteps = 6
    private let stepLabels = [
        "Define Space", "Place Units", "Number Everything",
        "Walk the Floor", "Count Everything", "Set Targets"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar

                // Step content
                TabView(selection: $currentStep) {
                    step1DefineSpace.tag(1)
                    step2PlaceUnits.tag(2)
                    step3NumberEverything.tag(3)
                    step4WalkTheFloor.tag(4)
                    step5CountEverything.tag(5)
                    step6SetTargets.tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                // Navigation buttons
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

    // MARK: - Progress Bar

    @ViewBuilder
    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(currentStep), total: Double(totalSteps))
                .tint(.blue)

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
                Text("Measure your warehouse space — width and length in feet. Don't worry about being exact; you can adjust later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Place Units

    @ViewBuilder
    private var step2PlaceUnits: some View {
        VStack(spacing: 16) {
            if floorPlanId != nil {
                Text("Use the Locations page to add storage units to your floor plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()

                Image(systemName: "cabinet.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue.opacity(0.5))

                Text("Add shelving, racks, gang boxes, and other storage units from the toolbar. Position them on the grid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text("Complete Step 1 first to create a floor plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Step 3: Number Everything

    @ViewBuilder
    private var step3NumberEverything: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Sticker Checklist")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Write location codes on stickers and place them on each shelf, area, and bin. Use the Sticker Checklist from any unit's context menu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 8) {
                stickerExample("R01-U01-G0-A01", label: "Ground Zero, Area 1")
                stickerExample("R01-U01-S02-A04", label: "Shelf 2, Area 4")
                stickerExample("R02-U03-ST-A01", label: "Top, Area 1")
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 30)
    }

    @ViewBuilder
    private func stickerExample(_ code: String, label: String) -> some View {
        HStack {
            Image(systemName: "tag")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(code)
                    .font(.subheadline)
                    .monospaced()
                    .fontWeight(.medium)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 4: Walk the Floor

    @ViewBuilder
    private var step4WalkTheFloor: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Walk the Floor")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Go to each location and identify what parts are there. Scan QR codes, search by name, or add new parts on the spot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if !step4AreasWalked.isEmpty {
                Text("\(step4AreasWalked.count) areas walked so far")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text("Use the Locations page to tap into units, levels, and areas. Assign parts to each location as you go.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()
        }
        .padding(.top, 30)
    }

    // MARK: - Step 5: Count Everything

    @ViewBuilder
    private var step5CountEverything: some View {
        VStack(spacing: 16) {
            Image(systemName: "number.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Count Everything")
                .font(.title3)
                .fontWeight(.semibold)

            Text("For each area you've identified parts in, enter the count. The system counts are hidden — enter what you actually see.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if !step5PartsCounted.isEmpty {
                Text("\(step5PartsCounted.count) parts counted")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(.purple.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text("Use the Audit feature to count stock in each location. The system will compare your counts against expected quantities.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()
        }
        .padding(.top, 30)
    }

    // MARK: - Step 6: Set Targets

    @ViewBuilder
    private var step6SetTargets: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Set Stock Targets")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Set MIN, TARGET, and MAX stock levels for each part. The system will suggest values based on usage history and forecasting data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if !step6TargetsSet.isEmpty {
                Text("\(step6TargetsSet.count) targets configured")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(.red.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text("Navigate to Settings > Stock Targets to configure min/max levels for your inventory items.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()
        }
        .padding(.top, 30)
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
                    withAnimation { currentStep += 1 }
                } label: {
                    Label(currentStep == 1 && floorPlanId == nil ? "Create & Continue" : "Next", systemImage: "chevron.right")
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
            }
        } catch {
            loadError = error.localizedDescription
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
            } catch {
                loadError = error.localizedDescription
            }
            return
        }

        // Save progress for current step
        guard let id = progress?.id else { return }
        do {
            switch currentStep {
            case 1:
                try service.updateOnboardingStep(id: id, currentStep: 2, step1Complete: true)
            case 2:
                try service.updateOnboardingStep(id: id, currentStep: 3, step2Complete: true)
            case 3:
                try service.updateOnboardingStep(id: id, currentStep: 4, step3Complete: true)
            case 4:
                try service.updateOnboardingStep(id: id, currentStep: 5)
            case 5:
                try service.updateOnboardingStep(id: id, currentStep: 6)
            default:
                break
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func saveAndExit() {
        guard let service = appCore.warehouseService, let id = progress?.id else {
            dismiss()
            return
        }
        do {
            try service.updateOnboardingStep(id: id, currentStep: currentStep)
        } catch {
            // Best-effort save
        }
        dismiss()
    }

    private func finishOnboarding() {
        guard let service = appCore.warehouseService, let id = progress?.id else {
            dismiss()
            return
        }
        do {
            try service.completeOnboarding(id: id)
        } catch {
            // Best-effort
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
                    .font(.system(size: 64))
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
        // Navigate to audit or inventory page for quick counting
        dismiss()
        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": "warehouse-audit"]
        )
    }
}
