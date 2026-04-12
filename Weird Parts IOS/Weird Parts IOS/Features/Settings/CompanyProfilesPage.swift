import SwiftUI
import WiredPartCore

/// Fully functional company profiles management page.
///
/// Lists all company profiles and allows creating, editing, and
/// deleting profiles via SettingsService.
struct CompanyProfilesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var profiles: [CompanyProfile] = []
    private enum ActiveSheet: Identifiable {
        case help
        case create
        case edit(CompanyProfile)

        var id: String {
            switch self {
            case .help: "help"
            case .create: "create"
            case .edit(let p): "edit-\(p.id ?? 0)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var errorMessage: String?
    @State private var profileToDelete: CompanyProfile?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if profiles.isEmpty {
                Section {
                    Text("No company profiles yet. Tap + to create one.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(profiles, id: \.id) { profile in
                    Button {
                        activeSheet = .edit(profile)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(profile.companyName)
                                    .font(.headline)
                                if profile.isPrimary == 1 {
                                    Text("Primary")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            if let branch = profile.branchName {
                                Text(branch)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let phone = profile.phone {
                                Text(phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            profileToDelete = profile
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    activeSheet = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add company profile")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(title: "Company Profiles Help", sections: [
                    ("What This Page Does", "Manages your company profiles including company name, address, contact info, and licensing details. The primary profile appears on generated documents."),
                    ("How to Use It", "Tap + to create a new profile. Tap a profile to edit it. Swipe left to delete. Toggle 'Primary Profile' to set which profile appears on PDFs and official documents."),
                ])
            case .create:
                CompanyProfileEditor(profile: nil) { _ in
                    loadProfiles()
                    activeSheet = nil
                }
                .environmentObject(appCore)
            case .edit(let profile):
                CompanyProfileEditor(profile: profile) { _ in
                    loadProfiles()
                    activeSheet = nil
                }
                .environmentObject(appCore)
            }
        }
        .refreshable { loadProfiles() }
        .task { loadProfiles() }
        .alert("Delete Profile", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { profileToDelete = nil }
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete { deleteProfile(profile) }
                profileToDelete = nil
            }
        } message: {
            if let profile = profileToDelete {
                Text("Are you sure you want to delete \"\(profile.companyName)\"? This cannot be undone.")
            }
        }
    }

    private func loadProfiles() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            profiles = try service.listCompanyProfiles()
        } catch {
            errorMessage = userFriendlyError(error, context: "save company profile")
        }
    }

    private func deleteProfile(_ profile: CompanyProfile) {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        guard let id = profile.id else { return }
        do {
            try service.deleteCompanyProfile(id)
            loadProfiles()
        } catch {
            errorMessage = userFriendlyError(error, context: "save company profile")
        }
    }
}

// MARK: - Profile Editor

private struct CompanyProfileEditor: View {
    @EnvironmentObject private var appCore: AppCore
    let profile: CompanyProfile?
    let onSave: (CompanyProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var companyName = ""
    @State private var branchName = ""
    @State private var addressStreet = ""
    @State private var addressCity = ""
    @State private var addressState = ""
    @State private var addressZip = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""
    @State private var contractorLicense = ""
    @State private var taxId = ""
    @State private var isPrimary = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Company Info") {
                    TextField("Company Name", text: $companyName)
                    TextField("Branch Name (optional)", text: $branchName)
                    Toggle("Primary Profile", isOn: $isPrimary)
                }

                Section("Address") {
                    TextField("Street", text: $addressStreet)
                    TextField("City", text: $addressCity)
                    TextField("State", text: $addressState)
                    TextField("ZIP", text: $addressZip)
                }

                Section("Contact") {
                    TextField("Phone", text: $phone)
                    TextField("Email", text: $email)
                    TextField("Website", text: $website)
                }

                Section("Licensing") {
                    TextField("Contractor License", text: $contractorLicense)
                    TextField("Tax ID", text: $taxId)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(profile == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(companyName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { loadFromProfile() }
        }
    }

    private func loadFromProfile() {
        guard let p = profile else { return }
        companyName = p.companyName
        branchName = p.branchName ?? ""
        addressStreet = p.addressStreet ?? ""
        addressCity = p.addressCity ?? ""
        addressState = p.addressState ?? ""
        addressZip = p.addressZip ?? ""
        phone = p.phone ?? ""
        email = p.email ?? ""
        website = p.website ?? ""
        contractorLicense = p.contractorLicense ?? ""
        taxId = p.taxId ?? ""
        isPrimary = p.isPrimary == 1
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        var record = CompanyProfile(
            id: profile?.id,
            companyName: companyName.trimmingCharacters(in: .whitespaces),
            addressStreet: addressStreet.isEmpty ? nil : addressStreet,
            addressCity: addressCity.isEmpty ? nil : addressCity,
            addressState: addressState.isEmpty ? nil : addressState,
            addressZip: addressZip.isEmpty ? nil : addressZip,
            phone: phone.isEmpty ? nil : phone,
            email: email.isEmpty ? nil : email,
            website: website.isEmpty ? nil : website,
            contractorLicense: contractorLicense.isEmpty ? nil : contractorLicense,
            insuranceInfo: profile?.insuranceInfo,
            taxId: taxId.isEmpty ? nil : taxId,
            isPrimary: isPrimary ? 1 : 0,
            branchName: branchName.isEmpty ? nil : branchName,
            notes: profile?.notes,
            deletedAt: nil,
            createdAt: profile?.createdAt,
            updatedAt: nil
        )

        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            if profile?.id != nil {
                try service.updateCompanyProfile(record)
            } else {
                let newId = try service.createCompanyProfile(record)
                record.id = newId
            }
            onSave(record)
        } catch {
            errorMessage = userFriendlyError(error, context: "save company profile")
        }
    }
}
