import SwiftUI
import Combine
import WiredPartCore

/// Tracks guided onboarding progress per-page, per-user.
/// Stores completion state in UserDefaults keyed by userId.
@MainActor
class OnboardingProgressManager: ObservableObject {
    @Published var completedTasks: Set<String> = []
    @Published var currentModule: String?
    @Published var isOnboardingActive = false

    private let userId: Int64
    private let storageKey: String

    init(userId: Int64) {
        self.userId = userId
        self.storageKey = "onboarding_progress_\(userId)"
        loadProgress()
    }

    func markCompleted(_ taskId: String) {
        guard !completedTasks.contains(taskId) else { return }
        completedTasks.insert(taskId)
        saveProgress()
    }

    func isCompleted(_ taskId: String) -> Bool {
        completedTasks.contains(taskId)
    }

    /// Clears all completed-task progress and persists the cleared state.
    /// Does NOT touch `isOnboardingActive` — tour activation is owned by
    /// `startTour()`/`endTour()`, so restart call sites pair this with
    /// `startTour()`. Keeping activation out of here avoids a redundant
    /// `isOnboardingActive` publish and duplicate UserDefaults write when
    /// the two methods run back-to-back.
    func resetProgress() {
        completedTasks.removeAll()
        saveProgress()
    }

    /// Starts (or restarts) the guided tour and persists the active flag.
    /// Use this instead of setting `isOnboardingActive` directly — direct
    /// assignment is not persisted, so the state would revert on relaunch.
    func startTour() {
        isOnboardingActive = true
        saveProgress()
    }

    /// Ends the guided tour and persists the inactive flag so per-page
    /// tour banners stop rendering after the walkthrough is completed,
    /// skipped, or explicitly dismissed (issue #1067).
    func endTour() {
        isOnboardingActive = false
        saveProgress()
    }

    /// Returns tasks for a page filtered by user's hat permissions.
    func tasksForPage(_ pageId: String, permissions: [String]) -> [OnboardingTask] {
        onboardingTaskRegistry[pageId]?.filter { task in
            guard let permission = task.requiredPermission else { return true }
            return permissions.contains(permission)
        } ?? []
    }

    /// Returns the count of completed vs total for a module.
    func moduleProgress(_ moduleId: String, permissions: [String]) -> (completed: Int, total: Int) {
        let moduleTasks = onboardingTaskRegistry.filter { $0.key.hasPrefix(moduleId) }
        let available = moduleTasks.values.flatMap { $0 }.filter { task in
            guard let permission = task.requiredPermission else { return true }
            return permissions.contains(permission)
        }
        let done = available.filter { completedTasks.contains($0.id) }
        return (done.count, available.count)
    }

    /// Overall progress across all modules.
    func overallProgress(permissions: [String]) -> (completed: Int, total: Int) {
        let available = onboardingTaskRegistry.values.flatMap { $0 }.filter { task in
            guard let permission = task.requiredPermission else { return true }
            return permissions.contains(permission)
        }
        let done = available.filter { completedTasks.contains($0.id) }
        return (done.count, available.count)
    }

    private func loadProgress() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedTasks = saved
        }
        // Also load active state
        isOnboardingActive = UserDefaults.standard.bool(forKey: storageKey + "_active")
    }

    private func saveProgress() {
        if let data = try? JSONEncoder().encode(completedTasks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(isOnboardingActive, forKey: storageKey + "_active")
    }
}

struct OnboardingTask: Identifiable {
    let id: String
    let title: String
    let description: String
    let requiredPermission: String?
    let isRequired: Bool
}
