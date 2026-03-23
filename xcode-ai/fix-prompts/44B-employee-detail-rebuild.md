# 44B — Employee Detail GRDB Removal + Rebuild

> **Chain position:** **44B** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. ALL database operations go through service layer

## Instructions

**IMPORTANT:** Before implementing, read `IOSEmployeeDetailPage.swift` and `PeopleService.swift`. Remove all `import GRDB` and raw SQL. Use the service layer for all edits. Add hat visibility rules and edit sheet.

## Context

IOSEmployeeDetailPage currently has `import GRDB` and uses raw SQL UPDATE statements to modify employee records directly. This bypasses the service layer, skips change tracking, and won't sync. It also needs hat visibility rules: employees can see their own hats but can't change them; managers can toggle hat assignments.

## Task

### Step 1: Remove `import GRDB` and Raw SQL

Search `IOSEmployeeDetailPage.swift` for:
- `import GRDB` — remove
- Any `try db.write` or `try db.read` — replace with service calls
- Any raw SQL strings — replace with service methods

### Step 2: Add Service Methods

```swift
// In PeopleService:

/// Update employee contact details
func updateEmployeeContact(
    employeeId: Int64,
    phone: String?,
    email: String?,
    address: String?,
    emergencyContact: String?,
    emergencyPhone: String?
) async throws

/// Get employee's assigned hats
func getEmployeeHats(employeeId: Int64) async throws -> [Hat]

/// Toggle hat assignment (manager only)
func toggleHatAssignment(employeeId: Int64, hatId: Int64, assign: Bool) async throws

/// Check if current user can manage this employee's hats
func canManageHats(forEmployeeId: Int64, currentUserId: Int64) async throws -> Bool
```

### Step 3: Hat Visibility Rules

```swift
// Hat display section
Section {
    ForEach(employeeHats) { hat in
        HStack {
            Text(hat.name)
            Spacer()
            if canManageHats {
                Toggle("", isOn: hatBinding(for: hat))
                    .labelsHidden()
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
            }
        }
    }
} header: {
    Text("Hats & Roles")
} footer: {
    if !canManageHats {
        Text("Contact a manager to change hat assignments")
    }
}
```

### Step 4: Edit Contact Details Sheet

```swift
private enum ActiveSheet: Identifiable {
    case editContact
    case editSkills

    var id: String { "\(self)" }
}

// Edit contact sheet
struct EditEmployeeContactSheet: View {
    @State var phone: String
    @State var email: String
    @State var address: String
    @State var emergencyContact: String
    @State var emergencyPhone: String
    let onSave: (String?, String?, String?, String?, String?) async throws -> Void
    @State private var saveError: String?
    @State private var isSaving = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section("Contact") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                    TextField("Address", text: $address)
                }
                Section("Emergency Contact") {
                    TextField("Name", text: $emergencyContact)
                    TextField("Phone", text: $emergencyPhone)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle("Edit Contact Info")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            do {
                                try await onSave(phone, email, address, emergencyContact, emergencyPhone)
                                dismiss()
                            } catch {
                                saveError = error.localizedDescription
                            }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
```

## Important Notes
- `import GRDB` must be completely removed — zero raw database access in UI files
- The service layer handles change tracking for sync
- Employees viewing their OWN profile can see hats but not toggle them
- Managers (with `manage_people` permission) can toggle hat assignments
- The edit sheet is for contact details only — name changes may require admin
- Emergency contact info is important for field workers (safety)

## Success Criteria
- [ ] `import GRDB` removed from IOSEmployeeDetailPage.swift
- [ ] Zero raw SQL statements remain
- [ ] All edits go through PeopleService methods
- [ ] Hat section shows assigned hats with toggle for managers
- [ ] Non-managers see hats as read-only
- [ ] Edit contact details sheet with save/error handling
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 44B Results (YYYY-MM-DD)
- Removed import GRDB + raw SQL from IOSEmployeeDetailPage
- X service methods added to PeopleService
- Hat visibility rules: manager toggle, employee read-only
- Edit contact sheet added
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
