# 17B — Supplier Form Rebuild: All Fields Editable

> **Chain position:** 17A → **17B** → 17C → 17D–17H
> **Prerequisite:** 17A complete (account_number column exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The current `SupplierFormSheet` in `PartsSuppliersPage.swift` only allows editing 7 fields (name, contact name, email, phone, address, website, notes). But the Supplier model has 15+ fields. Users need to edit: rep name, rep email, rep phone, delivery method, delivery days, account number, and active status.

**Key file:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift` — the `SupplierFormSheet` struct (lines ~342–479)

## Task

### Step 1: Rebuild SupplierFormSheet with all fields

Replace the existing `SupplierFormSheet` with an expanded version. Keep the same save pattern but add all editable fields organized into logical sections:

```swift
private struct SupplierFormSheet: View {
    let supplier: SupplierListRow?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Basic info
    @State private var name = ""
    @State private var accountNumber = ""
    @State private var isActive = true

    // Main contact
    @State private var contactName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var website = ""

    // Sales rep
    @State private var repName = ""
    @State private var repEmail = ""
    @State private var repPhone = ""

    // Delivery
    @State private var deliveryMethod = ""
    @State private var deliveryDays = ""

    // Notes
    @State private var notes = ""

    // Save state
    @State private var saveError: String?
    @State private var isSaving = false

    private let deliveryMethods = ["", "Pickup", "Delivery", "UPS", "FedEx", "USPS", "Freight", "Will Call", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                // Section 1: Basic Info
                Section("Supplier Details") {
                    TextField("Supplier Name *", text: $name)
                        .frame(minHeight: 44)
                    TextField("Account Number", text: $accountNumber)
                        .frame(minHeight: 44)
                    if supplier != nil {
                        Toggle("Active", isOn: $isActive)
                    }
                }

                // Section 2: Main Contact
                Section("Main Contact") {
                    TextField("Contact Name", text: $contactName)
                        .frame(minHeight: 44)
                    TextField("Email", text: $email)
                        .frame(minHeight: 44)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $phone)
                        .frame(minHeight: 44)
                        .keyboardType(.phonePad)
                    TextField("Address", text: $address)
                        .frame(minHeight: 44)
                    TextField("Website", text: $website)
                        .frame(minHeight: 44)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                // Section 3: Sales Rep
                Section("Sales Representative") {
                    TextField("Rep Name", text: $repName)
                        .frame(minHeight: 44)
                    TextField("Rep Email", text: $repEmail)
                        .frame(minHeight: 44)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Rep Phone", text: $repPhone)
                        .frame(minHeight: 44)
                        .keyboardType(.phonePad)
                }

                // Section 4: Delivery
                Section("Delivery Info") {
                    Picker("Delivery Method", selection: $deliveryMethod) {
                        ForEach(deliveryMethods, id: \.self) { method in
                            Text(method.isEmpty ? "Not Set" : method).tag(method)
                        }
                    }
                    TextField("Delivery Days (e.g. Mon-Fri, Next Day)", text: $deliveryDays)
                        .frame(minHeight: 44)
                }

                // Section 5: Notes
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(supplier == nil ? "New Supplier" : "Edit Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let s = supplier {
                    name = s.name
                    accountNumber = s.accountNumber ?? ""
                    isActive = s.isActive == 1
                    contactName = s.contactName ?? ""
                    email = s.email ?? ""
                    phone = s.phone ?? ""
                    address = s.address ?? ""
                    website = s.website ?? ""
                    repName = s.repName ?? ""
                    repEmail = s.repEmail ?? ""
                    repPhone = s.repPhone ?? ""
                    deliveryMethod = s.deliveryMethod ?? ""
                    deliveryDays = s.deliveryDays ?? ""
                    notes = s.notes ?? ""
                }
            }
        }
    }

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            try await save()
            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Supplier name is required"])
        }
        guard let service = appCore.partsService else {
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }
        if let s = supplier {
            try service.updateSupplier(
                id: s.id,
                name: trimmedName,
                contactName: contactName.isEmpty ? nil : contactName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                address: address.isEmpty ? nil : address,
                website: website.isEmpty ? nil : website,
                repName: repName.isEmpty ? nil : repName,
                repEmail: repEmail.isEmpty ? nil : repEmail,
                repPhone: repPhone.isEmpty ? nil : repPhone,
                deliveryMethod: deliveryMethod.isEmpty ? nil : deliveryMethod,
                deliveryDays: deliveryDays.isEmpty ? nil : deliveryDays,
                accountNumber: accountNumber.isEmpty ? nil : accountNumber,
                isActive: isActive ? 1 : 0,
                notes: notes.isEmpty ? nil : notes
            )
        } else {
            try service.createSupplier(
                name: trimmedName,
                contactName: contactName.isEmpty ? nil : contactName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                address: address.isEmpty ? nil : address,
                website: website.isEmpty ? nil : website,
                repName: repName.isEmpty ? nil : repName,
                repEmail: repEmail.isEmpty ? nil : repEmail,
                repPhone: repPhone.isEmpty ? nil : repPhone,
                deliveryMethod: deliveryMethod.isEmpty ? nil : deliveryMethod,
                deliveryDays: deliveryDays.isEmpty ? nil : deliveryDays,
                accountNumber: accountNumber.isEmpty ? nil : accountNumber,
                notes: notes.isEmpty ? nil : notes
            )
        }
    }
}
```

### Step 2: Add `accountNumber` to SupplierListRow

In the `SupplierListRow` struct, add:

```swift
let accountNumber: String?
```

Update the `loadData()` mapping to include it:

```swift
accountNumber: s.accountNumber,
```

### Step 3: Update PartsService.updateSupplier / createSupplier

Check the existing `updateSupplier` and `createSupplier` methods in `PartsService.swift`. They may not accept all the new parameters (repName, repEmail, repPhone, deliveryMethod, deliveryDays, accountNumber, isActive). Add any missing parameters.

For `updateSupplier`, ensure it includes:
```swift
public func updateSupplier(
    id: Int64,
    name: String,
    contactName: String? = nil,
    email: String? = nil,
    phone: String? = nil,
    address: String? = nil,
    website: String? = nil,
    repName: String? = nil,
    repEmail: String? = nil,
    repPhone: String? = nil,
    deliveryMethod: String? = nil,
    deliveryDays: String? = nil,
    accountNumber: String? = nil,
    isActive: Int? = nil,
    notes: String? = nil
) throws
```

For `createSupplier`, ensure all optional fields are accepted and written.

### Step 4: Make phone numbers and emails tappable

In the `supplierRow` view and `SupplierDetailSheet`, wrap phone numbers and emails with tappable links:

For phone numbers:
```swift
if let phone = supplier.phone, !phone.isEmpty {
    Button {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if let url = URL(string: "tel:\(cleaned)") {
            UIApplication.shared.open(url)
        }
    } label: {
        Label(phone, systemImage: "phone.fill")
            .font(.caption)
            .foregroundStyle(.blue)
    }
    .buttonStyle(.plain)
}
```

For emails:
```swift
if let email = supplier.email, !email.isEmpty {
    Button {
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    } label: {
        Label(email, systemImage: "envelope.fill")
            .font(.caption)
            .foregroundStyle(.blue)
    }
    .buttonStyle(.plain)
}
```

Apply the same pattern in the `SupplierDetailSheet` for all phone/email fields (main contact, rep).

### Step 5: Show account number in the list row

In `supplierRow`, after the contact info HStack, add:

```swift
if let acct = supplier.accountNumber, !acct.isEmpty {
    Label("Acct: \(acct)", systemImage: "number")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

## Important Notes

- The `#if os(iOS)` guards around `.keyboardType` and `.textInputAutocapitalization` can be removed since this is an iOS-only app now.
- The `updateSupplier` service method may need to be checked — it might use positional arguments or a builder pattern. Match whatever pattern exists.
- When calling `UIApplication.shared.open(url)` for tel: and mailto: links, SwiftUI needs `import UIKit` implicitly (available via SwiftUI on iOS).

## Success Criteria

- [ ] All 15 Supplier fields editable in the form (name, account#, contact, email, phone, address, website, rep name/email/phone, delivery method/days, active toggle, notes)
- [ ] Delivery method uses a Picker with preset options
- [ ] Account number shown in list row
- [ ] Phone numbers tappable → opens phone app
- [ ] Emails tappable → opens mail app
- [ ] Service methods accept all new parameters
- [ ] `SupplierListRow` includes accountNumber
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17B Results (YYYY-MM-DD)
- SupplierFormSheet rebuilt: 15 editable fields in 5 sections
- Tappable phone/email with tel:/mailto: URL schemes
- Account number in list row and form
- Service methods updated for all fields
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 17C.**
