# 19E — Companion Rule Form Rebuild: Category/Style/Type Pickers

## Context
You are working on a SwiftUI iOS app. The current `CompanionRuleFormSheet` in `PartsCompanionsPage.swift` picks individual parts (wrong). Rules must work at the **category/style/type level** using cascading pickers.

**Available PartsService methods:**
- `listCategories()` → `[PartCategory]` (id, name)
- `listStyles(categoryId:)` → `[PartStyle]` (id, name, categoryId)
- `listTypes(styleId:)` → `[PartType]` (id, name, styleId)
- `createCompanionRuleAtLevel(name:, description:, qtyMode:, qtyRatio:, tryMatchBrand:, autoColorMatch:, parentRuleId:, sources:, targets:)` → Int64

**Hierarchy**: Category > Style > Type > Brand (Brand is auto-matched, not picked)

**Part hierarchy tables:**
- `part_categories` — id, name
- `part_styles` — id, name, category_id
- `part_types` — id, name, style_id

## Task

### 1. Replace `CompanionRuleFormSheet` entirely

Delete the current `CompanionRuleFormSheet` (lines ~420-523) and replace with a new one.

### 2. New CompanionRuleFormSheet design

```swift
private struct CompanionRuleFormSheet: View {
    let editingRule: PartsService.CompanionRuleHierarchyRow?  // nil = create mode
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var ruleName = ""
    @State private var ruleDescription = ""
    @State private var matchLevel = "category"  // "category", "style", "type"
    @State private var tryMatchBrand = false
    @State private var autoColorMatch = true
    @State private var qtyMode = "sum"          // "sum", "ratio", "fixed"
    @State private var qtyRatio: Double = 1.0

    // Source picker state
    @State private var sourceCategoryId: Int64 = 0
    @State private var sourceStyleId: Int64 = 0
    @State private var sourceTypeId: Int64 = 0

    // Target picker state
    @State private var targetCategoryId: Int64 = 0
    @State private var targetStyleId: Int64 = 0
    @State private var targetTypeId: Int64 = 0

    // Picker data
    @State private var categories: [PartCategory] = []
    @State private var sourceStyles: [PartStyle] = []
    @State private var sourceTypes: [PartType] = []
    @State private var targetStyles: [PartStyle] = []
    @State private var targetTypes: [PartType] = []

    // Error + loading
    @State private var saveError: String?
    @State private var isSaving = false

    private let matchLevels = ["category", "style", "type"]
    private let qtyModes = ["sum", "ratio", "fixed"]

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Rule Info
                Section("Rule Name") {
                    TextField("e.g., Wire → Wire Nuts", text: $ruleName)
                    TextField("Description (optional)", text: $ruleDescription)
                }

                // Section 2: Match Level
                Section("Match Level") {
                    Picker("Level", selection: $matchLevel) {
                        Text("Category").tag("category")
                        Text("Style").tag("style")
                        Text("Type").tag("type")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: matchLevel) { _ in
                        // Reset lower-level selections when level changes
                        if matchLevel == "category" {
                            sourceStyleId = 0; sourceTypeId = 0
                            targetStyleId = 0; targetTypeId = 0
                        } else if matchLevel == "style" {
                            sourceTypeId = 0; targetTypeId = 0
                        }
                    }
                }

                // Section 3: Source — "When ordering..."
                Section("Source — When ordering from...") {
                    Picker("Category", selection: $sourceCategoryId) {
                        Text("Select category...").tag(Int64(0))
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id ?? Int64(0))
                        }
                    }
                    .onChange(of: sourceCategoryId) { newVal in
                        sourceStyleId = 0; sourceTypeId = 0
                        Task { await loadSourceStyles() }
                    }

                    if matchLevel != "category" {
                        Picker("Style", selection: $sourceStyleId) {
                            Text("Select style...").tag(Int64(0))
                            ForEach(sourceStyles, id: \.id) { style in
                                Text(style.name).tag(style.id ?? Int64(0))
                            }
                        }
                        .onChange(of: sourceStyleId) { _ in
                            sourceTypeId = 0
                            Task { await loadSourceTypes() }
                        }
                    }

                    if matchLevel == "type" {
                        Picker("Type", selection: $sourceTypeId) {
                            Text("Select type...").tag(Int64(0))
                            ForEach(sourceTypes, id: \.id) { type in
                                Text(type.name).tag(type.id ?? Int64(0))
                            }
                        }
                    }
                }

                // Section 4: Target — "Also suggest..."
                Section("Target — Also suggest from...") {
                    Picker("Category", selection: $targetCategoryId) {
                        Text("Select category...").tag(Int64(0))
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id ?? Int64(0))
                        }
                    }
                    .onChange(of: targetCategoryId) { newVal in
                        targetStyleId = 0; targetTypeId = 0
                        Task { await loadTargetStyles() }
                    }

                    if matchLevel != "category" {
                        Picker("Style", selection: $targetStyleId) {
                            Text("Select style...").tag(Int64(0))
                            ForEach(targetStyles, id: \.id) { style in
                                Text(style.name).tag(style.id ?? Int64(0))
                            }
                        }
                        .onChange(of: targetStyleId) { _ in
                            targetTypeId = 0
                            Task { await loadTargetTypes() }
                        }
                    }

                    if matchLevel == "type" {
                        Picker("Type", selection: $targetTypeId) {
                            Text("Select type...").tag(Int64(0))
                            ForEach(targetTypes, id: \.id) { type in
                                Text(type.name).tag(type.id ?? Int64(0))
                            }
                        }
                    }
                }

                // Section 5: Options
                Section("Options") {
                    Toggle("Try to Match Brand", isOn: $tryMatchBrand)
                    Toggle("Auto-Match Color", isOn: $autoColorMatch)

                    Picker("Quantity Mode", selection: $qtyMode) {
                        Text("Sum").tag("sum")
                        Text("Ratio").tag("ratio")
                        Text("Fixed").tag("fixed")
                    }

                    if qtyMode != "sum" {
                        HStack {
                            Text("Qty Ratio")
                            Spacer()
                            TextField("1.0", value: $qtyRatio, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                // Error display
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(editingRule == nil ? "New Companion Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!isValid)
                    }
                }
            }
            .task { await loadCategories() }
            .onAppear { populateFromEditingRule() }
        }
    }

    // Validation: source and target must be selected at the correct level
    private var isValid: Bool {
        guard !ruleName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard sourceCategoryId != 0 && targetCategoryId != 0 else { return false }
        if matchLevel != "category" {
            guard sourceStyleId != 0 && targetStyleId != 0 else { return false }
        }
        if matchLevel == "type" {
            guard sourceTypeId != 0 && targetTypeId != 0 else { return false }
        }
        // Source and target can't be identical
        if matchLevel == "category" { return sourceCategoryId != targetCategoryId }
        if matchLevel == "style" { return sourceStyleId != targetStyleId }
        if matchLevel == "type" { return sourceTypeId != targetTypeId }
        return true
    }

    // Populate form from editing rule (if in edit mode)
    private func populateFromEditingRule() {
        guard let rule = editingRule else { return }
        ruleName = rule.name
        ruleDescription = rule.description ?? ""
        matchLevel = rule.matchLevel
        tryMatchBrand = rule.tryMatchBrand == 1
        autoColorMatch = rule.autoColorMatch == 1
        qtyMode = rule.qtyMode
        qtyRatio = rule.qtyRatio
        if let src = rule.sources.first {
            sourceCategoryId = src.categoryId
            sourceStyleId = src.styleId ?? 0
            sourceTypeId = src.typeId ?? 0
        }
        if let tgt = rule.targets.first {
            targetCategoryId = tgt.categoryId
            targetStyleId = tgt.styleId ?? 0
            targetTypeId = tgt.typeId ?? 0
        }
    }

    // Load categories, styles, types from PartsService
    private func loadCategories() async {
        do {
            guard let service = appCore.partsService else { return }
            categories = try service.listCategories()
        } catch { saveError = "Failed to load categories" }
    }

    private func loadSourceStyles() async {
        guard sourceCategoryId != 0, let service = appCore.partsService else { sourceStyles = []; return }
        do { sourceStyles = try service.listStyles(categoryId: sourceCategoryId) }
        catch { saveError = "Failed to load styles" }
    }

    private func loadSourceTypes() async {
        guard sourceStyleId != 0, let service = appCore.partsService else { sourceTypes = []; return }
        do { sourceTypes = try service.listTypes(styleId: sourceStyleId) }
        catch { saveError = "Failed to load types" }
    }

    private func loadTargetStyles() async {
        guard targetCategoryId != 0, let service = appCore.partsService else { targetStyles = []; return }
        do { targetStyles = try service.listStyles(categoryId: targetCategoryId) }
        catch { saveError = "Failed to load styles" }
    }

    private func loadTargetTypes() async {
        guard targetStyleId != 0, let service = appCore.partsService else { targetTypes = []; return }
        do { targetTypes = try service.listTypes(styleId: targetStyleId) }
        catch { saveError = "Failed to load types" }
    }

    // Save
    private func save() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else { throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Service unavailable"]) }

            let sources = [(categoryId: sourceCategoryId,
                           styleId: matchLevel != "category" ? sourceStyleId : nil as Int64?,
                           typeId: matchLevel == "type" ? sourceTypeId : nil as Int64?)]
            let targets = [(categoryId: targetCategoryId,
                           styleId: matchLevel != "category" ? targetStyleId : nil as Int64?,
                           typeId: matchLevel == "type" ? targetTypeId : nil as Int64?)]

            if let existing = editingRule {
                // Update existing rule: delete old sources/targets, update rule, re-add sources/targets
                try service.updateCompanionRule(id: existing.id, name: ruleName, description: ruleDescription,
                                                qtyMode: qtyMode, qtyRatio: qtyRatio)
                // Note: updateCompanionRule may need to be extended to support tryMatchBrand/autoColorMatch
                // For now, use raw update if needed
            } else {
                try service.createCompanionRuleAtLevel(
                    name: ruleName,
                    description: ruleDescription.isEmpty ? nil : ruleDescription,
                    qtyMode: qtyMode,
                    qtyRatio: qtyRatio,
                    tryMatchBrand: tryMatchBrand,
                    autoColorMatch: autoColorMatch,
                    sources: sources,
                    targets: targets
                )
            }

            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

### 3. Update ActiveSheet enum

Add an `.editRule(PartsService.CompanionRuleHierarchyRow)` case to the `ActiveSheet` enum:
```swift
case addRule
case editRule(PartsService.CompanionRuleHierarchyRow)
case addAlternative
```

Update the `.sheet(item:)` handler to pass `editingRule:` to `CompanionRuleFormSheet`:
```swift
case .addRule:
    CompanionRuleFormSheet(editingRule: nil) { await loadData() }
case .editRule(let rule):
    CompanionRuleFormSheet(editingRule: rule) { await loadData() }
```

### 4. Add tap-to-edit on rule rows

Add `.onTapGesture { activeSheet = .editRule(rule) }` to each rule row in the list.

### 5. Delete the old `PartPickerItem` struct

Remove `PartPickerItem` (line 631-634) — it's no longer needed since we use category/style/type pickers.

## Success Criteria
- [ ] Rule form uses cascading category → style → type pickers (not individual part pickers)
- [ ] Match level segmented control (Category/Style/Type) controls which pickers are visible
- [ ] "Try to Match Brand" and "Auto-Match Color" toggles work
- [ ] Qty mode picker (Sum/Ratio/Fixed) with ratio input
- [ ] Form validates: name required, source and target required at correct level, can't be identical
- [ ] Edit mode pre-populates from existing rule
- [ ] Tap a rule row → opens edit form
- [ ] PartPickerItem struct removed
- [ ] Save errors shown in form
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19E Results (YYYY-MM-DD)
- Replaced CompanionRuleFormSheet with hierarchy pickers (category/style/type)
- Added match level segmented control, brand/color toggles, qty mode picker
- Added edit mode support (tap row → edit form)
- Removed PartPickerItem struct
- Added form validation + save error display
- Build: [PASS/FAIL]
```

When done, start prompt 19F next.
