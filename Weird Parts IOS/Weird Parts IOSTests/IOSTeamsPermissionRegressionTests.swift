import XCTest

final class IOSTeamsPermissionRegressionTests: XCTestCase {
    func testTeamsPageGatesCreateAffordanceAndPassesActorUserId() throws {
        let source = try Self.readPeopleSource("IOSTeamsPage.swift")
        let toolbarBody = try TestSourceSlicer.braceBalancedBody(after: ".toolbar", in: source)
        let saveBody = try TestSourceSlicer.braceBalancedBody(after: "private func save()", in: source)

        XCTAssertTrue(
            source.contains("private var canManageTeams: Bool {\n        appCore.hasPermission(\"manage_people\")\n    }"),
            "Teams page should derive create permission from appCore.hasPermission(\"manage_people\")."
        )
        XCTAssertTrue(
            toolbarBody.contains("if canManageTeams")
                && toolbarBody.contains("Button { activeSheet = .addTeam }"),
            "The add-team toolbar affordance must be hidden unless the current user can manage people."
        )
        XCTAssertTrue(
            saveBody.contains("let actorUserId = appCore.currentUser?.id")
                && saveBody.contains("try service.createTeam(")
                && saveBody.contains("actorUserId: actorUserId"),
            "AddTeamSheet must pass the logged-in actor to PeopleService.createTeam."
        )
    }

    func testTeamDetailPageGatesActionsAndRemoveAffordance() throws {
        let source = try Self.readPeopleSource("IOSTeamDetailPage.swift")
        let toolbarBody = try TestSourceSlicer.braceBalancedBody(after: ".toolbar", in: source)
        let contentBody = try TestSourceSlicer.braceBalancedBody(after: "private func teamContent", in: source)

        XCTAssertTrue(
            source.contains("private var canManageTeams: Bool {\n        appCore.hasPermission(\"manage_people\")\n    }"),
            "Team detail should derive action permission from appCore.hasPermission(\"manage_people\")."
        )
        XCTAssertTrue(
            toolbarBody.contains("if canManageTeams")
                && toolbarBody.contains("activeSheet = .addMember")
                && toolbarBody.contains("activeSheet = .editTeam")
                && toolbarBody.contains("showDeleteConfirm = true"),
            "Add, edit, and delete actions must be hidden unless the current user can manage people."
        )
        XCTAssertTrue(
            contentBody.contains("if canManageTeams")
                && contentBody.contains("Button(role: .destructive)")
                && contentBody.contains("Label(\"Remove\", systemImage: \"person.badge.minus\")"),
            "The remove-member swipe affordance must be hidden unless the current user can manage people."
        )
    }

    func testTeamDetailPagePassesActorUserIdToMutations() throws {
        let source = try Self.readPeopleSource("IOSTeamDetailPage.swift")
        let removeMemberBody = try TestSourceSlicer.braceBalancedBody(after: "private func removeMember", in: source)
        let deleteTeamBody = try TestSourceSlicer.braceBalancedBody(after: "private func deleteTeam()", in: source)
        let editSaveBody = try TestSourceSlicer.braceBalancedBody(after: "private struct EditTeamSheet", in: source)
        let addEmployeeBody = try TestSourceSlicer.braceBalancedBody(after: "private func addEmployee", in: source)

        XCTAssertTrue(
            removeMemberBody.contains("let actorUserId = appCore.currentUser?.id")
                && removeMemberBody.contains("try service.removeTeamMember(")
                && removeMemberBody.contains("actorUserId: actorUserId"),
            "removeMember must pass the logged-in actor to PeopleService.removeTeamMember."
        )
        XCTAssertTrue(
            deleteTeamBody.contains("let actorUserId = appCore.currentUser?.id")
                && deleteTeamBody.contains("try service.deleteTeam(teamId: teamId, actorUserId: actorUserId)"),
            "deleteTeam must pass the logged-in actor to PeopleService.deleteTeam."
        )
        XCTAssertTrue(
            editSaveBody.contains("let actorUserId = appCore.currentUser?.id")
                && editSaveBody.contains("try service.updateTeam(")
                && editSaveBody.contains("actorUserId: actorUserId"),
            "EditTeamSheet must pass the logged-in actor to PeopleService.updateTeam."
        )
        XCTAssertTrue(
            addEmployeeBody.contains("let actorUserId = appCore.currentUser?.id")
                && addEmployeeBody.contains("try service.addTeamMember(")
                && addEmployeeBody.contains("actorUserId: actorUserId"),
            "AddMemberSheet must pass the logged-in actor to PeopleService.addTeamMember."
        )
    }

    private static func readPeopleSource(_ filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("People")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
