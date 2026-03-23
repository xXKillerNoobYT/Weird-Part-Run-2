import GRDB
import SwiftUI
import WiredPartCore

/// Demand forecasting page showing parts with their forecast data.
///
/// Displays average daily usage (ADU), reorder points, suggested orders,
/// and days until low stock. Color-coded urgency indicators help prioritize
/// reordering decisions. Trend arrows compare ADU-30 vs ADU-90.
struct PartsForecastingPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var forecastRows: [PartsService.ForecastDataRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var filterUrgency: UrgencyFilter = .all
    @State private var selectedRow: PartsService.ForecastDataRow?
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

    var body: some View {
        VStack(spacing: 0) {
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
        .sheet(item: $selectedRow) { row in
            ForecastDetailSheet(row: row)
        }
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
                              let userId = appCore.currentUser?.id else { return }
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
        .background(DS.Background.page)
        .task {
            loadLocations()
            await loadData()
            await loadRecommendations()
        }
        .onAppear { postForecastContext() }
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
            result = result.filter { ($0.part.forecastDaysUntilLow ?? 999) <= 7 }
        case .warning:
            result = result.filter {
                let days = $0.part.forecastDaysUntilLow ?? 999
                return days > 7 && days <= 30
            }
        case .healthy:
            result = result.filter { ($0.part.forecastDaysUntilLow ?? 999) > 30 }
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
                        selectedRow = row
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
            Circle()
                .fill(urgencyColor(row.part.forecastDaysUntilLow))
                .frame(width: 12, height: 12)

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
        if days <= 7 { return .red }
        if days <= 30 { return .orange }
        return .green
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Forecast Data")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Forecast data is generated from order history and stock movements. Add parts and process orders to see forecasts.")
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
                isLoading = false
                postForecastContext()
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    @Sendable
    private func recalculateForecasts() async {
        isRecalculating = true
        do {
            guard let service = appCore.partsService else { return }
            try service.recalculateForecasts()
            await loadData()
        } catch {
            await MainActor.run {
                loadError = "Recalculation failed: \(error.localizedDescription)"
            }
        }
        await MainActor.run {
            isRecalculating = false
        }
    }

    // MARK: - AI Context

    private func postForecastContext() {
        let critical = forecastRows.filter { ($0.part.forecastDaysUntilLow ?? 999) <= 7 }
        let warning = forecastRows.filter {
            let d = $0.part.forecastDaysUntilLow ?? 999
            return d > 7 && d <= 30
        }

        var context = "User is on the Forecasting page. "
        context += "Total parts: \(forecastRows.count). "
        context += "Critical (≤7 days): \(critical.count). "
        context += "Warning (7-30 days): \(warning.count). "
        context += "Current filter: \(filterUrgency.label). "

        if !critical.isEmpty {
            let topCritical = critical.prefix(5).map {
                "\($0.part.name) (\($0.part.forecastDaysUntilLow ?? 0)d, order \($0.part.forecastSuggestedOrder ?? 0))"
            }
            context += "Top critical: \(topCritical.joined(separator: "; ")). "
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
        guard let db = appCore.db else { return }
        do {
            let rows = try db.writer.read { dbConn in
                try Row.fetchAll(dbConn, sql: """
                    SELECT DISTINCT s.location_type, s.location_id,
                        COALESCE(wl.name, v.vehicle_name, 'Location ' || s.location_id) AS name
                    FROM stock s
                    LEFT JOIN warehouse_locations wl ON s.location_type = 'warehouse' AND wl.id = s.location_id
                    LEFT JOIN vehicles v ON s.location_type IN ('truck', 'trailer') AND v.id = s.location_id
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

    // MARK: - Recommendations

    @Sendable
    private func loadRecommendations() async {
        guard let service = appCore.partsService else { return }
        do {
            let recs = try service.listPendingRecommendations()
            let count = try service.pendingRecommendationCount()
            await MainActor.run {
                recommendations = recs
                recommendationCount = count
            }
        } catch {
            // Non-critical
        }
    }

    private func approveRecommendation(_ rec: TargetRecommendation) async {
        guard let service = appCore.partsService,
              let userId = appCore.currentUser?.id else { return }
        do {
            try service.approveRecommendation(id: rec.id!, userId: userId)
            await loadRecommendations()
            await loadData()
        } catch {
            loadError = "Approve failed: \(error.localizedDescription)"
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

    // MARK: - Location Chip

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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return iso
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

    // Editable fields
    @State private var editName: String = ""
    @State private var editCode: String = ""
    @State private var editMinStock: String = ""
    @State private var editTargetStock: String = ""
    @State private var editMaxStock: String = ""

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
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(editError != nil)) {
                Button("OK") { editError = nil }
            } message: {
                Text(editError ?? "")
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
            }
            LabeledContent("Code") {
                TextField("Code", text: $editCode)
                    .multilineTextAlignment(.trailing)
                    .monospaced()
            }

            LabeledContent("Min Stock (Global)") {
                TextField("0", text: $editMinStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            LabeledContent("Target Stock (Global)") {
                TextField("0", text: $editTargetStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            LabeledContent("Max Stock (Global)") {
                TextField("0", text: $editMaxStock)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
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
            Button {} label: {
                Label("Add to Wishlist", systemImage: "heart")
            }
            Button {} label: {
                Label("View in Catalog", systemImage: "list.bullet")
            }
        }
    }

    // MARK: - Data Loading & Saving

    @Sendable
    private func loadLocationData() async {
        guard let service = appCore.partsService else {
            isLoadingLocations = false
            return
        }
        do {
            let targets = try service.listLocationStockTargets(partId: row.part.id!)
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

        do {
            try service.updatePart(
                id: row.part.id!,
                name: editName,
                code: editCode.isEmpty ? nil : editCode,
                minStockLevel: min,
                maxStockLevel: max,
                targetStockLevel: target
            )
            await MainActor.run {
                isSaving = false
            }
        } catch {
            await MainActor.run {
                editError = "Save failed: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}
