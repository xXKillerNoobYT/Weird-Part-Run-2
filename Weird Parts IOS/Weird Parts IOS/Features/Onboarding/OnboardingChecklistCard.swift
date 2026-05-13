import SwiftUI
import UIKit

struct OnboardingChecklistCard: View {
    let hasCompletedCompanySetup: Bool
    let employeeCount: Int
    let activeJobs: Int
    let supplierCount: Int
    let totalParts: Int
    let warehouseLocationCount: Int
    let onCardShown: () -> Void
    let onDismiss: () -> Void
    let onStepTapped: (String) -> Void
    let onSetUpCompany: () -> Void
    let onCreateFirstJob: () -> Void

    @AppStorage("onboarding_checklist_optional_strip_collapsed")
    private var optionalStripCollapsed = true
    @State private var employeeName = UIDevice.current.name
    @State private var hasLoggedCardShown = false

    private var steps: [OnboardingChecklistStep] {
        [
            OnboardingChecklistStep(
                number: 1,
                title: "Set up your company",
                helper: "Name, time zone, week start.",
                icon: "building.2.fill",
                isRequired: true,
                isComplete: hasCompletedCompanySetup,
                telemetryId: "company-setup",
                action: onSetUpCompany
            ),
            OnboardingChecklistStep(
                number: 2,
                title: "Add yourself",
                helper: "So you can clock in and show up on reports.",
                icon: "person.crop.circle.badge.plus",
                isRequired: true,
                isComplete: employeeCount > 0,
                telemetryId: "add-yourself",
                action: {},
                destinationPath: "/people/employees?addPersonOnAppear=true"
            ),
            OnboardingChecklistStep(
                number: 3,
                title: "Create your first job",
                helper: "Jobs are the home for time, parts, and notes.",
                icon: "briefcase.fill",
                isRequired: true,
                isComplete: activeJobs > 0,
                telemetryId: "create-first-job",
                action: onCreateFirstJob
            ),
            OnboardingChecklistStep(
                number: 4,
                title: "Add a supplier",
                helper: "Optional. Needed before you draft a PO.",
                icon: "shippingbox.fill",
                isRequired: false,
                isComplete: supplierCount > 0,
                telemetryId: "add-supplier",
                action: {},
                destinationPath: "/parts/suppliers?add=1"
            ),
            OnboardingChecklistStep(
                number: 5,
                title: "Bring in parts",
                helper: "Import a CSV or add a few by hand.",
                icon: "wrench.and.screwdriver.fill",
                isRequired: false,
                isComplete: totalParts > 0,
                telemetryId: "bring-in-parts",
                action: {},
                destinationPath: "/parts/catalog?bottomSheet=importOrAdd"
            ),
            OnboardingChecklistStep(
                number: 6,
                title: "Set up your warehouse",
                helper: "One location is enough to start.",
                icon: "square.grid.3x3.fill",
                isRequired: false,
                isComplete: warehouseLocationCount > 0,
                telemetryId: "setup-warehouse",
                action: {},
                destinationPath: "/warehouse/locations?showFloorPlanTutorial=1"
            ),
        ]
    }

    private var requiredCompleted: Int {
        steps.filter { $0.isRequired && $0.isComplete }.count
    }

    private var requiredSteps: [OnboardingChecklistStep] {
        steps.filter(\.isRequired)
    }

    private var recommendedSteps: [OnboardingChecklistStep] {
        steps.filter { !$0.isRequired }
    }

    private var completedCount: Int {
        steps.filter(\.isComplete).count
    }

    private var remainingRequired: Int {
        3 - requiredCompleted
    }

    private var remainingOptional: Int {
        steps.filter { !$0.isRequired && !$0.isComplete }.count
    }

    private var shouldCollapseToStrip: Bool {
        requiredCompleted == 3 && remainingOptional > 0 && optionalStripCollapsed
    }

    private var optionalStepsText: String {
        remainingOptional == 1 ? "1 optional step left" : "\(remainingOptional) optional steps left"
    }

    private var subtitle: String {
        switch remainingRequired {
        case 3: "Three quick steps to get going."
        case 2: "Two more required steps."
        case 1: "One required step left."
        default:
            remainingOptional > 0
                ? "Required setup done. \(remainingOptional) optional steps left."
                : "You're all set up."
        }
    }

    private var progressCaption: String {
        let requiredText = remainingRequired == 1 ? "1 required left" : "\(remainingRequired) required left"
        return "\(completedCount) of 6 complete · \(requiredText)"
    }

    var body: some View {
        Group {
            if shouldCollapseToStrip {
                collapsedStrip
            } else {
                fullCard
            }
        }
        .padding(.horizontal, DS.Space.lg)
    }

    private var collapsedStrip: some View {
        Button {
            withAnimation { optionalStripCollapsed = false }
        } label: {
            HStack(alignment: .center, spacing: DS.Space.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                    Text("Required setup done")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(optionalStepsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Required setup done, \(optionalStepsText)")
    }

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header
            progress

            VStack(spacing: DS.Space.xs) {
                ForEach(requiredSteps) { step in
                    OnboardingChecklistRow(
                        step: step,
                        employeeName: step.number == 2 ? $employeeName : nil,
                        onStepTapped: onStepTapped
                    )
                }

                optionalDivider

                ForEach(recommendedSteps) { step in
                    OnboardingChecklistRow(
                        step: step,
                        employeeName: step.number == 2 ? $employeeName : nil,
                        onStepTapped: onStepTapped
                    )
                }
            }

            if remainingRequired == 0 && remainingOptional > 0 {
                Button {
                    withAnimation { optionalStripCollapsed = true }
                } label: {
                    Label("Show optional setup as a small reminder", systemImage: "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
            }
        }
        .padding(DS.Space.lg)
        .background(cardBackground)
        .onAppear {
            guard !hasLoggedCardShown else { return }
            hasLoggedCardShown = true
            onCardShown()
        }
    }

    private var optionalDivider: some View {
        HStack(spacing: DS.Space.sm) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)

            Text("Optional")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Get set up")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Hide setup checklist")
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ProgressView(value: Double(requiredCompleted), total: 3.0)
                .accessibilityValue("\(completedCount) of 6 complete")
            Text(progressCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
    }
}

private struct OnboardingChecklistStep: Identifiable {
    let number: Int
    let title: String
    let helper: String
    let icon: String
    let isRequired: Bool
    let isComplete: Bool
    let telemetryId: String
    let action: () -> Void
    var destinationPath: String? = nil

    var id: Int { number }
}

private struct OnboardingChecklistRow: View {
    let step: OnboardingChecklistStep
    let employeeName: Binding<String>?
    let onStepTapped: (String) -> Void

    var body: some View {
        Group {
            if let destinationPath = step.destinationPath, !step.isComplete {
                NavigationLink {
                    IOSContentRouter(path: destinationPath)
                } label: {
                    rowContent
                }
                .simultaneousGesture(TapGesture().onEnded {
                    onStepTapped(step.telemetryId)
                })
                .buttonStyle(.plain)
            } else {
                Button {
                    if !step.isComplete {
                        onStepTapped(step.telemetryId)
                        step.action()
                    }
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(step.isComplete)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                statusIcon

                VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                    HStack(spacing: DS.Space.xs) {
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .strikethrough(step.isComplete)
                            .foregroundStyle(step.isComplete ? .secondary : .primary)
                    }

                    Text(step.helper)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DS.Space.sm)

                if !step.isComplete {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            if let employeeName, step.number == 2, !step.isComplete {
                TextField("Device name", text: employeeName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .accessibilityLabel("Suggested employee name")
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, DS.Space.xs)
        .contentShape(Rectangle())
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(step.isComplete ? Color.green : Color.blue.opacity(0.12))
                .frame(width: 36, height: 36)

            if step.isComplete {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            } else {
                Image(systemName: step.icon)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        if step.isComplete {
            return "\(step.title), complete, \(step.helper)"
        }
        return "\(step.title), step \(step.number) of 6, not started, \(step.helper)"
    }
}
