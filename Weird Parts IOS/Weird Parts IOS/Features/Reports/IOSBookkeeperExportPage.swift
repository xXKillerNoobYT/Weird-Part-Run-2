import SwiftUI
import GRDB
import WiredPartCore

/// Bookkeeper export summary page for iOS.
///
/// Displays labor totals per employee and a list of material purchase orders
/// for the selected date range. Designed for quick bookkeeper review before
/// exporting. Uses direct SQL queries against employees, labor_entries,
/// and purchase_orders tables.
struct IOSBookkeeperExportPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var laborRows: [LaborSummaryRow] = []
    @State private var materialRows: [MaterialPORow] = []
    @State private var isLoading = true
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
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
            dateRangePicker
            exportContent
        }
        .navigationTitle("Bookkeeper Export")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Date Range Picker

    private var dateRangePicker: some View {
        HStack(spacing: 12) {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: startDate) { loadData() }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            DatePicker("To", selection: $endDate, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: endDate) { loadData() }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var exportContent: some View {
        if isLoading {
            ProgressView("Loading bookkeeper data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    // MARK: - Labor Row

    private func laborRow(_ row: LaborSummaryRow) -> some View {
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

    private func materialRow(_ row: MaterialPORow) -> some View {
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

    // MARK: - Data Models

    struct LaborSummaryRow: Identifiable {
        let id: Int64
        let employeeName: String
        let regularHours: Double
        let overtimeHours: Double
    }

    struct MaterialPORow: Identifiable {
        let id: Int64
        let poNumber: String
        let supplierName: String
        let totalAmount: Double
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
        guard let db = appCore.db else { return }
        isLoading = laborRows.isEmpty && materialRows.isEmpty
        do {
            laborRows = try db.writer.read { db in
                let sql = """
                    SELECT e.id, COALESCE(e.first_name || ' ' || e.last_name, e.first_name) AS name,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours
                    FROM employees e
                    JOIN labor_entries le ON le.employee_id = e.id
                    WHERE le.work_date >= ? AND le.work_date <= ?
                    GROUP BY e.id
                    ORDER BY name
                    """
                return try Row.fetchAll(db, sql: sql, arguments: [startDateString, endDateString]).map { row in
                    LaborSummaryRow(
                        id: row["id"],
                        employeeName: row["name"],
                        regularHours: row["regular_hours"],
                        overtimeHours: row["overtime_hours"]
                    )
                }
            }

            materialRows = try db.writer.read { db in
                let sql = """
                    SELECT po.id, po.po_number, COALESCE(s.name, 'Unknown') AS supplier_name,
                           COALESCE(po.total_amount, 0) AS total_amount
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id
                    WHERE po.created_at >= ? AND po.created_at <= ?
                    ORDER BY po.po_number
                    """
                return try Row.fetchAll(db, sql: sql, arguments: [startDateString, endDateString]).map { row in
                    MaterialPORow(
                        id: row["id"],
                        poNumber: row["po_number"],
                        supplierName: row["supplier_name"],
                        totalAmount: row["total_amount"]
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[IOSBookkeeperExportPage] Load error: \(error)")
            }
        }
        isLoading = false
    }
}
