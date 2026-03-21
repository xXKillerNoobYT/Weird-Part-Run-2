import SwiftUI
import GRDB
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
    @State private var pickerSelection: Int64 = 0

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
            Picker("Add category", selection: $pickerSelection) {
                Text("Add category...").tag(Int64(0))
                ForEach(categories.filter { cat in
                    !selectedCategories.contains(where: { $0.categoryId == cat.id })
                }, id: \.id) { cat in
                    Text(cat.name).tag(cat.id ?? Int64(0))
                }
            }
            .onChange(of: pickerSelection) {
                if pickerSelection != 0, let cat = categories.first(where: { $0.id == pickerSelection }) {
                    selectedCategories.append(SelectedCategory(categoryId: pickerSelection, categoryName: cat.name))
                    pickerSelection = 0
                    Task { await analyze() }
                }
            }

            // Selected categories chips
            if !selectedCategories.isEmpty {
                WrappedHStack(spacing: 8) {
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
            let catIds = selectedCatIds
            let targetNames = matchedRules.map { $0.targetName }
            realExamples = try await db.writer.read { dbConn in
                let placeholders = catIds.map { _ in "?" }.joined(separator: ", ")
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
                    """, arguments: StatementArguments(catIds))

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
                        jobName: jobRow["job_name"] ?? "Unknown",
                        jobNumber: jobRow["job_number"] ?? "",
                        partsOrdered: parts.map {
                            (name: ($0["name"] as String?) ?? "",
                             category: ($0["cat_name"] as String?) ?? "",
                             qty: ($0["qty_consumed"] as Int?) ?? 0)
                        },
                        companionsThatWouldFire: targetNames
                    ))
                }
                return examples
            }

            // 3. Next level preview — check if deeper pairings exist in co_occurrence_pairs
            let matchedCatIds = matchedRules.flatMap { rule in
                [categories.first(where: { $0.name == rule.sourceName })?.id,
                 categories.first(where: { $0.name == rule.targetName })?.id]
            }.compactMap { $0 }

            if !matchedCatIds.isEmpty {
                nextLevelPreview = try await db.writer.read { dbConn in
                    let placeholders = matchedCatIds.map { _ in "?" }.joined(separator: ", ")
                    let rows = try Row.fetchAll(dbConn, sql: """
                        SELECT cop.id, cop.category_a_id, cop.category_b_id, cop.points,
                               cop.match_level, cop.confidence,
                               ca.name AS cat_a_name, cb.name AS cat_b_name
                        FROM co_occurrence_pairs cop
                        LEFT JOIN part_categories ca ON ca.id = cop.category_a_id
                        LEFT JOIN part_categories cb ON cb.id = cop.category_b_id
                        WHERE (cop.category_a_id IN (\(placeholders)) OR cop.category_b_id IN (\(placeholders)))
                          AND cop.match_level IN ('style', 'type')
                          AND cop.is_blocked = 0
                        ORDER BY cop.points DESC
                        LIMIT 5
                        """, arguments: StatementArguments(matchedCatIds + matchedCatIds))

                    return rows.map { row in
                        let catAName: String = row["cat_a_name"] ?? "Unknown"
                        let catBName: String = row["cat_b_name"] ?? "Unknown"
                        let matchLevel: String = row["match_level"] ?? "style"
                        let pts: Int = row["points"] ?? 0
                        let conf: Double = row["confidence"] ?? 0.0
                        let nextLevel = matchLevel == "category" ? "style" : (matchLevel == "style" ? "type" : "type")

                        return NextLevelPreview(
                            currentLevel: matchLevel,
                            nextLevel: nextLevel,
                            pairName: "\(catAName) + \(catBName)",
                            points: pts,
                            wouldQualify: conf >= 0.7
                        )
                    }
                }
            }

        } catch {
            // Sandbox is read-only best-effort — silently handle
        }

        isAnalyzing = false
    }
}

// MARK: - Wrapped HStack (Flow Layout)

/// Simple wrapping horizontal stack layout for chip display.
private struct WrappedHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(subviews: subviews, width: proposal.width ?? .infinity)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(subviews: subviews, width: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }

    private func computeLayout(subviews: Subviews, width: CGFloat) -> LayoutResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return LayoutResult(
            size: CGSize(width: maxWidth, height: y + rowHeight),
            positions: positions,
            sizes: sizes
        )
    }
}
