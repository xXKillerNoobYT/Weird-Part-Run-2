import Foundation

enum FirstLaunchDefaults {
    nonisolated static let completedOnboardingKey = "hasCompletedOnboarding"
    nonisolated static let completedCompanySetupKey = "hasCompletedCompanySetup"
    nonisolated static let legacyWelcomeSeenKey = "hasSeenWelcome"
    nonisolated static let moduleTourSeenKey = "hasSeenModuleTour"
    nonisolated static let onboardAIEntrySeenKey = "hasSeenOnboardAIMVPEntry"
    nonisolated static let welcomeSheetSeenKey = "firstLaunchSheetSeen"
    nonisolated static let checklistDismissedKey = "onboarding_checklist_dismissed"
    nonisolated static let optionalStripCollapsedKey = "onboarding_checklist_optional_strip_collapsed"
    nonisolated static let completionStartedKey = "onboarding_checklist_completion_started"

    nonisolated private static let resetKeys = [
        completedOnboardingKey,
        completedCompanySetupKey,
        legacyWelcomeSeenKey,
        moduleTourSeenKey,
        onboardAIEntrySeenKey,
        welcomeSheetSeenKey,
        checklistDismissedKey,
        optionalStripCollapsedKey,
        completionStartedKey,
    ]

    nonisolated static func clearForFreshDatabase(defaults: UserDefaults = .standard) {
        resetKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    nonisolated static func configureUITestFixture(
        showWelcome: Bool,
        showChecklist: Bool,
        defaults: UserDefaults = .standard
    ) {
        clearForFreshDatabase(defaults: defaults)
        defaults.set(true, forKey: completedOnboardingKey)
        defaults.set(true, forKey: completedCompanySetupKey)
        defaults.set(true, forKey: legacyWelcomeSeenKey)
        defaults.set(true, forKey: moduleTourSeenKey)
        defaults.set(true, forKey: onboardAIEntrySeenKey)
        defaults.set(!showWelcome, forKey: welcomeSheetSeenKey)
        defaults.set(!showWelcome && !showChecklist, forKey: checklistDismissedKey)
    }

    nonisolated static func restartChecklist(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: welcomeSheetSeenKey)
        defaults.set(false, forKey: checklistDismissedKey)
        defaults.removeObject(forKey: optionalStripCollapsedKey)
        defaults.removeObject(forKey: completionStartedKey)
    }
}
