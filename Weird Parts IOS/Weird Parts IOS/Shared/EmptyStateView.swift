import SwiftUI

/// Reusable empty state placeholder for lists and grids.
///
/// Usage:
///   if items.isEmpty {
///       EmptyStateView(
///           icon: "wrench.and.screwdriver",
///           title: "No Parts Yet",
///           message: "Add your first part to get started.",
///           actionLabel: "Add Part"
///       ) {
///           showAddSheet = true
///       }
///   }
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var actionIcon: String?
    var actionAccessibilityIdentifier: String?
    var secondaryActionLabel: String?
    var secondaryActionIcon: String?
    var secondaryActionAccessibilityIdentifier: String?
    var secondaryAction: (() -> Void)?
    var helpLabel: String?
    var helpAction: (() -> Void)?
    var action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionLabel: String? = nil,
        actionIcon: String? = nil,
        actionAccessibilityIdentifier: String? = nil,
        secondaryActionLabel: String? = nil,
        secondaryActionIcon: String? = nil,
        secondaryActionAccessibilityIdentifier: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        helpLabel: String? = nil,
        helpAction: (() -> Void)? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.actionIcon = actionIcon
        self.actionAccessibilityIdentifier = actionAccessibilityIdentifier
        self.secondaryActionLabel = secondaryActionLabel
        self.secondaryActionIcon = secondaryActionIcon
        self.secondaryActionAccessibilityIdentifier = secondaryActionAccessibilityIdentifier
        self.secondaryAction = secondaryAction
        self.helpLabel = helpLabel
        self.helpAction = helpAction
        self.action = action
    }

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    private var hasPrimaryAction: Bool {
        actionLabel != nil && action != nil
    }

    private var hasSecondaryAction: Bool {
        secondaryActionLabel != nil && secondaryAction != nil
    }

    private var hasHelpAction: Bool {
        helpLabel != nil && helpAction != nil
    }

    private var hasPrimaryOrSecondaryAction: Bool {
        hasPrimaryAction || hasSecondaryAction
    }

    private var hasAnyAction: Bool {
        hasPrimaryOrSecondaryAction || hasHelpAction
    }

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)

            Text(title)
                .dsStyle(.cardTitle)
                .font(.title3)

            Text(message)
                .dsStyle(.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.xxxl)

            if hasAnyAction {
                VStack(spacing: 0) {
                    if hasPrimaryOrSecondaryAction {
                        HStack(spacing: DS.Space.md) {
                            if let label = actionLabel, let action = action {
                                Button(action: action) {
                                    if let icon = actionIcon {
                                        Label(label, systemImage: icon)
                                            .fontWeight(.medium)
                                            .frame(minHeight: 44)
                                    } else {
                                        Text(label)
                                            .fontWeight(.medium)
                                            .frame(minHeight: 44)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifierIfPresent(actionAccessibilityIdentifier)
                            }

                            if let label = secondaryActionLabel, let action = secondaryAction {
                                Button(action: action) {
                                    if let icon = secondaryActionIcon {
                                        Label(label, systemImage: icon)
                                            .fontWeight(.medium)
                                            .frame(minHeight: 44)
                                    } else {
                                        Text(label)
                                            .fontWeight(.medium)
                                            .frame(minHeight: 44)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifierIfPresent(secondaryActionAccessibilityIdentifier)
                            }
                        }
                    }

                    if let label = helpLabel, let action = helpAction {
                        Button(action: action) {
                            Label(label, systemImage: "questionmark.circle")
                                .fontWeight(.medium)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("emptyStateHelpButton")
                        .padding(.top, hasPrimaryOrSecondaryAction ? DS.Space.xs : 0)
                    }
                }
                .padding(.top, DS.Space.xxs)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifierIfPresent(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

#Preview {
    EmptyStateView(
        icon: "tray",
        title: "No Items",
        message: "There's nothing here yet. Add something to get started.",
        actionLabel: "Add Item"
    ) {
        // Preview-only stub
    }
}
