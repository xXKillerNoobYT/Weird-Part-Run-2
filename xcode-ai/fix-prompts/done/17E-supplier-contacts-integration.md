# 17E — Supplier Contacts → People Integration

> **Chain position:** 17A → 17B → 17C → 17D → **17E** → 17F–17H
> **Prerequisite:** 17D complete (supplier detail rebuilt)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Each supplier company has contacts (main contact, sales rep, accounts receivable, etc.). Currently the supplier record stores one contact name + one rep name inline — but there's no link to the People system. The `entity_contacts` table already exists (migration 014) with `entity_type`/`entity_id` polymorphic pattern, and `PeopleService.createContact()` exists.

We need to:
1. Show linked contacts from `entity_contacts` on the supplier detail page
2. Let users quickly add a new contact and link it to this supplier
3. Let users link an existing contact from the People system to this supplier
4. Support multiple contacts per supplier with different roles

**Key files:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift` — SupplierDetailSheet
- `core/Sources/WiredPartCore/Services/PeopleService.swift` — existing contact methods
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add supplier-contact helpers

## Task

### Step 1: Add supplier-contact service methods

In `PartsService.swift`, add methods to work with supplier contacts via the `entity_contacts` table:

```swift
// =========================================================================
// MARK: - 13. Supplier Contacts
// =========================================================================

/// A contact linked to a supplier via entity_contacts.
public struct SupplierContact: Sendable {
    public let contactId: Int64
    public let firstName: String
    public let lastName: String
    public let role: String?         // "Sales Rep", "Accounts Payable", "Owner", etc.
    public let phone: String?
    public let email: String?
    public let isPrimary: Int
}

/// Get all contacts linked to a supplier.
public func getSupplierContacts(supplierId: Int64) throws -> [SupplierContact] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT id, first_name, last_name, role, phone, email, is_primary
            FROM entity_contacts
            WHERE entity_type = 'supplier' AND entity_id = ? AND deleted_at IS NULL
            ORDER BY is_primary DESC, last_name ASC
            """, arguments: [supplierId])

        return rows.map { row in
            SupplierContact(
                contactId: row["id"],
                firstName: row["first_name"] ?? "",
                lastName: row["last_name"] ?? "",
                role: row["role"],
                phone: row["phone"],
                email: row["email"],
                isPrimary: row["is_primary"] ?? 0
            )
        }
    }
}

/// Quick-add a new contact and link to this supplier.
public func addSupplierContact(
    supplierId: Int64,
    firstName: String,
    lastName: String,
    role: String?,
    phone: String?,
    email: String?,
    isPrimary: Bool
) throws {
    try db.writer.write { dbConn in
        // If setting as primary, clear existing primary
        if isPrimary {
            try dbConn.execute(sql: """
                UPDATE entity_contacts SET is_primary = 0
                WHERE entity_type = 'supplier' AND entity_id = ? AND deleted_at IS NULL
                """, arguments: [supplierId])
        }
        try dbConn.execute(sql: """
            INSERT INTO entity_contacts (entity_type, entity_id, first_name, last_name, role, phone, email, is_primary, created_at)
            VALUES ('supplier', ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            """, arguments: [supplierId, firstName, lastName, role, phone, email, isPrimary ? 1 : 0])
    }
    try changeTracker?.trackChange(table: "entity_contacts", rowId: supplierId, changeType: "insert")
}

/// Remove a contact link from a supplier (soft delete).
public func removeSupplierContact(contactId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE entity_contacts SET deleted_at = datetime('now')
            WHERE id = ?
            """, arguments: [contactId])
    }
    try changeTracker?.trackChange(table: "entity_contacts", rowId: contactId, changeType: "update")
}
```

### Step 2: Add contacts section to SupplierDetailSheet

In the `SupplierDetailSheet` (from prompt 17D), add a contacts section between the rep section and the scores section. Add state:

```swift
@State private var contacts: [PartsService.SupplierContact] = []
@State private var showAddContact = false
```

Add the section:

```swift
// Section: Linked Contacts
contactsListSection
```

Add the view builder:

```swift
// MARK: - Contacts

@ViewBuilder
private var contactsListSection: some View {
    Section {
        if contacts.isEmpty {
            Text("No contacts linked yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(contacts, id: \.contactId) { contact in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(contact.firstName) \(contact.lastName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if contact.isPrimary == 1 {
                            Text("PRIMARY")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if let role = contact.role, !role.isEmpty {
                            Text(role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        if let phone = contact.phone, !phone.isEmpty {
                            Button {
                                let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                                if let url = URL(string: "tel:\(cleaned)") { UIApplication.shared.open(url) }
                            } label: {
                                Label(phone, systemImage: "phone.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        if let email = contact.email, !email.isEmpty {
                            Button {
                                if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                            } label: {
                                Label(email, systemImage: "envelope.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 44)
            }
        }
    } header: {
        HStack {
            Text("Contacts (\(contacts.count))")
            Spacer()
            Button {
                showAddContact = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
        }
    }
}
```

### Step 3: Add Quick Add Contact sheet

Add a simple form sheet for quickly adding a contact to a supplier. This should be presented via the same single `.sheet(item:)` pattern. Add a case to the detail sheet or use `.sheet(isPresented:)` since the detail sheet itself is already a sheet (only one `.sheet` per view).

Since `SupplierDetailSheet` is already inside a `.sheet`, we can use `.sheet(isPresented:$showAddContact)` here — this is a second-level sheet which is allowed.

```swift
private struct AddSupplierContactSheet: View {
    let supplierId: Int64
    let onSave: () -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var isPrimary = false
    @State private var saveError: String?
    @State private var isSaving = false

    private let commonRoles = ["", "Sales Rep", "Accounts Payable", "Accounts Receivable", "Owner", "Manager", "Shipping", "Returns", "Technical Support", "Other"]

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

                Section("Contact Info") {
                    TextField("First Name *", text: $firstName)
                        .frame(minHeight: 44)
                    TextField("Last Name *", text: $lastName)
                        .frame(minHeight: 44)
                    Picker("Role", selection: $role) {
                        ForEach(commonRoles, id: \.self) { r in
                            Text(r.isEmpty ? "Not Set" : r).tag(r)
                        }
                    }
                }

                Section("Contact Methods") {
                    TextField("Phone", text: $phone)
                        .frame(minHeight: 44)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .frame(minHeight: 44)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Toggle("Primary Contact", isOn: $isPrimary)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty
                              || lastName.trimmingCharacters(in: .whitespaces).isEmpty
                              || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
            }
            try service.addSupplierContact(
                supplierId: supplierId,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                role: role.isEmpty ? nil : role,
                phone: phone.isEmpty ? nil : phone,
                email: email.isEmpty ? nil : email,
                isPrimary: isPrimary
            )
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

### Step 4: Wire up the add contact sheet

In `SupplierDetailSheet`, add the sheet modifier at the end of the `NavigationStack`:

```swift
.sheet(isPresented: $showAddContact) {
    AddSupplierContactSheet(supplierId: supplier.id) {
        // Reload contacts after adding
        if let service = appCore.partsService {
            contacts = (try? service.getSupplierContacts(supplierId: supplier.id)) ?? []
        }
    }
    .environmentObject(appCore)
}
```

Update `loadAllDetails()` to also load contacts:

```swift
contacts = try service.getSupplierContacts(supplierId: supplier.id)
```

### Step 5: Add swipe-to-delete for contacts

On the `ForEach(contacts, ...)` in `contactsListSection`, add:

```swift
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        if let service = appCore.partsService {
            try? service.removeSupplierContact(contactId: contact.contactId)
            contacts.removeAll { $0.contactId == contact.contactId }
        }
    } label: {
        Label("Remove", systemImage: "trash")
    }
}
```

## Important Notes

- The `entity_contacts` table uses `entity_type = 'supplier'` and `entity_id = supplier.id` to link contacts.
- Common roles are predefined in a Picker for fast selection — saves typing on mobile.
- Primary contact toggle clears any existing primary when set (only one primary per supplier).
- Contacts are tappable for phone/email, just like the main supplier contact fields.
- This does NOT sync with the inline contact_name/rep_name fields on the supplier record itself. Those remain as quick-reference fields. The entity_contacts provide the detailed multi-contact system.

## Success Criteria

- [ ] `getSupplierContacts` returns contacts linked via entity_contacts
- [ ] `addSupplierContact` creates a new entity_contact for the supplier
- [ ] `removeSupplierContact` soft-deletes the contact link
- [ ] Detail sheet shows contacts section with add button
- [ ] Quick add form has name, role picker, phone, email, primary toggle
- [ ] Contacts show tappable phone/email
- [ ] Swipe-to-delete removes contacts
- [ ] Primary badge shown on primary contact
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17E Results (YYYY-MM-DD)
- Service: getSupplierContacts, addSupplierContact, removeSupplierContact
- Contacts section in SupplierDetailSheet with add/delete
- Role picker with 9 common roles
- Tappable phone/email on contacts
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 17F.**
