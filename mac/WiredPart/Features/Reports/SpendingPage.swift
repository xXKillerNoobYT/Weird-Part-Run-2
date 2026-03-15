import SwiftUI
import WiredPartCore

/// Spending summary page showing procurement spending overview.
///
/// Displays dashboard-style KPI cards showing total spend, PO count,
/// average PO amount, and top supplier. Uses the ReportsService
/// spending summary which aggregates purchase order data over the last 30 days.
struct SpendingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var summary: ReportsService.SpendingSummary?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if isLoading {
                    ProgressView("Loading spending data...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if let summary {
                    kpiCards(summary)
                    topSupplierSection(summary)
                } else {
                    emptyState
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spending Overview")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Last 30 days of procurement activity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - KPI Cards

    private func kpiCards(_ summary: ReportsService.SpendingSummary) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            kpiCard(
                title: "Total Spend",
                value: String(format: "$%.2f", summary.totalSpend),
                icon: "dollarsign.circle.fill",
                color: .green
            )
            kpiCard(
                title: "PO Count",
                value: "\(summary.poCount)",
                icon: "doc.text.fill",
                color: .blue
            )
            kpiCard(
                title: "Avg PO Amount",
                value: String(format: "$%.2f", summary.avgPOAmount),
                icon: "chart.bar.fill",
                color: .purple
            )
            kpiCard(
                title: "Top Supplier",
                value: summary.topSupplierName ?? "N/A",
                icon: "building.2.fill",
                color: .orange
            )
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Top Supplier Section

    private func topSupplierSection(_ summary: ReportsService.SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Supplier Detail")
                .font(.headline)

            if let supplierName = summary.topSupplierName {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(supplierName)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Highest spend in the last 30 days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "$%.2f", summary.topSupplierAmount))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                            Text("Total spend")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No supplier data available for this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No spending data")
                .font(.headline)
            Text("No purchase orders found in the last 30 days.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            let service = ReportsService(db: db)
            summary = try service.getSpendingSummary()
        } catch {
            print("[SpendingPage] Load error: \(error)")
        }

        isLoading = false
    }
}
