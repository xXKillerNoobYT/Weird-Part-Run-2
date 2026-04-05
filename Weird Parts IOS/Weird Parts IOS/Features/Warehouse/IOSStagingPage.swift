import SwiftUI
import WiredPartCore

/// Pulled items staging area page for iOS.
///
/// Displays parts that have been pulled from warehouse stock and tagged
/// for specific jobs or destinations. Shows part name, quantity, destination,
/// and the person who tagged them.
///
/// Now also includes **physical box management** — creating labeled boxes,
/// marking them full (auto-creates next box), and tracking box contents.
///
/// Features swipe-to-load with confirmation, batch selection mode,
/// smart card filters by destination type, box management, and pull-to-refresh.
struct IOSStagingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var stagedItems: [WarehouseService.StagedItem] = []
    @State private var stagingBoxes: [WarehouseService.StagingBox] = []
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?

    // Confirmation
    @State private var itemToLoad: WarehouseService.StagedItem?
    @State private var showLoadConfirm = false

    // Batch selection
    @State private var selectedItems: Set<Int64> = []
    @State private var isSelecting = false
    @State private var showBatchConfirm = false

    // Box delete confirmation
    @State private var boxToDeleteId: Int64?
    @State private var showBoxDeleteConfirm = false

    // Smart card filter
    @State private var selectedFilter: DestinationFilter?

    // Sheet management
    private enum ActiveSheet: Identifiable {
        case createBox
        case help
        var id: String {
            switch self {
            case .createBox: return "createBox"
            case .help: return "help"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    // Box creation
    @State private var newBoxJobId: Int64?
    @State private var newBoxSize: String = "normal"

    // Active view tab
    @State private var activeTab: StagingTab = .items

    private enum StagingTab: String, CaseIterable {
        case items = "Staged Items"
        case boxes = "Boxes"
    }

    private enum DestinationFilter: String, CaseIterable {
        case job = "Jobs"
        case truck = "Trucks"
        case trailer = "Trailers"
        case other = "Other"

        var matchTypes: [String] {
            switch self {
            case .job: ["job"]
            case .truck: ["truck"]
            case .trailer: ["trailer"]
            case .other: ["warehouse", "staging", "pulled", ""]
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-staging")

            // Tab picker
            Picker("View", selection: $activeTab) {
                ForEach(StagingTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch activeTab {
            case .items:
                itemsContent
            case .boxes:
                boxesContent
            }
        }
        .navigationTitle("Staging Area")
        .searchable(text: $searchText, prompt: activeTab == .items ? "Search staged parts..." : "Search boxes...")
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if activeTab == .items {
                    itemsToolbar
                } else {
                    Button {
                        activeSheet = .createBox
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create box")
                }
            }
        }
        .alert("Mark as Loaded?", isPresented: $showLoadConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Confirm Loaded") {
                if let item = itemToLoad {
                    clearItem(id: item.id)
                }
            }
        } message: {
            Text("This will clear \(itemToLoad?.partName ?? "this item") from staging. It will be marked as loaded onto the truck/vehicle.")
        }
        .alert("Clear \(selectedItems.count) Items?", isPresented: $showBatchConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All Selected", role: .destructive) {
                clearSelectedItems()
            }
        } message: {
            Text("This will mark \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s") as loaded and remove them from staging.")
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Delete Box?", isPresented: $showBoxDeleteConfirm) {
            Button("Cancel", role: .cancel) { boxToDeleteId = nil }
            Button("Delete", role: .destructive) {
                if let id = boxToDeleteId {
                    deleteBox(boxId: id)
                }
                boxToDeleteId = nil
            }
        } message: {
            Text("This will permanently delete this staging box and all its contents.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createBox:
                createBoxSheet
            case .help:
                PageHelpSheet(
                    title: "Staging Area Help",
                    sections: [
                        ("Overview", "The staging area holds parts that have been pulled from warehouse stock and tagged for specific jobs or destinations."),
                        ("Boxes", "Switch to the Boxes tab to manage physical staging boxes. Mark a box as full to auto-create the next one."),
                        ("Loading", "Swipe an item or use batch selection to confirm items are loaded onto a truck or delivered to a job site.")
                    ]
                )
            }
        }
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("wh-staging-view")
        }
    }

    // MARK: - Items Tab Toolbar

    @ViewBuilder
    private var itemsToolbar: some View {
        if isSelecting {
            Button("Clear \(selectedItems.count)", role: .destructive) {
                showBatchConfirm = true
            }
            .disabled(selectedItems.isEmpty)

            Button("Cancel") {
                isSelecting = false
                selectedItems.removeAll()
            }
        } else if !stagedItems.isEmpty {
            Button {
                isSelecting = true
            } label: {
                Image(systemName: "checklist")
            }
            .accessibilityLabel("Select items")
        }
    }

    // MARK: - Items Content

    @ViewBuilder
    private var itemsContent: some View {
        // Smart card filters
        if !stagedItems.isEmpty {
            smartCardFilters
        }

        stagingList
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DestinationFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countForFilter(_ filter: DestinationFilter) -> Int {
        stagedItems.filter { item in
            let destType = item.destinationType ?? ""
            return filter.matchTypes.contains(destType)
        }.count
    }

    private func smartCard(filter: DestinationFilter, count: Int) -> some View {
        let isSelected = selectedFilter == filter
        let color = filterColor(filter)

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: filterIcon(filter))
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 80)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    private func filterIcon(_ filter: DestinationFilter) -> String {
        switch filter {
        case .job: "hammer.fill"
        case .truck: "truck.box.fill"
        case .trailer: "truck.box.badge.clock.fill"
        case .other: "tray.full.fill"
        }
    }

    private func filterColor(_ filter: DestinationFilter) -> Color {
        switch filter {
        case .job: .purple
        case .truck: .green
        case .trailer: .orange
        case .other: .blue
        }
    }

    // MARK: - Staging List

    @ViewBuilder
    private var stagingList: some View {
        if isLoading {
            ProgressView("Loading staged items...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredItems.isEmpty {
            if searchText.isEmpty && selectedFilter == nil {
                EmptyStateView(
                    icon: "tray",
                    title: "No Staged Items",
                    message: "No parts are currently staged for pickup. Use the Movement Wizard to pull parts from warehouse stock."
                )
            } else {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No staged items match your current filters."
                )
            }
        } else {
            List {
                Section {
                    Text("\(filteredItems.count) item\(filteredItems.count == 1 ? "" : "s") staged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredItems, id: \.id) { item in
                    HStack(spacing: 0) {
                        if isSelecting {
                            Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedItems.contains(item.id) ? .green : .secondary)
                                .font(.title3)
                                .accessibilityLabel(selectedItems.contains(item.id) ? "Selected" : "Not selected")
                                .padding(.trailing, 10)
                                .onTapGesture {
                                    toggleSelection(item.id)
                                }
                        }

                        stagedRow(item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            itemToLoad = item
                            showLoadConfirm = true
                        } label: {
                            Label("Loaded", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredItems: [WarehouseService.StagedItem] {
        var result = stagedItems

        // Destination filter
        if let filter = selectedFilter {
            result = result.filter { item in
                let destType = item.destinationType ?? ""
                return filter.matchTypes.contains(destType)
            }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.partName.lowercased().contains(query) ||
                ($0.partCode?.lowercased().contains(query) ?? false) ||
                ($0.destinationLabel?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    private func stagedRow(_ item: WarehouseService.StagedItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.title3)
                .foregroundStyle(Color.orange)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.partName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let code = item.partCode, !code.isEmpty {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let dest = item.destinationLabel, !dest.isEmpty {
                    Label(dest, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else if let destType = item.destinationType {
                    Label(destType.capitalized, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("x\(item.qty)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let taggedBy = item.taggedByName {
                    Text(taggedBy)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let taggedAt = item.taggedAt {
                    Text(formatDate(taggedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Boxes Content

    @ViewBuilder
    private var boxesContent: some View {
        if isLoading {
            ProgressView("Loading boxes...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredBoxes.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "No Staging Boxes",
                message: "Create a box to start organizing pulled parts by job. Tap + to create one."
            )
        } else {
            List {
                ForEach(boxJobGroups, id: \.jobId) { group in
                    Section {
                        ForEach(group.boxes, id: \.id) { box in
                            boxRow(box)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        boxToDeleteId = box.id
                                        showBoxDeleteConfirm = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if box.isFull {
                                        Button {
                                            reopenBox(boxId: box.id)
                                        } label: {
                                            Label("Reopen", systemImage: "arrow.uturn.backward")
                                        }
                                        .tint(.orange)
                                    } else {
                                        Button {
                                            markFull(boxId: box.id)
                                        } label: {
                                            Label("Full", systemImage: "checkmark.circle")
                                        }
                                        .tint(.green)
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.purple)
                                .accessibilityHidden(true)
                            Text(group.jobLabel)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(group.boxes.count) box\(group.boxes.count == 1 ? "" : "es")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Boxes grouped by job for display.
    private struct BoxJobGroup {
        let jobId: Int64
        let jobLabel: String
        let boxes: [WarehouseService.StagingBox]
    }

    private var filteredBoxes: [WarehouseService.StagingBox] {
        guard !searchText.isEmpty else { return stagingBoxes }
        let query = searchText.lowercased()
        return stagingBoxes.filter {
            $0.labelText.lowercased().contains(query) ||
            $0.boxNumber.lowercased().contains(query) ||
            ($0.jobName?.lowercased().contains(query) ?? false) ||
            ($0.jobNumber?.lowercased().contains(query) ?? false)
        }
    }

    private var boxJobGroups: [BoxJobGroup] {
        let grouped = Dictionary(grouping: filteredBoxes) { $0.jobId }
        return grouped.map { (jobId, boxes) in
            let first = boxes.first
            let label = [first?.jobNumber, first?.jobName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " - ")
            return BoxJobGroup(
                jobId: jobId,
                jobLabel: label.isEmpty ? "Job #\(jobId)" : label,
                boxes: boxes.sorted { $0.boxNumber < $1.boxNumber }
            )
        }
        .sorted { $0.jobLabel < $1.jobLabel }
    }

    private func boxRow(_ box: WarehouseService.StagingBox) -> some View {
        HStack(spacing: 12) {
            // Status icon: checkmark for full, half-circle for open
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(box.isFull ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: box.isFull ? "checkmark.circle.fill" : "circle.bottomhalf.filled")
                    .font(.title3)
                    .foregroundStyle(box.isFull ? .green : .orange)
                    .accessibilityLabel(box.isFull ? "Status: Full" : "Status: Open")
            }

            VStack(alignment: .leading, spacing: 4) {
                // Label guidance — the text to write on the box
                Text(box.labelText)
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(box.isFull ? .secondary : .primary)

                HStack(spacing: 8) {
                    // Size badge
                    boxSizeBadge(box.boxSize)

                    Text(box.isFull ? "FULL" : "OPEN")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(box.isFull ? .green : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(box.isFull ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        )
                }

                if let created = box.createdAt {
                    Text("Created \(formatDate(created))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Quick full/open toggle
            Button {
                if box.isFull {
                    reopenBox(boxId: box.id)
                } else {
                    markFull(boxId: box.id)
                }
            } label: {
                Image(systemName: box.isFull ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(box.isFull ? .orange : .green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(box.isFull ? "Reopen box" : "Mark box full")
        }
        .padding(.vertical, 4)
        .opacity(box.isFull ? 0.7 : 1.0)
    }

    private func boxSizeBadge(_ size: String) -> some View {
        let icon: String
        let color: Color
        switch size {
        case "small":
            icon = "s.square.fill"
            color = .blue
        case "large":
            icon = "l.square.fill"
            color = .purple
        default:
            icon = "n.square.fill"
            color = .gray
        }
        return Label {
            Text(size.capitalized)
                .font(.caption2)
        } icon: {
            Image(systemName: icon)
                .font(.caption2)
        }
        .foregroundStyle(color)
    }

    // MARK: - Create Box Sheet

    private var createBoxSheet: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    if jobs.isEmpty {
                        Text("No active jobs found")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Job", selection: $newBoxJobId) {
                            Text("Select a job...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text("\(job.jobNumber) - \(job.jobName)")
                                    .tag(job.id as Int64?)
                            }
                        }
                    }
                }

                Section("Box Size") {
                    Picker("Size", selection: $newBoxSize) {
                        Label("Small", systemImage: "s.square.fill")
                            .tag("small")
                        Label("Normal", systemImage: "n.square.fill")
                            .tag("normal")
                        Label("Large", systemImage: "l.square.fill")
                            .tag("large")
                    }
                    .pickerStyle(.segmented)
                }

                if let jobId = newBoxJobId,
                   let job = jobs.first(where: { $0.id == jobId }) {
                    Section("Label Preview") {
                        let existingCount = stagingBoxes.filter { $0.jobId == jobId }.count
                        let seqStr = String(format: "%02d", existingCount + 1)
                        let boxNum = "\(job.jobNumber)-\(seqStr)"
                        let shortName = buildShortLabel(jobName: job.jobName)
                        let preview = "\(shortName) \(boxNum)"

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Write this on the box:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(preview)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.yellow.opacity(0.15))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                                                .foregroundStyle(.orange)
                                        )
                                )

                            Text("Size: \(newBoxSize.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Staging Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        activeSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createBox()
                    }
                    .disabled(newBoxJobId == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    private func toggleSelection(_ id: Int64) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    /// Build a short label from a job name (mirrors service logic for preview).
    private func buildShortLabel(jobName: String) -> String {
        let words = jobName.split(separator: " ")
        guard !words.isEmpty else { return "JOB" }

        var label = ""
        for word in words {
            let candidate = label.isEmpty ? String(word) : "\(label) \(word)"
            if candidate.count > 15 {
                if label.isEmpty {
                    label = String(word.prefix(12))
                }
                break
            }
            label = candidate
        }
        return label.uppercased()
    }

    // MARK: - Actions

    private func clearItem(id: Int64) {
        guard let service = appCore.warehouseService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.clearStagingTag(id: id)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "update staging")
        }
    }

    private func clearSelectedItems() {
        guard let service = appCore.warehouseService else {
            actionError = "Service not available"
            return
        }
        var failCount = 0
        for itemId in selectedItems {
            do {
                try service.clearStagingTag(id: itemId)
            } catch {
                failCount += 1
            }
        }
        selectedItems.removeAll()
        isSelecting = false
        loadData()
        if failCount > 0 {
            actionError = "\(failCount) item\(failCount == 1 ? "" : "s") failed to clear."
        }
    }

    private func createBox() {
        guard let service = appCore.warehouseService,
              let jobId = newBoxJobId else {
            loadError = "Warehouse service not available"
            return
        }
        do {
            _ = try service.createStagingBox(jobId: jobId, size: newBoxSize)
            activeSheet = nil
            newBoxJobId = nil
            newBoxSize = "normal"
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "update staging")
        }
    }

    private func markFull(boxId: Int64) {
        guard let service = appCore.warehouseService else {
            actionError = "Service not available"
            return
        }
        do {
            _ = try service.markBoxFull(boxId: boxId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "update staging")
        }
    }

    private func reopenBox(boxId: Int64) {
        guard let service = appCore.warehouseService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.markBoxOpen(boxId: boxId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "update staging")
        }
    }

    private func deleteBox(boxId: Int64) {
        guard let service = appCore.warehouseService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.deleteStagingBox(boxId: boxId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "update staging")
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = stagedItems.isEmpty && stagingBoxes.isEmpty
        loadError = nil
        do {
            stagedItems = try service.getStagedItems()
            stagingBoxes = try service.listStagingBoxes()
            if let jobsService = appCore.jobsService {
                jobs = try jobsService.listJobs(status: "active", limit: 200)
            }
        } catch {
            loadError = userFriendlyError(error, context: "load staging area")
        }
        isLoading = false
    }
}
