import SwiftUI
import Combine

/// Tracks which onboarding walkthrough pages have been visited and actions completed.
/// Uses UserDefaults keys so progress persists per-device.
class OnboardingProgress: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("onboarding_current_step") var currentStep = 0

    /// Pages visited during onboarding (stored as JSON Set<String>)
    @Published var visitedPages: Set<String> = []
    @Published var completedActions: Set<String> = []

    init() {
        loadState()
    }

    func markPageVisited(_ pageId: String) {
        visitedPages.insert(pageId)
        save()
    }

    func markActionCompleted(_ actionId: String) {
        completedActions.insert(actionId)
        save()
    }

    func isPageVisited(_ pageId: String) -> Bool {
        visitedPages.contains(pageId)
    }

    func isActionCompleted(_ actionId: String) -> Bool {
        completedActions.contains(actionId)
    }

    /// Returns the set of module IDs that were skipped during onboarding
    var skippedModuleIds: Set<String> {
        if let data = UserDefaults.standard.data(forKey: "onboarding_skipped_modules"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            return saved
        }
        return []
    }

    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: "onboarding_visited_pages"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            visitedPages = saved
        }
        if let data = UserDefaults.standard.data(forKey: "onboarding_completed_actions"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedActions = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(visitedPages) {
            UserDefaults.standard.set(data, forKey: "onboarding_visited_pages")
        }
        if let data = try? JSONEncoder().encode(completedActions) {
            UserDefaults.standard.set(data, forKey: "onboarding_completed_actions")
        }
    }
}
