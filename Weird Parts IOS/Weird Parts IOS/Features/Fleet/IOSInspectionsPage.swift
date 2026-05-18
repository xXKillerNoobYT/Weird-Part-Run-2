import SwiftUI
import WiredPartCore

/// Vehicle inspections list page for iOS.
///
/// Displays a searchable list of inspection records with vehicle name,
/// inspector, date, and result badge (pass=green, fail=red).
/// Uses FleetService.listInspections() for data access.
struct IOSInspectionsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var inspections: [FleetService.InspectionRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        inspectionList
            .navigationTitle("Inspections")
            .searchable(text: $searchText, prompt: "Search inspections...")
            .refreshable { loadData() }
            .task { loadData() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loadData() }
            }
            .onAppear {
                NotificationCenter.default.post(
                    name: .fleetInspectionsPageActive,
                    object: nil,
                    userInfo: ["context": fleetInspectionsContext]
                )
            }
            .onDisappear {
                NotificationCenter.default.post(name: .fleetInspectionsPageInactive, object: nil)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(item: $activeSheet) { _ in
                PageHelpSheet(
                    title: "Inspections Help",
                    sections: [
                        ("Overview", "This page shows all vehicle inspection records. Each entry lists the vehicle, inspector, date, odometer reading, and the result — Pass (green), Fail (red), or Conditional (orange)."),
                        ("Results Explained", "Pass means all items checked out fine. Conditional means non-critical issues were found — the vehicle can operate but needs attention. Fail means a critical safety item failed — the vehicle should not be driven until repaired."),
                        ("Searching", "Use the search bar to filter by vehicle name, inspector name, or result status. For example, type 'fail' to see all failed inspections."),
                        ("Tips", "Pre-trip inspections should be completed every day before driving. Start an inspection from the vehicle detail page under the Inspections tab. The Fleet Dashboard shows which vehicles are missing today's inspection.")
                    ]
                )
            }
    }

    // MARK: - Inspection List

    private var fleetInspectionsContext: String {
        let searchState = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : "active"
        return "page=Fleet Inspections; total_inspections=\(inspections.count); visible_inspections=\(filteredInspections.count); search=\(searchState)"
    }

    @ViewBuilder
    private var inspectionList: some View {
        if isLoading {
            ProgressView("Loading inspections...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredInspections.isEmpty {
            ContentUnavailableView {
                Label("No Inspections", systemImage: "checklist")
            } description: {
                Text("No vehicle inspections have been recorded yet.")
            }
        } else {
            List(filteredInspections, id: \.id) { inspection in
                inspectionRow(inspection)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredInspections: [FleetService.InspectionRow] {
        guard !searchText.isEmpty else { return inspections }
        let query = searchText.lowercased()
        return inspections.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.inspectorName.lowercased().contains(query) ||
            $0.result.lowercased().contains(query)
        }
    }

    private func inspectionRow(_ inspection: FleetService.InspectionRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist.checked")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(inspection.vehicleName)
                        .fontWeight(.medium)
                    resultBadge(inspection.result)
                }
                HStack(spacing: 6) {
                    Label(inspection.inspectorName, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(inspection.inspectionDate.prefix(10)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let odo = inspection.odometerReading {
                Text("\(odo.formatted()) mi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func resultBadge(_ result: String) -> some View {
        let color: Color = switch result.lowercased() {
        case "pass", "passed": .green
        case "fail", "failed": .red
        case "conditional": .orange
        default: .gray
        }
        return Text(result.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        isLoading = inspections.isEmpty
        loadError = nil

        do {
            inspections = try service.listInspections()
        } catch {
            loadError = userFriendlyError(error, context: "load inspections")
        }

        isLoading = false
    }
}
