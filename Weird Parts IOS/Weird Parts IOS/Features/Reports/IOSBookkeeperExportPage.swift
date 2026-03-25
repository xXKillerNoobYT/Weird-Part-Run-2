import SwiftUI
import WiredPartCore

/// Bookkeeper export summary page for iOS.
///
/// Displays labor totals per employee and a list of material purchase orders
/// for the selected date range. Designed for quick bookkeeper review before
/// exporting. Uses `ReportsService` for data access.
struct IOSBookkeeperExportPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var laborRows: [ReportsService.BookkeeperLaborRow] = []
    @State private var materialRows: [ReportsService.BookkeeperMaterialRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @State private var endDate = Date()

    private var startDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: startDate)
    }

    private var endDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: endDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(startDate: $startDate, endDate: $endDate)
            exportContent
        }
        .navigationTitle("Bookkeeper Export")
        .reportExportToolbar(
            title: "Bookkeeper_Export",
            columns: ["Type", "Name", "Regular", "Overtime", "Amount"],
            rows: laborRows.map { ["Labor", $0.employeeName,
                                   String(format: "%.1f", $0.regularHours),
                                   String(format: "%.1f", $0.overtimeHours), ""] }
                 + materialRows.map { ["Material", $0.supplierName, $0.poNumber, "",
                                       String(format: "$%.2f", $0.totalAmount)] }
        )
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var exportContent: some View {
        if isLoading {
            ProgressView("Loading bookkeeper data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if laborRows.isEmpty && materialRows.isEmpty {
            ContentUnavailableView {
                Label("No Data", systemImage: "doc.richtext")
            } description: {
                Text("No labor or material data for the selected period.")
            }
        } else {
            List {
                if !laborRows.isEmpty {
                    Section("Labor by Employee") {
                        ForEach(laborRows) { row in
                            laborRow(row)
                        }
                    }
                }

                if !materialRows.isEmpty {
                    Section("Material Purchase Orders") {
                        ForEach(materialRows) { row in
                            materialRow(row)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Labor Row

    private func laborRow(_ row: ReportsService.BookkeeperLaborRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.employeeName)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    Label(String(format: "%.1f reg", row.regularHours), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if row.overtimeHours > 0 {
                        Label(String(format: "%.1f OT", row.overtimeHours), systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(String(format: "%.1f hrs", row.regularHours + row.overtimeHours))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Material Row

    private func materialRow(_ row: ReportsService.BookkeeperMaterialRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.poNumber)
                    .fontWeight(.medium)
                    .font(.system(.body, design: .monospaced))
                Text(row.supplierName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatCurrency(row.totalAmount))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service is not available."
            return
        }
        isLoading = laborRows.isEmpty && materialRows.isEmpty
        loadError = nil
        do {
            laborRows = try service.getBookkeeperLaborSummary(
                startDate: startDateString,
                endDate: endDateString
            )
            materialRows = try service.getBookkeeperMaterialPOs(
                startDate: startDateString,
                endDate: endDateString
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
