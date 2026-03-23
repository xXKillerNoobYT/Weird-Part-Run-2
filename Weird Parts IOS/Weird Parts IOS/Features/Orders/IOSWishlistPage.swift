import SwiftUI

/// Placeholder for the Wishlist feature, coming in a future update.
struct IOSWishlistPage: View {
    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "heart.text.clipboard",
            description: Text("Wishlist will be available in a future update.")
        )
        .navigationTitle("Wishlist")
    }
}
