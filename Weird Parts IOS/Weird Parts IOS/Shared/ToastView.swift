import SwiftUI

struct ToastView: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Spacer(minLength: DS.Space.sm)

                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.label).opacity(0.92))
        )
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.lg)
        .accessibilityElement(children: .combine)
    }
}

struct FirstLaunchOptOutToast: View {
    let onUndo: () -> Void

    var body: some View {
        ToastView(
            message: "Setup hidden. Re-open it in Settings.",
            actionTitle: "Undo",
            action: onUndo
        )
    }
}
