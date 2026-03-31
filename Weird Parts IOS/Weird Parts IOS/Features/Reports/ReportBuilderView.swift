import SwiftUI
import WiredPartCore

// MARK: - Report Type Definitions

/// Available custom report types with their columns and filters.
enum CustomReportType: String, CaseIterable, Sendable {
    case laborHours = "labor_hours"
    case partsUsage = "parts_usage"
    case jobCosts = "job_costs"
    case toolCheckouts = "tool_checkouts"
    case vehicleFuel = "vehicle_fuel"
    case orderHistory = "order_history"

    var displayName: String {
        switch self {
        case .laborHours: return "Labor Hours"
        case .partsUsage: return "Parts Usage"
        case .jobCosts: return "Job Costs"
        case .toolCheckouts: return "Tool Checkouts"
        case .vehicleFuel: return "Vehicle Fuel"
        case .orderHistory: return "Order History"
        }
    }

    var icon: String {
        switch self {
        case .laborHours: return "clock.fill"
        case .partsUsage: return "shippingbox.fill"
        case .jobCosts: return "dollarsign.circle.fill"
        case .toolCheckouts: return "wrench.fill"
        case .vehicleFuel: return "fuelpump.fill"
        case .orderHistory: return "doc.text.fill"
        }
    }

    var availableColumns: [ReportColumn] {
        switch self {
        case .laborHours:
            return [
                .init(key: "employee_name", label: "Employee"),
                .init(key: "date", label: "Date"),
                .init(key: "hours", label: "Hours"),
                .init(key: "job_name", label: "Job"),
                .init(key: "activity_type", label: "Activity"),
                .init(key: "clock_in", label: "Clock In"),
                .init(key: "clock_out", label: "Clock Out"),
                .init(key: "notes", label: "Notes"),
            ]
        case .partsUsage:
            return [
                .init(key: "part_name", label: "Part"),
                .init(key: "category", label: "Category"),
                .init(key: "quantity_used", label: "Qty Used"),
                .init(key: "job_name", label: "Job"),
                .init(key: "date", label: "Date"),
                .init(key: "cost", label: "Unit Cost"),
                .init(key: "total_cost", label: "Total Cost"),
            ]
        case .jobCosts:
            return [
                .init(key: "job_name", label: "Job"),
                .init(key: "labor_cost", label: "Labor Cost"),
                .init(key: "material_cost", label: "Material Cost"),
                .init(key: "total_cost", label: "Total Cost"),
                .init(key: "budget", label: "Budget"),
                .init(key: "variance", label: "Variance"),
            ]
        case .toolCheckouts:
            return [
                .init(key: "tool_name", label: "Tool"),
                .init(key: "employee_name", label: "Employee"),
                .init(key: "checkout_date", label: "Checkout Date"),
                .init(key: "return_date", label: "Return Date"),
                .init(key: "condition_out", label: "Condition Out"),
                .init(key: "condition_in", label: "Condition In"),
            ]
        case .vehicleFuel:
            return [
                .init(key: "vehicle_name", label: "Vehicle"),
                .init(key: "date", label: "Date"),
                .init(key: "gallons", label: "Gallons"),
                .init(key: "cost", label: "Cost"),
                .init(key: "odometer", label: "Odometer"),
            ]
        case .orderHistory:
            return [
                .init(key: "po_number", label: "PO #"),
                .init(key: "supplier_name", label: "Supplier"),
                .init(key: "order_date", label: "Order Date"),
                .init(key: "total", label: "Total"),
                .init(key: "status", label: "Status"),
                .init(key: "items_count", label: "Items"),
            ]
        }
    }
}

struct ReportColumn: Identifiable, Sendable {
    let key: String
    let label: String
    var id: String { key }
}

// MARK: - Report Builder View

/// 4-step wizard for building custom reports: Type → Fields → Filters → Results.
struct ReportBuilderView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var selectedType: CustomReportType = .laborHours
    @State private var selectedColumns: Set<String> = []
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var step: BuilderStep = .type
    @State private var reportName = ""
    @State private var generatedRows: [[String]] = []
    @State private var isGenerating = false
    @State private var generateError: String?
    @State private var saveError: String?
    @State private var savedSuccessfully = false
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    enum BuilderStep: Int, CaseIterable {
        case type = 0
        case fields = 1
        case filters = 2
        case results = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator

            // Step content
            List {
                switch step {
                case .type: typeStep
                case .fields: fieldsStep
                case .filters: filtersStep
                case .results: resultsStep
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Report Builder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Report Builder Help", sections: [
                ("What This Page Does", "Lets you build a custom report from scratch in four steps: pick a report type, choose which columns to include, set date filters, and generate results. You can also save your report configuration to run it again later."),
                ("How to Use It", "Step 1: Pick a report type (labor, parts, jobs, tools, fuel, or orders). Step 2: Toggle which data columns you want. Step 3: Set date range and hit Generate. Step 4: Preview results and export to PDF or CSV. You can also save the config with a name."),
                ("Tips", "Start with all columns selected, then remove what you do not need. Saved reports appear in the Custom Reports list so you can re-run them quickly. Use the Quick Range buttons for common date periods like This Week or This Month.")
            ])
        }
        .reportExportToolbar(
            title: "\(selectedType.displayName) Report",
            columns: selectedColumnLabels,
            rows: generatedRows
        )
        .alert("Report Saved", isPresented: $savedSuccessfully) {
            Button("OK") { savedSuccessfully = false }
        } message: {
            Text("'\(reportName)' has been saved and can be re-run from the Custom Reports list.")
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(BuilderStep.allCases, id: \.rawValue) { s in
                VStack(spacing: 4) {
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.indigo : Color.gray.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                        .overlay(
                            Text("\(s.rawValue + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        )
                    Text(stepLabel(s))
                        .font(.caption2)
                        .foregroundStyle(s.rawValue <= step.rawValue ? .primary : .secondary)
                }
                if s != .results {
                    Rectangle()
                        .fill(s.rawValue < step.rawValue ? Color.indigo : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    private func stepLabel(_ step: BuilderStep) -> String {
        switch step {
        case .type: return "Type"
        case .fields: return "Fields"
        case .filters: return "Filters"
        case .results: return "Results"
        }
    }

    // MARK: - Step 1: Type Selection

    @ViewBuilder
    private var typeStep: some View {
        Section("Select Report Type") {
            ForEach(CustomReportType.allCases, id: \.self) { type in
                Button {
                    selectedType = type
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: type.icon)
                            .font(.title3)
                            .foregroundStyle(.indigo)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(type.availableColumns.count) fields available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedType == type {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.indigo)
                                .accessibilityLabel("Selected")
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }

        Section {
            Button {
                selectedColumns = Set(selectedType.availableColumns.map(\.key))
                step = .fields
            } label: {
                HStack {
                    Spacer()
                    Text("Next: Select Fields")
                        .fontWeight(.medium)
                    Image(systemName: "chevron.right")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Step 2: Field Selection

    @ViewBuilder
    private var fieldsStep: some View {
        Section("Select Columns to Include") {
            ForEach(selectedType.availableColumns) { col in
                Toggle(col.label, isOn: Binding(
                    get: { selectedColumns.contains(col.key) },
                    set: { isOn in
                        if isOn { selectedColumns.insert(col.key) }
                        else { selectedColumns.remove(col.key) }
                    }
                ))
            }
        }

        Section {
            HStack {
                Button("Back") {
                    step = .type
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    step = .filters
                } label: {
                    HStack {
                        Text("Next: Filters")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(selectedColumns.isEmpty)
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Step 3: Filters

    @ViewBuilder
    private var filtersStep: some View {
        Section("Date Range") {
            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
            DatePicker("End Date", selection: $endDate, displayedComponents: .date)
        }

        Section("Quick Ranges") {
            HStack(spacing: 8) {
                quickRangeButton("This Week", range: .thisWeek)
                quickRangeButton("This Month", range: .thisMonth)
                quickRangeButton("This Quarter", range: .thisQuarter)
            }
            .listRowBackground(Color.clear)
        }

        Section {
            HStack {
                Button("Back") {
                    step = .fields
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    generateReport()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Generate Report")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(isGenerating)
            }
            .listRowBackground(Color.clear)
        }
    }

    private func quickRangeButton(_ label: String, range: ReportDateRange) -> some View {
        Button(label) {
            if let interval = range.dateInterval {
                startDate = interval.start
                endDate = interval.end
            }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    // MARK: - Step 4: Results

    @ViewBuilder
    private var resultsStep: some View {
        if isGenerating {
            Section {
                HStack {
                    Spacer()
                    ProgressView("Generating report...")
                    Spacer()
                }
            }
        } else if let error = generateError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            Section {
                Button("Try Again") { generateReport() }
                    .buttonStyle(.bordered)
                Button("Start Over") { step = .type; generatedRows = [] }
                    .buttonStyle(.bordered)
            }
        } else {
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("\(generatedRows.count) rows generated")
                        .font(.subheadline)
                }
            }

            // Results preview (first 50 rows)
            Section("Preview") {
                ForEach(0..<min(generatedRows.count, 50), id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(selectedColumnLabels.enumerated()), id: \.offset) { idx, label in
                            HStack {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                Text(idx < generatedRows[i].count ? generatedRows[i][idx] : "")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if generatedRows.count > 50 {
                    Text("Showing 50 of \(generatedRows.count) rows. Export for full data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Save configuration
            Section("Save Report") {
                TextField("Report Name", text: $reportName)

                if let error = saveError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                HStack {
                    Button {
                        saveReport()
                    } label: {
                        Label("Save Configuration", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(reportName.isEmpty)

                    Spacer()

                    Button {
                        step = .type
                        generatedRows = []
                        reportName = ""
                    } label: {
                        Label("New Report", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Computed

    private var selectedColumnLabels: [String] {
        selectedType.availableColumns
            .filter { selectedColumns.contains($0.key) }
            .map(\.label)
    }

    private var selectedColumnKeys: [String] {
        selectedType.availableColumns
            .filter { selectedColumns.contains($0.key) }
            .map(\.key)
    }

    // MARK: - Actions

    private func generateReport() {
        isGenerating = true
        generateError = nil
        step = .results
        guard let service = appCore.reportsService else {
            generateError = "Reports service not available"
            isGenerating = false
            return
        }
        do {
            generatedRows = try service.generateCustomReport(
                type: selectedType.rawValue,
                columns: selectedColumnKeys,
                startDate: startDate,
                endDate: endDate,
                filters: [:]
            )
        } catch {
            generateError = userFriendlyError(error, context: "generate document")
        }
        isGenerating = false
    }

    private func saveReport() {
        saveError = nil
        guard let service = appCore.reportsService else {
            saveError = "Reports service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "Not logged in"
            return
        }
        do {
            try service.saveReportConfig(
                name: reportName,
                type: selectedType.rawValue,
                columns: selectedColumnKeys,
                filters: [:],
                userId: userId,
                isShared: false
            )
            savedSuccessfully = true
        } catch {
            saveError = userFriendlyError(error, context: "save daily report")
        }
    }
}
