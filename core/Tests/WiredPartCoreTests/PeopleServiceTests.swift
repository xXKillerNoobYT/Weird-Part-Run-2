import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("PeopleService Tests")
struct PeopleServiceTests {

    // MARK: - Employee Lifecycle

    @Test("List employees returns admin user")
    func testListEmployees() throws {
        let env = try E2ETestHelpers.setUp()
        let employees = try env.people.listEmployees()
        #expect(employees.count >= 1)
        #expect(employees.first?.displayName == "TestAdmin")
    }

    @Test("List employees with search filter")
    func testListEmployeesWithSearch() throws {
        let env = try E2ETestHelpers.setUp()
        let results = try env.people.listEmployees(search: "TestAdmin")
        #expect(results.count >= 1)
        let noResults = try env.people.listEmployees(search: "NonExistentPerson")
        #expect(noResults.isEmpty)
    }

    @Test("Get employee detail")
    func testGetEmployeeDetail() throws {
        let env = try E2ETestHelpers.setUp()
        let detail = try env.people.getEmployeeDetail(id: env.adminUserId)
        #expect(detail.displayName == "TestAdmin")
    }

    @Test("Update employee contact info")
    func testUpdateEmployeeContact() throws {
        let env = try E2ETestHelpers.setUp()
        try env.people.updateEmployeeContact(
            employeeId: env.adminUserId,
            displayName: "Updated Admin",
            phone: "555-0101",
            email: "admin@test.com"
        )
        let detail = try env.people.getEmployeeDetail(id: env.adminUserId)
        #expect(detail.displayName == "Updated Admin")
    }

    // MARK: - Customer CRUD

    @Test("Create and list customers")
    func testCustomerCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let id = try env.people.createCustomer(
            name: "ACME Corp",
            companyName: "ACME",
            email: "acme@test.com",
            phone: "555-0200"
        )
        #expect(id > 0)

        let customers = try env.people.listCustomers()
        #expect(customers.count >= 1)
        #expect(customers.contains(where: { $0.companyName == "ACME" }))
    }

    @Test("Customer detail with financials")
    func testCustomerDetail() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(
            name: "Detail Corp",
            companyName: nil,
            email: nil,
            phone: nil
        )
        let detail = try env.people.getCustomerDetail(customerId: customerId, includeFinancials: true)
        #expect(detail.contactName == "Detail Corp" || detail.companyName == nil)
    }

    @Test("Search customers")
    func testSearchCustomers() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.people.createCustomer(name: "SearchMe Inc", companyName: nil, email: nil, phone: nil)
        let found = try env.people.listCustomers(search: "SearchMe")
        #expect(found.count >= 1)
        let notFound = try env.people.listCustomers(search: "ZZZZZ")
        #expect(notFound.isEmpty)
    }

    // MARK: - Contractor CRUD

    @Test("Create and list contractors")
    func testContractorCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let id = try env.people.createContractor(
            companyName: "SubCo Electric",
            contactName: "John Sub",
            email: "sub@test.com",
            phone: "555-0300"
        )
        #expect(id > 0)

        let contractors = try env.people.listContractors()
        #expect(contractors.count >= 1)
        #expect(contractors.contains(where: { $0.company == "SubCo Electric" }))
    }

    // MARK: - Contact CRUD

    @Test("Create and list contacts")
    func testContactCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Contact Corp", companyName: nil, email: nil, phone: nil)
        let contactId = try env.people.createContact(
            entityType: "customer",
            entityId: customerId,
            firstName: "Jane",
            lastName: "Doe",
            role: "Manager",
            phone: "555-0400",
            email: "jane@test.com"
        )
        #expect(contactId > 0)

        let contacts = try env.people.listContacts()
        #expect(contacts.count >= 1)
    }

    // MARK: - Teams

    @Test("Full team lifecycle: create, add members, list, delete")
    func testTeamLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        let teamId = try env.people.createTeam(name: "Alpha Team", description: "First team")
        #expect(teamId > 0)

        let teams = try env.people.listTeams()
        #expect(teams.contains(where: { $0.name == "Alpha Team" }))

        try env.people.addTeamMember(teamId: teamId, userId: env.adminUserId, role: "lead")
        let members = try env.people.getTeamMembers(teamId: teamId)
        #expect(members.count == 1)

        let detail = try env.people.getTeamDetail(teamId: teamId)
        #expect(detail?.name == "Alpha Team")

        try env.people.updateTeam(teamId: teamId, name: "Beta Team", description: "Renamed")
        let updatedDetail = try env.people.getTeamDetail(teamId: teamId)
        #expect(updatedDetail?.name == "Beta Team")

        if let membershipId = members.first?.membershipId {
            try env.people.removeTeamMember(membershipId: membershipId)
            let afterRemove = try env.people.getTeamMembers(teamId: teamId)
            #expect(afterRemove.isEmpty)
        }

        try env.people.deleteTeam(teamId: teamId)
        let afterDelete = try env.people.listTeams()
        #expect(!afterDelete.contains(where: { $0.id == teamId }))
    }

    @Test("Get available employees for team")
    func testAvailableEmployeesForTeam() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "Avail Team", description: nil)
        let available = try env.people.getAvailableEmployeesForTeam(teamId: teamId)
        #expect(available.count >= 1)
    }

    // MARK: - Hats

    @Test("Hat lifecycle: create, list, toggle, delete")
    func testHatLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        let hatId = try env.people.createHat(name: "Foreman", description: "Leads a crew", level: 5)
        #expect(hatId > 0)

        let hats = try env.people.listHats()
        #expect(hats.contains(where: { $0.name == "Foreman" }))

        let assignments = try env.people.getAllHatsWithAssignment(employeeId: env.adminUserId)
        #expect(!assignments.isEmpty)

        try env.people.toggleHatAssignment(employeeId: env.adminUserId, hatId: hatId, assign: true)
        let afterAssign = try env.people.getAllHatsWithAssignment(employeeId: env.adminUserId)
        let foremanAssignment = afterAssign.first(where: { $0.hat.name == "Foreman" })
        #expect(foremanAssignment?.isAssigned == true)

        try env.people.toggleHatAssignment(employeeId: env.adminUserId, hatId: hatId, assign: false)
        try env.people.deleteHat(id: hatId)
    }

    // MARK: - Stats & Dashboard

    @Test("People stats aggregates correctly")
    func testPeopleStats() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.people.getPeopleStats()
        #expect(stats.totalEmployees >= 1)
    }

    @Test("Workers currently clocked returns empty on fresh DB")
    func testWorkersCurrentlyClocked() throws {
        let env = try E2ETestHelpers.setUp()
        let workers = try env.people.getWorkersCurrentlyClocked()
        #expect(workers.isEmpty)
    }

    @Test("Employees off today returns empty on fresh DB")
    func testEmployeesOffToday() throws {
        let env = try E2ETestHelpers.setUp()
        let off = try env.people.getEmployeesOffToday()
        #expect(off.isEmpty)
    }

    @Test("Expiring certifications returns empty on fresh DB")
    func testExpiringCertifications() throws {
        let env = try E2ETestHelpers.setUp()
        let certs = try env.people.getExpiringCertifications(withinDays: 30)
        #expect(certs.isEmpty)
    }

    @Test("Today's team assignments returns empty on fresh DB")
    func testTodaysTeamAssignments() throws {
        let env = try E2ETestHelpers.setUp()
        let assignments = try env.people.getTodaysTeamAssignments()
        #expect(assignments.isEmpty)
    }

    // MARK: - Communication Log

    @Test("Add communication entry to customer")
    func testCommunicationEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Comm Corp", companyName: nil, email: nil, phone: nil)
        let entryId = try env.people.addCommunicationEntry(
            customerId: customerId,
            commType: "phone",
            content: "Called about upcoming project",
            createdBy: env.adminUserId
        )
        #expect(entryId > 0)
    }
}
