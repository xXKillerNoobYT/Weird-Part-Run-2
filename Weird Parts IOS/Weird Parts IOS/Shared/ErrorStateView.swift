import SwiftUI

/// Reusable error state with retry button.
///
/// Usage:
///   if let error = loadError {
///       ErrorStateView(message: error) {
///           loadData()
///       }
///   }
struct ErrorStateView: View {
    let message: String
    var retryAction: (() -> Void)?

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(DS.SemanticColor.warning)

            Text("Something went wrong")
                .dsStyle(.cardTitle)
                .font(.title3)

            Text(message)
                .dsStyle(.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.xxxl)

            if let retry = retryAction {
                Button(action: retry) {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, DS.Space.xxs)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ErrorStateView(message: "Failed to load parts catalog.") {
        // Preview-only stub
    }
}
