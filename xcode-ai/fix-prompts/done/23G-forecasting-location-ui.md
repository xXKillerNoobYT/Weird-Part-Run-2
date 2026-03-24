# 23G — Forecasting Page: Location Picker + Recommendations UI

> **Chain position:** 23A → … → 23F → **23G** → 23H
> **Prerequisite:** 23F complete (target_recommendations table + service methods)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The forecasting page currently shows a global view of all parts. After 23C-23F, we have per-location data and recommendation infrastructure. This prompt adds:
1. A location picker so users can filter forecasts by Shop, specific Truck, specific Trailer, or All
2. A "Recommendations" filter/section showing pending target change recommendations
3. Recommendation cards with Approve/Dismiss actions

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift` — current page
- `core/Sources/WiredPartCore/Services/PartsService.swift` — `listPendingRecommendations()`, `pendingRecommendationCount()`
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — `TargetRecommendation` model

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift`

## Task

### Step 1: Add location picker state

Add new state variables:

```swift
@State private var selectedLocationType: String = "all"  // "all", "warehouse", "truck", "trailer"
@State private var selectedLocationId: Int64?
@State private var availableLocations: [LocationOption] = []
@State private var recommendations: [TargetRecommendation] = []
@State private var recommendationCount: Int = 0
@State private var showRecommendations = false
```

Add a helper struct:

```swift
private struct LocationOption: Identifiable, Hashable {
    let id: String
    let locationType: String
    let locationId: Int64?
    let name: String
    let icon: String
}
```

### Step 2: Location picker UI

Add a location picker below the stat cards section (inside the List, after the stat cards Section):

```swift
Section {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            // "All" option
            locationChip(
                name: "All",
                icon: "square.grid.2x2",
                isSelected: selectedLocationType == "all",
                action: {
                    selectedLocationType = "all"
                    selectedLocationId = nil
                    Task { await loadData() }
                }
            )

            ForEach(availableLocations) { loc in
                locationChip(
                    name: loc.name,
                    icon: loc.icon,
                    isSelected: selectedLocationType == loc.locationType
                        && selectedLocationId == loc.locationId,
                    action: {
                        selectedLocationType = loc.locationType
                        selectedLocationId = loc.locationId
                        Task { await loadData() }
                    }
                )
            }
        }
        .padding(.horizontal, 4)
    }
    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
}
```

Location chip helper:

```swift
@ViewBuilder
private func locationChip(name: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
        )
        .foregroundStyle(isSelected ? .white : .primary)
    }
    .buttonStyle(.plain)
}
```

### Step 3: Recommendations filter badge

Add a "Recommendations" button in the toolbar (next to the existing Recalculate button):

```swift
ToolbarItem(placement: .secondaryAction) {
    Button {
        showRecommendations.toggle()
        if showRecommendations { Task { await loadRecommendations() } }
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "lightbulb")
            if recommendationCount > 0 {
                Text("\(recommendationCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(.white)
            }
        }
    }
}
```

### Step 4: Recommendations section in list

When `showRecommendations` is true, show recommendations above the parts list:

```swift
// In forecastList, after stat cards section and location picker section:
if showRecommendations && !recommendations.isEmpty {
    Section("Recommendations (\(recommendations.count))") {
        ForEach(recommendations) { rec in
            recommendationCard(rec)
        }
    }
}
```

Recommendation card:

```swift
@State private var dismissReason = ""
@State private var showDismissAlert = false
@State private var dismissingRecommendation: TargetRecommendation?

@ViewBuilder
private func recommendationCard(_ rec: TargetRecommendation) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        // Part name lookup
        HStack {
            Image(systemName: recommendationIcon(rec.recommendationType))
                .foregroundStyle(recommendationColor(rec.recommendationType))
            Text(partName(for: rec.partId))
                .fontWeight(.medium)
            Spacer()
            Text(rec.recommendationType.capitalized)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(recommendationColor(rec.recommendationType).opacity(0.15)))
                .foregroundStyle(recommendationColor(rec.recommendationType))
        }

        if rec.recommendationType == "adjust" {
            // Show current → recommended for all 3 values
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MIN").font(.caption2).foregroundStyle(.secondary)
                    Text("\(rec.currentMin ?? 0) → \(rec.recommendedMin ?? 0)")
                        .font(.caption).fontWeight(.medium)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET").font(.caption2).foregroundStyle(.secondary)
                    Text("\(rec.currentTarget ?? 0) → \(rec.recommendedTarget ?? 0)")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAX").font(.caption2).foregroundStyle(.secondary)
                    Text("\(rec.currentMax ?? 0) → \(rec.recommendedMax ?? 0)")
                        .font(.caption).fontWeight(.medium)
                }
            }
        }

        if let reason = rec.reason {
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 12) {
            Button {
                Task { await approveRecommendation(rec) }
            } label: {
                Label("Approve", systemImage: "checkmark")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                dismissingRecommendation = rec
                showDismissAlert = true
            } label: {
                Label("Dismiss", systemImage: "xmark")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
    .padding(.vertical, 4)
}
```

### Step 5: Approve and dismiss actions

```swift
private func approveRecommendation(_ rec: TargetRecommendation) async {
    guard let service = appCore.partsService,
          let userId = appCore.currentUserId else { return }
    do {
        try service.approveRecommendation(id: rec.id!, userId: userId)
        await loadRecommendations()
        await loadData() // Refresh forecast data with new values
    } catch {
        loadError = "Approve failed: \(error.localizedDescription)"
    }
}
```

Add a dismiss alert with required reason (use `.alert` with a TextField):

```swift
.alert("Dismiss Recommendation", isPresented: $showDismissAlert) {
    TextField("Reason (required)", text: $dismissReason)
    Button("Cancel", role: .cancel) {
        dismissReason = ""
        dismissingRecommendation = nil
    }
    Button("Dismiss", role: .destructive) {
        if let rec = dismissingRecommendation {
            Task {
                guard let service = appCore.partsService,
                      let userId = appCore.currentUserId else { return }
                do {
                    try service.dismissRecommendation(id: rec.id!, userId: userId, reason: dismissReason)
                    await loadRecommendations()
                } catch {
                    loadError = "Dismiss failed: \(error.localizedDescription)"
                }
                dismissReason = ""
                dismissingRecommendation = nil
            }
        }
    }
    .disabled(dismissReason.trimmingCharacters(in: .whitespaces).isEmpty)
} message: {
    Text("Why are you dismissing this recommendation?")
}
```

### Step 6: Load locations and recommendations

Add data loading methods:

```swift
private func loadLocations() {
    guard let db = appCore.db else { return }
    do {
        let rows = try db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: """
                SELECT DISTINCT s.location_type, s.location_id,
                    COALESCE(wl.name, v.name, tr.name, 'Unknown') AS name
                FROM stock s
                LEFT JOIN warehouse_locations wl ON s.location_type = 'warehouse' AND wl.id = s.location_id
                LEFT JOIN vehicles v ON s.location_type = 'truck' AND v.id = s.location_id
                LEFT JOIN trailers tr ON s.location_type = 'trailer' AND tr.id = s.location_id
                WHERE s.deleted_at IS NULL AND s.qty > 0
                GROUP BY s.location_type, s.location_id
                ORDER BY s.location_type, name
                """)
        }
        availableLocations = rows.map { row in
            let locType: String = row["location_type"] ?? "warehouse"
            let locId: Int64 = row["location_id"] ?? 1
            let name: String = row["name"] ?? "Unknown"
            let icon: String
            switch locType {
            case "warehouse": icon = "building.2"
            case "truck": icon = "truck.box"
            case "trailer": icon = "shippingbox"
            default: icon = "mappin"
            }
            return LocationOption(id: "\(locType)_\(locId)", locationType: locType,
                                  locationId: locId, name: name, icon: icon)
        }
    } catch {
        // Non-critical — location picker just won't show
    }
}

@Sendable
private func loadRecommendations() async {
    guard let service = appCore.partsService else { return }
    do {
        recommendations = try service.listPendingRecommendations()
        recommendationCount = try service.pendingRecommendationCount()
    } catch {
        // Non-critical
    }
}
```

### Step 7: Update loadData to filter by location

Update `loadData()` to pass location filter:

```swift
// In loadData(), replace the service call:
let rows: [PartsService.ForecastDataRow]
if selectedLocationType == "all" {
    rows = try service.listForecastDataWithStock()
} else {
    rows = try service.listForecastDataWithStock(
        locationType: selectedLocationType,
        locationId: selectedLocationId
    )
}
```

**NOTE:** This requires adding optional `locationType`/`locationId` parameters to `listForecastDataWithStock()` in PartsService. Add a WHERE clause filtering `stock` by location when these are provided.

### Step 8: Load locations on appear

Add to the `.task` modifier:

```swift
.task {
    loadLocations()
    await loadData()
    await loadRecommendations()
}
```

### Step 9: Helper methods

```swift
private func recommendationIcon(_ type: String) -> String {
    switch type {
    case "adjust": return "slider.horizontal.3"
    case "add": return "plus.circle"
    case "remove": return "minus.circle"
    case "category_change": return "arrow.left.arrow.right"
    default: return "lightbulb"
    }
}

private func recommendationColor(_ type: String) -> Color {
    switch type {
    case "adjust": return .blue
    case "add": return .green
    case "remove": return .red
    case "category_change": return .orange
    default: return .secondary
    }
}

private func partName(for partId: Int64) -> String {
    // Look up from forecastRows if available, otherwise return "Part #\(partId)"
    forecastRows.first(where: { $0.part.id == partId })?.part.name ?? "Part #\(partId)"
}
```

## Important Notes

- The location picker uses a horizontal scroll of capsule chips INSIDE the List (not a separate top bar). This is different from the old urgency filter chips — those were replaced by stat cards in 23C.
- `listForecastDataWithStock()` needs new optional location filter parameters — add `locationType: String? = nil, locationId: Int64? = nil` to the existing method signature.
- The dismiss alert uses a TextField for the reason — which is REQUIRED. The Dismiss button is disabled until text is entered.
- `appCore.currentUserId` — check if this property exists. If not, use `appCore.currentUser?.id` or whatever pattern is used in other pages for getting the logged-in user's ID.
- Truck locations should only show to the assigned user — add this filter in `loadLocations()` if `appCore` provides the current user's assigned vehicle ID.

## Success Criteria

- [ ] Location picker shows All + each location with stock
- [ ] Tapping a location filters the forecast list to that location
- [ ] Recommendations toolbar button with badge count
- [ ] Recommendation cards show current → recommended for MIN/TARGET/MAX
- [ ] Approve button applies recommendation
- [ ] Dismiss button requires reason (TextField in alert)
- [ ] Location data loads on appear
- [ ] `listForecastDataWithStock()` accepts optional location filter
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23G Results (YYYY-MM-DD)
- Location picker: horizontal chips for All/Shop/Truck/Trailer
- Recommendation toolbar badge + expandable section with approve/dismiss
- Dismiss requires reason (TextField alert)
- listForecastDataWithStock() now accepts location filter
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 23H.**
