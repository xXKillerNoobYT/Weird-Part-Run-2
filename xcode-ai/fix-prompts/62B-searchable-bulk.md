# 62B — Add .searchable to 28 List Pages Missing Search
> Chain position: Standalone

## Task

Add `.searchable(text: $searchText, prompt: "Search...")` and client-side filtering to 28 list pages that currently have no search capability. Each page already loads data into an array — you just need to add a `@State` for search text, a computed `filtered` array, and the `.searchable` modifier.

### Step-by-step for EVERY file listed below:

1. Open the file.
2. Add a `@State` property near the top of the view struct:
   ```swift
   @State private var searchText = ""
   ```
3. Add a computed property that filters the main data array:
   ```swift
   private var filteredItems: [ItemType] {
       if searchText.isEmpty { return items }
       return items.filter { item in
           item.name.localizedCaseInsensitiveContains(searchText)
           // Add other relevant fields to search (e.g., || item.code?.localizedCaseInsensitiveContains(searchText) == true)
       }
   }
   ```
   Choose which fields to search based on what makes sense for each page:
   - **People pages:** name, email, phone
   - **Parts pages:** name, code, description
   - **Orders pages:** PO number, supplier name, status
   - **Fleet pages:** vehicle name, plate number, VIN
   - **Jobs pages:** job name, customer name, address
   - **Tools pages:** tool name, serial number
   - **Warehouse pages:** location name, part name
   - **Chat pages:** channel name, message content
   - **Notebooks pages:** notebook name, title
4. Replace `items` with `filteredItems` in the `ForEach` that renders the list.
5. Add `.searchable` modifier to the `List` or `NavigationStack`:
   ```swift
   .searchable(text: $searchText, prompt: "Search...")
   ```

### Files to add .searchable to (28 files):

**Chat:**
- `Features/Chat/IOSQuestionsPage.swift` — search question text
- `Features/Chat/IOSRFIListPage.swift` — search RFI subject

**Fleet:**
- `Features/Fleet/IOSFleetDashboardPage.swift` — search vehicle names
- `Features/Fleet/IOSFuelPage.swift` — search vehicle name, date
- `Features/Fleet/IOSInspectionsPage.swift` — search vehicle, inspector
- `Features/Fleet/IOSMaintenancePage.swift` — search vehicle, description
- `Features/Fleet/IOSMileagePage.swift` — search vehicle name
- `Features/Fleet/IOSTelematicsPage.swift` — search vehicle name
- `Features/Fleet/IOSTrailerLocationsPage.swift` — search trailer name, location

**Jobs:**
- `Features/Jobs/IOSDailyReportsPage.swift` — search by date, user name

**Notebooks:**
- `Features/Notebooks/IOSNotebookDetailPage.swift` — search block content
- `Features/Notebooks/IOSNotebookTemplatesPage.swift` — search template name

**Office:**
- `Features/Office/IOSOfficeDashboardPage.swift` — search attention items
- `Features/Office/IOSSpendingDashboardPage.swift` — search spending items
- `Features/Office/IOSWarehouseExecPage.swift` — search metric names

**Orders:**
- `Features/Orders/IOSApprovalsPage.swift` — search by submitter, item
- `Features/Orders/IOSProcurementPage.swift` — search part name, supplier
- `Features/Orders/IOSReturnsPage.swift` — search return reason, PO number

**People:**
- `Features/People/IOSContractorDetailPage.swift` — search section content
- `Features/People/IOSCustomerDetailPage.swift` — search section content
- `Features/People/IOSPeopleDashboardPage.swift` — search people names

**Reports:**
- `Features/Reports/IOSDailyReportsSummaryPage.swift` — search by user, job
- `Features/Reports/IOSLaborOverviewPage.swift` — search employee name
- `Features/Reports/IOSSpendingPage.swift` — search supplier, category

**Scheduling:**
- `Features/Scheduling/IOSDispatchTemplatesPage.swift` — search template name
- `Features/Scheduling/IOSLongTermPipelinePage.swift` — search job name

**Tools:**
- `Features/Tools/IOSToolCheckoutsPage.swift` — search tool name, borrower
- `Features/Tools/IOSToolKitsPage.swift` — search kit name
- `Features/Tools/IOSToolMaintenancePage.swift` — search tool name, issue

### Pattern to follow (existing working example):

```swift
// Example from IOSChannelsPage.swift:
struct IOSChannelsPage: View {
    @State private var searchText = ""

    private var filteredChannels: [ChannelListItem] {
        if searchText.isEmpty { return channels }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filteredChannels) { channel in
                // ...
            }
        }
        .searchable(text: $searchText, prompt: "Search channels...")
    }
}
```

## Files to Modify

All 28 files listed above, located under:
`Weird Parts IOS/Weird Parts IOS/Features/`

## Success Criteria
- [ ] All 28 pages have a search bar that appears when pulling down on the list
- [ ] Typing in the search bar filters the list in real-time (client-side)
- [ ] Clearing the search text shows all items again
- [ ] Search is case-insensitive
- [ ] No compile errors introduced
- [ ] The search prompt text is contextual (e.g., "Search tools..." not just "Search...")
