import SwiftUI

/// Shows a hint for modules that were skipped during the onboarding walkthrough.
/// Auto-dismisses after first view (via FirstVisitHint's @AppStorage).
struct SkippedModuleHint: View {
    let moduleId: String

    private var wasSkipped: Bool {
        if let data = UserDefaults.standard.data(forKey: "onboarding_skipped_modules"),
           let skipped = try? JSONDecoder().decode(Set<String>.self, from: data) {
            return skipped.contains(moduleId)
        }
        return false
    }

    var body: some View {
        if wasSkipped {
            FirstVisitHint(
                pageId: "\(moduleId)-post-onboarding",
                message: "You skipped this during onboarding. Tap \u{2753} for a full guide."
            )
        }
    }
}
