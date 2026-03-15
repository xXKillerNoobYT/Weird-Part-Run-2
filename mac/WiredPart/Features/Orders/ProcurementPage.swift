import SwiftUI
import WiredPartCore

/// Procurement overview page with order statistics.
///
/// Displays four KPI stat cards showing pending JPOs, active POs,
/// pending returns, and 30-day spend. Auto-refreshes on appear.
struct ProcurementPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var stats: OrdersService.OrderStats?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                kpiCards
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Procurement")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Order statistics and procurement overview")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - KPI Cards

    @ViewBuilder
    private var kpiCards: some View {
        if isLoading {
            ProgressView("Loading statistics...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        } else if let stats {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                kpiCard(
                    title: "Pending JPOs",
                    value: "\(stats.pendingJPOs)",
                    icon: "doc.text.fill",
                    color: stats.pendingJPOs > 0 ? .orange : .green
                )
                kpiCard(
                    title: "Active POs",
                    value: "\(stats.activePOs)",
                    icon: "cart.fill",
                    color: .blue
                )
                kpiCard(
                    title: "Pending Returns",
                    value: "\(stats.pendingReturns)",
                    icon: "arrow.uturn.backward.circle.fill",
                    color: stats.pendingReturns > 0 ? .orange : .green
                )
                kpiCard(
                    title: "30-Day Spend",
                    value: formatCurrency(stats.totalSpend30Days),
                    icon: "dollarsign.circle.fill",
                    color: .purple
                )
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Unable to load statistics")
                    .font(.headline)
                Button("Retry") { load() }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Formatters

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = OrdersService(db: db)
        isLoading = true
        do {
            stats = try service.getOrderStats()
        } catch {
            print("[ProcurementPage] Load error: \(error)")
        }
        isLoading = false
    }
}
