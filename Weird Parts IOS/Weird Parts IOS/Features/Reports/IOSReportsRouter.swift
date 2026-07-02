import SwiftUI
import WiredPartCore

// MARK: - Report Category

/// Report categories for organized navigation.
enum ReportCategory: String, CaseIterable {
    case labor = "Labor"
    case financial = "Financial"
    case fleet = "Fleet"
    case warehouse = "Warehouse"
    case scheduling = "Scheduling"
    case custom = "Custom"
    case shared = "Shared"

    var icon: String {
        switch self {
        case .labor: return "clock.fill"
        case .financial: return "dollarsign.circle.fill"
        case .fleet: return "car.fill"
        case .warehouse: return "building.2.fill"
        case .scheduling: return "calendar"
        case .custom: return "slider.horizontal.3"
        case .shared: return "person.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .labor: return .blue
        case .financial: return .green
        case .fleet: return .orange
        case .warehouse: return .purple
        case .scheduling: return .cyan
        case .custom: return .indigo
        case .shared: return .pink
        }
    }
}

// MARK: - Reports Router

/// Categorized reports hub with horizontal category picker and permission gating.
///
/// Categories: Labor, Financial (hat-gated), Fleet (hat-gated),
/// Warehouse, Scheduling, Custom, Shared.
struct IOSReportsRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    @State private var selectedCategory: ReportCategory

    init(tabId: String, initialCategory: ReportCategory = .labor) {
        self.tabId = tabId
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category picker
            categoryPicker

            // Category content
            categoryContent
        }
        .navigationTitle("Reports")
        .onAppear {
            if !visibleCategories.contains(selectedCategory) {
                selectedCategory = visibleCategories.first ?? .labor
            }
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleCategories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .accessibilityHidden(true)
                            Text(category.rawValue)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategory == category
                                   ? category.color.opacity(0.2) : Color.clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(
                            selectedCategory == category ? category.color : .secondary.opacity(0.3)
                        ))
                        .foregroundStyle(selectedCategory == category ? category.color : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Visible Categories

    private var visibleCategories: [ReportCategory] {
        var cats = ReportCategory.allCases
        if !appCore.hasPermission("view_financials") {
            cats.removeAll { $0 == .financial }
        }
        if !appCore.hasPermission("view_fleet_financials") {
            cats.removeAll { $0 == .fleet }
        }
        return cats
    }

    // MARK: - Category Content

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .labor:
            LaborReportsView()
        case .financial:
            FinancialReportsView()
        case .fleet:
            FleetReportsView()
        case .warehouse:
            WarehouseReportsView()
        case .scheduling:
            SchedulingReportsView()
        case .custom:
            CustomReportsView()
        case .shared:
            SharedReportsView()
        }
    }
}

// MARK: - Labor Reports

/// Existing labor report pages reorganized into a single list view.
private struct LaborReportsView: View {
    var body: some View {
        List {
            Section("Time & Attendance") {
                NavigationLink {
                    IOSTimesheetsPage()
                } label: {
                    reportRow("Timesheets", icon: "clock.badge.checkmark",
                              description: "Employee timesheet records")
                }
                NavigationLink {
                    IOSDailyReportsSummaryPage()
                } label: {
                    reportRow("Daily Summary", icon: "chart.bar.fill",
                              description: "Daily hours and activity summary")
                }
                NavigationLink {
                    IOSLaborOverviewPage()
                } label: {
                    reportRow("Labor Overview", icon: "person.3.fill",
                              description: "Workforce hours and utilization")
                }
            }

            Section("Billing & Export") {
                NavigationLink {
                    IOSPreBillingPage()
                } label: {
                    reportRow("Pre-Billing Export", icon: "doc.text.fill",
                              description: "Prepare billing data for export")
                }
                NavigationLink {
                    IOSBookkeeperExportPage()
                } label: {
                    reportRow("Bookkeeper Export", icon: "books.vertical.fill",
                              description: "Export data for bookkeeping")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Financial Reports

/// Financial report pages (hat-gated: view_financials).
private struct FinancialReportsView: View {
    var body: some View {
        List {
            Section("Cost Analysis") {
                NavigationLink {
                    IOSSpendingPage()
                } label: {
                    reportRow("Spending Dashboard", icon: "chart.pie.fill",
                              description: "Spending breakdown and trends")
                }
                NavigationLink {
                    IOSProfitabilityPage()
                } label: {
                    reportRow("Profitability", icon: "dollarsign.circle.fill",
                              description: "Job profitability analysis")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Fleet Reports

private struct FleetReportsView: View {
    var body: some View {
        List {
            Section("Cost & Usage") {
                NavigationLink {
                    FleetFuelCostReport()
                } label: {
                    reportRow("Fuel Costs", icon: "fuelpump.fill",
                              description: "Fuel spending by vehicle")
                }
                NavigationLink {
                    FleetMaintenanceTrendsReport()
                } label: {
                    reportRow("Maintenance Trends", icon: "wrench.and.screwdriver.fill",
                              description: "Maintenance cost history and trends")
                }
            }

            Section("Activity") {
                NavigationLink {
                    FleetMileageSummaryReport()
                } label: {
                    reportRow("Mileage Summary", icon: "speedometer",
                              description: "Miles driven per vehicle")
                }
                NavigationLink {
                    FleetUtilizationReport()
                } label: {
                    reportRow("Vehicle Utilization", icon: "chart.bar.fill",
                              description: "Days active vs total days")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Warehouse Reports

private struct WarehouseReportsView: View {
    var body: some View {
        List {
            Section("Inventory") {
                NavigationLink {
                    WarehouseInventoryValueReport()
                } label: {
                    reportRow("Inventory Value", icon: "dollarsign.square.fill",
                              description: "On-hand and on-order value by category")
                }
                NavigationLink {
                    WarehouseBackorderReport()
                } label: {
                    reportRow("Backorder Status", icon: "clock.badge.exclamationmark.fill",
                              description: "PO items not yet fully received")
                }
            }

            Section("Activity") {
                NavigationLink {
                    WarehouseTurnoverReport()
                } label: {
                    reportRow("Inventory Turnover", icon: "arrow.left.arrow.right",
                              description: "Parts with the most movement activity")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Scheduling Reports

private struct SchedulingReportsView: View {
    var body: some View {
        List {
            Section("Workforce") {
                NavigationLink {
                    SchedulingCrewUtilizationReport()
                } label: {
                    reportRow("Crew Utilization", icon: "person.3.fill",
                              description: "Scheduled hours vs available hours")
                }
                NavigationLink {
                    SchedulingDispatchEfficiencyReport()
                } label: {
                    reportRow("Dispatch Efficiency", icon: "paperplane.fill",
                              description: "Completion rate of dispatch assignments")
                }
            }

            Section("Pipeline") {
                NavigationLink {
                    SchedulingPipelineReport()
                } label: {
                    reportRow("Pipeline Summary", icon: "rectangle.stack.fill",
                              description: "Job counts grouped by status")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Custom Reports

private struct CustomReportsView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var savedReports: [ReportsService.SavedReport] = []
    @State private var loadError: String?
    @State private var deleteOffsets: IndexSet?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReportBuilderView()
                } label: {
                    Label("Create New Report", systemImage: "plus.circle.fill")
                        .foregroundStyle(.indigo)
                        .fontWeight(.medium)
                }
            }

            if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Saved Reports") {
                if savedReports.isEmpty {
                    Text("No saved reports yet. Create one to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedReports) { report in
                        NavigationLink {
                            ReportBuilderView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(report.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(report.reportType.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let lastRun = report.lastRunAt, !lastRun.isEmpty {
                                    Text(String(lastRun.prefix(10)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        deleteOffsets = offsets
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task { loadSavedReports() }
        .confirmationDialog(
            "Delete Report?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let offsets = deleteOffsets {
                    deleteReports(at: offsets)
                }
            }
            Button("Cancel", role: .cancel) { deleteOffsets = nil }
        } message: {
            Text("This saved report will be permanently removed.")
        }
    }

    private func loadSavedReports() {
        guard let service = appCore.reportsService,
              let userId = appCore.currentUser?.id else {
            loadError = "Service or user not available"
            return
        }
        do {
            savedReports = try service.getSavedReports(userId: userId)
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
    }

    private func deleteReports(at offsets: IndexSet) {
        guard let service = appCore.reportsService else {
            loadError = "Service not available"
            return
        }
        for idx in offsets {
            let report = savedReports[idx]
            do {
                try service.deleteSavedReport(reportId: report.id)
            } catch {
                loadError = userFriendlyError(error, context: "load reports")
            }
        }
        savedReports.remove(atOffsets: offsets)
    }
}

// MARK: - Shared Reports

private struct SharedReportsView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var sharedReports: [ReportsService.SavedReport] = []
    @State private var loadError: String?

    var body: some View {
        List {
            if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            // NOTE (#1206): the "View Public Report" row was removed for beta.
            // IOSPublicReportView is a stub that always errors, so navigating to
            // it with an empty token was a guaranteed dead end. Re-add a token
            // entry/viewer flow here once public report sharing ships.

            if sharedReports.isEmpty {
                Section {
                    compactSharedReportsEmptyState
                }
            } else {
                Section("Shared by Team") {
                    ForEach(sharedReports) { report in
                        NavigationLink {
                            ReportBuilderView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(report.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(report.reportType.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "person.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Shared report")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task { loadSharedReports() }
    }

    private var compactSharedReportsEmptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("No Shared Reports")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Reports shared by team members will appear here. Create a custom report and share it to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func loadSharedReports() {
        guard let service = appCore.reportsService,
              let userId = appCore.currentUser?.id else {
            loadError = "Service or user not available"
            return
        }
        do {
            sharedReports = try service.getSavedReports(userId: userId).filter { $0.isShared }
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
    }
}

// MARK: - Report Row Helper

private func reportRow(_ title: String, icon: String, description: String) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(.blue)
            .frame(width: 30)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.vertical, 2)
}
