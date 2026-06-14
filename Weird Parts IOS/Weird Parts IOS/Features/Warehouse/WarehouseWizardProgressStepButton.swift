import SwiftUI

/// Shared progress-dot control for warehouse setup wizards.
///
/// Keeps the visual 10 pt dot affordance while exposing a real 44×44 pt
/// tappable button target with clear VoiceOver label/value/hint semantics.
struct WarehouseWizardProgressStepButton: View {
    let step: Int
    let totalSteps: Int
    let title: String
    let isCurrent: Bool
    let isCompleted: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            guard isEnabled else { return }
            onSelect()
        } label: {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Step \(step) of \(totalSteps), \(title)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("warehouseWizardProgressStep\(step)")
    }

    private var dotColor: Color {
        if isCurrent { return .blue }
        if isCompleted { return .green }
        return .gray.opacity(0.3)
    }

    private var accessibilityValue: String {
        if isCurrent { return "Current step" }
        if isCompleted { return "Completed step" }
        if isEnabled { return "Available step" }
        return "Not yet available"
    }

    private var accessibilityHint: String {
        if isCurrent { return "Currently selected." }
        if isEnabled { return "Double-tap to go to this step." }
        return "Complete earlier steps to unlock this step."
    }
}
