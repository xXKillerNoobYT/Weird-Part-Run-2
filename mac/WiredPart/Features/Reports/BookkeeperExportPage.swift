import SwiftUI
import GRDB
import WiredPartCore

/// Bookkeeper export page — generates summarized data for bookkeeping
/// and accounting purposes. Shows labor costs, material costs, and PO totals
/// in a format suitable for export.
///
/// This is an office-only feature for generating period-end summaries.
struct BookkeeperExportPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var laborSummary: [LaborExportRow] = []
    @State private var materialSummary: [MaterialExportRow] = []
    @State private var startDate: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var endDate: Date = Date()
    @State private var isLoading = true
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading export data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("View", selection: $selectedTab) {
                    Text("Labor Summary").tag(0)
                    Text("Material Summary").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    laborView
                } else {
                    materialView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bookkeeper Export")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Period summaries for accounting")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                DatePicker("From:", selection: $startDate, displayedComponents: .date)
                    .frame(width: 200)
                DatePicker("To:", selection: $endDate, displayedComponents: .date)
                    .frame(width: 200)
                Button {
                    loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .padding()
    }

    // MARK: - Labor View

    private var laborView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if laborSummary.isEmpty {
                emptyState(message: "No labor data for this period.")
            } else {
                // Totals bar
                HStack(spacing: 24) {
                    let totalHours = laborSummary.reduce(0) { $0 + $1.totalHours }
                    let totalCost = laborSummary.reduce(0) { $0 + $1.estimatedCost }
                    Label("Total Hours: \(String(format: "%.1f", totalHours))", systemImage: "clock")
                        .font(.callout)
                        .fontWeight(.medium)
                    Label("Est. Cost: $\(String(format: "%.2f", totalCost))", systemImage: "dollarsign.circle")
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))

                Table(laborSummary) {
                    TableColumn("Employee") { row in
                        Text(row.employeeName)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Regular Hrs") { row in
                        Text(String(format: "%.1f", row.regularHours))
                            .monospacedDigit()
                    }
                    .width(90)

                    TableColumn("OT Hrs") { row in
                        Text(String(format: "%.1f", row.overtimeHours))
                            .monospacedDigit()
                    }
                    .width(70)

                    TableColumn("Total Hrs") { row in
                        Text(String(format: "%.1f", row.totalHours))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .width(80)

                    TableColumn("Days") { row in
                        Text("\(row.daysWorked)")
                            .monospacedDigit()
                    }
                    .width(50)

                    TableColumn("Est. Cost") { row in
                        Text(String(format: "$%.2f", row.estimatedCost))
                            .monospacedDigit()
                    }
                    .width(90)
                }
            }
        }
    }

    // MARK: - Material View

    private var materialView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if materialSummary.isEmpty {
                emptyState(message: "No material purchases for this period.")
            } else {
                // Totals bar
                HStack(spacing: 24) {
                    let totalAmount = materialSummary.reduce(0) { $0 + $1.totalAmount }
                    let poCount = materialSummary.count
                    Label("\(poCount) purchase order\(poCount == 1 ? "" : "s")", systemImage: "cart")
                        .font(.callout)
                        .fontWeight(.medium)
                    Label("Total: $\(String(format: "%.2f", totalAmount))", systemImage: "dollarsign.circle")
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))

                Table(materialSummary) {
                    TableColumn("PO #") { row in
                        Text(row.poNumber)
                            .fontWeight(.medium)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Supplier") { row in
                        Text(row.supplierName)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Order Date") { row in
                        Text(String((row.orderDate ?? "—").prefix(10)))
                            .foregroundStyle(.secondary)
                    }
                    .width(100)

                    TableColumn("Status") { row in
                        Text(row.status.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.12)))
                            .foregroundStyle(.blue)
                    }
                    .width(90)

                    TableColumn("Amount") { row in
                        Text(String(format: "$%.2f", row.totalAmount))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .width(100)
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Data")
                .font(.title3)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        do {
            try db.writer.read { dbConn in
                // Labor summary per employee
                let laborSQL = """
                    SELECT le.user_id,
                           COALESCE(u.display_name, u.email, 'Unknown') AS employee_name,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours,
                           COALESCE(SUM(le.regular_hours + le.overtime_hours), 0) AS total_hours,
                           COUNT(DISTINCT date(le.clock_in)) AS days_worked,
                           COALESCE(SUM(le.regular_hours + le.overtime_hours), 0)
                               * COALESCE(u.hourly_rate, 0) AS estimated_cost
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id
                    WHERE le.deleted_at IS NULL
                      AND date(le.clock_in) >= ?
                      AND date(le.clock_in) <= ?
                    GROUP BY le.user_id
                    ORDER BY employee_name ASC
                    """

                let laborRows = try Row.fetchAll(dbConn, sql: laborSQL, arguments: [startStr, endStr])
                laborSummary = laborRows.enumerated().map { index, row in
                    LaborExportRow(
                        id: Int64(index + 1),
                        employeeName: row["employee_name"] ?? "Unknown",
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0,
                        totalHours: row["total_hours"] ?? 0.0,
                        daysWorked: row["days_worked"] ?? 0,
                        estimatedCost: row["estimated_cost"] ?? 0.0
                    )
                }

                // Material summary (POs in period)
                let materialSQL = """
                    SELECT po.id, po.po_number, po.status, po.order_date,
                           COALESCE(po.total_cost, 0) AS total_amount,
                           COALESCE(s.name, 'Unknown') AS supplier_name
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id
                    WHERE po.deleted_at IS NULL
                      AND po.status NOT IN ('cancelled')
                      AND date(po.created_at) >= ?
                      AND date(po.created_at) <= ?
                    ORDER BY po.order_date DESC
                    """

                let materialRows = try Row.fetchAll(dbConn, sql: materialSQL, arguments: [startStr, endStr])
                materialSummary = materialRows.map { row in
                    MaterialExportRow(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? "Unknown",
                        status: row["status"] ?? "draft",
                        orderDate: row["order_date"] as String?,
                        totalAmount: row["total_amount"] ?? 0.0
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[BookkeeperExportPage] Error: \(error)")
            }
            laborSummary = []
            materialSummary = []
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private struct LaborExportRow: Identifiable {
    let id: Int64
    let employeeName: String
    let regularHours: Double
    let overtimeHours: Double
    let totalHours: Double
    let daysWorked: Int
    let estimatedCost: Double
}

private struct MaterialExportRow: Identifiable {
    let id: Int64
    let poNumber: String
    let supplierName: String
    let status: String
    let orderDate: String?
    let totalAmount: Double
}
