//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Foundation
import Testing
@testable import Weird_Parts


struct Weird_Parts_IOSTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test func qaResolvedStatusBucketIncludesServiceResolvedStatus() async throws {
        #expect(QAThreadStatusBuckets.isResolved("resolved"))
        #expect(QAThreadStatusBuckets.isResolved("answered"))
        #expect(QAThreadStatusBuckets.isResolved("closed"))
        #expect(!QAThreadStatusBuckets.isResolved("open"))
        #expect(!QAThreadStatusBuckets.isResolved("escalated"))
    }

    @MainActor
    @Test func currentWalkthroughCompletionDoesNotBypassCompanySetupOnRelaunch() throws {
        let defaults = try temporaryDefaults()

        OnboardingCompletionDefaults.markCompleted(
            skippedModules: ["dashboard", "settings"],
            defaults: defaults
        )
        WiredPartIOSApp.migrateLegacyWelcomeFlags(defaults: defaults)

        #expect(defaults.bool(forKey: "hasCompletedOnboarding"))
        #expect(defaults.bool(forKey: "hasSeenModuleTour"))
        #expect(!defaults.bool(forKey: "hasSeenWelcome"))
        #expect(!defaults.bool(forKey: "hasCompletedCompanySetup"))
        #expect(defaults.data(forKey: "onboarding_skipped_modules") != nil)
    }

    @MainActor
    @Test func legacyWelcomeMigrationStillCompletesCompanySetupOnce() throws {
        let defaults = try temporaryDefaults()
        defaults.set(true, forKey: "hasSeenWelcome")

        WiredPartIOSApp.migrateLegacyWelcomeFlags(defaults: defaults)

        #expect(defaults.bool(forKey: "hasCompletedOnboarding"))
        #expect(defaults.bool(forKey: "hasCompletedCompanySetup"))
        #expect(!defaults.bool(forKey: "hasSeenWelcome"))
    }

    private func temporaryDefaults() throws -> UserDefaults {
        let suiteName = "WeirdPartsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestDefaultsError.unavailable
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private enum TestDefaultsError: Error {
        case unavailable
    }
}
