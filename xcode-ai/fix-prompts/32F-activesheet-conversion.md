# 32F — Convert showXxx Bools to ActiveSheet Enum (19 Files)

> **Chain position:** **32F** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. Use SINGLE `ActiveSheet` enum with `.sheet(item: $activeSheet)` pattern
2. DO NOT use multiple `@State private var showXxx: Bool` for sheets
3. DO NOT use multiple `.sheet(isPresented:)` modifiers — SwiftUI only respects the first one

## Instructions

Search the ENTIRE `Weird Parts IOS/Weird Parts IOS/Features/` directory for files using `showXxx` Bool patterns for sheets. Convert each to the `ActiveSheet` enum pattern.

## Known Files (from audit)

1. IOSNotebookTemplatesPage.swift — `showCreateTemplate`
2. IOSRFIListPage.swift — `showCreateRFI`
3. IOSChannelsPage.swift — multiple show bools
4. IOSContactsPage.swift
5. IOSCustomersPage.swift
6. IOSTeamsPage.swift
7. IOSHatsPage.swift
8. IOSEmployeeDetailPage.swift
9. IOSQuestionsPage.swift
10. IOSToolCheckoutsPage.swift
11. IOSScheduleCalendarPage.swift
12. IOSDispatchPage.swift
13. IOSTimeOffPage.swift
14. IOSClockOutQuestionsPage.swift
15. CompanyProfilesPage.swift
16. PartsCatalogPage.swift
17. CategoriesColorPicker.swift
18. PartsImportExportPage.swift
19. DashboardDailyReportPage.swift

**BUT:** Some of these may have been converted in prompts 20A-31I. Check each file FIRST — if it already has `ActiveSheet`, skip it. Only convert files still using Bool patterns.

## Fix Pattern

**BEFORE:**
```swift
@State private var showCreateItem = false
@State private var showEditItem = false
@State private var showQRScanner = false

.sheet(isPresented: $showCreateItem) { CreateSheet() }
.sheet(isPresented: $showEditItem) { EditSheet() }
.sheet(isPresented: $showQRScanner) { ScannerSheet() }
```

**AFTER:**
```swift
private enum ActiveSheet: Identifiable {
    case create
    case edit(ItemType)
    case qrScanner

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let item): "edit-\(item.id)"
        case .qrScanner: "qrScanner"
        }
    }
}

@State private var activeSheet: ActiveSheet?

.sheet(item: $activeSheet) { sheet in
    sheetContent(for: sheet)
}

@ViewBuilder
private func sheetContent(for sheet: ActiveSheet) -> some View {
    switch sheet {
    case .create: CreateSheet()
    case .edit(let item): EditSheet(item: item)
    case .qrScanner: ScannerSheet()
    }
}
```

## Success Criteria

- [ ] Zero `showXxx` Bool patterns for sheets in entire project
- [ ] Every page with sheets uses `ActiveSheet` enum + single `.sheet(item:)`
- [ ] All sheets dismiss properly (Done/Cancel buttons work)
- [ ] Project builds with no errors
