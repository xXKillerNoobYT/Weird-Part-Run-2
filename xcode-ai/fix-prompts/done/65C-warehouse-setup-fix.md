# 65C — Warehouse Setup Wizard Fix

> **Chain position:** After 65B
> **Priority:** HIGH — the warehouse wizard is broken beyond step 1
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

The warehouse onboarding wizard (`WarehouseOnboardingWizard.swift`) is broken beyond step 1. Steps 2-6 either crash, show only instructional text, or have broken navigation. Fix it so the entire wizard is fully functional and the user can set up their warehouse without leaving the wizard.

**Read these files first (READ ALL COMPLETELY):**
- `Features/Warehouse/WarehouseOnboardingWizard.swift` — current wizard (~560 lines, broken beyond step 1)
- `Features/Warehouse/WarehouseLocationsPage.swift` — has floor plan editor, unit placement, area management
- `Features/Warehouse/IOSAuditPage.swift` — has count audit flow
- `Features/Warehouse/IOSOrganizationAuditPage.swift` — orphaned page, needs to be reachable
- `Features/Warehouse/WarehouseDashboardPage.swift` — warehouse dashboard (navigation target)
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — all warehouse service methods
- `docs/plans/warehouse-audit-intelligence.md` — design plan for 5-level progressive setup

## Part 1: Fix the Wizard (Steps 1-6)

### Step 1: Room Dimensions (verify working)

Step 1 should already work — it creates the floor plan with room width x length in ft/in. Verify:
- Room name input
- Width and length inputs (feet + inches)
- "Create Floor Plan" button calls `warehouseService.createFloorPlan()`
- Success feedback + auto-advance to Step 2

If it's broken, fix it. If it works, leave it alone.

### Step 2: Place Storage Units (FIX — currently text-only or crashing)

Replace the current Step 2 content with a functional unit placement flow:

```swift
@ViewBuilder
private var step2PlaceUnits: some View {
    VStack(spacing: 0) {
        // Header instruction
        Text("Add your storage units — shelves, pipe racks, gang boxes, etc.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()

        // Add unit button
        Button {
            showAddUnitSheet = true
        } label: {
            Label("Add Storage Unit", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)

        // List of added units
        if !addedUnits.isEmpty {
            List {
                ForEach(addedUnits) { unit in
                    HStack {
                        Image(systemName: iconForUnitType(unit.unitType))
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(unit.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(unit.unitType.capitalized) • \(unit.totalAreas) areas")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .onDelete { indexSet in
                    deleteUnits(at: indexSet)
                }
            }
            .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView {
                Label("No Storage Units", systemImage: "cabinet.fill")
            } description: {
                Text("Tap the button above to add your first shelf, rack, or storage area.")
            }
        }
    }
}
```

**Add Unit Sheet** — a sheet that creates storage units via `WarehouseService`:

```swift
struct AddStorageUnitSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let floorPlanId: Int64
    var onSave: () -> Void

    @State private var unitName = ""
    @State private var unitType = "shelf"
    @State private var levelCount = 1
    @State private var areasPerLevel = 4
    @State private var saveError: String?
    @State private var isSaving = false

    let unitTypes = [
        ("shelf", "Shelf", "cabinet.fill"),
        ("pipe_rack", "Pipe Rack", "line.3.horizontal"),
        ("gang_box", "Gang Box", "shippingbox.fill"),
        ("wall_mount", "Wall Mount", "rectangle.portrait.on.rectangleportrait.angled.fill"),
        ("cabinet", "Cabinet", "door.left.hand.closed"),
        ("pallet_rack", "Pallet Rack", "square.stack.3d.up.fill"),
        ("floor_area", "Floor Area", "square.dashed"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Unit Info") {
                    TextField("Name (e.g., Shelf A)", text: $unitName)

                    Picker("Type", selection: $unitType) {
                        ForEach(unitTypes, id: \.0) { type in
                            Label(type.1, systemImage: type.2).tag(type.0)
                        }
                    }
                }

                Section("Structure") {
                    Stepper("Levels: \(levelCount)", value: $levelCount, in: 1...20)
                    Stepper("Areas per Level: \(areasPerLevel)", value: $areasPerLevel, in: 1...50)
                    Text("Total areas: \(levelCount * areasPerLevel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Storage Unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveUnit() }
                        .disabled(unitName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func saveUnit() {
        isSaving = true
        saveError = nil
        do {
            // Create the storage unit via WarehouseService
            // This should create the unit + all its levels + all its areas
            try appCore.warehouseService?.createStorageUnit(
                floorPlanId: floorPlanId,
                name: unitName.trimmingCharacters(in: .whitespaces),
                unitType: unitType,
                levels: levelCount,
                areasPerLevel: areasPerLevel
            )
            onSave()
            dismiss()
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
        }
    }
}
```

If `createStorageUnit` doesn't exist in WarehouseService, create it. It should:
1. Create a storage_unit record
2. Create level records (1 through levelCount)
3. Create area records for each level (areasPerLevel per level)
4. Generate location codes automatically (e.g., "A-1-01" for unit A, level 1, area 1)

### Step 3: Number Everything (FIX — make interactive)

Replace with an interactive sticker checklist:

```swift
@ViewBuilder
private var step3NumberEverything: some View {
    VStack(spacing: 0) {
        // Instructions
        VStack(spacing: 8) {
            Text("Write these codes on stickers and place them on each location")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Grab a Sharpie and sticker sheet. Check each off as you place it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()

        // Progress
        let total = stickerItems.count
        let done = stickerItems.filter { checkedStickers.contains($0.code) }.count
        HStack {
            Text("\(done) of \(total) stickers placed")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .frame(width: 100)
        }
        .padding(.horizontal)

        // Checklist grouped by unit
        List {
            ForEach(stickerGroups, id: \.unitName) { group in
                Section(group.unitName) {
                    ForEach(group.items, id: \.code) { item in
                        Button {
                            toggleSticker(item.code)
                        } label: {
                            HStack {
                                Image(systemName: checkedStickers.contains(item.code)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checkedStickers.contains(item.code) ? .green : .secondary)
                                VStack(alignment: .leading) {
                                    Text(item.code)
                                        .font(.subheadline)
                                        .monospaced()
                                        .fontWeight(.medium)
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
```

**Sticker items are auto-generated** from the units added in Step 2. Each unit generates sticker entries for: the unit itself, each level, and each area. Store `checkedStickers` as a `Set<String>` in `@AppStorage` so progress persists.

### Step 4: Walk the Floor (FIX — make functional)

Replace with a per-area part assignment flow:

```swift
@ViewBuilder
private var step4WalkTheFloor: some View {
    VStack(spacing: 0) {
        // Current area indicator
        if let area = currentWalkArea {
            VStack(spacing: 4) {
                Text("You are at:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(area.locationCode)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospaced()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }

        // Search + assign parts to this area
        HStack {
            TextField("Search parts to assign here...", text: $walkPartSearch)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal)

        // Search results (filtered parts not yet assigned to any area)
        if !walkPartSearch.isEmpty {
            List {
                ForEach(filteredUnassignedParts) { part in
                    Button {
                        assignPartToCurrentArea(part)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.blue)
                            Text(part.name)
                                .font(.subheadline)
                            Spacer()
                            if let code = part.partNumber {
                                Text(code)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
        }

        // Parts already assigned to this area
        if !partsInCurrentWalkArea.isEmpty {
            Section {
                ForEach(partsInCurrentWalkArea) { part in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(part.name)
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Assigned to this area")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }

        Spacer()

        // Area navigation
        HStack {
            Button {
                walkAreaIndex = max(0, walkAreaIndex - 1)
                loadWalkAreaData()
            } label: {
                Label("Prev", systemImage: "chevron.left")
            }
            .disabled(walkAreaIndex <= 0)

            Spacer()
            Text("Area \(walkAreaIndex + 1) of \(allWalkAreas.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                walkAreaIndex = min(allWalkAreas.count - 1, walkAreaIndex + 1)
                loadWalkAreaData()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(walkAreaIndex >= allWalkAreas.count - 1)
        }
        .padding()

        // Quick actions
        HStack(spacing: 12) {
            Button("Mark Empty") {
                markWalkAreaEmpty()
            }
            .buttonStyle(.bordered)

            Button("Skip Area") {
                walkAreaIndex = min(allWalkAreas.count - 1, walkAreaIndex + 1)
                loadWalkAreaData()
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}
```

The user walks through areas one-by-one, searching and assigning parts. Use `WarehouseService` methods to:
- List all areas from the floor plan
- Search parts from the catalog
- Assign a part to a location (update `part_locations` or `stock_locations` table)

### Step 5: Count Everything (FIX — make functional)

Replace with a per-area counting flow:

```swift
@ViewBuilder
private var step5CountEverything: some View {
    VStack(spacing: 0) {
        // Current area
        if let area = currentCountArea {
            VStack(spacing: 4) {
                Text("Count parts at:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(area.locationCode)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospaced()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.indigo.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }

        // IMPORTANT: System counts are HIDDEN — no cheating
        Text("Count each part on the shelf. System counts are hidden so you count fresh.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal)

        // Parts to count at this area
        List {
            ForEach(partsToCount) { partInfo in
                HStack {
                    VStack(alignment: .leading) {
                        Text(partInfo.name)
                            .font(.subheadline)
                        if let code = partInfo.partNumber {
                            Text(code)
                                .font(.caption)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    // Count input
                    TextField("Qty", value: Binding(
                        get: { countEntries[partInfo.id] },
                        set: { countEntries[partInfo.id] = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 80)

                    if countEntries[partInfo.id] != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)

        // Submit counts for this area
        Button("Submit Counts for This Area") {
            submitCountsForArea()
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .disabled(countEntries.isEmpty)

        // Area navigation (same pattern as Step 4)
        HStack {
            Button {
                countAreaIndex = max(0, countAreaIndex - 1)
                loadCountAreaData()
            } label: {
                Label("Prev", systemImage: "chevron.left")
            }
            .disabled(countAreaIndex <= 0)

            Spacer()
            Text("Area \(countAreaIndex + 1) of \(allCountAreas.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                countAreaIndex = min(allCountAreas.count - 1, countAreaIndex + 1)
                loadCountAreaData()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(countAreaIndex >= allCountAreas.count - 1)
        }
        .padding()
    }
}
```

Use `WarehouseService.submitAuditCount()` or equivalent to record the counted quantities. The system count must be HIDDEN — the user counts fresh without seeing what the system expects.

### Step 6: Set Targets (FIX — make functional)

Replace with MIN/TARGET/MAX entry with AI suggestions:

```swift
@ViewBuilder
private var step6SetTargets: some View {
    VStack(spacing: 0) {
        // AI suggestion banner
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text("Values suggested based on usage patterns. Adjust as needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.05))

        List {
            ForEach(partsNeedingTargets) { part in
                VStack(alignment: .leading, spacing: 8) {
                    Text(part.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        targetInput("MIN", value: Binding(
                            get: { targetValues[part.id]?.min ?? 0 },
                            set: { targetValues[part.id] = TargetValue(
                                min: $0,
                                target: targetValues[part.id]?.target ?? 0,
                                max: targetValues[part.id]?.max ?? 0
                            )}
                        ))
                        targetInput("TARGET", value: Binding(
                            get: { targetValues[part.id]?.target ?? 0 },
                            set: { targetValues[part.id] = TargetValue(
                                min: targetValues[part.id]?.min ?? 0,
                                target: $0,
                                max: targetValues[part.id]?.max ?? 0
                            )}
                        ))
                        targetInput("MAX", value: Binding(
                            get: { targetValues[part.id]?.max ?? 0 },
                            set: { targetValues[part.id] = TargetValue(
                                min: targetValues[part.id]?.min ?? 0,
                                target: targetValues[part.id]?.target ?? 0,
                                max: $0
                            )}
                        ))
                    }

                    // Accept AI suggestion
                    if let suggestion = aiSuggestions[part.id] {
                        Button {
                            targetValues[part.id] = suggestion
                        } label: {
                            Label("Accept AI: \(suggestion.min)/\(suggestion.target)/\(suggestion.max)",
                                  systemImage: "sparkles")
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)

        // Bulk actions
        HStack(spacing: 12) {
            Button("Accept All AI Values") {
                for (partId, suggestion) in aiSuggestions {
                    targetValues[partId] = suggestion
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Save Targets") {
                saveAllTargets()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

private func targetInput(_ label: String, value: Binding<Int>) -> some View {
    VStack(spacing: 2) {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
        TextField("0", value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numberPad)
            .frame(width: 60)
            .multilineTextAlignment(.center)
    }
}
```

Use `WarehouseService` methods to save MIN/TARGET/MAX values. For AI suggestions, check if a forecasting method exists — if not, use simple defaults (MIN=2, TARGET=5, MAX=10 for common parts; MIN=1, TARGET=2, MAX=5 for slow-movers).

## Part 2: Fix Navigation & Error Handling

### Save & Exit at Every Step

Ensure the wizard header has a "Save & Exit" button that:
1. Saves current step index to `@AppStorage("warehouseWizard_currentStep")`
2. Saves step-specific data (e.g., checked stickers, count entries)
3. Dismisses the wizard
4. When reopened, resumes at the saved step

```swift
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Save & Exit") {
            saveWizardState()
            dismiss()
        }
    }
}
```

### Error Handling

Every step must have:
```swift
@State private var stepError: String?

// In each step view:
if let error = stepError {
    HStack {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        Text(error)
            .font(.caption)
    }
    .padding()
    .background(Color.red.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .padding(.horizontal)
}
```

Wrap all `WarehouseService` calls in do/catch with meaningful error messages.

### Step Navigation

Steps can be revisited freely. The step indicator should show which steps are complete:

```swift
// Step indicator dots
HStack(spacing: 8) {
    ForEach(0..<6) { step in
        Circle()
            .fill(step == currentStep ? .blue :
                  completedWizardSteps.contains(step) ? .green : .gray.opacity(0.3))
            .frame(width: 10, height: 10)
            .onTapGesture {
                // Allow going back to completed steps or the next uncompleted step
                if step <= currentStep || completedWizardSteps.contains(step) {
                    currentStep = step
                }
            }
    }
}
```

## Part 3: Wire WarehouseService Methods

If any of these methods are missing from `WarehouseService`, create them:

1. `createStorageUnit(floorPlanId:name:unitType:levels:areasPerLevel:)` — creates unit + levels + areas
2. `listStorageUnits(floorPlanId:)` — returns all units for a floor plan
3. `deleteStorageUnit(id:)` — deletes unit and all its levels/areas
4. `listAreas(floorPlanId:)` — returns all areas across all units
5. `assignPartToLocation(partId:areaId:)` — assigns a part to a warehouse area
6. `getPartsAtArea(areaId:)` — returns parts assigned to an area
7. `submitInitialCount(areaId:partId:count:)` — records initial stock count
8. `setPartTargets(partId:locationId:min:target:max:)` — sets MIN/TARGET/MAX

Check what already exists first. Only create what's missing. Use existing table schemas — don't create new migrations unless absolutely necessary.

## Part 4: Fix IOSOrganizationAuditPage Routing

`IOSOrganizationAuditPage.swift` was flagged as orphaned in the audit. Wire it into the warehouse navigation:

1. Check `WarehouseRouter` or the warehouse tab configuration
2. Add a tab or navigation link to `IOSOrganizationAuditPage`
3. If it's already reachable via a different path, verify and document that path
4. If the page itself has issues, fix them

## Part 5: File Splitting (if needed)

If the wizard file exceeds 600 lines after fixes, split into:
- `WarehouseOnboardingWizard.swift` — main container + Step 1 + navigation
- `WarehouseWizardStep2.swift` — Place Units (add unit sheet, unit list)
- `WarehouseWizardStep3.swift` — Number Everything (sticker checklist)
- `WarehouseWizardStep4.swift` — Walk the Floor (part discovery)
- `WarehouseWizardStep5.swift` — Count Everything (count entry)
- `WarehouseWizardStep6.swift` — Set Targets (MIN/TARGET/MAX)

Each step file is a View that takes bindings/environment from the main wizard.

## Important Notes

- The user NEVER leaves the wizard. Every step does work inline (no "go to the Locations page" instructions).
- Save & Exit works at every step. Progress is saved to `@AppStorage`.
- Steps can be revisited. User can go back and forth freely.
- Skip for Now is always available. No step blocks the next (except Step 1 which must create the floor plan first).
- System counts are HIDDEN in Step 5. The user counts fresh — no copying the expected value.
- AI suggestions in Step 6 are best-effort. If no usage data exists, use sensible defaults.
- Area navigation in Steps 4 and 5 goes through every area created in Step 2.
- All service calls wrapped in do/catch with user-visible error messages.
- No raw SQL anywhere — use WarehouseService methods exclusively.

## Success Criteria

- [ ] Step 1 works: creates floor plan with room dimensions
- [ ] Step 2 works: add storage units inline (type, name, levels, areas per level)
- [ ] Step 2: added units show in list with green checkmarks, can be deleted
- [ ] Step 3 works: interactive sticker checklist auto-generated from Step 2 units
- [ ] Step 3: user checks off each sticker, progress persists
- [ ] Step 4 works: per-area walkthrough with part search + assign
- [ ] Step 4: can mark areas as empty or skip
- [ ] Step 5 works: per-part count entry with HIDDEN system counts
- [ ] Step 5: submit counts per area via WarehouseService
- [ ] Step 6 works: MIN/TARGET/MAX entry with AI suggestions
- [ ] Step 6: "Accept All AI Values" bulk action works
- [ ] Save & Exit works at every step (resumes where left off)
- [ ] Step dots show completed/current/incomplete status
- [ ] Error handling on every step (do/catch with visible error messages)
- [ ] No raw SQL — all calls go through WarehouseService
- [ ] Missing WarehouseService methods created if needed
- [ ] IOSOrganizationAuditPage reachable from warehouse navigation
- [ ] File split if wizard exceeds 600 lines
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 65C Results (YYYY-MM-DD)
- Step 1 (Room Dimensions): verified/fixed
- Step 2 (Place Units): functional inline
- Step 3 (Number Everything): interactive sticker checklist
- Step 4 (Walk the Floor): per-area part assignment
- Step 5 (Count Everything): per-area counting with hidden system counts
- Step 6 (Set Targets): MIN/TARGET/MAX with AI suggestions
- Save & Exit: works at every step
- Error handling: all steps wrapped in do/catch
- WarehouseService methods: X created/verified
- IOSOrganizationAuditPage: wired into navigation
- File split: yes/no (X files)
- Build: PASS/FAIL
```
