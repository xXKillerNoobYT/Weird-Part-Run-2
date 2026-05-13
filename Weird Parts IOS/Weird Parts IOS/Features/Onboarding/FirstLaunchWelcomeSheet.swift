import SwiftUI

struct FirstLaunchWelcomeSheet: View {
    let onStartSetup: () -> Void
    let onExploreOnOwn: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    header
                    bullets
                    actions
                    footer
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, DS.Space.xxl)
                .padding(.vertical, DS.Space.xxxl)
            }
            .background(DS.Background.page)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close welcome")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Welcome to WiredPart")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                Text("A quick setup to get you running.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            welcomeBullet("Tell us about your company")
            welcomeBullet("Add yourself and your first job")
            welcomeBullet("Bring in parts and a supplier when you're ready")
        }
        .font(.body)
    }

    private var actions: some View {
        VStack(spacing: DS.Space.md) {
            Button {
                onStartSetup()
                dismiss()
            } label: {
                Text("Start setup")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .dsButtonStyle(.primary, large: true)

            Button {
                onExploreOnOwn()
                dismiss()
            } label: {
                Text("I'll explore on my own")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .dsButtonStyle(.tertiary)
        }
    }

    private var footer: some View {
        Text("You can re-open this anytime in Settings.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private func welcomeBullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
