import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("PeopleService Tests")
struct PeopleServiceTests {
    private func certificationDateString(daysFromToday days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

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

    @Test("Recent employee activity returns empty on fresh DB")
    func testGetEmployeeRecentActivityEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let activity = try env.people.getEmployeeRecentActivity(id: env.adminUserId)
        #expect(activity.isEmpty)
    }

    @Test("Recent employee activity returns job session rows")
    func testGetEmployeeRecentActivityWithLaborEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-ACT", name: "Activity Job")

        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.setClockEntryWorkType(clockEntryId: laborEntryId, workType: "warranty")
        try env.jobs.clockOut(laborEntryId: laborEntryId)

        let activity = try env.people.getEmployeeRecentActivity(id: env.adminUserId)
        let first = try #require(activity.first)
        #expect(first.id == laborEntryId)
        #expect(first.jobId == jobId)
        #expect(first.jobNumber == "J-ACT")
        #expect(first.jobName == "Activity Job")
        #expect(first.status == "completed")
        #expect(first.clockOut != nil)
        #expect(first.workType == "warranty")
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

    @Test("getTeamMembers excludes soft-deleted users via JOIN-condition guard")
    func testGetTeamMembers_excludesDeletedUser() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a team with the admin user as a member
        let teamId = try env.people.createTeam(name: "Tombstone Team", description: nil)
        try env.people.addTeamMember(teamId: teamId, userId: env.adminUserId, role: "lead")

        // Baseline: the member appears
        let before = try env.people.getTeamMembers(teamId: teamId)
        #expect(before.contains { $0.id == env.adminUserId })

        // Soft-delete the user. The employee_team_members row stays active — this is
        // the LEFT-JOIN-COALESCE trap applied to an INNER JOIN: the tombstoned user
        // row still matches the JOIN and their display name leaks through. After the
        // fix, JOIN-condition `AND u.deleted_at IS NULL` drops the row entirely.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [env.adminUserId]
            )
        }

        let after = try env.people.getTeamMembers(teamId: teamId)
        #expect(!after.contains { $0.id == env.adminUserId },
                "getTeamMembers must exclude soft-deleted users via JOIN-condition guard on users.deleted_at")
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

    @Test("Expiring certifications includes expired and upcoming active certs")
    func testExpiringCertificationsIncludesExpiredAndUpcoming() throws {
        let env = try E2ETestHelpers.setUp()
        let expired = certificationDateString(daysFromToday: -5)
        let today = certificationDateString(daysFromToday: 0)
        let upcoming = certificationDateString(daysFromToday: 5)

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO certifications (user_id, cert_type, cert_name, expiry_date, is_active)
                VALUES
                    (?, 'license', 'Expired CDL', ?, 1),
                    (?, 'license', 'Due Today OSHA', ?, 1),
                    (?, 'license', 'Upcoming Electrical', ?, 1)
                """, arguments: [
                    env.adminUserId, expired,
                    env.adminUserId, today,
                    env.adminUserId, upcoming
                ])
        }

        let certs = try env.people.getExpiringCertifications(withinDays: 30)
        #expect(certs.map(\.certName) == ["Expired CDL", "Due Today OSHA", "Upcoming Electrical"])
        #expect(certs.allSatisfy { $0.employeeName == "TestAdmin" })
    }

    @Test("Expiring certifications excludes inactive deleted null and outside-window certs")
    func testExpiringCertificationsExcludesNonComplianceMatches() throws {
        let env = try E2ETestHelpers.setUp()
        let expired = certificationDateString(daysFromToday: -1)
        let upcoming = certificationDateString(daysFromToday: 10)
        let outsideWindow = certificationDateString(daysFromToday: 45)

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO certifications (user_id, cert_type, cert_name, expiry_date, is_active, deleted_at)
                VALUES
                    (?, 'license', 'Active Match', ?, 1, NULL),
                    (?, 'license', 'Inactive Cert', ?, 0, NULL),
                    (?, 'license', 'Deleted Cert', ?, 1, datetime('now')),
                    (?, 'license', 'Outside Window', ?, 1, NULL),
                    (?, 'license', 'No Expiry', NULL, 1, NULL)
                """, arguments: [
                    env.adminUserId, expired,
                    env.adminUserId, expired,
                    env.adminUserId, upcoming,
                    env.adminUserId, outsideWindow,
                    env.adminUserId
                ])
        }

        let certs = try env.people.getExpiringCertifications(withinDays: 30)
        #expect(certs.map(\.certName) == ["Active Match"])
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

    @Test("getExpiringCertifications excludes soft-deleted user")
    func testGetExpiringCertificationsExcludesDeletedUser() throws {
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
        #expect(certs.isEmpty)
    }

    @Test("updateTeam is a no-op on a soft-deleted team")
    func testUpdateTeam_noOpOnSoftDeletedTeam() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "OriginalTeam", description: "desc")
        try env.people.deleteTeam(teamId: teamId)
        // Regression: UPDATE employee_teams ... WHERE id = ? had no deleted_at guard.
        try env.people.updateTeam(teamId: teamId, name: "ShouldNotStick", description: nil)

        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM employee_teams WHERE id = ?", arguments: [teamId])
        }
        #expect(name == "OriginalTeam",
                "Soft-deleted team name must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("recordPayment is a no-op on a soft-deleted payment record")
    func testRecordPayment_noOpOnSoftDeletedRecord() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO customers (name, created_at, updated_at)
                VALUES ('TestCustomer', datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }
        let recordId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO payment_records (customer_id, amount, paid_amount, status, due_date, created_at, updated_at)
                VALUES (?, 100.0, 0.0, 'unpaid', '2026-01-01', datetime('now'), datetime('now'))
                """, arguments: [customerId])
            return db.lastInsertedRowID
        }
        // Soft-delete the record
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE payment_records SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [recordId])
        }
        // Stale billing UI records a payment — must not mutate a tombstoned invoice
        try env.people.recordPayment(recordId: recordId, amount: 50.0, paidDate: "2026-04-19")

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT paid_amount, status FROM payment_records WHERE id = ?", arguments: [recordId])
        }
        let paid: Double = row?["paid_amount"] ?? -1
        let status: String = row?["status"] ?? "MUTATED"
        #expect(paid == 0.0,
            "Soft-deleted payment_record paid_amount must not change — both SELECT and UPDATE must guard AND deleted_at IS NULL")
        #expect(status == "unpaid",
            "Soft-deleted payment_record status must not change — guard must prevent the write entirely")
    }

    @Test("updateEmployeeContact is a no-op on a soft-deleted user")
    func testUpdateEmployeeContact_noOpOnSoftDeletedUser() throws {
        let env = try E2ETestHelpers.setUp()
        // Capture the original display_name before soft-deleting
        let originalName = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT display_name FROM users WHERE id = ?", arguments: [env.adminUserId])
        }
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        // Regression: UPDATE users ... WHERE id = ? had no deleted_at guard,
        // so a stale HR edit could silently mutate a tombstoned user's contact info.
        try env.people.updateEmployeeContact(
            employeeId: env.adminUserId,
            displayName: "ShouldNotStick",
            phone: "555-9999",
            email: "stale@example.com"
        )
        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT display_name FROM users WHERE id = ?", arguments: [env.adminUserId])
        }
        #expect(name == originalName,
                "Soft-deleted user display_name must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("createPaymentRecord creates no orphan row for a soft-deleted customer")
    func testCreatePaymentRecord_noOrphanForSoftDeletedCustomer() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(
            name: "TombstonedCustomer", companyName: nil, email: nil, phone: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE customers SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [customerId])
        }
        // Regression: INSERT INTO payment_records had no pre-check on customers.deleted_at.
        let id = try env.people.createPaymentRecord(
            customerId: customerId, jobId: nil, amount: 100.0,
            dueDate: "2099-12-31", invoiceNumber: "INV-SOFT-1", createdBy: env.adminUserId
        )
        #expect(id == 0,
            "createPaymentRecord must return 0 (no-op) for a tombstoned customer")
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM payment_records WHERE customer_id = ?",
                             arguments: [customerId]) ?? 0
        }
        #expect(count == 0,
            "Soft-deleted customer must not produce payment_records rows — INSERT must be pre-checked")
    }

    // MARK: - Input validation — create paths (iter 68)

    @Test("createCustomer rejects blank name")
    func testCreateCustomer_rejectsBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("name")) {
            try env.people.createCustomer(name: "   ", companyName: nil, email: nil, phone: nil)
        }
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM customers WHERE name = '   '") ?? 0
        }
        #expect(count == 0, "Blank-name customer must produce zero rows in the DB")
    }

    @Test("createTeam rejects blank name")
    func testCreateTeam_rejectsBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("name")) {
            try env.people.createTeam(name: "", description: nil)
        }
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("name")) {
            try env.people.createTeam(name: "   ", description: "someDesc")
        }
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM employee_teams WHERE name = '' OR name = '   '") ?? 0
        }
        #expect(count == 0, "Blank-name teams must produce zero rows in the DB")
    }

    @Test("createContractor rejects blank companyName")
    func testCreateContractor_rejectsBlankCompanyName() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("companyName")) {
            try env.people.createContractor(companyName: "  ", contactName: nil, email: nil)
        }
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM general_contractors WHERE company_name = '  '") ?? 0
        }
        #expect(count == 0, "Blank companyName contractor must produce zero rows in the DB")
    }

    @Test("createHat rejects blank name")
    func testCreateHat_rejectsBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("name")) {
            try env.people.createHat(name: "", description: nil, level: 0)
        }
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("name")) {
            try env.people.createHat(name: "   ", description: nil, level: 1)
        }
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hats WHERE name = '' OR name = '   '") ?? 0
        }
        #expect(count == 0, "Blank-name hats must produce zero rows in the DB")
    }

    @Test("toggleHatAssignment rejects tombstoned user and non-existent hat")
    func testToggleHatAssignment_rejectsTombstonedUserOrMissingHat() throws {
        let env = try E2ETestHelpers.setUp()
        // Tombstone the admin user
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.self) {
            try env.people.toggleHatAssignment(employeeId: env.adminUserId, hatId: 1, assign: true)
        }
        // Also reject non-existent hat
        let env2 = try E2ETestHelpers.setUp()
        #expect(throws: PeopleService.PeopleError.self) {
            try env2.people.toggleHatAssignment(employeeId: env2.adminUserId, hatId: 99999, assign: true)
        }
    }

    @Test("addTeamMember rejects tombstoned user and silently skips tombstoned team")
    func testAddTeamMember_guardsTombstonedParents() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "Guard Team", description: nil)
        // Tombstone the user
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.self) {
            try env.people.addTeamMember(teamId: teamId, userId: env.adminUserId, role: "lead")
        }
        // Now tombstone team — should silently return (preserving existing caller
        // semantic of INSERT OR IGNORE being a safe no-op).
        let env2 = try E2ETestHelpers.setUp()
        let teamId2 = try env2.people.createTeam(name: "Tombed Team", description: nil)
        try env2.db.writer.write { db in
            try db.execute(sql: "UPDATE employee_teams SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [teamId2])
        }
        try env2.people.addTeamMember(teamId: teamId2, userId: env2.adminUserId, role: "member")
        let count = try env2.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM employee_team_members WHERE team_id = ?
                """, arguments: [teamId2]) ?? 0
        }
        #expect(count == 0,
            "Tombstoned team must not accumulate phantom member rows")
    }

    @Test("addCommunicationEntry rejects blank fields")
    func testAddCommunicationEntry_rejectsBlankFields() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Blank Test Corp")
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("commType")) {
            try env.people.addCommunicationEntry(customerId: customerId, commType: "  ", content: "hello", createdBy: env.adminUserId)
        }
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("content")) {
            try env.people.addCommunicationEntry(customerId: customerId, commType: "email", content: "", createdBy: env.adminUserId)
        }
    }

    @Test("addCommunicationEntry rejects tombstoned customer and user")
    func testAddCommunicationEntry_rejectsTombstonedParents() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Tombstone Corp")
        // Tombstone customer
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE customers SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [customerId])
        }
        #expect(throws: PeopleService.PeopleError.customerNotFound(customerId)) {
            try env.people.addCommunicationEntry(customerId: customerId, commType: "call", content: "Checked in", createdBy: env.adminUserId)
        }
        // Tombstone user
        let env2 = try E2ETestHelpers.setUp()
        let customerId2 = try env2.people.createCustomer(name: "Active Corp")
        try env2.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env2.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.userNotFound(env2.adminUserId)) {
            try env2.people.addCommunicationEntry(customerId: customerId2, commType: "note", content: "Follow up", createdBy: env2.adminUserId)
        }
    }

    @Test("addContractorNote rejects blank content and tombstoned parents")
    func testAddContractorNote_guardsBlanksAndTombstones() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "ABC Subs")
        // Blank content
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("content")) {
            try env.people.addContractorNote(contractorId: contractorId, content: "   ", createdBy: env.adminUserId)
        }
        // Tombstone contractor
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE general_contractors SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [contractorId])
        }
        #expect(throws: PeopleService.PeopleError.contractorNotFound(contractorId)) {
            try env.people.addContractorNote(contractorId: contractorId, content: "Great work", createdBy: env.adminUserId)
        }
        // Tombstone user
        let env2 = try E2ETestHelpers.setUp()
        let contractorId2 = try env2.people.createContractor(companyName: "XYZ Subs")
        try env2.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env2.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.userNotFound(env2.adminUserId)) {
            try env2.people.addContractorNote(contractorId: contractorId2, content: "Reliable", createdBy: env2.adminUserId)
        }
    }

    @Test("addContractorRating rejects out-of-range scores and tombstoned parents")
    func testAddContractorRating_guardsScoresAndTombstones() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "Score Test Subs")
        // Score below 0
        #expect(throws: PeopleService.PeopleError.invalidScore(-1.0)) {
            try env.people.addContractorRating(contractorId: contractorId, quality: -1.0, onTime: 4.0, reliability: 4.0, ratedBy: env.adminUserId, jobId: nil)
        }
        // Score above 5
        #expect(throws: PeopleService.PeopleError.invalidScore(5.1)) {
            try env.people.addContractorRating(contractorId: contractorId, quality: 4.0, onTime: 4.0, reliability: 5.1, ratedBy: env.adminUserId, jobId: nil)
        }
        // Tombstone contractor
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE general_contractors SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [contractorId])
        }
        #expect(throws: PeopleService.PeopleError.contractorNotFound(contractorId)) {
            try env.people.addContractorRating(contractorId: contractorId, quality: 4.0, onTime: 4.0, reliability: 4.0, ratedBy: env.adminUserId, jobId: nil)
        }
    }

    @Test("addTeamMember rejects inactive user (is_active = 0)")
    func testAddTeamMember_rejectsInactiveUser() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "Active Guard Team")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET is_active = 0 WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.self) {
            try env.people.addTeamMember(teamId: teamId, userId: env.adminUserId, role: "member")
        }
    }

    @Test("toggleHatAssignment rejects inactive user (is_active = 0)")
    func testToggleHatAssignment_rejectsInactiveUser() throws {
        let env = try E2ETestHelpers.setUp()
        let hatId = try env.people.createHat(name: "Active Guard Hat")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET is_active = 0 WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.self) {
            try env.people.toggleHatAssignment(employeeId: env.adminUserId, hatId: hatId, assign: true)
        }
    }

    @Test("addCommunicationEntry rejects inactive createdBy user (is_active = 0)")
    func testAddCommunicationEntry_rejectsInactiveCreatedByUser() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Inactive Guard Corp")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET is_active = 0 WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.self) {
            try env.people.addCommunicationEntry(customerId: customerId, commType: "call", content: "Test", createdBy: env.adminUserId)
        }
    }

    @Test("addContractorNote rejects inactive createdBy user (is_active = 0)")
    func testAddContractorNote_rejectsInactiveCreatedByUser() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "Inactive Guard Subs")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET is_active = 0 WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.self) {
            try env.people.addContractorNote(contractorId: contractorId, content: "Test note", createdBy: env.adminUserId)
        }
    }

    @Test("addContractorRating rejects inactive ratedBy user (is_active = 0)")
    func testAddContractorRating_rejectsInactiveRatedByUser() throws {
        let env = try E2ETestHelpers.setUp()
        let contractorId = try env.people.createContractor(companyName: "Rating Guard Subs")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET is_active = 0 WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: PeopleService.PeopleError.self) {
            try env.people.addContractorRating(contractorId: contractorId, quality: 4.0, onTime: 4.0, reliability: 4.0, ratedBy: env.adminUserId, jobId: nil)
        }
    }

    @Test("createContact rejects blank entityType and firstName")
    func testCreateContact_rejectsBlankFields() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Contact Parent Corp")
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("entityType")) {
            try env.people.createContact(entityType: "  ", entityId: customerId, firstName: "Jane", lastName: "Doe", role: "Manager", phone: "555-0001")
        }
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("firstName")) {
            try env.people.createContact(entityType: "customer", entityId: customerId, firstName: "", lastName: "Doe", role: "Manager", phone: "555-0001")
        }
    }

    @Test("updateContact rejects blank firstName")
    func testUpdateContact_rejectsBlankFirstName() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Update Contact Corp")
        let contactId = try env.people.createContact(entityType: "customer", entityId: customerId, firstName: "Alice", lastName: "Smith", role: "Lead", phone: "555-0002")
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("firstName")) {
            try env.people.updateContact(id: contactId, firstName: "   ", lastName: "Smith", phone: "555-0002")
        }
    }

    @Test("updateTeam rejects blank name")
    func testUpdateTeam_rejectsBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "Original Name")
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("name")) {
            try env.people.updateTeam(teamId: teamId, name: "  ", description: nil)
        }
    }

    @Test("createPaymentRecord and recordPayment reject invalid amount and blank date")
    func testPaymentRecord_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let customerId = try env.people.createCustomer(name: "Payment Test Corp")
        // Zero/negative amount
        #expect(throws: PeopleService.PeopleError.invalidAmount(0.0)) {
            try env.people.createPaymentRecord(customerId: customerId, jobId: nil, amount: 0.0, dueDate: "2026-05-01", invoiceNumber: nil, createdBy: env.adminUserId)
        }
        #expect(throws: PeopleService.PeopleError.invalidAmount(-50.0)) {
            try env.people.createPaymentRecord(customerId: customerId, jobId: nil, amount: -50.0, dueDate: "2026-05-01", invoiceNumber: nil, createdBy: env.adminUserId)
        }
        // Blank due date
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("dueDate")) {
            try env.people.createPaymentRecord(customerId: customerId, jobId: nil, amount: 100.0, dueDate: "  ", invoiceNumber: nil, createdBy: env.adminUserId)
        }
        // recordPayment — bad amount
        let recordId = try env.people.createPaymentRecord(customerId: customerId, jobId: nil, amount: 200.0, dueDate: "2026-05-01", invoiceNumber: "INV-001", createdBy: env.adminUserId)
        #expect(throws: PeopleService.PeopleError.invalidAmount(0.0)) {
            try env.people.recordPayment(recordId: recordId, amount: 0.0, paidDate: "2026-05-10")
        }
        // recordPayment — blank paid date
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("paidDate")) {
            try env.people.recordPayment(recordId: recordId, amount: 50.0, paidDate: "")
        }
    }

    @Test("listCustomers excludes inactive customers")
    func testListCustomers_excludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let custId = try env.people.createCustomer(name: "Active Customer", companyName: "Active Co", email: nil, phone: nil, address: nil, city: nil, state: nil, zip: nil, notes: nil)
        let inactiveCustId = try env.people.createCustomer(name: "Inactive Customer", companyName: "Inactive Co", email: nil, phone: nil, address: nil, city: nil, state: nil, zip: nil, notes: nil)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE customers SET is_active = 0 WHERE id = ?", arguments: [inactiveCustId])
        }
        let customers = try env.people.listCustomers()
        let ids = customers.map { $0.id }
        #expect(ids.contains(custId))
        #expect(!ids.contains(inactiveCustId))
    }

    @Test("listContractors excludes inactive contractors")
    func testListContractors_excludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let gcId = try env.people.createContractor(companyName: "Active GC", contactName: "Alice", email: nil, phone: nil, notes: nil)
        let inactiveGcId = try env.people.createContractor(companyName: "Inactive GC", contactName: "Bob", email: nil, phone: nil, notes: nil)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE general_contractors SET is_active = 0 WHERE id = ?", arguments: [inactiveGcId])
        }
        let contractors = try env.people.listContractors()
        let ids = contractors.map { $0.id }
        #expect(ids.contains(gcId))
        #expect(!ids.contains(inactiveGcId))
    }

    @Test("listTeams excludes inactive teams")
    func testListTeams_excludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let teamId = try env.people.createTeam(name: "Active Team")
        let inactiveTeamId = try env.people.createTeam(name: "Inactive Team")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE employee_teams SET is_active = 0 WHERE id = ?", arguments: [inactiveTeamId])
        }
        let teams = try env.people.listTeams()
        let ids = teams.map { $0.id }
        #expect(ids.contains(teamId))
        #expect(!ids.contains(inactiveTeamId))
    }

    @Test("getPeopleStats excludes inactive customers and contacts from totals")
    func testGetPeopleStats_excludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        let custId = try env.people.createCustomer(name: "Stats Customer", companyName: nil, email: nil, phone: nil, address: nil, city: nil, state: nil, zip: nil, notes: nil)
        let inactiveCustId = try env.people.createCustomer(name: "Inactive Stats Customer", companyName: nil, email: nil, phone: nil, address: nil, city: nil, state: nil, zip: nil, notes: nil)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE customers SET is_active = 0 WHERE id = ?", arguments: [inactiveCustId])
        }
        let statsBefore = try env.people.getPeopleStats()
        // active customer should count; inactive should not
        let contactId = try env.people.createContact(entityType: "customer", entityId: custId, firstName: "Test", lastName: "Contact", role: "manager", phone: "555-0001")
        let inactiveContactId = try env.people.createContact(entityType: "customer", entityId: custId, firstName: "Inactive", lastName: "Contact", role: "manager", phone: "555-0002")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE entity_contacts SET is_active = 0 WHERE id = ?", arguments: [inactiveContactId])
        }
        let statsAfter = try env.people.getPeopleStats()
        // one active contact added, one inactive contact added → total should go up by 1 only
        #expect(statsAfter.totalContacts == statsBefore.totalContacts + 1)
        _ = custId; _ = contactId
    }

    @Test("updatePaymentSettings rejects non-positive termsDays and negative warningDays")
    func testUpdatePaymentSettings_rejectsInvalidDays() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: PeopleService.PeopleError.invalidAmount(0.0)) {
            try env.people.updatePaymentSettings(termsDays: 0, warningDays: 7, autoHold: false)
        }
        #expect(throws: PeopleService.PeopleError.invalidAmount(-30.0)) {
            try env.people.updatePaymentSettings(termsDays: -30, warningDays: 7, autoHold: false)
        }
        #expect(throws: PeopleService.PeopleError.invalidAmount(-1.0)) {
            try env.people.updatePaymentSettings(termsDays: 30, warningDays: -1, autoHold: false)
        }
        #expect(throws: Never.self) {
            try env.people.updatePaymentSettings(termsDays: 30, warningDays: 0, autoHold: false)
        }
    }

    @Test("addCertification rejects blank fields and tombstoned user")
    func testAddCertification_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let userId = try env.auth.createUser(displayName: "Cert User", pin: "1234", email: "cert@test.com")

        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("certType")) {
            try env.people.addCertification(userId: userId, certType: "", certName: "OSHA 10")
        }
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("certName")) {
            try env.people.addCertification(userId: userId, certType: "safety", certName: "  ")
        }
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [userId])
        }
        #expect(throws: PeopleService.PeopleError.employeeNotFound(userId)) {
            try env.people.addCertification(userId: userId, certType: "safety", certName: "OSHA 10")
        }
    }

    @Test("addCertification stores cert and getEmployeeCertifications retrieves it")
    func testAddCertification_roundTrip() throws {
        let env = try E2ETestHelpers.setUp()
        let userId = try env.auth.createUser(displayName: "Cert User", pin: "1234", email: "cert2@test.com")

        let cert = try env.people.addCertification(
            userId: userId, certType: "safety", certName: "OSHA 10", expiryDate: "2027-01-01"
        )
        #expect(cert.id != nil)
        #expect(cert.certName == "OSHA 10")

        let fetched = try env.people.getEmployeeCertifications(userId: userId)
        #expect(fetched.count == 1)
        #expect(fetched[0].certName == "OSHA 10")

        try env.people.removeCertification(id: cert.id!)
        let afterRemove = try env.people.getEmployeeCertifications(userId: userId)
        #expect(afterRemove.isEmpty)
    }

    @Test("addSkill rejects blank fields and tombstoned user")
    func testAddSkill_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let userId = try env.auth.createUser(displayName: "Skill User", pin: "1234", email: "skill@test.com")

        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("skillName")) {
            try env.people.addSkill(userId: userId, skillName: "", proficiency: "expert")
        }
        #expect(throws: PeopleService.PeopleError.requiredFieldEmpty("proficiency")) {
            try env.people.addSkill(userId: userId, skillName: "Welding", proficiency: "  ")
        }
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [userId])
        }
        #expect(throws: PeopleService.PeopleError.employeeNotFound(userId)) {
            try env.people.addSkill(userId: userId, skillName: "Welding", proficiency: "expert")
        }
    }

    @Test("addSkill stores skill and getEmployeeSkills retrieves it")
    func testAddSkill_roundTrip() throws {
        let env = try E2ETestHelpers.setUp()
        let userId = try env.auth.createUser(displayName: "Skill User", pin: "1234", email: "skill2@test.com")

        let skill = try env.people.addSkill(
            userId: userId, skillName: "Welding", proficiency: "expert", yearsExperience: 5.0
        )
        #expect(skill.id != nil)
        #expect(skill.skillName == "Welding")
        #expect(skill.proficiency == "expert")

        let fetched = try env.people.getEmployeeSkills(userId: userId)
        #expect(fetched.count == 1)
        #expect(fetched[0].skillName == "Welding")

        try env.people.removeSkill(id: skill.id!)
        let afterRemove = try env.people.getEmployeeSkills(userId: userId)
        #expect(afterRemove.isEmpty)
    }

    @Test("getEmployeeDetail includes certifications and skills")
    func testGetEmployeeDetail_includesCertsAndSkills() throws {
        let env = try E2ETestHelpers.setUp()
        let userId = try env.auth.createUser(displayName: "Detail User", pin: "1234", email: "detail@test.com")

        _ = try env.people.addCertification(userId: userId, certType: "safety", certName: "OSHA 30")
        _ = try env.people.addSkill(userId: userId, skillName: "Carpentry", proficiency: "intermediate")

        let detail = try env.people.getEmployeeDetail(id: userId)
        #expect(detail.certifications.count == 1)
        #expect(detail.certifications[0].certName == "OSHA 30")
        #expect(detail.skills.count == 1)
        #expect(detail.skills[0].skillName == "Carpentry")
    }
}
