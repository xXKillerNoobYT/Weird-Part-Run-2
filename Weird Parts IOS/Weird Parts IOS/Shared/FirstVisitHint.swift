import SwiftUI

/// A brief inline hint banner shown the first time a user visits a complex page.
/// Auto-dismisses after 10 seconds or when the user taps the close button.
struct FirstVisitHint: View {
    let pageId: String
    let message: String
    @AppStorage private var hasSeen: Bool

    init(pageId: String, message: String) {
        self.pageId = pageId
        self.message = message
        self._hasSeen = AppStorage(wrappedValue: false, "firstVisit_\(pageId)")
    }

    var body: some View {
        if !hasSeen {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.caption)
                Spacer()
                Button { withAnimation { hasSeen = true } } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .dsMinTapTarget()
                .accessibilityLabel("Dismiss hint")
            }
            .padding(10)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation { hasSeen = true }
                }
            }
        }
    }
}
