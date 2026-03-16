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
    @State private var searchText = ""

    var body: some View {
        templateContent
            .navigationTitle("Dispatch Templates")
            .searchable(text: $searchText, prompt: "Search templates...")
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var templateContent: some View {
        if isLoading {
            ProgressView("Loading templates...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
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
        guard let service = appCore.schedulingService else { return }
        isLoading = templates.isEmpty
        do {
            templates = try service.listDispatchTemplates()
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[IOSDispatchTemplatesPage] Load error: \(error)")
            }
        }
        isLoading = false
    }
}
