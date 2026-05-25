import SwiftUI
import WiredPartCore

/// Demand forecasting page showing parts with their forecast data.
///
/// Displays average daily usage (ADU), reorder points, suggested orders,
/// and days until low stock. Color-coded urgency indicators help prioritize
/// reordering decisions. Trend arrows compare ADU-30 vs ADU-90.
struct PartsForecastingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - ActiveSheet

    private enum ActiveSheet: Identifiable {
        case help
        case forecastSettings
        case forecastDetail(PartsService.ForecastDataRow)
        var id: String {
            switch self {
            case .help: return "help"
            case .forecastSettings: return "forecastSettings"
            case .forecastDetail(let row): return "forecastDetail_\(row.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var forecastRows: [PartsService.ForecastDataRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var filterUrgency: UrgencyFilter = .all
    @State private var isRecalculating = false

    // Location picker
    @State private var selectedLocationType: String = "all"
    @State private var selectedLocationId: Int64?
    @State private var availableLocations: [LocationOption] = []

    // Recommendations
    @State private var recommendations: [TargetRecommendation] = []
    @State private var recommendationCount: Int = 0
    @State private var showRecommendations = false
    @State private var dismissReason = ""
    @State private var showDismissAlert = false
    @State private var dismissingRecommendation: TargetRecommendation?

    // Cached urgency counts and top-critical summaries — populated via single pass in loadData();
    // avoids per-render filter scans in stat cards and eliminates a separate filter in postForecastContext.
    @State private var urgencyCounts: [UrgencyFilter: Int] = [:]
    @State private var topCriticalSummary: String = ""

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "parts-forecasting")

            if isLoading {
                ProgressView("Loading forecast data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if filteredRows.isEmpty {
                emptyState
            } else {
                forecastList
            }
        }
        .searchable(text: $searchText, prompt: "Search parts...")
        .refreshable { await loadData() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Forecasting Help",
                    sections: [
                        ("Overview", "Demand forecasting shows predicted usage for each part based on historical consumption. Color-coded urgency helps prioritize reorders."),
                        ("Metrics", "ADU is Average Daily Usage. The trend arrow compares 30-day vs 90-day ADU. Reorder points are calculated from lead times and safety stock."),
                        ("Actions", "Tap Recalculate to refresh all forecasts. Use the lightbulb icon to see AI-generated reorder recommendations.")
                    ]
                )
            case .forecastSettings:
                ForecastSettingsSheet { await loadData() }
            case .forecastDetail(let row):
                ForecastDetailSheet(row: row)
            }
        }
        .presentationDetents([.medium, .large])
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await recalculateForecasts() }
                } label: {
                    if isRecalculating {
                        ProgressView()
                    } else {
                        Label("Recalculate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isRecalculating)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showRecommendations.toggle()
                    if showRecommendations { Task { await loadRecommendations() } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .accessibilityHidden(true)
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
            ToolbarItem(placement: .secondaryAction) {
                Button { activeSheet = .forecastSettings } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
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
                              let userId = appCore.currentUser?.id else {
                            loadError = "Parts service not available"
                            return
                        }
                        do {
                            guard let recId = rec.id else { return }
                            try service.dismissRecommendation(id: recId, byUserId: userId, reason: dismissReason)
                            await loadRecommendations()
                        } catch {
                            loadError = userFriendlyError(error, context: "dismiss recommendation")
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
        .background(DS.Background.page)
        .task {
            loadLocations()
            await loadData()
            await loadRecommendations()
            appCore.onboardingManager?.markCompleted("forecast-view")
        }
        .onDisappear {
            NotificationCenter.default.post(name: .forecastingPageInactive, object: nil)
        }
    }

    // MARK: - Filtered

    private var filteredRows: [PartsService.ForecastDataRow] {
        var result = forecastRows

        switch filterUrgency {
        case .all:
            break
        case .critical:
            result = result.filter { UrgencyFilter.classify($0.part.forecastDaysUntilLow ?? 999) == .critical }
        case .warning:
            result = result.filter { UrgencyFilter.classify($0.part.forecastDaysUntilLow ?? 999) == .warning }
        case .healthy:
            result = result.filter { UrgencyFilter.classify($0.part.forecastDaysUntilLow ?? 999) == .healthy }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.part.name.lowercased().contains(query) ||
                ($0.part.code?.lowercased().contains(query) ?? false)
            }
        }

        // Sort by urgency (most urgent first)
        result.sort { ($0.part.forecastDaysUntilLow ?? 999) < ($1.part.forecastDaysUntilLow ?? 999) }
        return result
    }

    // MARK: - Forecast List

    @ViewBuilder
    private var forecastList: some View {
        List {
            // Summary stat cards — tappable filters
            Section {
                HStack(spacing: 12) {
                    statCard(
                        label: "Critical",
                        count: urgencyCounts[.critical, default: 0],
                        color: .red,
                        filter: .critical
                    )
                    statCard(
                        label: "Warning",
                        count: urgencyCounts[.warning, default: 0],
                        color: .orange,
                        filter: .warning
                    )
                    statCard(
                        label: "Healthy",
                        count: urgencyCounts[.healthy, default: 0],
                        color: .green,
                        filter: .healthy
                    )
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Location picker
            if !availableLocations.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
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
            }

            // Recommendations section
            if showRecommendations && !recommendations.isEmpty {
                Section("Recommendations (\(recommendations.count))") {
                    ForEach(recommendations) { rec in
                        recommendationCard(rec)
                    }
                }
            }

            Section {
                ForEach(filteredRows) { row in
                    Button {
                        activeSheet = .forecastDetail(row)
                    } label: {
                        forecastRowView(row)
                    }
                    .buttonStyle(.plain)
                }
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

            // Last recalculated timestamp
            if let lastRun = forecastRows.first(where: { $0.part.forecastLastRun != nil })?.part.forecastLastRun {
                Section {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Last recalculated: \(formatTimestamp(lastRun))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func statCard(label: String, count: Int, color: Color, filter: UrgencyFilter) -> some View {
        let isSelected = filterUrgency == filter

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if filterUrgency == filter {
                    filterUrgency = .all
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

    @ViewBuilder
    private func forecastRowView(_ row: PartsService.ForecastDataRow) -> some View {
        HStack(spacing: 12) {
            // Urgency indicator
            let urgencyText = row.part.forecastDaysUntilLow.map { UrgencyFilter.classify($0).label } ?? "Unknown"
            VStack(spacing: 2) {
                Circle()
                    .fill(urgencyColor(row.part.forecastDaysUntilLow))
                    .frame(width: 12, height: 12)
                Text(urgencyText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(urgencyColor(row.part.forecastDaysUntilLow))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(urgencyText)")

            VStack(alignment: .leading, spacing: 3) {
                Text(row.part.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let code = row.part.code {
                        Text(code)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        if let adu = row.part.forecastAdu30, adu > 0 {
                            Text(String(format: "ADU: %.1f/day", adu))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        trendIndicator(adu30: row.part.forecastAdu30, adu90: row.part.forecastAdu90)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let days = row.part.forecastDaysUntilLow {
                    Text("\(days)d")
                        .font(.headline)
                        .foregroundStyle(urgencyColor(row.part.forecastDaysUntilLow))
                    Text("until low")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("no data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let suggested = row.part.forecastSuggestedOrder, suggested > 0 {
                    Text("Order \(suggested)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 60)
    }

    // MARK: - Trend Indicator

    @ViewBuilder
    private func trendIndicator(adu30: Double?, adu90: Double?) -> some View {
        if let short = adu30, let long = adu90, long > 0 {
            let ratio = short / long
            if ratio > 1.15 {
                // Usage trending up (30-day > 90-day by 15%+)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if ratio < 0.85 {
                // Usage trending down
                Image(systemName: "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                // Stable
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func urgencyColor(_ daysUntilLow: Int?) -> Color {
        guard let days = daysUntilLow else { return .secondary }
        return UrgencyFilter.classify(days).color
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        let isFiltered = !searchText.isEmpty || filterUrgency != .all
        return VStack(spacing: 16) {
            Image(systemName: isFiltered ? "magnifyingglass" : "chart.line.uptrend.xyaxis")
                .decorativeIconFont(48)
                .foregroundStyle(.secondary)
            Text(isFiltered ? "No Results" : "No Forecast Data")
                .font(.title3)
                .fontWeight(.semibold)
            Text(isFiltered
                 ? "Try adjusting your search or urgency filter."
                 : "Forecast data is generated from order history and stock movements. Add parts and process orders to see forecasts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                isLoading = false
                return
            }
            let locType = selectedLocationType == "all" ? nil : selectedLocationType
            let rows = try service.listForecastDataWithStock(
                locationType: locType,
                locationId: selectedLocationId
            )
            await MainActor.run {
                forecastRows = rows
                // Single-pass urgency counts and top-critical summary — avoids per-render filter
                // scans in stat cards and removes a second filter in postForecastContext().
                var counts: [UrgencyFilter: Int] = [.critical: 0, .warning: 0, .healthy: 0]
                var criticalRows: [PartsService.ForecastDataRow] = []
                for row in rows {
                    let bucket = UrgencyFilter.classify(row.part.forecastDaysUntilLow ?? 999)
                    counts[bucket, default: 0] += 1
                    if bucket == .critical && criticalRows.count < 5 {
                        criticalRows.append(row)
                    }
                }
                urgencyCounts = counts
                topCriticalSummary = criticalRows.map {
                    "\($0.part.name) (\($0.part.forecastDaysUntilLow ?? 0)d, order \($0.part.forecastSuggestedOrder ?? 0))"
                }.joined(separator: "; ")
                isLoading = false
                postForecastContext()
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load forecasting data")
                isLoading = false
            }
        }
    }

    @Sendable
    private func recalculateForecasts() async {
        isRecalculating = true
        do {
            guard let service = appCore.partsService else {
                await MainActor.run { loadError = "Service not available"; isRecalculating = false }
                return
            }
            try service.recalculateForecasts()
            await loadData()
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "recalculate forecasts")
            }
        }
        await MainActor.run {
            isRecalculating = false
        }
    }

    // MARK: - AI Context

    private func postForecastContext() {
        let criticalCount = urgencyCounts[.critical, default: 0]
        let warningCount = urgencyCounts[.warning, default: 0]

        var context = "User is on the Forecasting page. "
        context += "Total parts: \(forecastRows.count). "
        context += "Critical (≤7 days): \(criticalCount). "
        context += "Warning (7-30 days): \(warningCount). "
        context += "Current filter: \(filterUrgency.label). "

        if criticalCount > 0 && !topCriticalSummary.isEmpty {
            context += "Top critical: \(topCriticalSummary). "
        }

        if let lastRun = forecastRows.first(where: { $0.part.forecastLastRun != nil })?.part.forecastLastRun {
            context += "Last recalculated: \(lastRun). "
        }

        NotificationCenter.default.post(
            name: .forecastingPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }

    // MARK: - Location Loading

    private func loadLocations() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        do {
            let locations = try service.listDistinctStockLocations()
            availableLocations = locations.map { loc in
                let icon: String
                switch loc.locationType {
                case "warehouse": icon = "building.2"
                case "truck": icon = "truck.box"
                case "trailer": icon = "shippingbox"
                default: icon = "mappin"
                }
                return LocationOption(id: loc.id, locationType: loc.locationType,
                                      locationId: loc.locationId, name: loc.name, icon: icon)
            }
        } catch {
            // Non-critical — location picker just won't show
        }
    }

    // MARK: - Recommendations

    @Sendable
    private func loadRecommendations() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            let recs = try service.listPendingRecommendations()
            await MainActor.run {
                recommendations = recs
                recommendationCount = recs.count
            }
        } catch {
            // Non-critical
        }
    }

    private func approveRecommendation(_ rec: TargetRecommendation) async {
        guard let service = appCore.partsService,
              let userId = appCore.currentUser?.id else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            guard let recId = rec.id else { return }
            try service.approveRecommendation(id: recId, byUserId: userId)
            await loadRecommendations()
            await loadData()
        } catch {
            loadError = userFriendlyError(error, context: "approve recommendation")
        }
    }

    // MARK: - Recommendation Card

    @ViewBuilder
    private func recommendationCard(_ rec: TargetRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: recommendationIcon(rec.recommendationType))
                    .foregroundStyle(recommendationColor(rec.recommendationType))
                Text(partName(for: rec.partId))
                    .fontWeight(.medium)
                Spacer()
                Text(rec.recommendationType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(recommendationColor(rec.recommendationType).opacity(0.15)))
                    .foregroundStyle(recommendationColor(rec.recommendationType))
            }

            if rec.recommendationType == "adjust" {
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
                            .foregroundStyle(Color.accentColor)
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
                .accessibilityLabel("Approve recommendation")

                Button {
                    dismissingRecommendation = rec
                    showDismissAlert = true
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .accessibilityLabel("Dismiss recommendation")
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Location Chip

    @ViewBuilder
    private func locationChip(name: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .accessibilityHidden(true)
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

    // MARK: - Recommendation Helpers

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
        forecastRows.first(where: { $0.part.id == partId })?.part.name ?? "Part #\(partId)"
    }

    // MARK: - Helpers

    private func formatTimestamp(_ iso: String) -> String {
        let date = Formatters.iso8601Fractional.date(from: iso)
            ?? Formatters.iso8601Basic.date(from: iso)
        guard let date else { return iso }
        return Formatters.mediumDateTimeFormatter.string(from: date)
    }
}

// MARK: - Types

private struct LocationOption: Identifiable, Hashable {
    let id: String
    let locationType: String
    let locationId: Int64?
    let name: String
    let icon: String
}

private enum UrgencyFilter: CaseIterable {
    case all, critical, warning, healthy

    var label: String {
        switch self {
        case .all: return "All"
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .healthy: return "Healthy"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .critical: return .red
        case .warning: return .orange
        case .healthy: return .green
        }
    }

    static func classify(_ days: Int) -> UrgencyFilter {
        if days <= 7 { return .critical }
        if days <= 30 { return .warning }
        return .healthy
    }
}

// MARK: - Forecast Detail Sheet

private struct ForecastDetailSheet: View {
    let row: PartsService.ForecastDataRow
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var locationTargets: [PartsService.LocationStockTargetWithStock] = []
    @State private var isLoadingLocations = true
    @State private var editError: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showCancelConfirmation = false

    // Editable fields
    @State private var editName: String = ""
    @State private var editCode: String = ""
    @State private var editMinStock: String = ""
    @State private var editTargetStock: String = ""
    @State private var editMaxStock: String = ""

    // Toast
    @State private var showComingSoon = false
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            List {
                partInfoSection
                stockHealthSection
                forecastMetricsSection
                actionsSection
            }
            .navigationTitle("Part Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        if isDirty { showCancelConfirmation = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isDirty || isSaving)
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Error", isPresented: Binding(
                get: { editError != nil },
                set: { if !$0 { editError = nil } }
            )) {
                Button("OK") { editError = nil }
            } message: {
                Text(editError ?? "")
            }
            .overlay(alignment: .bottom) {
                if showComingSoon {
                    Text("Coming in a future update")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showComingSoon = false }
                            }
                        }
                }
                if let message = toastMessage {
                    Text(message)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task {
                editName = row.part.name
                editCode = row.part.code ?? ""
                editMinStock = "\(row.part.minStockLevel ?? 0)"
                editTargetStock = "\(row.part.targetStockLevel ?? 0)"
                editMaxStock = "\(row.part.maxStockLevel ?? 0)"
                await loadLocationData()
            }
        }
    }

    // MARK: - Part Info Section

    @ViewBuilder
    private var partInfoSection: some View {
        Section("Part Info") {
            LabeledContent("Name") {
                TextField("Name", text: $editName)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: editName) { _ in isDirty = true }
            }
            LabeledContent("Code") {
                TextField("Code", text: $editCode)
                    .multilineTextAlignment(.trailing)
                    .monospaced()
                    .onChange(of: editCode) { _ in isDirty = true }
            }

            LabeledContent("Min Stock (Global)") {
                TextField("0", text: $editMinStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .onChange(of: editMinStock) { _ in isDirty = true }
            }
            LabeledContent("Target Stock (Global)") {
                TextField("0", text: $editTargetStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .onChange(of: editTargetStock) { _ in isDirty = true }
            }
            LabeledContent("Max Stock (Global)") {
                TextField("0", text: $editMaxStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .onChange(of: editMaxStock) { _ in isDirty = true }
            }

            LabeledContent("Total Stock (All Locations)", value: "\(row.currentStock)")

            if hasChanges {
                Button {
                    Task { await savePartChanges() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().padding(.trailing, 4) }
                        Text("Save Changes")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    private var hasChanges: Bool {
        editName != row.part.name ||
        editCode != (row.part.code ?? "") ||
        editMinStock != "\(row.part.minStockLevel ?? 0)" ||
        editTargetStock != "\(row.part.targetStockLevel ?? 0)" ||
        editMaxStock != "\(row.part.maxStockLevel ?? 0)"
    }

    // MARK: - Stock Health Section

    @ViewBuilder
    private var stockHealthSection: some View {
        Section("Stock by Location") {
            if isLoadingLocations {
                ProgressView("Loading locations...")
            } else if locationTargets.isEmpty {
                Text("No stock at any location")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(locationTargets) { target in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: locationIcon(target.locationType))
                                .foregroundStyle(.secondary)
                            Text(target.locationName)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(target.currentStock)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(healthColor(target.healthScore))
                        }

                        stockHealthBar(target: target)

                        HStack {
                            Text("MIN: \(target.minStock)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("TGT: \(target.targetStock)")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Spacer()
                            Text("MAX: \(target.maxStock)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            if let cert = target.certaintyRating {
                                Text("Certainty: \(Int(cert * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(cert >= 0.8 ? .green : .orange)
                            }
                            Spacer()
                            if let adu = target.forecastAdu30, adu > 0 {
                                Text(String(format: "Usage: %.1f", adu))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func stockHealthBar(target: PartsService.LocationStockTargetWithStock) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let maxVal = max(target.maxStock, target.currentStock, 1)

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 12)

                // MIN zone (red)
                if target.minStock > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.2))
                        .frame(width: width * CGFloat(target.minStock) / CGFloat(maxVal), height: 12)
                }

                // Current stock bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(healthColor(target.healthScore))
                    .frame(width: max(4, width * CGFloat(target.currentStock) / CGFloat(maxVal)), height: 12)

                // TARGET marker (center line)
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: 16)
                    .offset(x: width * CGFloat(target.targetStock) / CGFloat(maxVal) - 1)
            }
        }
        .frame(height: 16)
    }

    private func healthColor(_ score: Double) -> Color {
        if score <= -0.5 { return .red }
        if score < 0 { return .orange }
        if score <= 0.5 { return .green }
        if score < 1.0 { return .yellow }
        return .red
    }

    private func locationIcon(_ type: String) -> String {
        switch type {
        case "warehouse": return "building.2"
        case "truck": return "truck.box"
        case "trailer": return "shippingbox"
        default: return "mappin"
        }
    }

    // MARK: - Forecast Metrics Section

    @ViewBuilder
    private var forecastMetricsSection: some View {
        Section("Forecast Metrics") {
            if let adu30 = row.part.forecastAdu30 {
                LabeledContent("Avg Daily Usage (30d)", value: String(format: "%.2f", adu30))
            }
            if let adu90 = row.part.forecastAdu90 {
                LabeledContent("Avg Daily Usage (90d)", value: String(format: "%.2f", adu90))
            }
            if let adu30 = row.part.forecastAdu30, let adu90 = row.part.forecastAdu90, adu90 > 0 {
                let ratio = adu30 / adu90
                LabeledContent("Usage Trend") {
                    HStack(spacing: 4) {
                        if ratio > 1.15 {
                            Image(systemName: "arrow.up.right").foregroundStyle(.red)
                            Text("Increasing").foregroundStyle(.red)
                        } else if ratio < 0.85 {
                            Image(systemName: "arrow.down.right").foregroundStyle(.green)
                            Text("Decreasing").foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text("Stable")
                        }
                    }
                    .font(.subheadline)
                }
            }
            if let days = row.part.forecastDaysUntilLow {
                LabeledContent("Days Until Low") {
                    Text("\(days)")
                        .fontWeight(.bold)
                        .foregroundStyle(days <= 7 ? .red : days <= 30 ? .orange : .green)
                }
            }
            if let suggested = row.part.forecastSuggestedOrder, suggested > 0 {
                LabeledContent("Suggested Order") {
                    Text("\(suggested)")
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            if let lastRun = row.part.forecastLastRun {
                LabeledContent("Last Recalculated", value: lastRun)
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        Section("Actions") {
            Button {
                guard let service = appCore.wishlistService else {
                    editError = "Wishlist service not available"
                    return
                }
                do {
                    let _ = try service.addItem(
                        partId: row.part.id,
                        partName: row.part.name,
                        qtySuggested: max(1, (row.part.targetStockLevel ?? 0) - row.currentStock),
                        reason: "Added from forecasting page",
                        sourceType: "forecast"
                    )
                    toastMessage = "Added to wishlist"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { toastMessage = nil }
                    }
                } catch {
                    editError = userFriendlyError(error, context: "add to wishlist")
                }
            } label: {
                Label("Add to Wishlist", systemImage: "heart")
            }
            Button {
                // Post notification to navigate to catalog filtered to this part
                NotificationCenter.default.post(
                    name: .init("navigateToPartsCatalog"),
                    object: nil,
                    userInfo: ["searchText": row.part.name]
                )
                dismiss()
            } label: {
                Label("View in Catalog", systemImage: "list.bullet")
            }
        }
    }

    // MARK: - Data Loading & Saving

    @Sendable
    private func loadLocationData() async {
        guard let service = appCore.partsService else {
            editError = "Parts service not available"
            isLoadingLocations = false
            return
        }
        do {
            guard let partId = row.part.id else { isLoadingLocations = false; return }
            let targets = try service.listLocationStockTargets(partId: partId)
            await MainActor.run {
                locationTargets = targets
                isLoadingLocations = false
            }
        } catch {
            await MainActor.run {
                isLoadingLocations = false
            }
        }
    }

    private func savePartChanges() async {
        isSaving = true
        guard let service = appCore.partsService else {
            editError = "Service not available"
            isSaving = false
            return
        }

        let min = Int(editMinStock) ?? 0
        let target = Int(editTargetStock) ?? 0
        let max = Int(editMaxStock) ?? 0
        guard min < target else {
            editError = "Min stock must be less than target stock"
            isSaving = false
            return
        }
        guard target < max else {
            editError = "Target stock must be less than max stock"
            isSaving = false
            return
        }

        guard let partId = row.part.id else { isSaving = false; return }

        do {
            try service.updatePart(
                id: partId,
                name: editName,
                code: editCode.isEmpty ? nil : editCode,
                minStockLevel: min,
                maxStockLevel: max,
                targetStockLevel: target
            )
            await MainActor.run {
                isDirty = false
                isSaving = false
            }
        } catch {
            await MainActor.run {
                editError = userFriendlyError(error, context: "save forecast settings")
                isSaving = false
            }
        }
    }
}
