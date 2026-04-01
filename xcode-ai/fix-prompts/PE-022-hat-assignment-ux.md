# PE-022 — Hat Assignment & Access Control UX

> **Plan:** `docs/plans/ios-hat-assignment-ux.md`
> **GitHub Issue:** [#17](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/17)
> **Priority:** High — owner cannot manage user access without this working intuitively

---

```
┌─────────────────────────────────────────────────────────────────┐
│  BEFORE WRITING ANY CODE: Read `xcode-ai/xcode.md` first.      │
│  It contains the patterns, rules, and standards for this project.│
│  Also log your result to `xcode-ai/prompt-results-log.md`.      │
└─────────────────────────────────────────────────────────────────┘
```

---

## What to Change (3 files)

1. **`Weird Parts IOS/Weird Parts IOS/Features/People/IOSHatsPage.swift`**
   — Make hat rows tappable. Add `HatDetailSheet` and `AddEmployeeToHatSheet` private structs.

2. **`Weird Parts IOS/Weird Parts IOS/Features/People/IOSPeopleDashboardPage.swift`**
   — Add a "Management" section with Hats & Roles + Permissions tiles (visible only to `manage_people` users).

3. **`Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeeDetailPage.swift`**
   — Add a "Permissions Granted" section to the Hats tab showing the combined permissions from all assigned hats.

---

## Core Types (already exist — do not create)

```swift
// PeopleService.HatListItem (the model used in IOSHatsPage)
public struct HatListItem: Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let userCount: Int
}

// PeopleService.HatMember (returned by getHatMembers)
public struct HatMember: Sendable, Identifiable {
    public let id: Int64
    public let displayName: String
    public let phone: String?
    public let email: String?
    public let assignedAt: String?
}

// PeopleService.EmployeeListItem (used in listEmployees())
public struct EmployeeListItem: Sendable, Identifiable {
    public let id: Int64
    public let displayName: String
    public let email: String
    public let phone: String?
    public let status: String
    public let role: String
    public let hatNames: String?
}

// PeopleService.HatInfo (used in IOSEmployeeDetailPage allHats array)
// Each element is (hat: HatInfo, isAssigned: Bool)
```

## Core Methods (already exist in WiredPartCore — do not create)

```swift
// PeopleService
appCore.peopleService?.getHatMembers(hatId: Int64)    throws -> [HatMember]
appCore.peopleService?.listEmployees()                 throws -> [EmployeeListItem]
appCore.peopleService?.toggleHatAssignment(employeeId: Int64, hatId: Int64, assign: Bool) throws

// AuthService
appCore.authService?.getHatPermissions(_ hatId: Int64) throws -> [String]

// AppCore
appCore.hasPermission("permission_key") -> Bool   // checks the CURRENT logged-in user's permissions
```

---

## File 1: IOSHatsPage.swift

### Change A — Update ActiveSheet to support hat detail

Replace the current `ActiveSheet` enum (which only has `addHat` and `help`) with one that also handles `.hatDetail`:

```swift
private enum ActiveSheet: Identifiable {
    case addHat
    case help
    case hatDetail(PeopleService.HatListItem)
    var id: String {
        switch self {
        case .addHat:            return "addHat"
        case .help:              return "help"
        case .hatDetail(let h):  return "hat-\(h.id)"
        }
    }
}
```

### Change B — Make hat rows tappable

In `hatList`, change the `List(filteredHats, id: \.id) { hat in` content from plain `hatRow(hat)` to a button that opens the detail sheet:

```swift
List(filteredHats, id: \.id) { hat in
    Button { activeSheet = .hatDetail(hat) } label: {
        hatRow(hat)
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing) {
        Button(role: .destructive) {
            hatToDelete = hat
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
```

### Change C — Add `.hatDetail` case to the sheet switch

In the `.sheet(item: $activeSheet)` block, add:

```swift
case .hatDetail(let hat):
    HatDetailSheet(hat: hat) { loadData() }
        .environmentObject(appCore)
```

### Change D — Add HatDetailSheet private struct (add at bottom of file)

```swift
// MARK: - Hat Detail Sheet

private struct HatDetailSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let hat: PeopleService.HatListItem
    let onChanged: () -> Void

    @State private var members: [PeopleService.HatMember] = []
    @State private var permissions: [String] = []
    @State private var canManageHats = false
    @State private var isLoading = true
    @State private var showAddPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // Members section
                Section {
                    if isLoading {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity)
                    } else if members.isEmpty {
                        Text("No employees assigned to this hat yet.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(members) { member in
                            HStack(spacing: 12) {
                                NavigationLink(destination: IOSEmployeeDetailPage(employeeId: member.id)
                                    .environmentObject(appCore)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        if let phone = member.phone, !phone.isEmpty {
                                            Text(phone)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                if canManageHats {
                                    Spacer()
                                    Button(role: .destructive) {
                                        removeMember(member)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Remove \(member.displayName) from hat")
                                }
                            }
                        }
                    }
                    if canManageHats {
                        Button {
                            showAddPicker = true
                        } label: {
                            Label("Add Employee", systemImage: "plus.circle")
                                .frame(minHeight: 44)
                        }
                    }
                } header: {
                    Text("Members (\(members.count))")
                }

                // Permissions summary section
                if !permissions.isEmpty {
                    Section {
                        let displayed = Array(permissions.prefix(5))
                        ForEach(displayed, id: \.self) { perm in
                            HStack {
                                Image(systemName: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .accessibilityHidden(true)
                                Text(permissionLabel(perm))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if permissions.count > 5 {
                            Text("…and \(permissions.count - 5) more permissions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        NavigationLink(destination: IOSPermissionsPage()
                            .environmentObject(appCore)) {
                            Label("Edit Permissions", systemImage: "lock.shield.fill")
                                .frame(minHeight: 44)
                        }
                    } header: {
                        Text("Permissions (\(permissions.count))")
                    }
                }

                // Error message (if any)
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(hat.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { loadData() }
            .sheet(isPresented: $showAddPicker) {
                AddEmployeeToHatSheet(hat: hat, currentMembers: members) {
                    loadData()
                    onChanged()
                }
                .environmentObject(appCore)
            }
        }
    }

    private func permissionLabel(_ key: String) -> String {
        key.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }

    private func removeMember(_ member: PeopleService.HatMember) {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        do {
            try service.toggleHatAssignment(employeeId: member.id, hatId: hat.id, assign: false)
            loadData()
            onChanged()
        } catch {
            errorMessage = userFriendlyError(error, context: "remove from hat")
        }
    }

    private func loadData() {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            isLoading = false
            return
        }
        canManageHats = appCore.hasPermission("manage_hats")
        errorMessage = nil
        do {
            members = try service.getHatMembers(hatId: hat.id)
            if let auth = appCore.authService {
                permissions = (try? auth.getHatPermissions(hat.id)) ?? []
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "load hat details")
        }
        isLoading = false
    }
}
```

### Change E — Add AddEmployeeToHatSheet private struct (add after HatDetailSheet)

```swift
// MARK: - Add Employee to Hat Sheet

private struct AddEmployeeToHatSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let hat: PeopleService.HatListItem
    let currentMembers: [PeopleService.HatMember]
    let onAdded: () -> Void

    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var unassigned: [PeopleService.EmployeeListItem] {
        let memberIds = Set(currentMembers.map(\.id))
        let available = employees.filter { !memberIds.contains($0.id) }
        guard !searchText.isEmpty else { return available }
        let query = searchText.lowercased()
        return available.filter { $0.displayName.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if unassigned.isEmpty && searchText.isEmpty {
                    ContentUnavailableView(
                        "All Employees Assigned",
                        systemImage: "graduationcap.fill",
                        description: Text("Every active employee already has this hat.")
                    )
                } else if unassigned.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(unassigned) { employee in
                        Button {
                            addEmployee(employee)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(employee.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if !employee.email.isEmpty {
                                    Text(employee.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search employees...")
            .navigationTitle("Add to \(hat.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { loadEmployees() }
        }
    }

    private func addEmployee(_ employee: PeopleService.EmployeeListItem) {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        do {
            try service.toggleHatAssignment(employeeId: employee.id, hatId: hat.id, assign: true)
            onAdded()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "assign hat")
        }
    }

    private func loadEmployees() {
        guard let service = appCore.peopleService else { return }
        employees = (try? service.listEmployees()) ?? []
    }
}
```

---

## File 2: IOSPeopleDashboardPage.swift

### Change A — Add canManagePeople state

Add to the existing `@State` properties at the top of `IOSPeopleDashboardPage`:

```swift
@State private var canManagePeople = false
```

### Change B — Set canManagePeople in loadData()

Inside `loadData()`, add this line (it doesn't throw, so place it anywhere before the `do` block or at the start):

```swift
canManagePeople = appCore.hasPermission("manage_people")
```

### Change C — Add Management section to dashboardContent

In `dashboardContent`, add a "Management" section as the FIRST section inside the `List`, BEFORE the smart cards section:

```swift
// Management section (manage_people users only)
if canManagePeople {
    Section {
        NavigationLink(destination: IOSHatsPage().environmentObject(appCore)) {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hats & Roles")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Assign roles to employees")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
        }
        NavigationLink(destination: IOSPermissionsPage().environmentObject(appCore)) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Configure what each hat can access")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
        }
    } header: {
        Text("Management")
    }
}
```

---

## File 3: IOSEmployeeDetailPage.swift

### Change A — Add hatPermissions state variable

Add to the existing `@State` properties (near `allHats` and `canManageHats`):

```swift
@State private var combinedPermissions: [String] = []
```

### Change B — Load permissions in loadData()

At the end of `loadData()`, after `allHats` and `canManageHats` are set, add:

```swift
// Collect permissions from all assigned hats
if let auth = appCore.authService {
    let assignedHatIds = allHats.filter(\.isAssigned).map(\.hat.id)
    var perms = Set<String>()
    for hatId in assignedHatIds {
        let keys = (try? auth.getHatPermissions(hatId)) ?? []
        keys.forEach { perms.insert($0) }
    }
    combinedPermissions = perms.sorted()
}
```

The existing `loadData()` currently ends with:
```swift
allHats = try service.getAllHatsWithAssignment(employeeId: employeeId)
canManageHats = appCore.hasPermission("manage_people")
```
Add the new block right after `canManageHats = ...`.

### Change C — Add "Permissions Granted" section to hatsTab

In `hatsTab(_:)`, add a new section AFTER the existing hats section (after the `}` that closes the `ForEach` section). Add it before the closing `}` of the `List`:

```swift
// Permissions Granted section — visible to everyone viewing this profile
if !combinedPermissions.isEmpty {
    Section {
        ForEach(combinedPermissions, id: \.self) { perm in
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(permissionLabel(perm))
                    .font(.subheadline)
            }
        }
    } header: {
        Text("Permissions Granted (\(combinedPermissions.count))")
    } footer: {
        Text("These permissions come from all assigned hats.")
            .font(.caption2)
    }
} else if !allHats.filter(\.isAssigned).isEmpty {
    Section {
        Text("No permissions configured for the assigned hats.")
            .foregroundStyle(.secondary)
            .font(.subheadline)
    } header: {
        Text("Permissions Granted")
    }
}
```

### Change D — Add permissionLabel helper to IOSEmployeeDetailPage

Add this private helper anywhere in the `IOSEmployeeDetailPage` struct body (e.g. near the bottom, before the closing `}`):

```swift
private func permissionLabel(_ key: String) -> String {
    key.split(separator: "_").map(\.capitalized).joined(separator: " ")
}
```

---

## Navigation Pattern Reference

Navigation to IOSEmployeeDetailPage in a sheet context:
```swift
NavigationLink(destination: IOSEmployeeDetailPage(employeeId: member.id)
    .environmentObject(appCore)) { ... }
```

This works inside `HatDetailSheet`'s own `NavigationStack`. The sheet has its own nav hierarchy.

Navigation to IOSPermissionsPage:
```swift
NavigationLink(destination: IOSPermissionsPage()
    .environmentObject(appCore)) { ... }
```

---

## Checklist Before Finishing

- [ ] `IOSHatsPage`: hat rows open `HatDetailSheet` on tap (not just swipe-to-delete)
- [ ] `HatDetailSheet`: members load from `getHatMembers(hatId:)` on `.task { loadData() }`
- [ ] `HatDetailSheet`: "Add Employee" button only shows when `canManageHats == true`
- [ ] `HatDetailSheet`: remove button only shows when `canManageHats == true`
- [ ] `HatDetailSheet`: member row navigates to `IOSEmployeeDetailPage` via `NavigationLink`
- [ ] `HatDetailSheet`: permissions section shows with "Edit Permissions →" link
- [ ] `AddEmployeeToHatSheet`: filters out employees already in the hat's `currentMembers`
- [ ] `IOSPeopleDashboardPage`: Management section only shows when `canManagePeople == true`
- [ ] `IOSPeopleDashboardPage`: Hats tile navigates to `IOSHatsPage`, Permissions tile navigates to `IOSPermissionsPage`
- [ ] `IOSEmployeeDetailPage`: "Permissions Granted" section shows combined permissions from assigned hats
- [ ] Build passes with 0 errors
- [ ] All tap targets are `minHeight: 44` (buttons, navigation links)
- [ ] All interactive elements have `.accessibilityLabel()`

---

## Log Result

After completing, append to `xcode-ai/prompt-results-log.md`:

```markdown
## Prompt PE-022 — Hat Assignment & Access Control UX (YYYY-MM-DD)

**Status:** SUCCESS | PARTIAL | FAILED
**Files Changed:**
- Weird Parts IOS/Weird Parts IOS/Features/People/IOSHatsPage.swift
- Weird Parts IOS/Weird Parts IOS/Features/People/IOSPeopleDashboardPage.swift
- Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeeDetailPage.swift
**What Was Done:**
- [list each change made]
**Issues Found:**
- [any compile errors, missing types, or behavioral issues]
**Build:** PASS | FAIL
```
