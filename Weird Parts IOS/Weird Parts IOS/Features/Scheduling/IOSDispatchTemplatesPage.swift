import SwiftUI
import WiredPartCore

/// Dispatch templates list page for iOS.
///
/// Displays a searchable list of dispatch templates showing template name,
/// description, and active/inactive status. Uses
/// `SchedulingService.listDispatchTemplates()` with pull-to-refresh.
struct IOSDispatchTemplatesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var templates: [SchedulingService.TemplateListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        templateContent
            .navigationTitle("Dispatch Templates")
            .searchable(text: $searchText, prompt: "Search templates...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .sheet(item: $activeSheet) { _ in
                PageHelpSheet(title: "Dispatch Templates Help", sections: [
                    ("What This Page Does", "Dispatch Templates are reusable crew assignment patterns. Instead of building the same dispatch layout every week, you save a template and apply it to quickly fill the board."),
                    ("How to Use It", "Browse your saved templates in the list. Active templates are highlighted in green; inactive ones are grayed out. Use the search bar to find a specific template by name or description."),
                    ("Tips", "Create templates for your most common weekly patterns, like 'Full Crew Monday-Friday' or 'Weekend Skeleton Crew.' Mark templates inactive when they are seasonal or no longer needed rather than deleting them.")
                ])
            }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var templateContent: some View {
        if isLoading {
            ProgressView("Loading templates...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if filteredTemplates.isEmpty {
            ContentUnavailableView {
                Label("No Templates", systemImage: "doc.on.doc")
            } description: {
                Text("No dispatch templates found.")
            }
        } else {
            List(filteredTemplates, id: \.id) { template in
                templateRow(template)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredTemplates: [SchedulingService.TemplateListItem] {
        guard !searchText.isEmpty else { return templates }
        let query = searchText.lowercased()
        return templates.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Row

    private func templateRow(_ template: SchedulingService.TemplateListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.title2)
                .foregroundStyle(template.isActive ? Color.accentColor : .secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let desc = template.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Label(template.isActive ? "Active" : "Inactive", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(template.isActive ? .green : .secondary)
            }

            Spacer()

            activeBadge(template.isActive)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badge

    private func activeBadge(_ isActive: Bool) -> some View {
        Text(isActive ? "Active" : "Inactive")
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15)))
            .foregroundStyle(isActive ? .green : .secondary)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            isLoading = false
            loadError = "Scheduling service unavailable"
            return
        }
        isLoading = templates.isEmpty
        do {
            templates = try service.listDispatchTemplates()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
