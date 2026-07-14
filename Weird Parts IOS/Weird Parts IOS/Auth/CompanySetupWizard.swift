import SwiftUI
import WiredPartCore
import OSLog

/// Guided 8-step company setup wizard for new businesses.
/// Shows after bootstrap when @AppStorage("hasCompletedCompanySetup") is false AND user is admin.
struct CompanySetupWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("hasCompletedCompanySetup") private var hasCompletedCompanySetup = false
    @State private var currentStep = 0
    @State private var completedSteps: Set<Int> = []
    @State private var skippedSteps: Set<Int> = []

    // Step 1: Company Profile
    @State private var companyName = ""
    @State private var companyAddress = ""
    @State private var companyPhone = ""
    @State private var companyEmail = ""

    // Step 2: Employees
    @State private var addedEmployeeCount = 0

    // Step 4: First Job
    @State private var firstJobCreated = false

    // Step 7: Break/Lunch Policy
    @State private var selectedState = "California"
    @State private var breakPolicySet = false
    // Company policy: require a device GPS location to clock in. Defaults ON —
    // matches the app's historical behavior; companies that don't want location
    // tracking turn it off here (or later in Settings).
    @State private var requireClockLocation = true

    // Errors
    @State private var saveError: String?
    @State private var showExitConfirmation = false

    private let logger = Logger(subsystem: "com.wiredpart.ios", category: "CompanySetupWizard")
    let totalSteps = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader
                ScrollView {
                    stepContent
                        .padding()
                }
                // Fix #149: dismiss keyboard when scrolling through setup steps
                .scrollDismissesKeyboard(.interactively)
                navigationFooter
            }
            .navigationTitle("Company Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit Setup") {
                        showExitConfirmation = true
                    }
                }
            }
            .onAppear { loadProgress() }
            .alert("Error", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .confirmationDialog(
                "Leave Company Setup?",
                isPresented: $showExitConfirmation,
                titleVisibility: .visible
            ) {
                Button("Continue to App") {
                    saveProgress()
                    completeSetupAfterDraftCleanup()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can finish setup anytime from the Getting Started checklist on your Dashboard. Everything works without completing setup.")
            }
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(completedSteps.count), total: Double(totalSteps))
                .tint(.blue)

            HStack {
                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(completedSteps.count) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: step1CompanyProfile
        case 1: step2AddEmployees
        case 2: step3ConfigureHats
        case 3: step4CreateFirstJob
        case 4: step5AddParts
        case 5: step6SetupWarehouse
        case 6: step7BreakLunchPolicy
        case 7: step8Complete
        default: EmptyView()
        }
    }

    // MARK: - Step 1: Company Profile

    private var step1CompanyProfile: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                icon: "building.2.fill",
                color: .blue,
                title: "Company Profile",
                subtitle: "Basic info about your business. This appears on reports, POs, and invoices."
            )

            VStack(alignment: .leading, spacing: 12) {
                labeledField("Company Name", text: $companyName, placeholder: "Acme Plumbing LLC")
                labeledField("Address", text: $companyAddress, placeholder: "123 Main St, City, ST 12345")
                labeledField("Phone", text: $companyPhone, placeholder: "(555) 123-4567")
                labeledField("Email", text: $companyEmail, placeholder: "office@acmeplumbing.com")
            }

            Button {
                saveCompanyProfile()
            } label: {
                Label("Save Company Profile", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if completedSteps.contains(0) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Company profile saved!")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Step 2: Add Employees

    private var step2AddEmployees: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                icon: "person.badge.plus",
                color: .green,
                title: "Add Your Team",
                subtitle: "Add employees so they can log in, clock in, and get assigned to jobs. You can add more later."
            )

            if addedEmployeeCount > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(addedEmployeeCount) employee(s) added")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How to Add Employees")
                    .font(.headline)
                Text("The Employees page lets you create accounts with name, PIN, and hat (role). Employees can then log in from any device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            NavigationLink {
                IOSEmployeesPage()
                    .environmentObject(appCore)
            } label: {
                Label("Open Full Employees Page", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Add at least one employee besides yourself, then come back and tap Next.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await checkEmployeeCount() }
    }

    // MARK: - Step 3: Configure Hats

    private var step3ConfigureHats: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                icon: "crown.fill",
                color: .purple,
                title: "Set Up Hats & Permissions",
                subtitle: "Hats control what each person can see and do. Common hats: Admin, Foreman, Journeyman, Apprentice, Office."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Hats")
                    .font(.headline)

                Text("WiredPart creates these hats automatically:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(["Admin — Full access to everything",
                         "Foreman — Manage jobs, scheduling, approve JPOs",
                         "Journeyman — Clock in, create JPOs, use tools",
                         "Apprentice — Clock in, view assignments",
                         "Office — Manage orders, reports, approvals"], id: \.self) { hat in
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Text(hat)
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.purple.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            NavigationLink {
                IOSHatsPage()
                    .environmentObject(appCore)
            } label: {
                Label("Customize Hats & Permissions", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("The defaults work for most companies. Customize later if needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 4: Create First Job

    private var step4CreateFirstJob: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                icon: "briefcase.fill",
                color: .orange,
                title: "Create Your First Job",
                subtitle: "Jobs are the core of WiredPart. Every clock-in, parts order, and report ties to a job."
            )

            if firstJobCreated {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("First job created!")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What makes a job?")
                    .font(.headline)

                ForEach([
                    ("doc.text.fill", "Name + Address — where the work happens"),
                    ("person.fill", "Customer — who you're working for"),
                    ("flag.fill", "Priority — Low / Normal / High / Urgent"),
                    ("calendar", "Dates — estimated start and end"),
                ], id: \.1) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.0)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        Text(item.1)
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            NavigationLink {
                JobsListPage()
                    .environmentObject(appCore)
            } label: {
                Label("Open Jobs Page to Create One", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .task { await checkJobCount() }
    }

    // MARK: - Step 5: Add Parts

    private var step5AddParts: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                icon: "shippingbox.fill",
                color: .teal,
                title: "Add Your Parts",
                subtitle: "Import your parts catalog from CSV, or add parts manually. You need parts before you can order or track inventory."
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Two ways to add parts:")
                    .font(.headline)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.title3)
                        .foregroundStyle(.teal)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from CSV")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Upload a spreadsheet with part names, categories, and prices. Best for large catalogs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.teal)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Manually")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Add parts one at a time from the catalog page. Best for small catalogs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.teal.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            NavigationLink {
                PartsImportExportPage()
                    .environmentObject(appCore)
            } label: {
                Label("Import Parts from CSV", systemImage: "doc.badge.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            NavigationLink {
                PartsCatalogPage()
                    .environmentObject(appCore)
            } label: {
                Label("Add Parts Manually", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Step 6: Set Up Warehouse

    private var step6SetupWarehouse: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                icon: "building.2.fill",
                color: .indigo,
                title: "Set Up Your Warehouse",
                subtitle: "Define your shop layout so the system knows where parts are stored. This is a multi-step process — you can do it now or later."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("The Warehouse Setup Wizard covers:")
                    .font(.headline)

                ForEach([
                    ("1.", "Room dimensions (width x length)"),
                    ("2.", "Place storage units on the grid"),
                    ("3.", "Number everything (print stickers)"),
                    ("4.", "Walk the floor (assign parts to areas)"),
                    ("5.", "Count everything (initial stock audit)"),
                    ("6.", "Set reorder targets (MIN/TARGET/MAX)"),
                ], id: \.0) { item in
                    HStack(spacing: 8) {
                        Text(item.0)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.indigo)
                            .frame(width: 20)
                        Text(item.1)
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.indigo.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            NavigationLink {
                WarehouseOnboardingWizard()
                    .environmentObject(appCore)
            } label: {
                Label("Start Warehouse Setup Wizard", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("This can take 30-60 minutes for a large warehouse. You can save progress and come back.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 7: Break/Lunch Policy

    private var step7BreakLunchPolicy: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                icon: "cup.and.saucer.fill",
                color: .brown,
                title: "Break & Lunch Policy",
                subtitle: "Set your state's break/lunch rules. The app will track compliance and remind workers to take required breaks."
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Select Your State")
                    .font(.headline)

                Picker("State", selection: $selectedState) {
                    ForEach(["California", "Oregon", "Washington", "Nevada",
                             "Arizona", "Colorado", "Texas", "New York",
                             "Florida", "Illinois", "Other / Federal"], id: \.self) { state in
                        Text(state).tag(state)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 4) {
                    if selectedState == "California" {
                        Text("California Rules:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("• 10-min paid break every 4 hours")
                            .font(.caption)
                        Text("• 30-min unpaid meal break before 5th hour")
                            .font(.caption)
                        Text("• 2nd meal break before 10th hour")
                            .font(.caption)
                    } else {
                        Text("Federal minimum rules will be applied.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("You can customize break rules in Settings later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.brown.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Company time-clock location policy. Saved to the synced "company"
            // category so every device in the company enforces the same rule.
            Toggle(isOn: $requireClockLocation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require location to clock in")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Workers must allow GPS so each clock in/out records where it happened. Turn off if your company doesn't want location tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .background(Color.brown.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                saveBreakPolicy()
            } label: {
                Label("Apply Break Policy", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if breakPolicySet {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Break policy saved!")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Step 8: Complete

    private var step8Complete: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)

            Image(systemName: "checkmark.seal.fill")
                .decorativeIconFont(72)
                .foregroundStyle(.green)

            Text("You're Ready!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your company is set up and ready to use WiredPart.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(step: 0, label: "Company Profile")
                summaryRow(step: 1, label: "Employees")
                summaryRow(step: 2, label: "Hats & Permissions")
                summaryRow(step: 3, label: "First Job")
                summaryRow(step: 4, label: "Parts Catalog")
                summaryRow(step: 5, label: "Warehouse")
                summaryRow(step: 6, label: "Break Policy")
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !skippedSteps.isEmpty {
                Text("Skipped items can be completed from the Getting Started checklist on your Dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                completeSetupAfterDraftCleanup()
            } label: {
                Text("Go to Dashboard")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - Helpers

    private func stepHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .decorativeIconFont(48)
                .foregroundStyle(color)

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func summaryRow(step: Int, label: String) -> some View {
        HStack(spacing: 8) {
            if completedSteps.contains(step) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if skippedSteps.contains(step) {
                Image(systemName: "forward.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.subheadline)
            Spacer()
            if skippedSteps.contains(step) {
                Text("Skipped")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Navigation Footer

    private var navigationFooter: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Skip for Now") {
                    skippedSteps.insert(currentStep)
                    saveProgress()
                    withAnimation { currentStep += 1 }
                }
                .foregroundStyle(.secondary)

                Button {
                    if !completedSteps.contains(currentStep) {
                        completedSteps.insert(currentStep)
                    }
                    saveProgress()
                    withAnimation { currentStep += 1 }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Data Operations

    private func saveCompanyProfile() {
        // Persist the trimmed values — SettingsService stores them verbatim,
        // so validating trimmed but saving raw can store stray whitespace (#1337).
        let trimmedName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            try appCore.settingsService?.updateSetting(key: "company_name", value: trimmedName)
            try appCore.settingsService?.updateSetting(key: "company_address", value: companyAddress.trimmingCharacters(in: .whitespacesAndNewlines))
            try appCore.settingsService?.updateSetting(key: "company_phone", value: companyPhone.trimmingCharacters(in: .whitespacesAndNewlines))
            try appCore.settingsService?.updateSetting(key: "company_email", value: companyEmail.trimmingCharacters(in: .whitespacesAndNewlines))
            completedSteps.insert(0)
            saveProgress()
        } catch {
            saveError = userFriendlyError(error, context: "save company profile")
        }
    }

    private func saveBreakPolicy() {
        do {
            try appCore.settingsService?.updateSetting(key: "break_policy_state", value: selectedState, category: "compliance")
            // "company" category syncs, so every device enforces the same rule.
            try appCore.settingsService?.updateSetting(
                key: "clock_location_required",
                value: requireClockLocation ? "true" : "false",
                category: "company"
            )
            breakPolicySet = true
            completedSteps.insert(6)
            saveProgress()
        } catch {
            saveError = userFriendlyError(error, context: "save break policy")
        }
    }

    private func checkEmployeeCount() async {
        do {
            let employees = try appCore.peopleService?.listEmployees() ?? []
            addedEmployeeCount = max(employees.count - 1, 0)
            if addedEmployeeCount > 0 {
                completedSteps.insert(1)
                saveProgress()
            }
        } catch {
            // Non-fatal: wizard step check — employee list may fail if service is initializing
        }
    }

    private func checkJobCount() async {
        do {
            let jobs = try appCore.jobsService?.listJobs() ?? []
            firstJobCreated = !jobs.isEmpty
            if firstJobCreated {
                completedSteps.insert(3)
                saveProgress()
            }
        } catch {
            // Non-fatal: wizard step check — job list may fail if service is initializing
        }
    }

    // MARK: - Persistence (SQLite draft — no PII in UserDefaults)

    private func loadProgress() {
        guard let settingsService = appCore.settingsService else {
            saveError = "Settings are still loading. Please try again in a moment."
            return
        }

        let draft: SettingsService.CompanySetupDraft?
        do {
            draft = try settingsService.loadSetupDraft()
        } catch {
            saveError = userFriendlyError(error, context: "load saved setup progress")
            logger.error("loadSetupDraft failed; keeping setup wizard in a visible retryable state: \(error.localizedDescription)")
            return
        }

        if let draft {
            completedSteps = draft.completedSteps
            skippedSteps = draft.skippedSteps
            companyName = draft.name
            companyAddress = draft.address
            companyPhone = draft.phone
            companyEmail = draft.email
            selectedState = draft.selectedState
            currentStep = draft.currentStep
        }

        // No repeat questions: pre-fill the Company Profile step from data the
        // user already entered during the welcome flow (BusinessProfileSetupView
        // writes a BusinessProfile row; older paths wrote company_* settings).
        // In-progress draft edits above take precedence — we only fill blanks.
        hydrateCompanyProfileFromExistingData(settingsService)
    }

    /// Fill the Step 1 company fields from the already-saved BusinessProfile (or
    /// legacy `company_*` settings) so the wizard reflects — rather than re-asks —
    /// what the user typed on the welcome screens. Only empty fields are filled,
    /// so a returning user's draft edits are never clobbered.
    private func hydrateCompanyProfileFromExistingData(_ settingsService: SettingsService) {
        let profile = (try? settingsService.getBusinessProfile()) ?? nil

        func fillIfBlank(_ field: inout String, _ candidates: [String?]) {
            guard field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let resolved = candidates
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let resolved { field = resolved }
        }

        fillIfBlank(&companyName, [profile?.companyName, (try? settingsService.getSettingValue("company_name")) ?? nil])
        fillIfBlank(&companyAddress, [profile?.address, (try? settingsService.getSettingValue("company_address")) ?? nil])
        fillIfBlank(&companyPhone, [profile?.phone, (try? settingsService.getSettingValue("company_phone")) ?? nil])
        fillIfBlank(&companyEmail, [profile?.email, (try? settingsService.getSettingValue("company_email")) ?? nil])
    }

    private func saveProgress() {
        let draft = SettingsService.CompanySetupDraft(
            currentStep: currentStep,
            completedSteps: completedSteps,
            skippedSteps: skippedSteps,
            name: companyName,
            address: companyAddress,
            phone: companyPhone,
            email: companyEmail,
            selectedState: selectedState
        )
        do {
            try appCore.settingsService?.saveSetupDraft(draft)
        } catch {
            logger.warning("saveSetupDraft failed — wizard progress may be lost on app switch: \(error.localizedDescription)")
        }
    }

    /// Remove draft row before marking setup complete.
    ///
    /// The completion flag hides this wizard and exposes the Dashboard checklist instead.
    /// Gate that flag on cleanup success so a stale setup draft cannot remain hidden after
    /// a failed delete.
    private func completeSetupAfterDraftCleanup() {
        guard let settingsService = appCore.settingsService else {
            saveError = "Settings are still loading. Please try again in a moment."
            return
        }

        do {
            try settingsService.deleteSetupDraft()
            hasCompletedCompanySetup = true
        } catch {
            saveError = userFriendlyError(error, context: "clear setup draft")
            logger.error("deleteSetupDraft failed; keeping company setup incomplete to avoid hiding a stale draft: \(error.localizedDescription)")
        }
    }
}
