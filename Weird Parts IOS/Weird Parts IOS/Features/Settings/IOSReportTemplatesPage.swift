import SwiftUI
import WiredPartCore

/// Manage saved report templates (configurations for generating reports).
///
/// Reads from the `saved_reports` table via ReportsService.
struct IOSReportTemplatesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?

    private enum ActiveSheet: Identifiable {
        case help
        case create
        var id: String {
            switch self {
            case .help: return "help"
            case .create: return "create"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    @State private var templates: [ReportsService.SavedReport] = []
    @State private var deleteCandidate: ReportsService.SavedReport?

    // Create form
    @State private var newName = ""
    @State private var newReportType = "labor_hours"
    @State private var newIsShared = false

    private let reportTypes = [
        ("labor_hours", "Timesheet"),
        ("parts_usage", "Parts Usage"),
        ("job_costs", "Job Costs"),
        ("tool_checkouts", "Tool Checkouts"),
        ("vehicle_fuel", "Vehicle Fuel"),
        ("order_history", "Order History"),
    ]

    private let reportTypeIcons: [String: String] = [
        "labor_hours": "clock",
        "parts_usage": "shippingbox",
        "job_costs": "dollarsign.circle",
        "tool_checkouts": "wrench",
        "vehicle_fuel": "fuelpump",
        "order_history": "doc.text",
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading templates...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView("Unable to Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                templateList
            }
        }
        .navigationTitle("Report Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button { activeSheet = .create } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add template")
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                NavigationStack {
                    List {
                        Section("About Report Templates") {
                            Text("Save report configurations as templates to quickly generate the same type of report with your preferred columns and filters.")
                        }
                        Section("Sharing") {
                            Text("Shared templates are visible to all team members. Private templates are only visible to you.")
                        }
                    }
                    .navigationTitle("Templates Help")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
                }
            case .create:
                createSheet
            }
        }
        .alert("Delete Template?", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .refreshable { loadTemplates() }
        .task { loadTemplates() }
    }

    // MARK: - Template List

    private var templateList: some View {
        List {
            if let actionError {
                Section {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if templates.isEmpty {
                EmptyStateView(
                    icon: "doc.on.doc",
                    title: "No Templates",
                    message: "Tap + to create a report template.",
                    actionLabel: "Add Template",
                    helpLabel: "Learn how report templates work",
                    helpAction: { activeSheet = .help },
                    action: { activeSheet = .create }
                )
            } else {
                // My templates
                let myTemplates = templates.filter { !$0.isShared }
                if !myTemplates.isEmpty {
                    Section("My Templates") {
                        ForEach(myTemplates) { template in
                            templateRow(template)
                        }
                        .onDelete { offsets in
                            if let idx = offsets.first {
                                deleteCandidate = myTemplates[idx]
                            }
                        }
                    }
                }

                // Shared templates
                let sharedTemplates = templates.filter(\.isShared)
                if !sharedTemplates.isEmpty {
                    Section("Shared Templates") {
                        ForEach(sharedTemplates) { template in
                            templateRow(template)
                        }
                        .onDelete { offsets in
                            if let idx = offsets.first {
                                deleteCandidate = sharedTemplates[idx]
                            }
                        }
                    }
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling templates list
        .scrollDismissesKeyboard(.interactively)
    }

    private func templateRow(_ template: ReportsService.SavedReport) -> some View {
        HStack {
            Image(systemName: reportTypeIcons[template.reportType] ?? "doc")
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(reportTypeLabel(template.reportType))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if template.isShared {
                        Label("Shared", systemImage: "person.2")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if let lastRun = template.lastRunAt {
                        Text("Last: \(lastRun.prefix(10))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
    }

    private func reportTypeLabel(_ type: String) -> String {
        reportTypes.first { $0.0 == type }?.1 ?? type.capitalized
    }

    // MARK: - Create Sheet

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("Template Info") {
                    TextField("Template name", text: $newName)

                    Picker("Report type", selection: $newReportType) {
                        ForEach(reportTypes, id: \.0) { type in
                            Text(type.1).tag(type.0)
                        }
                    }

                    Toggle("Share with team", isOn: $newIsShared)
                }

                Section {
                    Text("After creating, use the Report Builder to configure columns and filters for this template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!newName.trimmingCharacters(in: .whitespaces).isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTemplate() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadTemplates() {
        guard let service = appCore.reportsService,
              let userId = appCore.currentUser?.id else {
            loadError = "Reports service unavailable"
            isLoading = false
            return
        }

        do {
            templates = try service.getSavedReports(userId: userId)
        } catch {
            loadError = userFriendlyError(error, context: "load")
        }
        isLoading = false
    }

    private func createTemplate() {
        guard let service = appCore.reportsService,
              let userId = appCore.currentUser?.id else {
            actionError = "Reports service unavailable"
            return
        }

        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            try service.saveReportConfig(
                name: trimmed,
                type: newReportType,
                columns: [],
                filters: [:],
                userId: userId,
                isShared: newIsShared
            )
            activeSheet = nil
            newName = ""
            newIsShared = false
            loadTemplates()
        } catch {
            actionError = userFriendlyError(error, context: "save template")
        }
    }

    private func confirmDelete() {
        guard let service = appCore.reportsService,
              let template = deleteCandidate else {
            loadError = "Reports service not available"
            return
        }

        do {
            try service.deleteSavedReport(reportId: template.id)
            deleteCandidate = nil
            loadTemplates()
        } catch {
            actionError = userFriendlyError(error, context: "save template")
        }
    }
}
