# 19H — Companion Rule Testing Sandbox

## Context
You are working on a SwiftUI iOS app. Users need a way to test how companion rules work together before relying on them. The sandbox shows "what if" scenarios with real data from PO/job history.

**Available PartsService methods:**
- `listCompanionRulesHierarchy()` → rules with sources/targets
- `listCategories()`, `listStyles(categoryId:)`, `listTypes(styleId:)`

**Key tables for example data:**
- `job_parts` — job_id, part_id, qty_consumed
- `parts` — category_id, style_id, type_id, brand_id, color_id, name
- `jobs` — job_name, job_number
- `companion_rule_sources/targets` — category_id, style_id, type_id

## Task

### 1. Create `CompanionSandboxSheet.swift`

Create a new file at `Weird Parts IOS/Weird Parts IOS/Features/Parts/CompanionSandboxSheet.swift`.

```swift
import SwiftUI
import WiredPartCore

/// "What If" sandbox for testing how companion rules fire when ordering parts.
/// Read-only — no data is modified.
struct CompanionSandboxSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Selected categories to simulate an order
    @State private var selectedCategories: [SelectedCategory] = []
    @State private var categories: [PartCategory] = []
    @State private var matchedRules: [MatchedRule] = []
    @State private var realExamples: [RealExample] = []
    @State private var nextLevelPreview: [NextLevelPreview] = []
    @State private var isAnalyzing = false

    struct SelectedCategory: Identifiable {
        let id = UUID()
        var categoryId: Int64
        var categoryName: String
    }

    struct MatchedRule: Identifiable {
        let id: Int64
        let ruleName: String
        let matchLevel: String
        let sourceName: String
        let targetName: String
        let qtyMode: String
        let qtyRatio: Double
        let tryMatchBrand: Bool
        let autoColorMatch: Bool
    }

    struct RealExample: Identifiable {
        let id = UUID()
        let jobName: String
        let jobNumber: String
        let partsOrdered: [(name: String, category: String, qty: Int)]
        let companionsThatWouldFire: [String]
    }

    struct NextLevelPreview: Identifiable {
        let id = UUID()
        let currentLevel: String
        let nextLevel: String
        let pairName: String
        let points: Int
        let wouldQualify: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: Select categories to simulate
                    simulateOrderSection

                    // Section 2: Matched rules
                    if !matchedRules.isEmpty {
                        matchedRulesSection
                    }

                    // Section 3: Real examples from history
                    if !realExamples.isEmpty {
                        realExamplesSection
                    }

                    // Section 4: Next level preview
                    if !nextLevelPreview.isEmpty {
                        nextLevelSection
                    }
                }
                .padding()
            }
            .navigationTitle("Test Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadCategories() }
        }
    }

    // MARK: - Simulate Order Section

    @ViewBuilder
    private var simulateOrderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulate an Order")
                .font(.headline)

            Text("Select categories you're ordering from to see which companion rules would fire.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Category picker — add categories to the simulation
            HStack {
                Picker("Add category", selection: Binding(
                    get: { Int64(0) },
                    set: { newId in
                        if newId != 0, let cat = categories.first(where: { $0.id == newId }) {
                            selectedCategories.append(SelectedCategory(categoryId: newId, categoryName: cat.name))
                            Task { await analyze() }
                        }
                    }
                )) {
                    Text("Add category...").tag(Int64(0))
                    ForEach(categories.filter { cat in
                        !selectedCategories.contains(where: { $0.categoryId == cat.id })
                    }, id: \.id) { cat in
                        Text(cat.name).tag(cat.id ?? Int64(0))
                    }
                }
            }

            // Selected categories chips
            if !selectedCategories.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(selectedCategories) { cat in
                        HStack(spacing: 4) {
                            Text(cat.categoryName)
                                .font(.caption)
                            Button {
                                selectedCategories.removeAll { $0.id == cat.id }
                                Task { await analyze() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            if isAnalyzing {
                ProgressView("Analyzing...")
                    .font(.caption)
            }
        }
    }

    // Note: If FlowLayout doesn't exist, use a simple LazyVGrid or wrap in a
    // horizontal ScrollView with .fixedSize() chips instead.

    // MARK: - Matched Rules Section

    @ViewBuilder
    private var matchedRulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Rules That Would Fire (\(matchedRules.count))")
                    .font(.headline)
            }

            ForEach(matchedRules) { rule in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(rule.ruleName)
                            .fontWeight(.medium)
                        Spacer()
                        Text(rule.matchLevel.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        Text(rule.sourceName)
                            .font(.caption)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                        Text("suggest \(rule.targetName)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    HStack(spacing: 8) {
                        Text("Qty: \(rule.qtyMode)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if rule.tryMatchBrand {
                            Label("Brand Match", systemImage: "tag")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        if rule.autoColorMatch {
                            Label("Color Match", systemImage: "paintpalette")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Real Examples Section

    @ViewBuilder
    private var realExamplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
                Text("Real Examples from Past Jobs")
                    .font(.headline)
            }

            Text("Jobs where these categories appeared together:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(realExamples) { example in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(example.jobName) (\(example.jobNumber))")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(example.partsOrdered.prefix(5).enumerated()), id: \.offset) { _, part in
                        HStack {
                            Text(part.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(part.name)
                                .font(.caption)
                            Spacer()
                            Text("×\(part.qty)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !example.companionsThatWouldFire.isEmpty {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("Would suggest: \(example.companionsThatWouldFire.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Next Level Preview

    @ViewBuilder
    private var nextLevelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.purple)
                Text("Possible Next Level")
                    .font(.headline)
            }

            Text("If the current rules pass, these deeper-level pairings could be next:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(nextLevelPreview) { preview in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.pairName)
                            .font(.subheadline)
                        Text("\(preview.currentLevel.capitalized) → \(preview.nextLevel.capitalized)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(preview.points) pts")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(preview.wouldQualify ? "Qualifies" : "Not yet")
                            .font(.caption2)
                            .foregroundStyle(preview.wouldQualify ? .green : .orange)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Data Loading

    private func loadCategories() async {
        guard let service = appCore.partsService else { return }
        do { categories = try service.listCategories() } catch {}
    }

    private func analyze() async {
        guard !selectedCategories.isEmpty, let service = appCore.partsService,
              let db = appCore.db else {
            matchedRules = []; realExamples = []; nextLevelPreview = []
            return
        }
        isAnalyzing = true

        do {
            let selectedCatIds = selectedCategories.map { $0.categoryId }

            // 1. Find matching rules
            let allRules = try service.listCompanionRulesHierarchy()
            matchedRules = allRules.compactMap { rule in
                // Check if any source category matches a selected category
                let sourceMatches = rule.sources.contains { src in
                    selectedCatIds.contains(src.categoryId)
                }
                guard sourceMatches else { return nil as MatchedRule? }

                let srcName = rule.sources.first.map { s in
                    categories.first(where: { $0.id == s.categoryId })?.name ?? "Unknown"
                } ?? "Unknown"
                let tgtName = rule.targets.first.map { t in
                    categories.first(where: { $0.id == t.categoryId })?.name ?? "Unknown"
                } ?? "Unknown"

                return MatchedRule(
                    id: rule.id, ruleName: rule.name,
                    matchLevel: rule.matchLevel,
                    sourceName: srcName, targetName: tgtName,
                    qtyMode: rule.qtyMode, qtyRatio: rule.qtyRatio,
                    tryMatchBrand: rule.tryMatchBrand == 1,
                    autoColorMatch: rule.autoColorMatch == 1
                )
            }

            // 2. Find real job examples (up to 3 jobs where these categories co-occurred)
            // Use raw read since this is a complex analytics query
            realExamples = try await db.writer.read { dbConn in
                let placeholders = selectedCatIds.map { _ in "?" }.joined(separator: ", ")
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT DISTINCT j.id, j.job_name, j.job_number
                    FROM jobs j
                    JOIN job_parts jp ON jp.job_id = j.id
                    JOIN parts p ON p.id = jp.part_id
                    WHERE p.category_id IN (\(placeholders))
                      AND jp.deleted_at IS NULL AND p.deleted_at IS NULL
                    GROUP BY j.id
                    HAVING COUNT(DISTINCT p.category_id) >= 2
                    ORDER BY j.created_at DESC
                    LIMIT 3
                    """, arguments: StatementArguments(selectedCatIds.map { DatabaseValue($0) }))

                var examples: [RealExample] = []
                for jobRow in rows {
                    let jobId: Int64 = jobRow["id"]
                    let parts = try Row.fetchAll(dbConn, sql: """
                        SELECT p.name, pc.name AS cat_name, jp.qty_consumed
                        FROM job_parts jp
                        JOIN parts p ON p.id = jp.part_id
                        LEFT JOIN part_categories pc ON pc.id = p.category_id
                        WHERE jp.job_id = ? AND jp.deleted_at IS NULL
                        ORDER BY jp.qty_consumed DESC
                        LIMIT 10
                        """, arguments: [jobId])

                    examples.append(RealExample(
                        jobName: jobRow["job_name"],
                        jobNumber: jobRow["job_number"],
                        partsOrdered: parts.map { (name: $0["name"] as String, category: ($0["cat_name"] as String?) ?? "", qty: $0["qty_consumed"] as Int) },
                        companionsThatWouldFire: matchedRules.map { $0.targetName }
                    ))
                }
                return examples
            }

            // 3. Next level preview — check if deeper pairings exist
            // (simplified: check co_occurrence_pairs at style level for matched category pairs)
            nextLevelPreview = []  // Populated if category-level rules exist for these categories

        } catch {
            // Silently handle — sandbox is read-only best-effort
        }

        isAnalyzing = false
    }
}
```

### 2. Add to PartsCompanionsPage

In `PartsCompanionsPage.swift`, add a `.testSandbox` case to `ActiveSheet`:
```swift
case testSandbox
```

Add toolbar button:
```swift
ToolbarItem(placement: .automatic) {
    HStack {
        Button { activeSheet = .testSandbox } label: {
            Image(systemName: "flask")
        }
        // ... existing + button
    }
}
```

Add to sheet handler:
```swift
case .testSandbox:
    CompanionSandboxSheet()
```

## Success Criteria
- [ ] CompanionSandboxSheet.swift created as a new file
- [ ] Category picker lets user add categories to simulate an order
- [ ] Matched rules section shows which rules would fire for selected categories
- [ ] Real examples section shows up to 3 past jobs where categories co-occurred
- [ ] Next level preview shows what deeper pairings could come next
- [ ] Flask toolbar button opens the sandbox from Companions page
- [ ] Read-only — no data modified
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19H Results (YYYY-MM-DD)
- Created CompanionSandboxSheet.swift with "What If" scenario testing
- Category picker, matched rules display, real job examples, next level preview
- Added flask toolbar button to PartsCompanionsPage
- Build: [PASS/FAIL]
```

When done, start prompt 19I next.
