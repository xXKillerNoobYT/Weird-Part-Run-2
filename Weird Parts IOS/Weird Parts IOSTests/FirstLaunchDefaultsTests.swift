import Foundation
import Testing
@testable import Weird_Parts

@Suite("First launch defaults")
struct FirstLaunchDefaultsTests {
    @Test func freshDatabaseResetClearsStaleWelcomeAndChecklistFlags() {
        let suiteName = makeSuiteName()
        let defaults = makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        seedAllFirstLaunchKeys(in: defaults)
        defaults.set("keep", forKey: "preferredTheme")

        FirstLaunchDefaults.clearForFreshDatabase(defaults: defaults)

        #expect(defaults.object(forKey: FirstLaunchDefaults.completedOnboardingKey) == nil)
        #expect(defaults.object(forKey: FirstLaunchDefaults.completedCompanySetupKey) == nil)
        #expect(defaults.object(forKey: FirstLaunchDefaults.legacyWelcomeSeenKey) == nil)
        #expect(defaults.object(forKey: FirstLaunchDefaults.welcomeSheetSeenKey) == nil)
        #expect(defaults.object(forKey: FirstLaunchDefaults.checklistDismissedKey) == nil)
        #expect(defaults.object(forKey: FirstLaunchDefaults.optionalStripCollapsedKey) == nil)
        #expect(defaults.object(forKey: FirstLaunchDefaults.completionStartedKey) == nil)
        #expect(defaults.string(forKey: "preferredTheme") == "keep")
    }

    @Test func uiTestFixtureCanForceWelcomeAndChecklistVisible() {
        let suiteName = makeSuiteName()
        let defaults = makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FirstLaunchDefaults.configureUITestFixture(
            showWelcome: true,
            showChecklist: false,
            defaults: defaults
        )

        #expect(defaults.bool(forKey: FirstLaunchDefaults.completedOnboardingKey))
        #expect(defaults.bool(forKey: FirstLaunchDefaults.completedCompanySetupKey))
        #expect(defaults.bool(forKey: FirstLaunchDefaults.legacyWelcomeSeenKey))
        #expect(defaults.bool(forKey: FirstLaunchDefaults.welcomeSheetSeenKey) == false)
        #expect(defaults.bool(forKey: FirstLaunchDefaults.checklistDismissedKey) == false)
    }

    @Test func uiTestFixtureCanSkipWelcomeAndShowChecklistOnly() {
        let suiteName = makeSuiteName()
        let defaults = makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FirstLaunchDefaults.configureUITestFixture(
            showWelcome: false,
            showChecklist: true,
            defaults: defaults
        )

        #expect(defaults.bool(forKey: FirstLaunchDefaults.welcomeSheetSeenKey))
        #expect(defaults.bool(forKey: FirstLaunchDefaults.checklistDismissedKey) == false)
    }

    @Test func restartChecklistClearsDismissalAndTransientChecklistState() {
        let suiteName = makeSuiteName()
        let defaults = makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        seedAllFirstLaunchKeys(in: defaults)

        FirstLaunchDefaults.restartChecklist(defaults: defaults)

        #expect(defaults.bool(forKey: FirstLaunchDefaults.welcomeSheetSeenKey) == false)
        #expect(defaults.bool(forKey: FirstLaunchDefaults.checklistDismissedKey) == false)
        #expect(defaults.object(forKey: FirstLaunchDefaults.optionalStripCollapsedKey) == nil)
        #expect(defaults.object(forKey: FirstLaunchDefaults.completionStartedKey) == nil)
        #expect(defaults.bool(forKey: FirstLaunchDefaults.completedOnboardingKey))
    }

    private func makeSuiteName() -> String {
        "FirstLaunchDefaultsTests.\(UUID().uuidString)"
    }

    private func makeDefaults(suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func seedAllFirstLaunchKeys(in defaults: UserDefaults) {
        defaults.set(true, forKey: FirstLaunchDefaults.completedOnboardingKey)
        defaults.set(true, forKey: FirstLaunchDefaults.completedCompanySetupKey)
        defaults.set(true, forKey: FirstLaunchDefaults.legacyWelcomeSeenKey)
        defaults.set(true, forKey: FirstLaunchDefaults.moduleTourSeenKey)
        defaults.set(true, forKey: FirstLaunchDefaults.onboardAIEntrySeenKey)
        defaults.set(true, forKey: FirstLaunchDefaults.welcomeSheetSeenKey)
        defaults.set(true, forKey: FirstLaunchDefaults.checklistDismissedKey)
        defaults.set(true, forKey: FirstLaunchDefaults.optionalStripCollapsedKey)
        defaults.set(true, forKey: FirstLaunchDefaults.completionStartedKey)
    }
}
