import SwiftUI
import WiredPartCore

/// Spending report page for iOS.
///
/// Displays KPI cards summarising procurement spending over the
/// selected lookback window: Total Spend, PO Count, Average PO Amount,
/// and Top Supplier. Supports pull-to-refresh and period selection.
struct IOSSpendingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var summary: ReportsService.SpendingSummary?
    @State private var isLoading = true
    @State private var selectedDays = 30
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    private let periodOptions = [7, 14, 30, 60, 90]

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            periodPicker
            spendingContent
        }
        .navigationTitle("Spending")
        .reportExportToolbar(
            title: "Spending",
            columns: ["Metric", "Value"],
            rows: {
                guard let s = summary else { return [] }
                return [
                    ["Total Spend", String(format: "$%.2f", s.totalSpend)],
                    ["PO Count", "\(s.poCount)"],
                    ["Avg PO Amount", String(format: "$%.2f", s.avgPOAmount)],
                    ["Top Supplier", s.topSupplierName ?? "N/A"],
                    ["Top Supplier Amount", String(format: "$%.2f", s.topSupplierAmount)],
                ]
            }()
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Spending Help", sections: [
                ("What This Page Does", "Shows how much money has been spent on purchase orders over a time window. Displays total spend, number of POs, average PO amount, and your top supplier by dollar volume."),
                ("How to Use It", "Tap a time period button (7d, 14d, 30d, etc.) to change the lookback window. The four KPI cards update automatically. Pull down to refresh if new POs have been submitted."),
                ("Tips", "Use the 30-day view for monthly budget checks. If the top supplier keeps changing, it might mean you are spreading orders too thin. Consolidating with fewer suppliers can get better pricing.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: dateRange) { loadData() }
        .onChange(of: customStart) { loadData() }
        .onChange(of: customEnd) { loadData() }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(periodOptions, id: \.self) { days in
                    Button {
                        selectedDays = days
                        loadData()
                    } label: {
                        Text("\(days)d")
                            .font(.caption)
                            .fontWeight(selectedDays == days ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selectedDays == days ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(selectedDays == days ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Spending Content

    @ViewBuilder
    private var spendingContent: some View {
        if isLoading {
            ProgressView("Loading spending data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if let summary {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    kpiCard(
                        title: "Total Spend",
                        value: formatCurrency(summary.totalSpend),
                        icon: "dollarsign.circle.fill",
                        color: .blue
                    )
                    kpiCard(
                        title: "PO Count",
                        value: "\(summary.poCount)",
                        icon: "doc.text.fill",
                        color: .green
                    )
                    kpiCard(
                        title: "Avg PO",
                        value: formatCurrency(summary.avgPOAmount),
                        icon: "chart.bar.fill",
                        color: .purple
                    )
                    kpiCard(
                        title: "Top Supplier",
                        value: summary.topSupplierName ?? "N/A",
                        subtitle: summary.topSupplierName != nil
                            ? formatCurrency(summary.topSupplierAmount)
                            : nil,
                        icon: "building.2.fill",
                        color: .orange
                    )
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Spending Data", systemImage: "dollarsign.circle")
            } description: {
                Text("No spending data available for the selected period.")
            }
        }
    }

    // MARK: - KPI Card

    private func kpiCard(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service unavailable"
            return
        }
        isLoading = summary == nil
        loadError = nil
        do {
            summary = try service.getSpendingSummary(days: selectedDays)
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
    }
}
