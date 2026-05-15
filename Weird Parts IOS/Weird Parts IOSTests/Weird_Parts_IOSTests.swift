//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Testing
import Foundation
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
    @Test func dailyBriefingNotificationSchedulesOnceWhenAuthorized() async throws {
        let center = FakeOfficeDailyBriefingNotificationCenter(permission: .authorized)
        let scheduler = OfficeDailyBriefingNotificationScheduler(center: center)

        let first = await scheduler.scheduleIfAllowed(userId: 42, hasOfficeAccess: true)
        let second = await scheduler.scheduleIfAllowed(userId: 42, hasOfficeAccess: true)

        #expect(first == .scheduled)
        #expect(second == .alreadyScheduled)
        #expect(await center.addCount == 1)
        #expect(await center.lastHour == 7)
        #expect(await center.lastMinute == 0)
    }

    @MainActor
    @Test func dailyBriefingNotificationSkipsDeniedPermissionAndAccess() async throws {
        let deniedCenter = FakeOfficeDailyBriefingNotificationCenter(permission: .denied)
        let deniedScheduler = OfficeDailyBriefingNotificationScheduler(center: deniedCenter)
        let denied = await deniedScheduler.scheduleIfAllowed(userId: 42, hasOfficeAccess: true)

        let noAccessCenter = FakeOfficeDailyBriefingNotificationCenter(permission: .authorized)
        let noAccessScheduler = OfficeDailyBriefingNotificationScheduler(center: noAccessCenter)
        let noAccess = await noAccessScheduler.scheduleIfAllowed(userId: 42, hasOfficeAccess: false)

        #expect(denied == .permissionDenied)
        #expect(await deniedCenter.addCount == 0)
        #expect(noAccess == .noOfficeAccess)
        #expect(await noAccessCenter.addCount == 0)
    }

    @MainActor
    @Test func officeNavigationUsesOfficeOnlyGateAndFinancialRedactionGate() throws {
        let leadPermissions = ["view_jobs", "manage_jobs", "view_orders"]
        let officePermissions = ["approve_orders", "show_dollar_values", "manage_jobs"]

        let officeModule = try #require(allModulesById["office"])
        #expect(!visibleModules(permissions: leadPermissions).contains(where: { $0.id == "office" }))
        #expect(visibleModules(permissions: officePermissions).contains(where: { $0.id == "office" }))

        let leadOfficeTabs = visibleTabs(for: officeModule, permissions: leadPermissions).map(\.id)
        let officeTabs = visibleTabs(for: officeModule, permissions: officePermissions).map(\.id)
        #expect(!leadOfficeTabs.contains("office-dashboard"))
        #expect(!leadOfficeTabs.contains("office-approvals"))
        #expect(officeTabs.contains("office-dashboard"))
        #expect(officeTabs.contains("office-approvals"))
        #expect(officeTabs.contains("office-spending"))
        #expect(financialValuesPermission == "show_dollar_values")
    }
}

private actor FakeOfficeDailyBriefingNotificationCenter: OfficeDailyBriefingNotificationCenter {
    private let permission: OfficeDailyBriefingNotificationPermission
    private var identifiers: Set<String> = []
    private(set) var addCount = 0
    private(set) var lastHour: Int?
    private(set) var lastMinute: Int?

    init(permission: OfficeDailyBriefingNotificationPermission) {
        self.permission = permission
    }

    func authorizationStatus() async -> OfficeDailyBriefingNotificationPermission {
        permission
    }

    func pendingRequestIdentifiers() async -> Set<String> {
        identifiers
    }

    func addCalendarNotification(
        identifier: String,
        title: String,
        body: String,
        dateComponents: DateComponents,
        repeats: Bool
    ) async throws {
        identifiers.insert(identifier)
        addCount += 1
        lastHour = dateComponents.hour
        lastMinute = dateComponents.minute
    }
}
