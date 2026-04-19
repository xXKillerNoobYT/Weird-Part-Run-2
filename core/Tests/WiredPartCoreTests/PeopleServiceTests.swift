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

    // MARK: - Team Members & Jobs

    @Test("getTeamMembers returns members after addTeamMember")
    func testGetTeamMembers() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "Crew Alpha")
        try env.people.addTeamMember(teamId: teamId, userId: env.adminUserId)

        let members = try env.people.getTeamMembers(teamId: teamId)
        #expect(members.count == 1)
        #expect(members[0].id == env.adminUserId)
    }

    @Test("getTeamJobs returns empty when no jobs assigned to team")
    func testGetTeamJobsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "Crew Beta")
        let jobs = try env.people.getTeamJobs(teamId: teamId)
        #expect(jobs.isEmpty)
    }

    // MARK: - Contractor Notes

    @Test("getContractorNotes returns empty on fresh contractor")
    func testContractorNotesEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "Note Contractor")

        let notes = try env.people.getContractorNotes(contractorId: contractorId)
        #expect(notes.isEmpty)
    }

    @Test("addContractorNote creates note and is retrievable")
    func testAddContractorNote() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "Note GC")

        let noteId = try env.people.addContractorNote(
            contractorId: contractorId,
            content: "Specializes in high-voltage work",
            createdBy: env.adminUserId
        )
        #expect(noteId > 0)

        let notes = try env.people.getContractorNotes(contractorId: contractorId)
        #expect(notes.count == 1)
        #expect(notes[0].content == "Specializes in high-voltage work")
    }

    // MARK: - Contractor Ratings

    @Test("getContractorRating returns nil when no ratings exist")
    func testContractorRatingNil() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "Unrated GC")

        let rating = try env.people.getContractorRating(contractorId: contractorId)
        #expect(rating == nil)
    }

    @Test("addContractorRating creates rating and getContractorRating returns average")
    func testContractorRating() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "Rated GC")

        _ = try env.people.addContractorRating(
            contractorId: contractorId, quality: 4.0, onTime: 5.0, reliability: 4.5,
            ratedBy: env.adminUserId, jobId: nil
        )

        let rating = try env.people.getContractorRating(contractorId: contractorId)
        #expect(rating != nil)
        #expect(rating!.qualityScore == 4.0)
        #expect(rating!.onTimeScore == 5.0)
        #expect(rating!.reliabilityScore == 4.5)
    }

    @Test("getContractorJobHistory returns empty on fresh contractor")
    func testContractorJobHistoryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "History GC")

        let history = try env.people.getContractorJobHistory(contractorId: contractorId)
        #expect(history.isEmpty)
    }

    // MARK: - Contact Sorting

    @Test("getContactsSorted returns contacts sorted by name")
    func testContactsSorted() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.people.createContact(entityType: "vendor", entityId: 1, firstName: "Zach", lastName: "A", role: "contact", phone: "")
        _ = try env.people.createContact(entityType: "vendor", entityId: 2, firstName: "Aaron", lastName: "B", role: "contact", phone: "")

        let (active, _) = try env.people.getContactsSorted(sortBy: "name", typeFilter: nil)
        #expect(active.count >= 2)
        // Aaron should come before Zach alphabetically
        let names = active.compactMap { $0.firstName }
        if let zIdx = names.firstIndex(of: "Zach"), let aIdx = names.firstIndex(of: "Aaron") {
            #expect(aIdx < zIdx)
        }
    }

    @Test("getContactTypeCounts returns counts by type")
    func testContactTypeCounts() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.people.createContact(entityType: "vendor", entityId: 1, firstName: "V1", lastName: "", role: "contact", phone: "")
        _ = try env.people.createContact(entityType: "vendor", entityId: 2, firstName: "V2", lastName: "", role: "contact", phone: "")
        _ = try env.people.createContact(entityType: "supplier", entityId: 1, firstName: "S1", lastName: "", role: "contact", phone: "")

        let counts = try env.people.getContactTypeCounts()
        #expect((counts["vendor"] ?? 0) >= 2)
        #expect((counts["supplier"] ?? 0) >= 1)
    }

    @Test("getContact returns single contact by ID")
    func testGetContactById() throws {
        let env = try E2ETestHelpers.setUp()
        let id = try env.people.createContact(entityType: "gc", entityId: 1, firstName: "Dana", lastName: "Lee", role: "Project Manager", phone: "555-0100")

        let found = try env.people.getContact(id: id)
        #expect(found != nil)
        #expect(found?.firstName == "Dana")
        #expect(found?.lastName == "Lee")
        #expect(found?.contactType == "gc")

        let missing = try env.people.getContact(id: 99999)
        #expect(missing == nil)
    }

    // MARK: - Payment Tracking

    @Test("isPaymentTrackingEnabled and setPaymentTrackingEnabled round-trip")
    func testPaymentTrackingToggle() throws {
        let env = try E2ETestHelpers.setUp()
        // Default should be some value; toggle it and verify
        let original = try env.people.isPaymentTrackingEnabled()
        try env.people.setPaymentTrackingEnabled(!original)
        let toggled = try env.people.isPaymentTrackingEnabled()
        #expect(toggled == !original)
    }

    @Test("getPaymentSettings returns default values")
    func testPaymentSettingsDefaults() throws {
        let env = try E2ETestHelpers.setUp()
        let (terms, warning, _) = try env.people.getPaymentSettings()
        #expect(terms >= 0)
        #expect(warning >= 0)
    }

    @Test("updatePaymentSettings persists changes")
    func testUpdatePaymentSettings() throws {
        let env = try E2ETestHelpers.setUp()
        try env.people.updatePaymentSettings(termsDays: 45, warningDays: 10, autoHold: true)
        let (terms, warning, hold) = try env.people.getPaymentSettings()
        #expect(terms == 45)
        #expect(warning == 10)
        #expect(hold == true)
    }

    @Test("createPaymentRecord and getPaymentRecords round-trip")
    func testPaymentRecord() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Invoice Corp", companyName: nil, email: nil, phone: nil)

        let recordId = try env.people.createPaymentRecord(
            customerId: customerId, jobId: nil, amount: 1500.0,
            dueDate: "2026-04-30", invoiceNumber: "INV-001", createdBy: env.adminUserId
        )
        #expect(recordId > 0)

        let records = try env.people.getPaymentRecords(customerId: customerId)
        #expect(records.count == 1)
        #expect(records[0].amount == 1500.0)
        #expect(records[0].invoiceNumber == "INV-001")
    }

    @Test("recordPayment updates paid_amount and status to paid")
    func testRecordPayment() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Payment Corp", companyName: nil, email: nil, phone: nil)

        let recordId = try env.people.createPaymentRecord(
            customerId: customerId, jobId: nil, amount: 500.0,
            dueDate: "2026-04-15", invoiceNumber: "INV-002", createdBy: env.adminUserId
        )

        try env.people.recordPayment(recordId: recordId, amount: 500.0, paidDate: "2026-03-31")

        let records = try env.people.getPaymentRecords(customerId: customerId)
        #expect(records[0].status == "paid")
    }

    @Test("getOverdueCustomers returns empty on fresh DB")
    func testOverdueCustomersEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let overdue = try env.people.getOverdueCustomers()
        #expect(overdue.isEmpty)
    }

    @Test("getCustomerPaymentStatus returns zero totals for new customer")
    func testCustomerPaymentStatusEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(
            name: "Status Corp", companyName: nil, email: nil, phone: nil
        )
        let status = try env.people.getCustomerPaymentStatus(customerId: customerId)
        #expect(status.totalInvoiced == 0.0)
        #expect(status.totalPaid == 0.0)
        #expect(status.totalOverdue == 0.0)
        #expect(status.oldestOverdueDays == nil)
    }

    @Test("getCustomerPaymentStatus aggregates invoiced and paid amounts")
    func testCustomerPaymentStatusWithRecords() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(
            name: "Agg Corp", companyName: nil, email: nil, phone: nil
        )

        // Create two invoices
        let r1 = try env.people.createPaymentRecord(
            customerId: customerId, jobId: nil, amount: 1000.0,
            dueDate: "2026-05-01", invoiceNumber: "AGG-001", createdBy: env.adminUserId
        )
        _ = try env.people.createPaymentRecord(
            customerId: customerId, jobId: nil, amount: 500.0,
            dueDate: "2026-06-01", invoiceNumber: "AGG-002", createdBy: env.adminUserId
        )

        // Pay the first one in full
        try env.people.recordPayment(recordId: r1, amount: 1000.0, paidDate: "2026-04-01")

        let status = try env.people.getCustomerPaymentStatus(customerId: customerId)
        #expect(status.totalInvoiced == 1500.0)
        #expect(status.totalPaid == 1000.0)
    }

    // MARK: - Hat Members

    @Test("getHatMembers returns empty for a hat with no assignments")
    func testGetHatMembersEmpty() throws {
        let env = try E2ETestHelpers.setUp()

        let hatId = try env.people.createHat(name: "Foreman", description: nil, level: 1)
        let members = try env.people.getHatMembers(hatId: hatId)
        #expect(members.isEmpty)
    }

    @Test("getHatMembers returns assigned user after toggleHatAssignment")
    func testGetHatMembersAfterAssign() throws {
        let env = try E2ETestHelpers.setUp()

        let hatId = try env.people.createHat(name: "Electrician", description: nil, level: 0)

        // Admin user is active — assign the hat
        try env.people.toggleHatAssignment(
            employeeId: env.adminUserId,
            hatId: hatId,
            assign: true
        )

        let members = try env.people.getHatMembers(hatId: hatId)
        #expect(members.count == 1)
        #expect(members[0].id == env.adminUserId)
    }

    @Test("getHatMembers excludes user after hat is unassigned")
    func testGetHatMembersAfterUnassign() throws {
        let env = try E2ETestHelpers.setUp()

        let hatId = try env.people.createHat(name: "Inspector", description: nil, level: 2)

        // Assign then immediately unassign
        try env.people.toggleHatAssignment(
            employeeId: env.adminUserId,
            hatId: hatId,
            assign: true
        )
        try env.people.toggleHatAssignment(
            employeeId: env.adminUserId,
            hatId: hatId,
            assign: false
        )

        let members = try env.people.getHatMembers(hatId: hatId)
        #expect(members.isEmpty)
    }

    @Test("updateContact changes contact fields")
    func testUpdateContact() throws {
        let env = try E2ETestHelpers.setUp()

        let contactId = try env.people.createContact(
            entityType: "customer",
            entityId: 1,
            firstName: "Jane",
            lastName: "Smith",
            role: "PM",
            phone: "555-0001"
        )

        try env.people.updateContact(
            id: contactId,
            firstName: "Janet",
            lastName: "Jones",
            phone: "555-9999",
            email: "janet@example.com",
            role: "Superintendent"
        )

        let updated = try #require(try env.people.getContact(id: contactId))
        #expect(updated.firstName == "Janet")
        #expect(updated.lastName == "Jones")
        #expect(updated.phone == "555-9999")
    }

    @Test("getWorkersCurrentlyClocked shows Unknown for soft-deleted user")
    func testGetWorkersCurrentlyClockedHidesDeletedUserName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let workers = try env.people.getWorkersCurrentlyClocked()
        #expect(workers.isEmpty == false)
        #expect(workers.first?.name == "Unknown")
    }

    @Test("getExpiringCertifications shows Unknown for soft-deleted user")
    func testGetExpiringCertificationsHidesDeletedUserName() throws {
        let env = try E2ETestHelpers.setUp()
        let expiryDate = "2099-12-31"
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO certifications (user_id, cert_type, cert_name, expiry_date)
                VALUES (?, 'license', 'CDL', ?)
                """, arguments: [env.adminUserId, expiryDate])
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let certs = try env.people.getExpiringCertifications(withinDays: 36500)
        #expect(certs.isEmpty == false)
        #expect(certs.first?.employeeName == "Unknown")
    }
}
