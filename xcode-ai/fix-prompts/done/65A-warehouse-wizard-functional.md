# 65A — Warehouse Onboarding Wizard: Make ALL Steps Functional

> **Chain position:** Standalone
> **Priority:** HIGH — the wizard is text-only, needs to actually DO things
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

The warehouse onboarding wizard (`WarehouseOnboardingWizard.swift`) currently has 6 steps but only Step 1 actually does anything. Steps 2-6 are instructional text that tells the user to go somewhere else. This defeats the purpose of a guided setup.

**Rebuild Steps 2-6 to be FULLY FUNCTIONAL inline.** The user should be able to complete the entire warehouse setup without leaving the wizard.

**Read these files first:**
- `Features/Warehouse/WarehouseOnboardingWizard.swift` — current wizard (560 lines)
- `Features/Warehouse/WarehouseLocationsPage.swift` — has the floor plan editor, unit placement, area management
- `Features/Warehouse/IOSAuditPage.swift` — has the count audit flow
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — all warehouse service methods

## What Each Step Must Do

### Step 2: Place Storage Units (FUNCTIONAL)

Instead of "go to Locations page," embed a simplified unit placement flow:

```swift
@ViewBuilder
private var step2PlaceUnits: some View {
    VStack(spacing: 0) {
        // Header
        Text("Add your storage units — shelves, pipe racks, gang boxes, etc.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()

        // Add unit button
        Button {
            showAddUnitSheet = true
        } label: {
            Label("+ Add Storage Unit", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)

        // List of units added so far
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
            }
            .listStyle(.insetGrouped)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "cabinet.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No storage units added yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Tap the button above to add your first shelf, rack, or storage area.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
        }

        Spacer()
    }
}
```

The "Add Storage Unit" sheet should be a simplified version of `AddStorageUnitSheet` from WarehouseLocationsPage — asking for:
- Unit name (e.g., "Shelf A")
- Type picker (Shelf, Pipe Rack, Gang Box, Wall Mount, Cabinet, Pallet Rack, Floor Area)
- Number of shelves/levels
- Number of areas per level (can be different per level)
- Width/depth/height (optional — can set later)

After adding, the unit shows in the list with a green checkmark. The user can add as many as they want, or skip to the next step.

### Step 3: Number Everything (FUNCTIONAL)

Instead of just showing examples, show an INTERACTIVE CHECKLIST of all the location codes the user needs to write on stickers:

```swift
@ViewBuilder
private var step3NumberEverything: some View {
    VStack(spacing: 0) {
        // Instructions
        VStack(spacing: 8) {
            Text("Write these codes on stickers and place them")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Grab a Sharpie and sticker sheet. Check each one off as you place it.")
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

The sticker items are auto-generated from the units added in Step 2. Each unit generates: row sticker, unit sticker, per-level stickers, per-area stickers.

### Step 4: Walk the Floor (FUNCTIONAL)

Instead of "go to Locations page," embed a per-area part discovery flow:

```swift
@ViewBuilder
private var step4WalkTheFloor: some View {
    VStack(spacing: 0) {
        // Current area indicator
        if let area = currentArea {
            VStack(spacing: 4) {
                Text("You are at:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(area.fullCode)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospaced()
                Text(area.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }

        // Search + add parts to this area
        HStack {
            TextField("Search parts...", text: $partSearchText)
                .textFieldStyle(.roundedBorder)
            Button { showAddPartSheet = true } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
        .padding(.horizontal)

        // Parts assigned to this area
        if !partsInCurrentArea.isEmpty {
            List {
                ForEach(partsInCurrentArea) { part in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(part.name)
                            .font(.subheadline)
                        if let code = part.code {
                            Text(code)
                                .font(.caption)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }

        // Area navigation
        HStack {
            Button {
                goToPreviousArea()
            } label: {
                Label("Prev Area", systemImage: "chevron.left")
            }
            .disabled(currentAreaIndex <= 0)

            Spacer()

            Text("Area \(currentAreaIndex + 1) of \(allAreas.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                goToNextArea()
            } label: {
                Label("Next Area", systemImage: "chevron.right")
            }
            .disabled(currentAreaIndex >= allAreas.count - 1)
        }
        .padding()

        // Skip/empty buttons
        HStack {
            Button("Mark Empty") {
                markAreaEmpty()
                goToNextArea()
            }
            .buttonStyle(.bordered)

            Button("Skip for Now") {
                goToNextArea()
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal)
    }
}
```

The user walks through areas one-by-one: identify what parts are here, search or add new parts, then move to the next area.

### Step 5: Count Everything (FUNCTIONAL)

Embed a counting flow similar to the audit page, but simpler:

```swift
@ViewBuilder
private var step5CountEverything: some View {
    VStack(spacing: 0) {
        // Current area
        if let area = currentCountArea {
            Text(area.fullCode)
                .font(.title3)
                .fontWeight(.bold)
                .monospaced()
                .padding()
        }

        // Parts to count at this area (counts HIDDEN)
        List {
            ForEach(partsToCount) { part in
                HStack {
                    VStack(alignment: .leading) {
                        Text(part.name)
                            .font(.subheadline)
                        if let code = part.code {
                            Text(code)
                                .font(.caption)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    // Count input (system count HIDDEN — no cheating)
                    TextField("Count", value: $partCounts[part.id], format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)

                    if partCounts[part.id] != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)

        // Area navigation (same as Step 4)
        // Submit counts button
        Button("Submit Counts for This Area") {
            submitCounts()
            goToNextCountArea()
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .disabled(partsToCount.allSatisfy { partCounts[$0.id] == nil })
    }
}
```

### Step 6: Set Targets (FUNCTIONAL)

Show each part with AI-suggested MIN/TARGET/MAX values:

```swift
@ViewBuilder
private var step6SetTargets: some View {
    VStack(spacing: 0) {
        // AI suggestion banner
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text("Values suggested based on your order history. Adjust as needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.05))

        List {
            ForEach(partsForTargets) { part in
                VStack(alignment: .leading, spacing: 8) {
                    Text(part.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        targetField("MIN", value: $partTargets[part.id]?.min, suggestion: part.suggestedMin)
                        targetField("TARGET", value: $partTargets[part.id]?.target, suggestion: part.suggestedTarget)
                        targetField("MAX", value: $partTargets[part.id]?.max, suggestion: part.suggestedMax)
                    }

                    // Accept AI suggestion button
                    if part.hasSuggestion {
                        Button("Accept AI Values") {
                            partTargets[part.id] = TargetValues(
                                min: part.suggestedMin,
                                target: part.suggestedTarget,
                                max: part.suggestedMax
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)

        // Bulk accept
        Button("Accept All AI Suggestions") {
            acceptAllSuggestions()
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}
```

## Key Design Rules

1. **The user NEVER leaves the wizard.** Every step does the work inline.
2. **Save & Exit works at any step.** Progress is saved. User can come back tomorrow.
3. **Steps can be revisited.** User can go back and forth freely.
4. **Skip for Now is always available.** No step blocks the next (except Step 1 which must create the floor plan).
5. **System counts are HIDDEN in Step 5.** User counts fresh — no copying.
6. **AI suggestions in Step 6.** User can accept all, adjust individually, or skip.
7. **Area navigation** in Steps 4 and 5 goes through every area created in Step 2.
8. **The Quick Count wizard** should also be functional — it combines Steps 4+5 without requiring Steps 1-3.

## File Structure

The wizard is getting large. Split into multiple files:
- `WarehouseOnboardingWizard.swift` — main wizard container + Step 1
- `WarehouseOnboardingStep2.swift` — Place Units (add unit sheet, unit list)
- `WarehouseOnboardingStep3.swift` — Number Everything (sticker checklist)
- `WarehouseOnboardingStep4.swift` — Walk the Floor (part discovery per area)
- `WarehouseOnboardingStep5.swift` — Count Everything (count entry per area)
- `WarehouseOnboardingStep6.swift` — Set Targets (MIN/TARGET/MAX with AI)

Each step file is a View that takes bindings from the main wizard.

## Success Criteria

- [ ] Step 2: Can add storage units inline (type, name, levels, areas)
- [ ] Step 2: Added units show in a list with green checkmarks
- [ ] Step 3: Interactive sticker checklist auto-generated from units
- [ ] Step 3: User checks off each sticker as they place it
- [ ] Step 4: Per-area walkthrough with search + add parts
- [ ] Step 4: Can mark areas as empty or skip
- [ ] Step 5: Per-part count entry with hidden system counts
- [ ] Step 5: Submit counts per area
- [ ] Step 6: AI-suggested MIN/TARGET/MAX values shown
- [ ] Step 6: Accept All or adjust individually
- [ ] Save & Exit works at every step
- [ ] Quick Count wizard is also functional
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 65A Results (YYYY-MM-DD)
- Step 2: unit placement functional
- Step 3: sticker checklist functional
- Step 4: part discovery per area functional
- Step 5: counting per area functional
- Step 6: target setting with AI functional
- Quick Count: functional
- Files created: X split files
- Build: PASS/FAIL
```
