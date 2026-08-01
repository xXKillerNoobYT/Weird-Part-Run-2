import SwiftUI
import WiredPartCore

/// Notebook detail page with hierarchical structure: Groups → Sections → Block Entries.
struct IOSNotebookDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let notebookId: Int64

    // MARK: - State

    @State private var notebook: NotebooksService.NotebookDetail?
    @State private var hierarchy: NotebooksService.NotebookHierarchy?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var activeEditLockEntryId: Int64?
    @State private var expandedGroups: Set<Int64> = []
    @State private var expandedSections: Set<Int64> = []
    @State private var isWarrantyJob = false
    @State private var todosNeedingReview: [NotebooksService.NotebookEntryRow] = []
    @State private var panelSchedule = PanelSchedule()
    @State private var designPanelState = DesignPanelState()
    @AppStorage("panelPrintConfigJSON") private var panelPrintConfigJSON = ""
    @State private var showPanelPrintPreview = false
    @State private var blockConflicts: [NotebookBlockConflict] = []
    @State private var activeEditLocks: [NotebookEntryEditLock] = []
    @State private var pendingDelete: PendingDelete?
    @State private var selectedPageId: Int64?
    @State private var compactPageId: Int64?

    // MARK: - PendingDelete

    private enum PendingDelete: Identifiable {
        case group(Int64)
        case section(Int64)
        case entry(Int64)

        var id: String {
            switch self {
            case .group(let id): return "group-\(id)"
            case .section(let id): return "section-\(id)"
            case .entry(let id): return "entry-\(id)"
            }
        }

        var label: String {
            switch self {
            case .group: return "Delete Group"
            case .section: return "Delete Section"
            case .entry: return "Delete Block"
            }
        }

        var message: String {
            switch self {
            case .group: return "This will delete the group and all its sections and entries."
            case .section: return "This will delete the section and all its entries."
            case .entry: return "This block entry will be permanently deleted."
            }
        }
    }

    // MARK: - ActiveSheet

    private enum ActiveSheet: Identifiable {
        case addEntry(sectionId: Int64)
        case editEntry(NotebooksService.NotebookEntryRow)
        case addSection(groupId: Int64?)
        case addGroup
        case editSection(sectionId: Int64, name: String)
        case editGroup(groupId: Int64, name: String)
        case panelScheduleEditor
        case panelRedesignBuilder
        case conflictResolution
        case notebookSections
        case help

        var id: String {
            switch self {
            case .addEntry(let id): return "addEntry-\(id)"
            case .editEntry(let entry): return "editEntry-\(entry.id)"
            case .addSection(let id): return "addSection-\(id ?? 0)"
            case .addGroup: return "addGroup"
            case .editSection(let id, _): return "editSection-\(id)"
            case .editGroup(let id, _): return "editGroup-\(id)"
            case .panelScheduleEditor: return "panelSchedule"
            case .panelRedesignBuilder: return "panelRedesign"
            case .conflictResolution: return "conflictResolution"
            case .notebookSections: return "notebookSections"
            case .help: return "help"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading notebook...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                notebookShell
            }
        }
        .navigationTitle(notebook?.title ?? "Notebook")
        .toolbar {
            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .notebookSections
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Notebook sections")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        activeSheet = .addGroup
                    } label: {
                        Label("Add Section Group", systemImage: "folder.badge.plus")
                    }
                    Button {
                        activeSheet = .addSection(groupId: nil)
                    } label: {
                        Label("Add Section", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Add content")
                .accessibilityIdentifier("notebookToolbar_addBlock")
                .disabled(isReadOnly)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            if let entryId = activeEditLockEntryId {
                releaseEditLock(entryId: entryId)
                activeEditLockEntryId = nil
            }
        }) { sheet in
            sheetContent(for: sheet)
                .environmentObject(appCore)
        }
        .confirmationDialog(
            pendingDelete?.label ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button(item.label, role: .destructive) {
                switch item {
                case .group(let id): deleteSectionGroup(id)
                case .section(let id): deleteSection(id)
                case .entry(let id): deleteEntry(id)
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { item in
            Text(item.message)
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Responsive Shell

    private var isReadOnly: Bool {
        notebook?.status == "locked" || notebook?.status == "archived"
    }

    private struct NotebookPage: Identifiable {
        let id: Int64
        let section: NotebooksService.SectionWithEntries
        let groupName: String?
        let derivedPreview: String
        let updatedText: String?

        var title: String { section.name }
        var blockCountText: String {
            "\(section.entries.count) block\(section.entries.count == 1 ? "" : "s")"
        }
    }

    @ViewBuilder
    private var notebookShell: some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                pageSidebar
                    .frame(width: 320)
                    .background(Color(.secondarySystemGroupedBackground))
                Divider()
                selectedPageSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
        } else {
            if compactPageId == nil {
                compactPageList
            } else {
                compactSelectedPageSurface
            }
        }
    }

    private var notebookPages: [NotebookPage] {
        var pages: [NotebookPage] = []
        hierarchy?.groups.forEach { group in
            group.sections.forEach { section in
                pages.append(makeNotebookPage(section: section, groupName: group.name))
            }
        }
        hierarchy?.ungroupedSections.forEach { section in
            pages.append(makeNotebookPage(section: section, groupName: nil))
        }
        return pages
    }

    private var selectedPage: NotebookPage? {
        let pages = notebookPages
        if let selectedPageId, let page = pages.first(where: { $0.id == selectedPageId }) {
            return page
        }
        return pages.first
    }

    private func makeNotebookPage(section: NotebooksService.SectionWithEntries, groupName: String?) -> NotebookPage {
        NotebookPage(
            id: section.id,
            section: section,
            groupName: groupName,
            derivedPreview: derivedPreview(for: section),
            updatedText: updatedText(for: section)
        )
    }

    private func selectPage(_ page: NotebookPage, compact: Bool = false) {
        selectedPageId = page.id
        if compact {
            compactPageId = page.id
        }
    }

    private var pageSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                notebookSummaryCard
                if !blockConflicts.isEmpty {
                    Button {
                        activeSheet = .conflictResolution
                    } label: {
                        Label("Open conflicts", systemImage: "exclamationmark.triangle")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("notebookSidebar_openConflicts")
                }
                Text("Pages")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                if notebookPages.isEmpty {
                    Text("No pages yet. Create a section to start this notebook.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    pageSidebarGroups
                }
            }
            .padding(14)
        }
        .accessibilityIdentifier("notebookPageSidebar")
    }

    @ViewBuilder
    private var pageSidebarGroups: some View {
        if let groups = hierarchy?.groups, !groups.isEmpty {
            ForEach(groups) { group in
                pageGroupHeader(group)
                ForEach(group.sections) { section in
                    let page = makeNotebookPage(section: section, groupName: group.name)
                    pageSidebarRow(page, compact: false)
                }
            }
        }
        if let sections = hierarchy?.ungroupedSections, !sections.isEmpty {
            Text("Ungrouped")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            ForEach(sections) { section in
                let page = makeNotebookPage(section: section, groupName: nil)
                pageSidebarRow(page, compact: false)
            }
        }
    }

    private func pageGroupHeader(_ group: NotebooksService.SectionGroupWithChildren) -> some View {
        HStack(spacing: 8) {
            Text(group.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Menu {
                Button { activeSheet = .editGroup(groupId: group.id, name: group.name) } label: {
                    Label("Rename Group", systemImage: "pencil")
                }
                Button { activeSheet = .addSection(groupId: group.id) } label: {
                    Label("Add Section", systemImage: "plus")
                }
                Button(role: .destructive) { pendingDelete = .group(group.id) } label: {
                    Label("Delete Group", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .disabled(isReadOnly)
            .accessibilityLabel("Group actions for \(group.name)")
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func pageSidebarRow(_ page: NotebookPage, compact: Bool) -> some View {
        let isSelected = selectedPage?.id == page.id
        return Button {
            selectPage(page, compact: compact)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.text")
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(page.derivedPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(page.blockCountText)
                            if let groupName = page.groupName {
                                Text("•")
                                Text(groupName)
                            }
                            if let updatedText = page.updatedText {
                                Text("•")
                                Text(updatedText)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        Button { activeSheet = .editSection(sectionId: page.id, name: page.title) } label: {
                            Label("Rename Page", systemImage: "pencil")
                        }
                        Button { activeSheet = .addEntry(sectionId: page.id) } label: {
                            Label("Add Block", systemImage: "plus.circle")
                        }
                        Button(role: .destructive) { pendingDelete = .section(page.id) } label: {
                            Label("Delete Page", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(isReadOnly)
                    .accessibilityLabel("Page actions for \(page.title)")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(.systemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelForPageRow(page, isSelected: isSelected))
        .accessibilityIdentifier("notebookPageRow_\(page.id)")
    }

    private func sidebarRow(id: String, title: String, systemImage: String, badge: String?, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .frame(minHeight: 44)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelForSidebarRow(title: title, badge: badge, isSelected: isSelected))
        .accessibilityIdentifier("notebookSidebar_\(id)")
    }

    private var compactPageList: some View {
        List {
            actionErrorSection
            syncConflictBannerSection
            managerReviewSection
            if notebookPages.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No pages yet",
                        message: "Create a section to start this notebook."
                    )
                    Button {
                        activeSheet = .addSection(groupId: nil)
                    } label: {
                        Label("Create page", systemImage: "doc.badge.plus")
                            .frame(minHeight: 44)
                    }
                    .disabled(isReadOnly)
                }
            } else {
                Section("Pages") {
                    ForEach(notebookPages) { page in
                        pageSidebarRow(page, compact: true)
                    }
                }
            }
            panelScheduleSection
            notebookInfoSection
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("notebookCompactPageList")
    }

    private var selectedPageSurface: some View {
        List {
            selectedPageContentSections
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("notebookSelectedPageSurface")
    }

    private var compactSelectedPageSurface: some View {
        List {
            Section {
                Button {
                    compactPageId = nil
                } label: {
                    Label("Back to pages", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
            }
            selectedPageContentSections
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("notebookCompactSelectedPageSurface")
    }

    @ViewBuilder
    private var selectedPageContentSections: some View {
        actionErrorSection
        syncConflictBannerSection
        managerReviewSection
        if let page = selectedPage {
            selectedPageHeader(page)
            Section {
                if page.section.entries.isEmpty {
                    EmptyStateView(
                        icon: "text.badge.plus",
                        title: "Empty page",
                        message: "This page has no blocks yet. Add the first block when you're ready."
                    )
                } else {
                    ForEach(page.section.entries) { entry in
                        entryRow(entry)
                    }
                }
                Button {
                    activeSheet = .addEntry(sectionId: page.id)
                } label: {
                    Label("Add Block", systemImage: "plus.circle")
                        .frame(minHeight: 44)
                }
                .disabled(isReadOnly)
            } header: {
                Text("Page Blocks")
            } footer: {
                Text("Showing only the selected page's blocks, not the whole notebook.")
            }
        } else {
            Section {
                EmptyStateView(
                    icon: "note.text",
                    title: "No pages yet",
                    message: "Create a section to organize this job notebook."
                )
                Button {
                    activeSheet = .addSection(groupId: nil)
                } label: {
                    Label("Create page", systemImage: "doc.badge.plus")
                        .frame(minHeight: 44)
                }
                .disabled(isReadOnly)
            }
        }
        legacyEntriesSection
        panelScheduleSection
        notebookInfoSection
    }

    private func selectedPageHeader(_ page: NotebookPage) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(page.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.derivedPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    statusBadge(notebook?.status ?? "active")
                    Text(page.blockCountText)
                    if let groupName = page.groupName {
                        Text("• \(groupName)")
                    }
                    if let updatedText = page.updatedText {
                        Text("• \(updatedText)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        activeSheet = .editSection(sectionId: page.id, name: page.title)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isReadOnly)
                    Button {
                        activeSheet = .addEntry(sectionId: page.id)
                    } label: {
                        Label("Add Block", systemImage: "plus.circle")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isReadOnly)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var actionErrorSection: some View {
        if let error = actionError {
            Section {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
    }

    @ViewBuilder
    private var syncConflictBannerSection: some View {
        if !blockConflicts.isEmpty {
            Section {
                Button {
                    activeSheet = .conflictResolution
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.white)
                            .font(.title3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(blockConflicts.count) Sync Conflict\(blockConflicts.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            Text("Tap to review and resolve")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
    }

    @ViewBuilder
    private var managerReviewSection: some View {
        if isWarrantyJob && appCore.hasPermission("manage_jobs") && !todosNeedingReview.isEmpty {
            Section {
                ForEach(todosNeedingReview) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title ?? entry.content)
                                .font(.subheadline)
                            Text("Classified as: \(entry.workClassification ?? "unset")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Approve") {
                            approveClassification(entryId: entry.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                Text("Needs Review (\(todosNeedingReview.count))")
            }
        }
    }

    @ViewBuilder
    private var legacyEntriesSection: some View {
        let legacyEntries = notebook?.entries ?? []
        if !legacyEntries.isEmpty && notebookPages.isEmpty {
            Section {
                ForEach(legacyEntries) { entry in
                    entryRow(entry)
                }
            } header: {
                Text("Entries")
            } footer: {
                Text("Legacy entries are shown only when this notebook has no pages yet.")
            }
        }
    }

    @ViewBuilder
    private var panelScheduleSection: some View {
        if notebook?.notebookType == "panel_schedule" {
            Section("Panel Schedule") {
                Button {
                    activeSheet = .panelScheduleEditor
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Panel Schedule Builder")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Edit circuit breaker assignments")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                Button {
                    activeSheet = .panelRedesignBuilder
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New Builder (redesign)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Three layouts, tandem/quad breakers, pro print")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("openPanelRedesignBuilder")
            }
        }
    }

    private var notebookInfoSection: some View {
        Section {
            if let nb = notebook {
                detailRow("Type", nb.notebookType)
                detailRow("Status", nb.status.capitalized)
                if let created = nb.createdAt {
                    detailRow("Created", String(created.prefix(10)))
                }
                if let updated = nb.updatedAt {
                    detailRow("Updated", String(updated.prefix(10)))
                }
                if let jobName = nb.jobName {
                    detailRow("Job", jobName)
                }
            }
        } header: {
            Text("Notebook Info")
        }
    }

    private var notebookSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notebook?.jobName ?? "Job notebook", systemImage: "hammer")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(notebook?.title ?? "Notebook")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                statusBadge(notebook?.status ?? "active")
                if let updated = notebook?.updatedAt {
                    Text("Updated \(String(updated.prefix(10)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var allEntries: [NotebooksService.NotebookEntryRow] {
        var entries: [NotebooksService.NotebookEntryRow] = notebook?.entries ?? []
        hierarchy?.groups.forEach { group in
            group.sections.forEach { entries.append(contentsOf: $0.entries) }
        }
        hierarchy?.ungroupedSections.forEach { entries.append(contentsOf: $0.entries) }
        return entries
    }

    private var todoBadgeText: String? {
        let count = allEntries.filter { $0.blockType == "todo" && !$0.isCompleted }.count
        return count > 0 ? "\(count)" : nil
    }

    private func derivedPreview(for section: NotebooksService.SectionWithEntries) -> String {
        for entry in section.entries {
            let title = (entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
            let content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { return content }
        }
        return "This page has no blocks yet."
    }

    private func updatedText(for section: NotebooksService.SectionWithEntries) -> String? {
        section.entries.compactMap(\.createdAt).last.map { "Updated \(String($0.prefix(10)))" }
    }

    private func accessibilityLabelForPageRow(_ page: NotebookPage, isSelected: Bool) -> String {
        [page.title, page.derivedPreview, page.blockCountText, isSelected ? "selected" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func accessibilityLabelForSidebarRow(title: String, badge: String?, isSelected: Bool) -> String {
        [title, badge.map { "\($0) items" }, isSelected ? "selected" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Content List

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "locked": .red
        case "archived": .secondary
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Section Row

    private func sectionRow(_ sectionItem: NotebooksService.SectionWithEntries) -> some View {
        DisclosureGroup(
            isExpanded: sectionBinding(sectionItem.id)
        ) {
            ForEach(sectionItem.entries) { entry in
                entryRow(entry)
            }
            Button {
                activeSheet = .addEntry(sectionId: sectionItem.id)
            } label: {
                Label("Add Block", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .frame(minHeight: 44)
            }
            .disabled(isReadOnly)
        } label: {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(sectionItem.name).font(.subheadline)
                Spacer()
                Text("\(sectionItem.entries.count)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .contextMenu {
                Button {
                    activeSheet = .editSection(sectionId: sectionItem.id, name: sectionItem.name)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    activeSheet = .addEntry(sectionId: sectionItem.id)
                } label: {
                    Label("Add Block", systemImage: "plus.circle")
                }
                Button(role: .destructive) {
                    pendingDelete = .section(sectionItem.id)
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Block Entry Display

    @ViewBuilder
    private func entryRow(_ entry: NotebooksService.NotebookEntryRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
            switch entry.blockType {
            case "heading":
                Text(entry.title ?? entry.content)
                    .font(headingFont(level: entry.headingLevel ?? 1))
                    .bold()

            case "checklist":
                if let items = decodeChecklistItems(entry.checklistItems) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = entry.title, !title.isEmpty {
                            Text(title).font(.subheadline).bold()
                        }
                        ForEach(items.indices, id: \.self) { idx in
                            HStack(spacing: 8) {
                                Image(systemName: items[idx].checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(items[idx].checked ? .green : .secondary)
                                    .accessibilityLabel(items[idx].checked ? "Completed" : "Not completed")
                                Text(items[idx].text)
                                    .strikethrough(items[idx].checked)
                                    .font(.subheadline)
                            }
                        }
                    }
                } else {
                    Text(entry.content).font(.subheadline)
                }

            case "quote":
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(.secondary.opacity(0.45))
                        .frame(width: 3)
                        .accessibilityHidden(true)
                    Text(entry.content)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

            case "code":
                Text(entry.content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

            case "photo":
                if let path = entry.photoPath, let url = URL(string: path) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } placeholder: {
                        HStack {
                            Image(systemName: "photo")
                            Text("Loading photo...")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(entry.title ?? "Photo").font(.subheadline)
                    }
                }

            case "part_reference":
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text(entry.title ?? "Part Reference")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                }
                .padding(8)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            case "divider":
                Divider()

            case "callout":
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(.yellow)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = entry.title, !title.isEmpty {
                            Text(title).font(.subheadline).bold()
                        }
                        Text(entry.content)
                            .font(.callout)
                            .italic()
                    }
                }
                .padding(.vertical, 4)

            case "table":
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "tablecells")
                            .foregroundStyle(.purple)
                            .accessibilityHidden(true)
                        Text(entry.title ?? "Table").font(.subheadline).bold()
                    }
                    if !entry.content.isEmpty {
                        Text(entry.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            case "panel_schedule":
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title ?? "Panel Schedule")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Open the panel builder to edit breaker assignments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            case "todo":
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(entry.isCompleted ? .green : .secondary)
                            .accessibilityLabel(entry.isCompleted ? "Status: Completed" : "Status: Pending")
                        Text(entry.title ?? entry.content)
                            .font(.subheadline)
                            .strikethrough(entry.isCompleted)

                        if entry.isQuestion {
                            Text("?")
                                .font(.caption).bold()
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.purple)
                                .clipShape(Circle())
                        }
                    }

                    // Classification UI for warranty jobs
                    if isWarrantyJob {
                        HStack(spacing: 8) {
                            // Classification picker
                            classificationPicker(for: entry)

                            // Review status
                            if entry.workClassification != nil {
                                if entry.classificationReviewed {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                        .accessibilityLabel("Status: Reviewed")
                                } else {
                                    Text("Needs Review")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        // Warranty timer
                        if let timerEnd = entry.warrantyTimerEnd {
                            warrantyTimerView(endDate: timerEnd)
                        }
                    }
                }

            default: // "text" and any other type
                VStack(alignment: .leading, spacing: 2) {
                    if let title = entry.title, !title.isEmpty {
                        Text(title).font(.subheadline).bold()
                    }
                    if !entry.content.isEmpty {
                        Text(entry.content)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    HStack {
                        Text(entry.createdByName)
                            .font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        if let date = entry.createdAt {
                            Text(String(date.prefix(10)))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let lock = activeLock(for: entry.id) {
                Label(lock.userName, systemImage: "person.crop.circle.badge.clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("\(lock.userName) is editing this block")
            }

            Button {
                beginEditing(entry)
            } label: {
                Image(systemName: "pencil.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit block")
            .accessibilityHint("Opens this block for editing while preserving change history")
        }
        .contextMenu {
            Button {
                beginEditing(entry)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = .entry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Classification UI

    @ViewBuilder
    private func classificationPicker(for entry: NotebooksService.NotebookEntryRow) -> some View {
        let currentValue = entry.workClassification ?? ""
        HStack(spacing: 4) {
            Button {
                classifyEntry(entryId: entry.id, classification: "regular")
            } label: {
                Text("Regular")
                    .font(.caption2)
                    .fontWeight(currentValue == "regular" ? .bold : .regular)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(currentValue == "regular" ? Color.blue : Color.blue.opacity(0.1))
                    .foregroundStyle(currentValue == "regular" ? .white : .blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                classifyEntry(entryId: entry.id, classification: "warranty")
            } label: {
                Text("Warranty")
                    .font(.caption2)
                    .fontWeight(currentValue == "warranty" ? .bold : .regular)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(currentValue == "warranty" ? Color.purple : Color.purple.opacity(0.1))
                    .foregroundStyle(currentValue == "warranty" ? .white : .purple)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func warrantyTimerView(endDate: String) -> some View {
        let fmt = ISO8601DateFormatter()
        let _ = fmt.formatOptions = [.withInternetDateTime]
        if let end = fmt.date(from: endDate) {
            let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text("Warranty: \(daysRemaining) days remaining")
                    .font(.caption2)
                    .foregroundStyle(daysRemaining < 7 ? .red : .secondary)
            }
        }
    }

    private func classifyEntry(entryId: Int64, classification: String) {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else {
            loadError = "Notebooks service not available"
            return
        }
        do {
            try service.classifyTodoWork(entryId: entryId, classification: classification, classifiedBy: userId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func approveClassification(entryId: Int64) {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else {
            loadError = "Notebooks service not available"
            return
        }
        do {
            try service.reviewClassification(entryId: entryId, reviewedBy: userId, approved: true, newClassification: nil)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    // MARK: - Helpers

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .headline
        }
    }

    private struct ChecklistItemData: Codable {
        let text: String
        let checked: Bool

        // Tolerant decode: AddNotebookEntrySheet historically wrote `checked` as
        // the STRINGS "true"/"false", which a plain Bool decode rejects — so every
        // checklist saved there silently rendered as nothing here (2026-07-06
        // panel-quality audit). New rows are canonical Bool; legacy rows decode too.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            if let flag = try? container.decode(Bool.self, forKey: .checked) {
                checked = flag
            } else if let legacy = try? container.decode(String.self, forKey: .checked) {
                checked = legacy == "true"
            } else {
                checked = false
            }
        }
    }

    private func decodeChecklistItems(_ json: String?) -> [ChecklistItemData]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ChecklistItemData].self, from: data)
    }

    private func groupBinding(_ id: Int64) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(id) },
            set: { expanded in
                if expanded { expandedGroups.insert(id) }
                else { expandedGroups.remove(id) }
            }
        )
    }

    private func sectionBinding(_ id: Int64) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(id) },
            set: { expanded in
                if expanded { expandedSections.insert(id) }
                else { expandedSections.remove(id) }
            }
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .addEntry(let sectionId):
            AddNotebookEntrySheet(
                notebookId: notebookId,
                sectionId: sectionId,
                onSave: { loadData() }
            )

        case .editEntry(let entry):
            AddNotebookEntrySheet(
                notebookId: notebookId,
                sectionId: nil,
                editingEntry: entry,
                onSave: {
                    releaseEditLock(entryId: entry.id)
                    activeEditLockEntryId = nil
                    loadData()
                }
            )

        case .addSection(let groupId):
            NameInputSheet(title: "New Section", placeholder: "Section name") { name in
                createSection(groupId: groupId, name: name)
            }

        case .addGroup:
            NameInputSheet(title: "New Section Group", placeholder: "Group name") { name in
                createSectionGroup(name: name)
            }

        case .editSection(let sectionId, let currentName):
            NameInputSheet(title: "Rename Section", placeholder: "Section name", initialValue: currentName) { name in
                renameSection(sectionId: sectionId, name: name)
            }

        case .editGroup(let groupId, let currentName):
            NameInputSheet(title: "Rename Group", placeholder: "Group name", initialValue: currentName) { name in
                renameSectionGroup(groupId: groupId, name: name)
            }

        case .panelScheduleEditor:
            NavigationStack {
                PanelScheduleBuilder(schedule: $panelSchedule) { saved in
                    panelSchedule = saved
                    persistPanelSchedule(saved)
                }
                .navigationTitle("Panel Schedule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
            }

        case .panelRedesignBuilder:
            NavigationStack {
                PanelRedesignBuilderView(panel: $designPanelState)
                    .navigationTitle("Panel Schedule")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                persistDesignPanelState()
                                activeSheet = nil
                            }
                            .accessibilityIdentifier("panelRedesignDone")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showPanelPrintPreview = true
                            } label: {
                                Label("Print", systemImage: "printer")
                            }
                            .accessibilityIdentifier("panelRedesignPrint")
                        }
                    }
                    .onChange(of: designPanelState) { _, _ in
                        persistDesignPanelState()
                    }
                    .sheet(isPresented: $showPanelPrintPreview) {
                        PanelPrintPreviewSheet(
                            panelName: notebook?.title ?? "Panel",
                            panel: designPanelState,
                            config: panelPrintConfigBinding
                        )
                    }
            }

        case .conflictResolution:
            NotebookConflictResolutionSheet(
                conflicts: blockConflicts,
                onResolve: { conflictLogId, keepVersion in
                    resolveConflict(conflictLogId: conflictLogId, keepVersion: keepVersion)
                },
                onAIMerge: { conflictLogId in
                    mergeConflictWithAI(conflictLogId: conflictLogId)
                },
                onResolveAll: { keepVersion in
                    resolveAllConflicts(keepVersion: keepVersion)
                }
            )

        case .notebookSections:
            NavigationStack {
                List {
                    Section {
                        notebookSummaryCard
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    Section("Notebook") {
                        sidebarRow(id: "overview", title: "Overview", systemImage: "doc.text", badge: nil, isSelected: true)
                        sidebarRow(id: "dailyLogs", title: "Daily Logs", systemImage: "calendar", badge: nil, isSelected: false)
                        sidebarRow(id: "todos", title: "To-Dos", systemImage: "checklist", badge: todoBadgeText, isSelected: false)
                        sidebarRow(id: "photos", title: "Photos", systemImage: "photo.on.rectangle", badge: nil, isSelected: false)
                        sidebarRow(id: "panelSchedules", title: "Panel Schedules", systemImage: "bolt.rectangle", badge: nil, isSelected: false)
                        if !blockConflicts.isEmpty {
                            sidebarRow(id: "openConflicts", title: "Open conflicts", systemImage: "exclamationmark.triangle", badge: "\(blockConflicts.count)", isSelected: false)
                        }
                    }
                    if let groups = hierarchy?.groups, !groups.isEmpty {
                        Section("Sections") {
                            ForEach(groups) { group in
                                Text(group.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(group.sections) { section in
                                    sidebarRow(
                                        id: "section_\(section.id)",
                                        title: section.name,
                                        systemImage: "doc.text",
                                        badge: "\(section.entries.count)",
                                        isSelected: false
                                    )
                                    .accessibilityIdentifier("notebookSectionSheet_section_\(section.id)")
                                }
                            }
                        }
                    }
                    if let sections = hierarchy?.ungroupedSections, !sections.isEmpty {
                        Section("Pages") {
                            ForEach(sections) { section in
                                sidebarRow(
                                    id: "section_\(section.id)",
                                    title: section.name,
                                    systemImage: "doc.text",
                                    badge: "\(section.entries.count)",
                                    isSelected: false
                                )
                                .accessibilityIdentifier("notebookSectionSheet_section_\(section.id)")
                            }
                        }
                    }
                }
                .navigationTitle("Notebook Sections")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
            }

        case .help:
            PageHelpSheet(title: "Notebook Detail Help", sections: [
                ("What This Page Does", "Shows the full contents of a notebook organized into section groups, sections, and block entries. This is where you read, add, and edit all the content within a notebook."),
                ("How It Is Organized", "Notebooks use a three-level hierarchy: Section Groups contain Sections, and Sections contain Block Entries. Ungrouped sections appear under 'Pages' at the bottom. Tap disclosure arrows to expand or collapse groups and sections."),
                ("Adding Content", "Use the + menu in the toolbar to add a new Section Group or Section. Within each section, tap 'Add Block' to insert a new entry. Entries can be text, headings, checklists, photos, part references, callouts, tables, dividers, or to-do items."),
                ("Editing & Deleting", "Long-press on any section, group, or entry to access context menu options for renaming, editing, or deleting. Swipe actions may also be available on some items."),
                ("Warranty Jobs", "If this notebook is linked to a warranty job, to-do entries will show classification buttons (Regular or Warranty) and a review workflow. Managers can approve classifications from the 'Needs Review' section at the top.")
            ])
        }
    }

    // MARK: - Data Operations

    private func loadData() {
        guard let service = appCore.notebooksService else {
            loadError = "Notebooks service unavailable"
            isLoading = false
            return
        }
        isLoading = notebook == nil
        loadError = nil
        actionError = nil
        do {
            notebook = try service.getNotebookDetail(id: notebookId)
            hierarchy = try service.getNotebookHierarchy(notebookId: notebookId)
            // Auto-expand all groups and sections on first load
            if expandedGroups.isEmpty, let groups = hierarchy?.groups {
                expandedGroups = Set(groups.map(\.id))
            }
            if expandedSections.isEmpty {
                var ids: [Int64] = []
                hierarchy?.groups.forEach { g in ids.append(contentsOf: g.sections.map(\.id)) }
                hierarchy?.ungroupedSections.forEach { s in ids.append(s.id) }
                expandedSections = Set(ids)
            }
            let currentPages = notebookPages
            if let selectedPageId, !currentPages.contains(where: { $0.id == selectedPageId }) {
                self.selectedPageId = currentPages.first?.id
            } else if selectedPageId == nil {
                selectedPageId = currentPages.first?.id
            }
            if let compactPageId, !currentPages.contains(where: { $0.id == compactPageId }) {
                self.compactPageId = nil
            }
            // Check for sync conflicts on this notebook's entries (62J)
            blockConflicts = (try? service.detectBlockConflicts(notebookId: notebookId)) ?? []
            activeEditLocks = (try? service.activeBlockEditLocks(notebookId: notebookId)) ?? []

            // Load panel schedule from first panel_schedule block entry
            loadPanelScheduleFromEntries(service: service)

            // Check if this notebook belongs to a warranty job
            if let jobId = notebook?.jobId, let jobsService = appCore.jobsService {
                if let job = try? jobsService.getJob(id: jobId) {
                    isWarrantyJob = job.status == "warranty"
                    if isWarrantyJob {
                        todosNeedingReview = (try? service.getTodosNeedingReview(jobId: jobId)) ?? []
                    }
                }
            }
        } catch {
            loadError = userFriendlyError(error, context: "load notebooks")
        }
        isLoading = false
    }

    // MARK: - Panel Schedule Persistence

    /// Load panel schedule data from the first block entry with type "panel_schedule".
    private func loadPanelScheduleFromEntries(service: NotebooksService) {
        guard let groups = hierarchy?.groups else { return }
        // Search all block entries for a panel_schedule type
        for group in groups {
            for section in group.sections {
                for entry in section.entries where entry.blockType == "panel_schedule" {
                    if let data = entry.blockData?.data(using: .utf8),
                       let schedule = try? JSONDecoder().decode(PanelSchedule.self, from: data) {
                        // Clamp malformed/synced totalSpaces before rendering —
                        // a negative value traps range construction (#1239).
                        panelSchedule = schedule.clampingTotalSpacesToSupportedRange()
                        loadDesignPanelState()
                        return
                    }
                }
            }
        }
        // Also check ungrouped sections
        if let ungrouped = hierarchy?.ungroupedSections {
            for section in ungrouped {
                for entry in section.entries where entry.blockType == "panel_schedule" {
                    if let data = entry.blockData?.data(using: .utf8),
                       let schedule = try? JSONDecoder().decode(PanelSchedule.self, from: data) {
                        panelSchedule = schedule.clampingTotalSpacesToSupportedRange()
                        loadDesignPanelState()
                        return
                    }
                }
            }
        }
    }

    /// Persist panel schedule to a block entry with type "panel_schedule".
    private func persistPanelSchedule(_ schedule: PanelSchedule) {
        guard let service = appCore.notebooksService else {
            loadError = "Service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            loadError = "Not logged in. Please log in and try again."
            return
        }
        guard let notebookId = notebook?.id else {
            loadError = "No notebook loaded"
            return
        }
        guard let json = try? JSONEncoder().encode(schedule),
              let jsonString = String(data: json, encoding: .utf8) else {
            loadError = "Failed to encode panel schedule"
            return
        }

        do {
            if let existingEntryId = findPanelScheduleEntryId() {
                // Update existing panel schedule entry
                try service.updateBlockEntry(
                    entryId: existingEntryId,
                    content: nil,
                    blockData: jsonString,
                    updatedBy: userId
                )
            } else {
                // Create new panel_schedule block entry in the first available section
                guard let sectionId = try findOrCreateDefaultSectionId(service: service, notebookId: notebookId) else {
                    loadError = "No section available for panel schedule"
                    return
                }
                _ = try service.createBlockEntry(
                    sectionId: sectionId,
                    blockType: "panel_schedule",
                    title: "Panel Schedule",
                    content: nil,
                    blockData: jsonString,
                    createdBy: userId
                )
            }
            // Reload to reflect saved state
            loadData()
        } catch {
            loadError = userFriendlyError(error, context: "save panel schedule")
        }
    }

    /// Find the first available section ID, or create a default section if none exist.
    private func findOrCreateDefaultSectionId(service: NotebooksService, notebookId: Int64) throws -> Int64? {
        // Check grouped sections first
        if let sectionId = hierarchy?.groups.first?.sections.first?.id {
            return sectionId
        }
        // Check ungrouped sections
        if let sectionId = hierarchy?.ungroupedSections.first?.id {
            return sectionId
        }
        // No sections exist — create a default one (throws on failure so caller can surface the error)
        return try service.createSection(notebookId: notebookId, groupId: nil, name: "General")
    }

    /// Print config persists app-wide (spec: set once, reused for every
    /// schedule) as JSON in AppStorage.
    private var panelPrintConfigBinding: Binding<PanelPrintConfig> {
        Binding(
            get: {
                guard let data = panelPrintConfigJSON.data(using: .utf8),
                      let config = try? JSONDecoder().decode(PanelPrintConfig.self, from: data) else {
                    return PanelPrintConfig()
                }
                return config
            },
            set: { newValue in
                if let data = try? JSONEncoder().encode(newValue),
                   let json = String(data: data, encoding: .utf8) {
                    panelPrintConfigJSON = json
                }
            }
        )
    }

    /// Loads the redesigned panel state from its own block entry; when absent
    /// but a legacy schedule exists, seeds it via the migration helper (the
    /// legacy entry stays untouched until the user saves here).
    private func loadDesignPanelState() {
        if let entryId = findDesignPanelEntryId(),
           let entry = blockEntry(withId: entryId),
           let data = entry.blockData?.data(using: .utf8),
           let state = try? JSONDecoder().decode(DesignPanelState.self, from: data) {
            designPanelState = state
        } else if !panelSchedule.circuits.isEmpty {
            designPanelState = .migrated(fromLegacy: panelSchedule)
        }
    }

    private func persistDesignPanelState() {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id,
              let notebookId = notebook?.id,
              let json = try? JSONEncoder().encode(designPanelState),
              let jsonString = String(data: json, encoding: .utf8) else { return }
        do {
            if let existingEntryId = findDesignPanelEntryId() {
                try service.updateBlockEntry(
                    entryId: existingEntryId,
                    content: nil,
                    blockData: jsonString,
                    updatedBy: userId
                )
            } else {
                guard let sectionId = try findOrCreateDefaultSectionId(service: service, notebookId: notebookId) else { return }
                _ = try service.createBlockEntry(
                    sectionId: sectionId,
                    blockType: "panel_design_state",
                    title: "Panel Schedule (Redesign)",
                    content: nil,
                    blockData: jsonString,
                    createdBy: userId
                )
            }
        } catch {
            loadError = userFriendlyError(error, context: "save panel design")
        }
    }

    private func findDesignPanelEntryId() -> Int64? {
        findEntryId(blockType: "panel_design_state")
    }

    private func blockEntry(withId id: Int64) -> NotebooksService.NotebookEntryRow? {
        for group in hierarchy?.groups ?? [] {
            for section in group.sections {
                if let entry = section.entries.first(where: { $0.id == id }) { return entry }
            }
        }
        for section in hierarchy?.ungroupedSections ?? [] {
            if let entry = section.entries.first(where: { $0.id == id }) { return entry }
        }
        return nil
    }

    private func findEntryId(blockType: String) -> Int64? {
        for group in hierarchy?.groups ?? [] {
            for section in group.sections {
                for entry in section.entries where entry.blockType == blockType {
                    return entry.id
                }
            }
        }
        for section in hierarchy?.ungroupedSections ?? [] {
            for entry in section.entries where entry.blockType == blockType {
                return entry.id
            }
        }
        return nil
    }

    private func findPanelScheduleEntryId() -> Int64? {
        if let groups = hierarchy?.groups {
            for group in groups {
                for section in group.sections {
                    for entry in section.entries where entry.blockType == "panel_schedule" {
                        return entry.id
                    }
                }
            }
        }
        if let ungrouped = hierarchy?.ungroupedSections {
            for section in ungrouped {
                for entry in section.entries where entry.blockType == "panel_schedule" {
                    return entry.id
                }
            }
        }
        return nil
    }

    private func createSectionGroup(name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            _ = try service.createSectionGroup(notebookId: notebookId, name: name)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func createSection(groupId: Int64?, name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            _ = try service.createSection(notebookId: notebookId, groupId: groupId, name: name)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func renameSectionGroup(groupId: Int64, name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.updateSectionGroup(groupId: groupId, name: name)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func renameSection(sectionId: Int64, name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.updateSection(sectionId: sectionId, name: name)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func deleteSectionGroup(_ groupId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.deleteSectionGroup(groupId: groupId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func deleteSection(_ sectionId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.deleteSection(sectionId: sectionId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func deleteEntry(_ entryId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.deleteBlockEntry(entryId: entryId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func activeLock(for entryId: Int64) -> NotebookEntryEditLock? {
        activeEditLocks.first { $0.entryId == entryId }
    }

    private func beginEditing(_ entry: NotebooksService.NotebookEntryRow) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in. Please log in and try again."
            return
        }
        do {
            _ = try service.acquireBlockEditLock(entryId: entry.id, userId: userId)
            activeEditLockEntryId = entry.id
            activeSheet = .editEntry(entry)
            activeEditLocks = (try? service.activeBlockEditLocks(notebookId: notebookId)) ?? activeEditLocks
        } catch {
            actionError = userFriendlyError(error, context: "start editing")
            activeEditLockEntryId = entry.id
            activeSheet = .editEntry(entry)
        }
    }

    private func releaseEditLock(entryId: Int64) {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else { return }
        try? service.releaseBlockEditLock(entryId: entryId, userId: userId)
    }

    // MARK: - Conflict Resolution (62J)

    private func resolveConflict(conflictLogId: Int64, keepVersion: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.resolveBlockConflict(conflictLogId: conflictLogId, keepVersion: keepVersion)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func resolveAllConflicts(keepVersion: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.resolveAllBlockConflicts(notebookId: notebookId, keepVersion: keepVersion)
            activeSheet = nil
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func mergeConflictWithAI(conflictLogId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        Task {
            do {
                let merged = try await service.resolveBlockConflictWithFoundationModels(conflictLogId: conflictLogId)
                if !merged {
                    actionError = "AI merge unavailable. Both versions were preserved for manual resolution."
                }
                loadData()
            } catch {
                actionError = userFriendlyError(error, context: "merge conflict")
            }
        }
    }
}

// MARK: - NotebookConflictResolutionSheet (62J)

/// Sheet that displays notebook block conflicts side-by-side and lets the user
/// choose which version to keep for each conflict, or bulk-resolve all at once.
private struct NotebookConflictResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let conflicts: [NotebookBlockConflict]
    let onResolve: (Int64, String) -> Void      // (conflictLogId, "local" | "remote")
    let onAIMerge: (Int64) -> Void
    let onResolveAll: (String) -> Void           // "local" | "remote"

    var body: some View {
        NavigationStack {
            List {
                // Bulk actions
                Section {
                    HStack(spacing: 12) {
                        Button {
                            onResolveAll("local")
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "iphone")
                                Text("Keep All Local")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)

                        Button {
                            onResolveAll("remote")
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Keep All Remote")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                    }
                } header: {
                    Text("Bulk Actions")
                } footer: {
                    Text("Resolve all \(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s") at once, or review each one individually below.")
                }

                // Individual conflicts
                ForEach(conflicts) { conflict in
                    Section {
                        // Entry context
                        HStack(spacing: 8) {
                            Image(systemName: blockTypeIcon(conflict.blockType ?? "text"))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conflict.entryTitle ?? "Entry #\(conflict.entryId)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Field: \(conflict.fieldName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            // Show which version LWW auto-picked
                            Text("Auto: \(conflict.winner)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(conflict.winner == "local" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                                .foregroundStyle(conflict.winner == "local" ? .blue : .purple)
                                .clipShape(Capsule())
                        }

                        // Side-by-side comparison
                        VStack(spacing: 12) {
                            // Local version
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "iphone")
                                        .font(.caption)
                                        .accessibilityHidden(true)
                                    Text("Local (This Device)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(formatTimestamp(conflict.localTimestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(.blue)

                                Text(conflict.localValue ?? "(empty)")
                                    .font(.caption)
                                    .foregroundStyle(conflict.localValue == nil ? .tertiary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .lineLimit(6)
                            }

                            // Remote version
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.caption)
                                        .accessibilityHidden(true)
                                    Text("Remote (Other Device)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(formatTimestamp(conflict.remoteTimestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(.purple)

                                Text(conflict.remoteValue ?? "(empty)")
                                    .font(.caption)
                                    .foregroundStyle(conflict.remoteValue == nil ? .tertiary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.purple.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .lineLimit(6)
                            }
                        }

                        // Resolution buttons
                        HStack(spacing: 8) {
                            Button {
                                onResolve(conflict.conflictLogId, "local")
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("Keep Local")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.small)

                            Button {
                                onAIMerge(conflict.conflictLogId)
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("AI Merge")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!["title", "content", "block_data", "checklist_items"].contains(conflict.fieldName))

                            Button {
                                onResolve(conflict.conflictLogId, "remote")
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("Keep Remote")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Resolve Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func blockTypeIcon(_ type: String) -> String {
        switch type {
        case "heading": return "textformat.size"
        case "checklist": return "checklist"
        case "photo": return "photo"
        case "part_reference": return "shippingbox"
        case "panel_schedule": return "bolt"
        case "divider": return "minus"
        case "callout": return "exclamationmark.bubble"
        case "quote": return "quote.opening"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "table": return "tablecells"
        case "todo": return "circle"
        default: return "text.alignleft"
        }
    }

    private func formatTimestamp(_ ts: String) -> String {
        // Show just date + time, trimming ISO 8601 cruft
        let cleaned = ts.replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "Z", with: "")
        // Take first 19 chars: "YYYY-MM-DD HH:MM:SS"
        return String(cleaned.prefix(19))
    }
}

// MARK: - NameInputSheet

/// Simple sheet for entering a name (group or section).
private struct NameInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    var initialValue: String = ""
    let onSave: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $name)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = initialValue
            }
        }
    }
}
