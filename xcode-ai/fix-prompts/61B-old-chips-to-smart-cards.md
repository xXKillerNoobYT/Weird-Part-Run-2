# 61B — Convert Old Capsule Chip Filters to Smart Card Filters

> **Chain position:** **61B** (standalone)
> **Issue:** T2-04
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT change any filter logic or data — only change the UI presentation
2. DO NOT remove any filter options — every existing chip must become a smart card
3. Smart cards must show a COUNT of matching items (not just a label)
4. Smart cards must be tappable and show selected state
5. Project must build with zero errors when done

## Context

Six pages use old-style capsule chip filter bars (small rounded pills in a horizontal scroll). The app standard is "smart card" filters — larger cards that show the filter label AND a count of matching items, with a selected highlight state. This is more informative and touch-friendly.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSVehiclesPage.swift`
4. `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebooksListPage.swift`
5. `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSManageJobsPage.swift`
6. `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSTimeOffPage.swift`

## Task

### 1. Identify Old Chip Pattern in Each File

Look for this kind of pattern:
```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack {
        ForEach(filterOptions, id: \.self) { option in
            Button(option) {
                selectedFilter = option
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedFilter == option ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundColor(selectedFilter == option ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}
```

Or any variant with `Capsule()`, small paddings, and filter selection.

### 2. Replace with Smart Card Pattern

Replace each old chip bar with this smart card pattern:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 12) {
        ForEach(filterOptions, id: \.self) { option in
            SmartFilterCard(
                title: option,
                count: countForFilter(option),
                isSelected: selectedFilter == option
            ) {
                selectedFilter = option
            }
        }
    }
    .padding(.horizontal)
}
```

### 3. Create SmartFilterCard if It Doesn't Exist

Check if `SmartFilterCard` already exists in `Shared/`. If not, create it:

```swift
struct SmartFilterCard: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 100, minHeight: 44)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
```

### 4. Add Count Computation to Each Page

For each page, add a `countForFilter(_ filter: String) -> Int` method that counts items matching each filter from the already-loaded data. Examples:

- **IOSPurchaseOrdersPage:** Count POs by status (Draft, Submitted, Received, etc.)
- **IOSJPOsPage:** Count JPOs by status (Pending, Approved, Ordered, etc.)
- **IOSVehiclesPage:** Count vehicles by status (Active, In Shop, Out of Service)
- **IOSNotebooksListPage:** Count notebooks by type or status
- **IOSManageJobsPage:** Count jobs by status (Active, Completed, On Hold)
- **IOSTimeOffPage:** Count requests by status (Pending, Approved, Denied)

The count must use the FULL dataset (before filtering), so users can see "12 Active, 3 On Hold, 5 Completed" and choose which to view.

### 5. Add "All" Card as First Option

Each page should have an "All" smart card as the first option showing the total count. This is the default selection.

## Success Criteria

- [ ] All 6 pages converted from capsule chips to smart cards
- [ ] Each smart card shows filter label + count of matching items
- [ ] Selected state has accent color highlight with border
- [ ] "All" card is first option on each page
- [ ] Touch targets are at least 44px tall
- [ ] Counts are computed from actual data, not hardcoded
- [ ] Project builds with zero errors
