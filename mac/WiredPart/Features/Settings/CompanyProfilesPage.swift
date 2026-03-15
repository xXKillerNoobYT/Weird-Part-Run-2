import SwiftUI
import WiredPartCore

/// Company profiles management page.
///
/// Fully functional — CRUD operations via SettingsService.
/// Lists all profiles with inline add/edit/delete.
struct CompanyProfilesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var profiles: [CompanyProfile] = []
    @State private var isEditing: Bool = false
    @State private var editingProfile: CompanyProfile? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var deleteTarget: CompanyProfile? = nil

    // Form fields
    @State private var formName: String = ""
    @State private var formStreet: String = ""
    @State private var formCity: String = ""
    @State private var formState: String = ""
    @State private var formZip: String = ""
    @State private var formPhone: String = ""
    @State private var formEmail: String = ""
    @State private var formWebsite: String = ""
    @State private var formLicense: String = ""
    @State private var formInsurance: String = ""
    @State private var formTaxId: String = ""
    @State private var formBranch: String = ""
    @State private var formNotes: String = ""
    @State private var formIsPrimary: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Company Profiles")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    Button {
                        startNewProfile()
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if isEditing {
                    editForm
                }

                // Profile List
                ForEach(profiles, id: \.id) { profile in
                    profileCard(profile)
                }

                if profiles.isEmpty && !isEditing {
                    Text("No company profiles yet. Add one to get started.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadProfiles() }
        .alert("Delete Profile", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget, let id = target.id {
                    try? appCore.settingsService?.deleteCompanyProfile(id)
                    loadProfiles()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this company profile?")
        }
    }

    // MARK: - Profile Card

    private func profileCard(_ profile: CompanyProfile) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(profile.companyName)
                        .font(.headline)
                    if profile.isPrimary == 1 {
                        Text("PRIMARY")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.15)))
                            .foregroundStyle(.blue)
                    }
                    if let branch = profile.branchName, !branch.isEmpty {
                        Text(branch)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        startEditing(profile)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    Button {
                        deleteTarget = profile
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                if let street = profile.addressStreet {
                    Text([street, profile.addressCity, profile.addressState, profile.addressZip]
                        .compactMap { $0 }
                        .joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    if let phone = profile.phone { Label(phone, systemImage: "phone").font(.caption) }
                    if let email = profile.email { Label(email, systemImage: "envelope").font(.caption) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Edit Form

    private var editForm: some View {
        GroupBox(editingProfile == nil ? "New Company Profile" : "Edit Company Profile") {
            VStack(alignment: .leading, spacing: 12) {
                formField("Company Name", text: $formName)
                formField("Branch Name", text: $formBranch)

                Divider()
                Text("Address").font(.caption).foregroundStyle(.secondary)
                formField("Street", text: $formStreet)
                HStack(spacing: 8) {
                    formField("City", text: $formCity)
                    formField("State", text: $formState).frame(maxWidth: 100)
                    formField("ZIP", text: $formZip).frame(maxWidth: 100)
                }

                Divider()
                Text("Contact").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    formField("Phone", text: $formPhone)
                    formField("Email", text: $formEmail)
                }
                formField("Website", text: $formWebsite)

                Divider()
                Text("Business Info").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    formField("Contractor License", text: $formLicense)
                    formField("Tax ID", text: $formTaxId)
                }
                formField("Insurance Info", text: $formInsurance)

                Divider()
                formField("Notes", text: $formNotes)
                Toggle("Primary Profile", isOn: $formIsPrimary)

                HStack {
                    Button("Save") { saveProfile() }
                        .buttonStyle(.borderedProminent)
                        .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { isEditing = false }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func formField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func loadProfiles() {
        guard let settings = appCore.settingsService else { return }
        profiles = (try? settings.listCompanyProfiles()) ?? []
    }

    private func startNewProfile() {
        editingProfile = nil
        clearForm()
        isEditing = true
    }

    private func startEditing(_ profile: CompanyProfile) {
        editingProfile = profile
        formName = profile.companyName
        formStreet = profile.addressStreet ?? ""
        formCity = profile.addressCity ?? ""
        formState = profile.addressState ?? ""
        formZip = profile.addressZip ?? ""
        formPhone = profile.phone ?? ""
        formEmail = profile.email ?? ""
        formWebsite = profile.website ?? ""
        formLicense = profile.contractorLicense ?? ""
        formInsurance = profile.insuranceInfo ?? ""
        formTaxId = profile.taxId ?? ""
        formBranch = profile.branchName ?? ""
        formNotes = profile.notes ?? ""
        formIsPrimary = profile.isPrimary == 1
        isEditing = true
    }

    private func clearForm() {
        formName = ""; formStreet = ""; formCity = ""; formState = ""; formZip = ""
        formPhone = ""; formEmail = ""; formWebsite = ""; formLicense = ""
        formInsurance = ""; formTaxId = ""; formBranch = ""; formNotes = ""
        formIsPrimary = false
    }

    private func saveProfile() {
        guard let settings = appCore.settingsService else { return }

        var profile = editingProfile ?? CompanyProfile(
            id: nil, companyName: "", addressStreet: nil, addressCity: nil,
            addressState: nil, addressZip: nil, phone: nil, email: nil,
            website: nil, contractorLicense: nil, insuranceInfo: nil,
            taxId: nil, isPrimary: 0, branchName: nil, notes: nil,
            deletedAt: nil, createdAt: nil, updatedAt: nil
        )
        profile.companyName = formName.trimmingCharacters(in: .whitespaces)
        profile.addressStreet = formStreet.isEmpty ? nil : formStreet
        profile.addressCity = formCity.isEmpty ? nil : formCity
        profile.addressState = formState.isEmpty ? nil : formState
        profile.addressZip = formZip.isEmpty ? nil : formZip
        profile.phone = formPhone.isEmpty ? nil : formPhone
        profile.email = formEmail.isEmpty ? nil : formEmail
        profile.website = formWebsite.isEmpty ? nil : formWebsite
        profile.contractorLicense = formLicense.isEmpty ? nil : formLicense
        profile.insuranceInfo = formInsurance.isEmpty ? nil : formInsurance
        profile.taxId = formTaxId.isEmpty ? nil : formTaxId
        profile.branchName = formBranch.isEmpty ? nil : formBranch
        profile.notes = formNotes.isEmpty ? nil : formNotes
        profile.isPrimary = formIsPrimary ? 1 : 0

        if profile.id != nil {
            try? settings.updateCompanyProfile(profile)
        } else {
            _ = try? settings.createCompanyProfile(profile)
        }

        isEditing = false
        loadProfiles()
    }
}
