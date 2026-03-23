import SwiftUI

/// Full-screen loading indicator shown while AppCore initializes
/// the database and services.
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Loading WiredPart...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
