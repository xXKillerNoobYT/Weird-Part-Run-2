# 23C — Forecasting: Stat Cards as Filters

> **Chain position:** 23A → 23B → **23C** → 23D
> **Prerequisite:** 23A complete (service layer, recalculate button)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The forecasting page currently has TWO filter controls that do the same thing: a horizontal scroll bar of filter capsule chips (All/Critical/Warning/Healthy) AND a row of stat cards showing counts. This is redundant. The stat cards should BE the filters — tap a card to filter, tap again to deselect. The chip bar gets deleted.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift` — current page

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift`

## Task

### Step 1: Delete the filter chip ScrollView

Remove the entire `ScrollView(.horizontal, showsIndicators: false)` block at the top of the body (the one containing `ForEach(UrgencyFilter.allCases)` with capsule-shaped buttons). This includes the `.background(Color(.secondarySystemGroupedBackground))` on it.

### Step 2: Make stat cards tappable filters

Replace the current `statCard` function and the `Section` containing the stat cards. The cards should:

1. **Act as toggle filters** — tap to select, tap again to deselect (show all)
2. **Always show global counts** — counts come from `forecastRows` (unfiltered), not `filteredRows`
3. **Visual feedback** — selected card gets filled background with white text, slight scale

```swift
@ViewBuilder
private func statCard(label: String, count: Int, color: Color, filter: UrgencyFilter) -> some View {
    let isSelected = filterUrgency == filter

    Button {
        withAnimation(.easeInOut(duration: 0.2)) {
            if filterUrgency == filter {
                filterUrgency = .all  // Deselect = show all
            } else {
                filterUrgency = filter
            }
        }
    } label: {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(isSelected ? .white : color)
            Text(label)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? color : color.opacity(0.08))
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
    }
    .buttonStyle(.plain)
}
```

### Step 3: Update the stat card Section in the list

Replace the current stat card `Section` in `forecastList`:

```swift
Section {
    HStack(spacing: 12) {
        statCard(
            label: "Critical",
            count: forecastRows.filter { ($0.part.forecastDaysUntilLow ?? 999) <= 7 }.count,
            color: .red,
            filter: .critical
        )
        statCard(
            label: "Warning",
            count: forecastRows.filter { let d = $0.part.forecastDaysUntilLow ?? 999; return d > 7 && d <= 30 }.count,
            color: .orange,
            filter: .warning
        )
        statCard(
            label: "Healthy",
            count: forecastRows.filter { ($0.part.forecastDaysUntilLow ?? 999) > 30 }.count,
            color: .green,
            filter: .healthy
        )
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
}
```

### Step 4: Update section header to reflect filter

Change the section header from `"\(filteredRows.count) parts"` to something contextual:

```swift
Section {
    // ... ForEach
} header: {
    switch filterUrgency {
    case .all:
        Text("\(filteredRows.count) parts")
    case .critical:
        Text("\(filteredRows.count) critical parts")
    case .warning:
        Text("\(filteredRows.count) warning parts")
    case .healthy:
        Text("\(filteredRows.count) healthy parts")
    }
}
```

### Step 5: Clean up

- The `UrgencyFilter` enum stays (still used for state), but its `label` and `color` properties can stay for the detail sheet or other uses.
- Remove the `ScrollView` from the body's top-level `VStack` — the stat cards are now inside the List's first Section.
- Make sure the `VStack(spacing: 0)` at the top of `body` still works without the scroll bar. It should now just contain the conditional content (loading/error/empty/list).

## Success Criteria

- [ ] Horizontal filter chip bar completely removed
- [ ] Stat cards are tappable — tap filters, tap again deselects
- [ ] Cards always show global counts (from `forecastRows`, not `filteredRows`)
- [ ] Selected card: filled background with urgency color, white text, slight scale
- [ ] Unselected cards: subtle tinted background, colored number, gray label
- [ ] Section header shows "X critical/warning/healthy parts" based on filter
- [ ] Smooth animation on filter toggle
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23C Results (YYYY-MM-DD)
- Deleted horizontal filter chip ScrollView
- Stat cards now act as toggle filters (tap to filter, tap again for all)
- Cards always show global counts, selected card fills with urgency color
- Section header contextual: "X critical/warning/healthy parts"
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 23D.**
