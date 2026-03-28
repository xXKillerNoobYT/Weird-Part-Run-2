import SwiftUI
import WiredPartCore

/// Company profile setup form — first step of the "Create New Business" path.
///
/// Collects business name (required), industry, address, contact info.
/// On submit, creates a `BusinessProfile` row and navigates to admin account setup.
struct BusinessProfileSetupView: View {
    @EnvironmentObject private var appCore: AppCore

    // Required
    @State private var companyName = ""

    // Optional details
    @State private var industry = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""

    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var navigateToAdmin = false

    private var isValid: Bool {
        !companyName.trimmingCharacters(in: .whitespaces).isEmpty
            && !industry.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Your Business")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Tell us about your company. You can update this later in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("* Required fields")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 16)

                // Company Name (Required)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Company Name *")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Smith Electrical", text: $companyName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.organizationName)
                }
                .padding(.horizontal, 24)

                // Industry (Required)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Industry *")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Electrical, Plumbing, HVAC", text: $industry)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 24)

                // Address Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Address")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("Street Address", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.streetAddressLine1)
                    HStack(spacing: 8) {
                        TextField("City", text: $city)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.addressCity)
                        TextField("State", text: $state)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.addressState)
                            .frame(width: 80)
                        TextField("ZIP", text: $zip)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.postalCode)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                    }
                }
                .padding(.horizontal, 24)

                // Contact Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("Phone", text: $phone)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Website", text: $website)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 24)

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Continue Button
                Button {
                    saveProfile()
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: 300)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isLoading)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Business Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToAdmin) {
            AdminAccountSetupView()
                .environmentObject(appCore)
        }
    }

    // MARK: - Actions

    private func saveProfile() {
        isLoading = true
        errorMessage = nil

        let profile = BusinessProfile(
            companyName: companyName.trimmingCharacters(in: .whitespaces),
            industry: industry.isEmpty ? nil : industry,
            address: address.isEmpty ? nil : address,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            zip: zip.isEmpty ? nil : zip,
            phone: phone.isEmpty ? nil : phone,
            email: email.isEmpty ? nil : email,
            website: website.isEmpty ? nil : website,
            isActive: 1
        )

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            do {
                guard let settingsService = appCore.settingsService else {
                    errorMessage = "Settings service not available. Please restart the app."
                    isLoading = false
                    return
                }
                _ = try settingsService.createBusinessProfile(profile)
                navigateToAdmin = true
            } catch {
                errorMessage = userFriendlyError(error, context: "save profile")
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        BusinessProfileSetupView()
            .environmentObject(AppCore())
    }
}
