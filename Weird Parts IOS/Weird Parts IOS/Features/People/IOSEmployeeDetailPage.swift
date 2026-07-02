import SwiftUI
import WiredPartCore

/// Employee detail page with tabs for profile, hats, skills, teams, certifications, and activity.
struct IOSEmployeeDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let employeeId: Int64

    @State private var employee: PeopleService.EmployeeDetail?
    @State private var activity: [PeopleService.EmployeeActivityItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activityError: String?
    @State private var selectedTab = "profile"

    // Hat management
    @State private var allHats: [(hat: PeopleService.HatInfo, isAssigned: Bool)] = []
    @State private var canManageHats = false
    @State private var combinedPermissions: [String] = []
    @State private var certificationToRemove: Certification?

    private enum ActiveSheet: String, Identifiable {
        case editContact
        case addSkill
        case addCertification
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    private let tabs = ["profile", "hats", "skills", "teams", "certifications", "activity"]

    var body: some View {
        VStack(spacing: 0) {
            tabPicker

            if isLoading {
                ProgressView("Loading employee...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let emp = employee {
                tabContent(emp)
            }
        }
        .navigationTitle(employee?.displayName ?? "Employee")
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { activeSheet = .editContact }
                    .disabled(employee == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editContact:
                if let emp = employee {
                    EditEmployeeContactSheet(
                        displayName: emp.displayName,
                        email: emp.email,
                        phone: emp.phone ?? ""
                    ) { name, email, phone in
                        guard let service = appCore.peopleService else {
                            loadError = "People service not available"
                            struct ServiceUnavailableError: Error {}
                            throw ServiceUnavailableError()
                        }
                        try service.updateEmployeeContact(
                            employeeId: emp.id,
                            displayName: name,
                            phone: phone.isEmpty ? nil : phone,
                            email: email.isEmpty ? nil : email
                        )
                        loadData()
                    }
                }
            case .addSkill:
                AddSkillSheet { skillName, proficiency, yearsExperience in
                    guard let service = appCore.peopleService else {
                        loadError = "People service not available"
                        struct ServiceUnavailableError: Error {}
                        throw ServiceUnavailableError()
                    }
                    _ = try service.addSkill(
                        userId: employeeId,
                        skillName: skillName,
                        proficiency: proficiency,
                        yearsExperience: yearsExperience
                    )
                    loadData()
                }
            case .addCertification:
                AddCertificationSheet { certType, certName, issuingAuthority, certNumber, issuedDate, expiryDate, notes in
                    guard let service = appCore.peopleService else {
                        loadError = "People service not available"
                        struct ServiceUnavailableError: Error {}
                        throw ServiceUnavailableError()
                    }
                    _ = try service.addCertification(
                        userId: employeeId,
                        certType: certType,
                        certName: certName,
                        issuingAuthority: issuingAuthority,
                        certNumber: certNumber,
                        issuedDate: issuedDate,
                        expiryDate: expiryDate,
                        notes: notes
                    )
                    loadData()
                }
            case .help:
                PageHelpSheet(
                    title: "Employee Detail Help",
                    sections: [
                        ("What This Page Does", "View and edit a single employee's profile, hat assignments, skills, team memberships, certifications, and recent activity. Use the tabs to switch between Profile, Hats, Skills, Teams, Certifications, and Activity views."),
                        ("Profile Tab", "Shows the employee's basic info: name, email, phone, role, status, and important dates. Tap Edit in the toolbar to update their contact information."),
                        ("Hats Tab", "Displays all available hats (roles) and which ones are assigned to this employee. If you have manage_people permission, you can toggle hats on and off directly. Each hat grants a set of permissions."),
                        ("Skills Tab", "Shows employee skills, proficiency, and years of experience. If you have manage_people permission, you can add or remove skills."),
                        ("Teams Tab", "Shows which teams this employee belongs to, their role within each team, and when they joined."),
                        ("Certifications Tab", "Shows employee certifications, issuing details, certificate numbers, and expiry status. Managers can add or remove certifications."),
                        ("Activity Tab", "Shows recent job sessions worked by this employee, including the job, clock times, status, and recorded hours."),
                        ("Tips", "Pull down to refresh all data. Only managers and admins can toggle hat assignments or change skills. The Edit button updates contact info only — use the Hats tab for role changes.")
                    ]
                )
            }
        }
        .alert("Remove certification?", isPresented: Binding(
            get: { certificationToRemove != nil },
            set: { if !$0 { certificationToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let certificationToRemove {
                    removeCertification(certificationToRemove)
                }
            }
            Button("Cancel", role: .cancel) {
                certificationToRemove = nil
            }
        } message: {
            Text("This certification will no longer appear on the employee profile.")
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.capitalized)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedTab == tab ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(tab.capitalized) tab"))
                    .accessibilityIdentifier("employeeDetailTab_\(tab)")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ emp: PeopleService.EmployeeDetail) -> some View {
        switch selectedTab {
        case "profile":
            profileTab(emp)
        case "hats":
            hatsTab(emp)
        case "skills":
            skillsTab(emp)
        case "teams":
            teamsTab(emp)
        case "certifications":
            certificationsTab(emp)
        case "activity":
            activityTab()
        default:
            Text("Unknown tab")
        }
    }

    // MARK: - Profile

    private func profileTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            Section("Basic Info") {
                detailRow("Name", emp.displayName)
                detailRow("Email", emp.email)
                if let phone = emp.phone, !phone.isEmpty {
                    detailRow("Phone", phone)
                }
                detailRow("Role", emp.role.capitalized)
                detailRow("Status", emp.status.capitalized)
            }

            Section("Dates") {
                if let created = emp.createdAt {
                    detailRow("Added", String(created.prefix(10)))
                }
                if let updated = emp.updatedAt {
                    detailRow("Updated", String(updated.prefix(10)))
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling employee detail lists
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Skills

    private func skillsTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            if canManageHats {
                Section {
                    Button {
                        activeSheet = .addSkill
                    } label: {
                        Label("Add Skill", systemImage: "plus.circle.fill")
                    }
                }
            }

            if emp.skills.isEmpty {
                Section {
                    Text("No skills recorded")
                        .foregroundStyle(.secondary)
                } footer: {
                    if !canManageHats {
                        Text("Contact a manager to add employee skills")
                    }
                }
            } else {
                Section {
                    ForEach(Array(emp.skills.enumerated()), id: \.offset) { _, skill in
                        skillRow(skill)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canManageHats, let skillId = skill.id {
                                    Button(role: .destructive) {
                                        removeSkill(id: skillId)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text("Skills (\(emp.skills.count))")
                } footer: {
                    if !canManageHats {
                        Text("Contact a manager to change employee skills")
                    }
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling employee detail lists
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    private func skillRow(_ skill: UserSkill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(skill.skillName)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(skill.proficiency.capitalized)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(proficiencyColor(skill.proficiency).opacity(0.18)))
                        .foregroundStyle(proficiencyColor(skill.proficiency))
                    if let years = skill.yearsExperience {
                        Text(yearsExperienceLabel(years))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Hats

    private func hatsTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            if allHats.isEmpty {
                Section {
                    Text("No hats available")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(allHats, id: \.hat.id) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill")
                                .foregroundStyle(item.isAssigned ? Color.accentColor : .gray)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.hat.name)
                                    .fontWeight(.medium)
                                if let desc = item.hat.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if canManageHats {
                                Toggle("", isOn: Binding<Bool>(
                                    get: { item.isAssigned },
                                    set: { newValue in
                                        toggleHat(hatId: item.hat.id, assign: newValue)
                                    }
                                ))
                                .labelsHidden()
                            } else if item.isAssigned {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                } header: {
                    Text("Hats & Roles (\(allHats.filter(\.isAssigned).count) assigned)")
                } footer: {
                    if !canManageHats {
                        Text("Contact a manager to change hat assignments")
                    }
                }
            }

            // Permissions Granted section
            Section {
                if combinedPermissions.isEmpty {
                    if allHats.filter(\.isAssigned).isEmpty && !allHats.isEmpty {
                        Text("Assign hats above to grant permissions")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("No permissions granted")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(combinedPermissions, id: \.self) { perm in
                        Label(permissionLabel(perm), systemImage: "checkmark.shield")
                            .font(.subheadline)
                            .accessibilityLabel(permissionLabel(perm))
                    }
                }
            } header: {
                Text("Permissions Granted (\(combinedPermissions.count))")
            } footer: {
                if !combinedPermissions.isEmpty {
                    Text("These permissions come from all assigned hats.")
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling employee detail lists
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Teams

    private func teamsTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            if emp.teams.isEmpty {
                Section {
                    Text("Not a member of any teams")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Teams (\(emp.teams.count))") {
                    ForEach(emp.teams) { membership in
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(membership.teamName)
                                    .fontWeight(.medium)
                                Text("Role: \(membership.role.capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let joined = membership.joinedAt {
                                    Text("Joined: \(String(joined.prefix(10)))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling employee detail lists
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Certifications

    private func certificationsTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            if canManageHats {
                Section {
                    Button {
                        activeSheet = .addCertification
                    } label: {
                        Label("Add Certification", systemImage: "plus.circle.fill")
                    }
                }
            }

            if emp.certifications.isEmpty {
                Section {
                    Text("No certifications on file")
                        .foregroundStyle(.secondary)
                } footer: {
                    if !canManageHats {
                        Text("Contact a manager to add employee certifications")
                    }
                }
            } else {
                Section {
                    ForEach(emp.certifications, id: \.id) { cert in
                        certificationRow(cert)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canManageHats {
                                    Button(role: .destructive) {
                                        certificationToRemove = cert
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text("Certifications (\(emp.certifications.count))")
                } footer: {
                    if !canManageHats {
                        Text("Contact a manager to change employee certifications")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Activity

    private func activityTab() -> some View {
        List {
            if let activityError {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Activity unavailable", systemImage: "exclamationmark.triangle")
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                        Text(activityError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            loadData()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                }
            } else if activity.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "clock.badge.questionmark",
                        title: "No recent activity",
                        message: "Recent job sessions will appear here after this employee clocks in."
                    )
                }
            } else {
                Section("Recent Sessions (\(activity.count))") {
                    ForEach(activity) { item in
                        activityRow(item)
                    }
                }
            }
        }
        .refreshable { loadData() }
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    private func activityRow(_ item: PeopleService.EmployeeActivityItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.clockOut == nil ? "clock.badge" : "checkmark.circle")
                .foregroundStyle(item.clockOut == nil ? .orange : Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.jobName)
                    .fontWeight(.medium)
                if !item.jobNumber.isEmpty {
                    Text(item.jobNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(activityStatusLabel(item))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(activityStatusColor(item).opacity(0.18)))
                        .foregroundStyle(activityStatusColor(item))
                    if let workType = item.workType, !workType.isEmpty {
                        Text(workType.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(activityTimeRange(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if item.regularHours > 0 || item.overtimeHours > 0 {
                    Text(activityHoursLabel(item))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func certificationRow(_ cert: Certification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(expiryColor(for: cert.expiryDate))
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cert.certName)
                        .fontWeight(.medium)
                    Spacer(minLength: 8)
                    Text(cert.certType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(expiryColor(for: cert.expiryDate).opacity(0.18)))
                        .foregroundStyle(expiryColor(for: cert.expiryDate))
                }

                if let issuingAuthority = cert.issuingAuthority, !issuingAuthority.isEmpty {
                    Label(issuingAuthority, systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let certNumber = cert.certNumber, !certNumber.isEmpty {
                    Label(certNumber, systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(expiryLabel(for: cert.expiryDate), systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(expiryColor(for: cert.expiryDate))
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func permissionLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func expiryLabel(for expiryDate: String?) -> String {
        guard let expiryDate, !expiryDate.isEmpty else {
            return "No expiry date"
        }
        let displayDate = Formatters.formatDateString(expiryDate)
        guard let expiry = Formatters.localDateFormatter.date(from: String(expiryDate.prefix(10))) else {
            return "Expires \(displayDate)"
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expiryDay = calendar.startOfDay(for: expiry)

        if expiryDay < today {
            return "Expired \(displayDate)"
        }
        if let days = calendar.dateComponents([.day], from: today, to: expiryDay).day, days <= 30 {
            return "Expires soon \(displayDate)"
        }
        return "Expires \(displayDate)"
    }

    private func expiryColor(for expiryDate: String?) -> Color {
        guard let expiryDate,
              let expiry = Formatters.localDateFormatter.date(from: String(expiryDate.prefix(10))) else {
            return .secondary
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expiryDay = calendar.startOfDay(for: expiry)

        if expiryDay < today { return .red }
        if let days = calendar.dateComponents([.day], from: today, to: expiryDay).day, days <= 30 {
            return .orange
        }
        return .green
    }

    private func proficiencyColor(_ proficiency: String) -> Color {
        switch proficiency.lowercased() {
        case "expert":
            return .purple
        case "intermediate":
            return .blue
        default:
            return .green
        }
    }

    private func yearsExperienceLabel(_ years: Double) -> String {
        let formatted = years == floor(years) ? String(Int(years)) : String(format: "%.1f", years)
        return "\(formatted) \(years == 1 ? "year" : "years")"
    }

    private func activityStatusLabel(_ item: PeopleService.EmployeeActivityItem) -> String {
        if item.clockOut == nil { return "Clocked In" }
        return item.status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func activityStatusColor(_ item: PeopleService.EmployeeActivityItem) -> Color {
        item.clockOut == nil ? .orange : .green
    }

    private func activityTimeRange(_ item: PeopleService.EmployeeActivityItem) -> String {
        let start = "\(Formatters.formatSQLiteDate(item.clockIn)) \(activityTime(item.clockIn))"
        guard let clockOut = item.clockOut, !clockOut.isEmpty else {
            return "Started \(start)"
        }
        return "\(start) - \(activityTime(clockOut))"
    }

    private func activityTime(_ value: String) -> String {
        if value.count >= 16 {
            let startIdx = value.index(value.startIndex, offsetBy: 11)
            let endIdx = value.index(value.startIndex, offsetBy: 16)
            return String(value[startIdx..<endIdx])
        }
        return value
    }

    private func activityHoursLabel(_ item: PeopleService.EmployeeActivityItem) -> String {
        let total = item.regularHours + item.overtimeHours
        if item.overtimeHours > 0 {
            return String(format: "%.2f hours (%.2f OT)", total, item.overtimeHours)
        }
        return String(format: "%.2f hours", total)
    }

    private func toggleHat(hatId: Int64, assign: Bool) {
        guard let service = appCore.peopleService else {
            loadError = "Service not available"
            return
        }
        do {
            try service.toggleHatAssignment(employeeId: employeeId, hatId: hatId, assign: assign)
            // Reload hats — a reload failure now surfaces via loadError and keeps
            // the previous list instead of showing zero hats assigned (#1335).
            allHats = try service.getAllHatsWithAssignment(employeeId: employeeId)
        } catch {
            loadError = userFriendlyError(error, context: "update hat")
        }
    }

    private func removeSkill(id: Int64) {
        guard let service = appCore.peopleService else {
            loadError = "Service not available"
            return
        }
        do {
            try service.removeSkill(id: id)
            loadData()
        } catch {
            loadError = userFriendlyError(error, context: "remove skill")
        }
    }

    private func removeCertification(_ cert: Certification) {
        guard canManageHats else {
            certificationToRemove = nil
            return
        }
        guard let service = appCore.peopleService else {
            loadError = "Service not available"
            certificationToRemove = nil
            return
        }
        guard let certId = cert.id else {
            loadError = "Certification cannot be removed because it has no saved id."
            certificationToRemove = nil
            return
        }
        do {
            try service.removeCertification(id: certId)
            certificationToRemove = nil
            loadData()
        } catch {
            loadError = userFriendlyError(error, context: "remove certification")
            certificationToRemove = nil
        }
    }

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = employee == nil
        loadError = nil
        do {
            employee = try service.getEmployeeDetail(id: employeeId)
            do {
                activity = try service.getEmployeeRecentActivity(id: employeeId)
                activityError = nil
            } catch {
                activity = []
                activityError = userFriendlyError(error, context: "load employee activity")
            }
            allHats = try service.getAllHatsWithAssignment(employeeId: employeeId)
            canManageHats = appCore.hasPermission("manage_people")

            // Collect combined permissions from all assigned hats
            var allPerms = Set<String>()
            if let auth = appCore.authService {
                for item in allHats where item.isAssigned {
                    let hatPerms = (try? auth.getHatPermissions(item.hat.id)) ?? []
                    allPerms.formUnion(hatPerms)
                }
            }
            combinedPermissions = allPerms.sorted()
        } catch {
            loadError = userFriendlyError(error, context: "load employee details")
        }
        isLoading = false
    }
}

// MARK: - Edit Employee Contact Sheet

private struct EditEmployeeContactSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var displayName: String
    @State var email: String
    @State var phone: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    let onSave: (String, String, String) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
                Section("Contact Info") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                        .onChange(of: displayName) { _, _ in isDirty = true }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .onChange(of: email) { _, _ in isDirty = true }
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, _ in isDirty = true }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Contact Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    private func save() {
        isSaving = true
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        do {
            try onSave(trimmedName, email, phone)
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "load employee")
        }
        isSaving = false
    }
}

// MARK: - Add Certification Sheet

private struct AddCertificationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var certType = ""
    @State private var certName = ""
    @State private var issuingAuthority = ""
    @State private var certNumber = ""
    @State private var hasIssuedDate = false
    @State private var issuedDate = Date()
    @State private var hasExpiryDate = true
    @State private var expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    let onSave: (String, String, String?, String?, String?, String?, String?) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }

                Section("Certification") {
                    TextField("Certification Type", text: $certType)
                        .textInputAutocapitalization(.words)
                        .onChange(of: certType) { _, _ in isDirty = true }
                    TextField("Certification Name", text: $certName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: certName) { _, _ in isDirty = true }
                }

                Section("Details") {
                    TextField("Issuing Authority", text: $issuingAuthority)
                        .textInputAutocapitalization(.words)
                        .onChange(of: issuingAuthority) { _, _ in isDirty = true }
                    TextField("Certificate Number", text: $certNumber)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: certNumber) { _, _ in isDirty = true }
                    Toggle("Issued Date", isOn: $hasIssuedDate)
                        .onChange(of: hasIssuedDate) { _, _ in isDirty = true }
                    if hasIssuedDate {
                        DatePicker("Issued", selection: $issuedDate, displayedComponents: .date)
                            .onChange(of: issuedDate) { _, _ in isDirty = true }
                    }
                    Toggle("Expiry Date", isOn: $hasExpiryDate)
                        .onChange(of: hasExpiryDate) { _, _ in isDirty = true }
                    if hasExpiryDate {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                            .onChange(of: expiryDate) { _, _ in isDirty = true }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: notes) { _, _ in isDirty = true }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Certification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || certType.trimmingCharacters(in: .whitespaces).isEmpty || certName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        let trimmedType = certType.trimmingCharacters(in: .whitespaces)
        let trimmedName = certName.trimmingCharacters(in: .whitespaces)
        let trimmedAuthority = issuingAuthority.trimmingCharacters(in: .whitespaces)
        let trimmedNumber = certNumber.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try onSave(
                trimmedType,
                trimmedName,
                trimmedAuthority.isEmpty ? nil : trimmedAuthority,
                trimmedNumber.isEmpty ? nil : trimmedNumber,
                hasIssuedDate ? Formatters.localDateFormatter.string(from: issuedDate) : nil,
                hasExpiryDate ? Formatters.localDateFormatter.string(from: expiryDate) : nil,
                trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "add certification")
        }
        isSaving = false
    }
}

// MARK: - Add Skill Sheet

private struct AddSkillSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var skillName = ""
    @State private var proficiency = "beginner"
    @State private var yearsExperience = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    let onSave: (String, String, Double?) throws -> Void

    private let proficiencyOptions = ["beginner", "intermediate", "expert"]

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
                Section("Skill") {
                    TextField("Skill Name", text: $skillName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: skillName) { _, _ in isDirty = true }
                    Picker("Proficiency", selection: $proficiency) {
                        ForEach(proficiencyOptions, id: \.self) { option in
                            Text(option.capitalized).tag(option)
                        }
                    }
                    .onChange(of: proficiency) { _, _ in isDirty = true }
                    TextField("Years Experience", text: $yearsExperience)
                        .keyboardType(.decimalPad)
                        .onChange(of: yearsExperience) { _, _ in isDirty = true }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || skillName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let trimmedName = skillName.trimmingCharacters(in: .whitespaces)
        let trimmedYears = yearsExperience.trimmingCharacters(in: .whitespaces)
        let parsedYears: Double?

        if trimmedYears.isEmpty {
            parsedYears = nil
        } else if let value = Double(trimmedYears), value >= 0 {
            parsedYears = value
        } else {
            errorMessage = "Years experience must be a positive number."
            isSaving = false
            return
        }

        do {
            try onSave(trimmedName, proficiency, parsedYears)
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "add skill")
        }
        isSaving = false
    }
}
