import SwiftUI

/// Placeholder view for Office module pages that are planned for future development.
///
/// Shows a clean "coming soon" message with the page name.
/// Used for features like QR Management, which will be built out over time.
struct OfficePlaceholderView: View {
    let pageName: String

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()

            VStack(spacing: DS.Space.md) {
                Image(systemName: "building.2")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)

                Text("Office — \(pageName)")
                    .dsStyle(.sectionTitle)

                VStack(spacing: DS.Space.sm) {
                    Text("Planned for future development")
                        .dsStyle(.label)
                        .foregroundStyle(.secondary)

                    Text("This feature is coming in a future update.")
                        .dsStyle(.detail)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, DS.Space.xl)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 400)
            .dsCard()

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(DS.Background.page)
    }
}
