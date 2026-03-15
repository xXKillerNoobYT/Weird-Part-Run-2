import SwiftUI
import WiredPartCore

/// Dispatch templates page showing reusable dispatch configurations.
///
/// Displays a table of dispatch templates with name, description, and
/// active status columns. Templates can be used to quickly populate
/// dispatch boards with common configurations.
struct DispatchTemplatesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var templates: [SchedulingService.TemplateListItem] = []
    @State private var isLoading = true

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\SchedulingService.TemplateListItem.name)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dispatch Templates")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(templates.count) template\(templates.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading templates...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if templates.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No dispatch templates")
                    .font(.headline)
                Text("Create templates to quickly populate dispatch boards.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedTemplates, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { template in
                    Text(template.name)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 250)

                TableColumn("Description") { (template: SchedulingService.TemplateListItem) in
                    Text(template.description ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 200, ideal: 350)

                TableColumn("Active") { (template: SchedulingService.TemplateListItem) in
                    if template.isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 60, ideal: 70)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedTemplates: [SchedulingService.TemplateListItem] {
        templates.sorted(using: sortOrder)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            let service = SchedulingService(db: db)
            templates = try service.listDispatchTemplates()
        } catch {
            print("[DispatchTemplatesPage] Load error: \(error)")
        }

        isLoading = false
    }
}
