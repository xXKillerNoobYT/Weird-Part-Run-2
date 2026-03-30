# 44E — Contacts Page Redesign

> **Chain position:** **44E** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSContactsPage.swift`. Redesign with smart cards for contact types, active/inactive sections, sort options, and contact detail navigation.

## Context

The contacts page currently shows a simple flat list. Contacts need organization by type (GC, Supplier, Contractor, Owner, Vendor), active/inactive status, and sorting options. Inactive contacts should be collapsed by default to keep the list clean. Each contact should navigate to a detail view.

## Task

### Step 1: Smart Cards for Contact Types

```swift
@State private var typeFilter: ContactTypeFilter = .all
@State private var sortOption: ContactSort = .recentlyUpdated
@State private var showInactive = false

enum ContactTypeFilter: String, CaseIterable {
    case all = "All"
    case gc = "GC"
    case supplier = "Supplier"
    case contractor = "Contractor"
    case owner = "Owner"
    case vendor = "Vendor"
    case active = "Active"
    case inactive = "Inactive"
}

enum ContactSort: String, CaseIterable {
    case recentlyUpdated = "Recently Updated"
    case name = "Name"
    case type = "Type"
    case mostJobs = "Most Jobs"
}

// Smart cards
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 10) {
        ForEach(ContactTypeFilter.allCases, id: \.self) { filter in
            SmartCard(
                title: filter.rawValue,
                count: countFor(filter),
                isActive: typeFilter == filter
            ) {
                typeFilter = filter
            }
        }
    }
    .padding(.horizontal)
}
```

### Step 2: Sort Options

```swift
// Sort picker in toolbar
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Menu {
            Picker("Sort", selection: $sortOption) {
                ForEach(ContactSort.allCases, id: \.self) { sort in
                    Text(sort.rawValue).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}
```

### Step 3: Active/Inactive Sections

```swift
List {
    // Active contacts
    Section {
        ForEach(activeContacts) { contact in
            NavigationLink(value: contact.id) {
                ContactRow(contact: contact)
            }
        }
    } header: {
        Text("Active (\(activeContacts.count))")
    }

    // Inactive (collapsed by default)
    if !inactiveContacts.isEmpty {
        Section {
            DisclosureGroup("Inactive (\(inactiveContacts.count))", isExpanded: $showInactive) {
                ForEach(inactiveContacts) { contact in
                    NavigationLink(value: contact.id) {
                        ContactRow(contact: contact)
                            .opacity(0.6)
                    }
                }
            }
        }
    }
}
.navigationDestination(for: Int64.self) { contactId in
    IOSContactDetailPage(contactId: contactId)
}
```

### Step 4: Contact Row

```swift
struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.headline)
                HStack(spacing: 4) {
                    Text(contact.contactType?.capitalized ?? "Contact")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(typeColor(contact.contactType))
                        .clipShape(Capsule())
                    if let company = contact.company {
                        Text(company).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let jobCount = contact.jobCount, jobCount > 0 {
                Text("\(jobCount) jobs")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    func typeColor(_ type: String?) -> Color {
        switch type {
        case "gc": return .blue
        case "supplier": return .purple
        case "contractor": return .orange
        case "owner": return .green
        case "vendor": return .teal
        default: return .gray
        }
    }
}
```

### Step 5: Service Method for Sorting

```swift
// In PeopleService:
func getContactsSorted(sortBy: String, typeFilter: String?) async throws -> [Contact] {
    // sortBy: "recently_updated", "name", "type", "most_jobs"
    // typeFilter: nil for all, or specific type
}
```

## Important Notes
- Inactive contacts collapsed by default (DisclosureGroup)
- Sort option persists during session (not across app restarts)
- Type badges use consistent colors across the app
- Contact detail navigation should work within the People navigation stack
- "Most Jobs" sort requires a join with job assignments

## Success Criteria
- [ ] Smart cards for all contact types (All, GC, Supplier, Contractor, Owner, Vendor, Active, Inactive)
- [ ] Sort options (Recently Updated, Name, Type, Most Jobs)
- [ ] Active contacts section
- [ ] Inactive contacts collapsed by default
- [ ] Color-coded type badges
- [ ] NavigationLink to contact detail
- [ ] .searchable and .refreshable present
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 44E Results (YYYY-MM-DD)
- IOSContactsPage redesigned with smart cards + sort
- Active/inactive sections
- Contact type badges
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
