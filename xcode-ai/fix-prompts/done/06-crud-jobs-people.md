# Fix Prompt 06: Missing CRUD — Jobs & People

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

A user opens the Employees page and sees a list of employees — but there's no "Add Employee" button. They can't create new employees from their phone. Same for Customers, Contractors, Contacts, and Teams. The job detail tabs show placeholder text instead of real data with actions.

---

## Files To Fix

### 1. IOSEmployeesPage.swift — Add "Create Employee" Button

The page lists employees but has no way to add one. Add a toolbar button and sheet:

```swift
@State private var showAddEmployee = false

// In toolbar:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showAddEmployee = true
        } label: {
            Image(systemName: "plus")
        }
    }
}
.sheet(isPresented: $showAddEmployee) {
    // Simple form: display name, PIN, role picker
    AddEmployeeSheet(onSave: { loadData() })
}
```

Create `AddEmployeeSheet` as a NavigationStack form inside the same file (or a new file). Fields:
- Display Name (text field, required)
- PIN (secure field, required, min 4 digits)
- Role picker (admin, manager, worker)
- Save button calls `appCore.authService?.seedUser(displayName:pin:role:)`

### 2. IOSCustomersPage.swift — Add "Create Customer" Button

Same pattern. Add toolbar + button, create `AddCustomerSheet`. Fields:
- Company Name (required)
- Contact Name
- Phone
- Email
- Save calls `appCore.peopleService?.createCustomer(...)`

### 3. IOSContractorsPage.swift — Add "Create Contractor" Button

Same pattern. Fields:
- Company Name (required)
- Contact Name
- Phone, Email
- Trade/Specialty
- Save calls `appCore.peopleService?.createContractor(...)`

### 4. IOSContactsPage.swift — Add "Create Contact" Button

Same. Fields: Name, Phone, Email, Entity type (customer/contractor/supplier), Entity ID.

### 5. IOSTeamsPage.swift — Add "Create Team" Button

Same. Fields: Team Name, Description.

### 6. IOSEmployeeDetailPage.swift — Add Edit Button

The detail page shows employee info but has no edit capability. Add:
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("Edit") { showEditSheet = true }
    }
}
```

### 7. IOSCustomerDetailPage.swift — Fix Job History Placeholder

Replace the placeholder text `"Job history will be populated from JobsService"` with actual data loading:

```swift
// In loadData():
if let jobsService = appCore.jobsService {
    // Load jobs linked to this customer
    customerJobs = try jobsService.listJobsByCustomer(customerId: customerId)
}

// In body, Job History section:
if customerJobs.isEmpty {
    EmptyStateView(title: "No Jobs", message: "No jobs linked to this customer yet.", icon: "briefcase")
} else {
    ForEach(customerJobs, id: \.id) { job in
        // job row
    }
}
```

### 8. IOSJobDetailTabView.swift — Fix Team and Parts Tabs

**Team tab** — Replace placeholder text with actual team loading:
```swift
// Load job team members in loadData()
if let jobsService = appCore.jobsService {
    teamMembers = try jobsService.getJobTeamMembers(jobId: jobId)
}

// In teamTab view:
if teamMembers.isEmpty {
    EmptyStateView(title: "No Team Members", message: "Assign employees to this job.", icon: "person.2")
} else {
    ForEach(teamMembers, id: \.id) { member in
        // member row with name, role, avatar
    }
}
```

**Parts tab** — Same pattern:
```swift
// Load parts in loadData()
if let partsService = appCore.partsService {
    jobParts = try partsService.getPartsForJob(jobId: jobId)
}
```

### 9. IOSHatsPage.swift — Add "Create Hat" and edit/delete

If the page only shows hats without CRUD, add toolbar + button for creating new hats (roles).

### 10. IOSPermissionsPage.swift — Make permissions editable

If currently read-only, add toggle switches that call the service to update permissions.

---

## Service Methods You May Need

Check these exist in `core/Sources/WiredPartCore/Services/`:
- `AuthService.seedUser(displayName:pin:role:)` — may need to create if missing
- `PeopleService.createCustomer(...)`, `createContractor(...)`, `createContact(...)`
- `PeopleService.createTeam(name:description:)`
- `JobsService.getJobTeamMembers(jobId:)`
- `JobsService.listJobsByCustomer(customerId:)`
- `PartsService.getPartsForJob(jobId:)`

If a service method doesn't exist, create a stub that returns an empty array for now and add a `// TODO: implement` comment. The important thing is the UI has the buttons and flows — the backend can be filled in.

---

## Testing Checklist

1. People → Employees → tap "+" → fill form → Save → new employee appears in list
2. People → Customers → tap "+" → fill form → Save → new customer appears
3. Open a Job → Team tab → shows team members or "No Team Members" (not placeholder text)
4. Open a Job → Parts tab → shows parts or "No Parts" (not placeholder text)
5. Open a Customer → Job History → shows jobs or "No Jobs" (not placeholder text)

---

## When Done

Start **prompt 07 (Missing CRUD — Orders & Warehouse)** next.
