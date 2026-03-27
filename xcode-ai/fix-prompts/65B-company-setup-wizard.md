# 65B — Company Setup Wizard

> **Chain position:** After 65A
> **Priority:** HIGH — new companies need guided data entry before the app is useful
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Create a guided setup wizard for NEW companies. When the database is empty after initial bootstrap and the user is an admin, walk them through the essential data entry needed before the app is useful. This is different from the user onboarding (65A) — this is about populating the company's data.

**Read these files first:**
- `Auth/OnboardingCompleteView.swift` — existing completion view
- `Auth/BusinessProfileSetupView.swift` — existing business profile form (may already handle Step 1)
- `Auth/AdminAccountSetupView.swift` — existing admin creation
- `Features/Dashboard/DashboardView.swift` — Getting Started checklist (should link to this wizard)
- `Features/People/IOSEmployeesPage.swift` — employee CRUD
- `Features/People/IOSHatsPage.swift` — hats/permissions
- `Features/Jobs/JobsListPage.swift` — job creation
- `Features/Parts/PartsImportExportPage.swift` — CSV import
- `Features/Warehouse/WarehouseOnboardingWizard.swift` — warehouse setup (linked from Step 6)
- `App/AppCore.swift` — services and auth state
- `core/Sources/WiredPartCore/Services/AuthService.swift` — user management
- `core/Sources/WiredPartCore/Services/PeopleService.swift` — employee/customer creation
- `core/Sources/WiredPartCore/Services/JobsService.swift` — job creation

## Architecture

### CompanySetupWizard.swift

Create `Auth/CompanySetupWizard.swift`:

```swift
import SwiftUI
import WiredPartCore

/// Guided 8-step company setup wizard for new businesses.
/// Shows after bootstrap when @AppStorage("hasCompletedCompanySetup") is false AND user is admin.
struct CompanySetupWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("hasCompletedCompanySetup") private var hasCompletedCompanySetup = false
    @AppStorage("companySetup_currentStep") private var currentStep = 0
    @AppStorage("companySetup_completedSteps") private var completedStepsData: Data = Data()

    @State private var completedSteps: Set<Int> = []
    @State private var skippedSteps: Set<Int> = []

    // Step 1: Company Profile
    @State private var companyName = ""
    @State private var companyAddress = ""
    @State private var companyPhone = ""
    @State private var companyEmail = ""

    // Step 2: Employees
    @State private var addedEmployeeCount = 0

    // Step 3: Hats
    @State private var hatsConfigured = false

    // Step 4: First Job
    @State private var firstJobCreated = false

    // Step 5: Parts
    @State private var partsAdded = false

    // Step 6: Warehouse
    @State private var warehouseConfigured = false

    // Step 7: Break/Lunch Policy
    @State private var selectedState = "California"
    @State private var breakPolicySet = false

    // Errors
    @State private var saveError: String?

    let totalSteps = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress header
                progressHeader

                // Step content
                ScrollView {
                    stepContent
                        .padding()
                }

                // Navigation footer
                navigationFooter
            }
            .navigationTitle("Company Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") {
                        saveProgress()
                        // Don't mark complete — they can come back
                    }
                }
            }
            .onAppear { loadProgress() }
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

            if let error = saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                saveCompanyProfile()
            } label: {
                Label("Save Company Profile", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(companyName.trimmingCharacters(in: .whitespaces).isEmpty)
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

            // Embed a simplified employee creation form
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Add Employee")
                    .font(.headline)

                @State var newFirstName = ""
                @State var newLastName = ""
                @State var newPin = ""

                labeledField("First Name", text: .constant(""), placeholder: "John")
                labeledField("Last Name", text: .constant(""), placeholder: "Smith")
                labeledField("4-Digit PIN", text: .constant(""), placeholder: "1234")

                Text("Tip: Use the Employees page later for full details (email, phone, skills, certifications).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

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
                        Text("Add parts one at a time from the catalog page. Best for small catalogs or adding items as you go.")
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

                // State picker (simplified — common states)
                Picker("State", selection: $selectedState) {
                    ForEach(["California", "Oregon", "Washington", "Nevada",
                             "Arizona", "Colorado", "Texas", "New York",
                             "Florida", "Illinois", "Other / Federal"], id: \.self) { state in
                        Text(state).tag(state)
                    }
                }
                .pickerStyle(.menu)

                // Show rules for selected state
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
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("You're Ready!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your company is set up and ready to use WiredPart.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Summary of what was done
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
                hasCompletedCompanySetup = true
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
                .font(.system(size: 48))
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
        guard !companyName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            // Save to settings via AppCore
            try appCore.settingsService?.updateSetting("company_name", value: companyName)
            try appCore.settingsService?.updateSetting("company_address", value: companyAddress)
            try appCore.settingsService?.updateSetting("company_phone", value: companyPhone)
            try appCore.settingsService?.updateSetting("company_email", value: companyEmail)
            completedSteps.insert(0)
            saveProgress()
            saveError = nil
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func saveBreakPolicy() {
        do {
            try appCore.settingsService?.updateSetting("break_policy_state", value: selectedState)
            breakPolicySet = true
            completedSteps.insert(6)
            saveProgress()
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func checkEmployeeCount() async {
        do {
            let employees = try appCore.peopleService?.listEmployees() ?? []
            addedEmployeeCount = employees.count - 1  // Exclude admin
            if addedEmployeeCount > 0 {
                completedSteps.insert(1)
                saveProgress()
            }
        } catch {}
    }

    private func checkJobCount() async {
        do {
            let jobs = try appCore.jobsService?.listJobs() ?? []
            firstJobCreated = !jobs.isEmpty
            if firstJobCreated {
                completedSteps.insert(3)
                saveProgress()
            }
        } catch {}
    }

    // MARK: - Persistence

    private func loadProgress() {
        if let data = UserDefaults.standard.data(forKey: "companySetup_completedSteps"),
           let saved = try? JSONDecoder().decode(Set<Int>.self, from: data) {
            completedSteps = saved
        }
        if let data = UserDefaults.standard.data(forKey: "companySetup_skippedSteps"),
           let saved = try? JSONDecoder().decode(Set<Int>.self, from: data) {
            skippedSteps = saved
        }
        // Load saved form data
        companyName = UserDefaults.standard.string(forKey: "companySetup_name") ?? ""
        companyAddress = UserDefaults.standard.string(forKey: "companySetup_address") ?? ""
        companyPhone = UserDefaults.standard.string(forKey: "companySetup_phone") ?? ""
        companyEmail = UserDefaults.standard.string(forKey: "companySetup_email") ?? ""
        selectedState = UserDefaults.standard.string(forKey: "companySetup_state") ?? "California"
    }

    private func saveProgress() {
        if let data = try? JSONEncoder().encode(completedSteps) {
            UserDefaults.standard.set(data, forKey: "companySetup_completedSteps")
        }
        if let data = try? JSONEncoder().encode(skippedSteps) {
            UserDefaults.standard.set(data, forKey: "companySetup_skippedSteps")
        }
        // Save form data for resume
        UserDefaults.standard.set(companyName, forKey: "companySetup_name")
        UserDefaults.standard.set(companyAddress, forKey: "companySetup_address")
        UserDefaults.standard.set(companyPhone, forKey: "companySetup_phone")
        UserDefaults.standard.set(companyEmail, forKey: "companySetup_email")
        UserDefaults.standard.set(selectedState, forKey: "companySetup_state")
    }
}
```

### Wiring Into the App

In `WiredPartIOSApp.swift` or the root view, show the wizard after bootstrap for admin users:

```swift
if appCore.isAuthenticated {
    if appCore.isAdmin && !hasCompletedCompanySetup {
        CompanySetupWizard()
            .environmentObject(appCore)
    } else if !hasCompletedOnboarding {
        OnboardingWalkthroughView()
            .environmentObject(appCore)
    } else {
        IOSMainView()
            .environmentObject(appCore)
    }
}
```

Order matters: company setup comes BEFORE user onboarding for admins. Non-admins skip company setup entirely.

### Dashboard Integration

In `DashboardView.swift`, the Getting Started checklist should link back to the wizard:

```swift
// Add a "Resume Setup" button if hasCompletedCompanySetup is false
if !hasCompletedCompanySetup && appCore.isAdmin {
    Button {
        showCompanySetupWizard = true
    } label: {
        Label("Resume Company Setup", systemImage: "arrow.right.circle.fill")
            .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .padding()
}
```

## Important Notes

- The wizard is admin-only. Non-admin users never see it.
- `@AppStorage("hasCompletedCompanySetup")` is per-device. If the admin sets up on iPad, the Mac will also ask — but it should detect existing data and auto-complete steps.
- Steps auto-detect completion: if employees exist, Step 2 is auto-marked done. If jobs exist, Step 4 is auto-marked done.
- Form data saves on every step change (so the admin can quit and resume).
- Step 6 (Warehouse) links to the existing `WarehouseOnboardingWizard` — it does NOT duplicate that flow.
- Step 7 (Break Policy) is a simplified version — just pick a state. Full customization is in Settings.
- The "Exit" button saves progress but does NOT mark complete. The wizard shows again next launch.
- The "Go to Dashboard" button on the final step marks `hasCompletedCompanySetup = true`.
- If `BusinessProfileSetupView.swift` already collects company name during bootstrap, coordinate — don't ask twice. Pre-populate Step 1 from existing data.

## Success Criteria

- [ ] `CompanySetupWizard.swift` created in `Auth/`
- [ ] 8 steps: Company Profile, Employees, Hats, First Job, Parts, Warehouse, Break Policy, Complete
- [ ] Shows only for admin users when `hasCompletedCompanySetup == false`
- [ ] Progress bar and step counter work
- [ ] "Skip for Now" available on every step
- [ ] "Back" button navigates to previous step
- [ ] Progress persists across app restarts (can resume)
- [ ] Step 1 saves company profile to settings
- [ ] Step 2 links to Employees page, auto-detects existing employees
- [ ] Step 4 links to Jobs page, auto-detects existing jobs
- [ ] Step 6 links to WarehouseOnboardingWizard
- [ ] Step 7 saves break policy state
- [ ] Completion screen shows summary with completed/skipped
- [ ] Dashboard shows "Resume Setup" button if not complete
- [ ] Wired into app root (admin sees this before user onboarding)
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 65B Results (YYYY-MM-DD)
- CompanySetupWizard: created with 8 steps
- Wired into app root for admin users
- Dashboard: Resume Setup button added
- Step 1 (Company Profile): saves to settings
- Step 2 (Employees): links to employees page
- Step 6 (Warehouse): links to warehouse wizard
- Step 7 (Break Policy): state picker + save
- Persistence: resume works across restarts
- Build: PASS/FAIL
```
