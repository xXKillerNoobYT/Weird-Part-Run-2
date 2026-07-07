import SwiftUI
import WiredPartCore

/// Settings UI for reusable job stage workflows.
///
/// Operators can create, duplicate, rename, archive, and edit the ordered stages
/// that power job progress bars and job create/edit workflow pickers.
struct IOSJobStageTemplatesSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var templates: [JobsService.JobStageTemplate] = []
    @State private var selectedTemplateId: Int64?
    @State private var draftStages: [StageDraft] = []
    @State private var loadedStages: [StageDraft] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @State private var newTemplateName = ""
    @State private var duplicateTemplateName = ""
    @State private var renameTemplateName = ""
    @State private var newStageName = ""

    @State private var showingCreateTemplate = false
    @State private var showingDuplicateTemplate = false
    @State private var showingRenameTemplate = false
    @State private var showingArchiveConfirmation = false
    @State private var showingCancelChangesConfirmation = false
    @State private var pendingStageDeleteOffsets: IndexSet?
    @State private var showingHelp = false

    private var selectedTemplate: JobsService.JobStageTemplate? {
        templates.first(where: { $0.id == selectedTemplateId })
    }

    private var trimmedNewTemplateName: String {
        newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRenameTemplateName: String {
        renameTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDuplicateTemplateName: String {
        duplicateTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreateTemplate: Bool { !trimmedNewTemplateName.isEmpty }
    private var canRenameTemplate: Bool { !trimmedRenameTemplateName.isEmpty }
    private var canDuplicateTemplate: Bool { !trimmedDuplicateTemplateName.isEmpty }

    private var hasUnsavedStageEdits: Bool { draftStages != loadedStages }

    private var pendingStageDeleteName: String {
        guard let first = pendingStageDeleteOffsets?.first,
              draftStages.indices.contains(first) else { return "stage" }
        let name = draftStages[first].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled stage" : name
    }

    private var archiveMessageSuffix: String {
        let stagePhrase = DestructiveConfirmationCopy.countPhrase(
            count: selectedTemplate?.stageCount ?? 0,
            noun: "stage"
        )
        return "Its \(stagePhrase) will no longer appear in job create/edit pickers. Templates with active jobs are protected."
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading job stage templates...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if templates.isEmpty {
                emptyState
            } else {
                settingsForm
            }
        }
        .navigationTitle("Job Stage Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-job-stage-templates-help-button")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { prepareCreateTemplate() } label: {
                    Label("New Template", systemImage: "plus")
                }
                .accessibilityHint("Creates a workflow template with three starter stages.")
                .accessibilityIdentifier("settings-job-stage-new-template-button")
            }
        }
        .sheet(isPresented: $showingHelp) {
            PageHelpSheet(title: "Job Stage Templates Help", sections: [
                ("What This Page Does", "Build reusable job workflows such as Rough-In → Trim → Final or longer custom templates. Jobs use the selected template for progress bars and stage routing."),
                ("Safe Editing", "Changes are staged locally until Save. Cancel reloads the template from the database. Stages in use by active jobs or order lines may be protected from archive."),
                ("Archiving", "Templates assigned to active jobs cannot be archived. Duplicate a live template first when you need to create a revised workflow.")
            ])
        }
        .alert("Create Template", isPresented: $showingCreateTemplate) {
            TextField("Template name", text: $newTemplateName)
                .textInputAutocapitalization(.words)
            Button("Create") { createTemplate() }
                .disabled(!canCreateTemplate)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(canCreateTemplate
                ? "Creates a workflow with three starter stages. Rename, add, remove, or reorder stages after it is created."
                : "Enter a template name before creating this workflow.")
        }
        .alert("Duplicate Template", isPresented: $showingDuplicateTemplate) {
            TextField("New template name", text: $duplicateTemplateName)
                .textInputAutocapitalization(.words)
            Button("Duplicate") { duplicateTemplate() }
                .disabled(!canDuplicateTemplate)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(canDuplicateTemplate
                ? "Creates a copy of the selected workflow using this new template name."
                : "Enter a new template name before duplicating this workflow.")
        }
        .alert("Rename Template", isPresented: $showingRenameTemplate) {
            TextField("Template name", text: $renameTemplateName)
                .textInputAutocapitalization(.words)
            Button("Rename") { renameTemplate() }
                .disabled(!canRenameTemplate)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(canRenameTemplate
                ? "Renames the selected workflow template. Existing jobs keep their current stage data."
                : "Enter a template name before renaming this workflow.")
        }
        .confirmDestruction(
            ofRecordNamed: selectedTemplate?.name ?? "template",
            noun: "workflow template",
            actionLabel: "Archive",
            actionVerb: "archives",
            isPresented: $showingArchiveConfirmation,
            messageSuffix: archiveMessageSuffix
        ) {
            archiveTemplate()
        }
        .confirmDestruction(
            ofRecordNamed: pendingStageDeleteName,
            noun: "stage",
            actionLabel: "Remove",
            isPresented: Binding(
                get: { pendingStageDeleteOffsets != nil },
                set: { if !$0 { pendingStageDeleteOffsets = nil } }
            ),
            messageSuffix: "Removal is applied when you save. Stages protected by live work remain after saving."
        ) {
            if let offsets = pendingStageDeleteOffsets {
                deleteStage(at: offsets)
            }
            pendingStageDeleteOffsets = nil
        }
        .confirmationDialog(
            "Discard Job Stage Templates changes?",
            isPresented: $showingCancelChangesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { reloadSelectedStages() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Unsaved stage edits will be lost.")
        }
        .task { loadTemplates() }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "list.bullet.rectangle.portrait",
            title: "No job stage templates",
            message: "Create a workflow template to power job progress bars and stage pickers.",
            actionLabel: "Create Template",
            actionIcon: "plus.circle.fill",
            action: { prepareCreateTemplate() }
        )
        .padding()
    }

    private var settingsForm: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            templatePickerSection
            stageEditorSection
            templateActionsSection
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var templatePickerSection: some View {
        Section {
            Picker("Template", selection: Binding(
                get: { selectedTemplateId ?? templates.first?.id ?? 0 },
                set: { templateId in
                    selectedTemplateId = templateId
                    loadStages(for: templateId)
                }
            )) {
                ForEach(templates) { template in
                    Text(template.name).tag(template.id)
                }
            }

            if let selectedTemplate {
                LabeledContent("Stages", value: "\(selectedTemplate.stageCount)")
                LabeledContent("Active jobs", value: "\(selectedTemplate.activeJobCount)")
                if selectedTemplate.isDefault {
                    Label("Default workflow", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Label("Workflow", systemImage: "rectangle.stack")
        }
    }

    private var stageEditorSection: some View {
        Section {
            if draftStages.isEmpty {
                Text("Add at least one stage before saving this template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($draftStages) { $stage in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Stage name", text: $stage.name)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel("Stage name")
                            .accessibilityIdentifier("settings-job-stage-name-\(stage.id)")
                    }
                    .contextMenu {
                        Button {
                            if let index = draftStages.firstIndex(where: { $0.id == stage.id }), index > 0 {
                                moveStage(from: IndexSet(integer: index), to: index - 1)
                            }
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .disabled(draftStages.first?.id == stage.id)

                        Button {
                            if let index = draftStages.firstIndex(where: { $0.id == stage.id }), index < draftStages.count - 1 {
                                moveStage(from: IndexSet(integer: index), to: index + 2)
                            }
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .disabled(draftStages.last?.id == stage.id)

                        Button(role: .destructive) {
                            if let index = draftStages.firstIndex(where: { $0.id == stage.id }) {
                                pendingStageDeleteOffsets = IndexSet(integer: index)
                            }
                        } label: {
                            Label("Remove Stage", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveStage)
                .onDelete { offsets in
                    pendingStageDeleteOffsets = offsets
                }
            }

            HStack {
                TextField("New stage name", text: $newStageName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("New stage name")
                    .accessibilityIdentifier("settings-job-stage-new-stage-field")
                Button { addDraftStage() } label: {
                    Image(systemName: "plus.circle.fill")
                        .dsMinTapTarget()
                }
                .disabled(newStageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add stage")
                .accessibilityHint("Appends the typed stage to the end of this workflow.")
                .accessibilityIdentifier("settings-job-stage-add-stage-button")
            }

            HStack {
                Button("Cancel Changes", role: .cancel) {
                    if hasUnsavedStageEdits {
                        showingCancelChangesConfirmation = true
                    } else {
                        reloadSelectedStages()
                    }
                }
                Spacer()
                Button { saveStages() } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Save Stages", systemImage: "checkmark.circle.fill")
                    }
                }
                .disabled(isSaving || selectedTemplateId == nil || draftStages.isEmpty)
                .accessibilityLabel("Save Stages")
                .accessibilityValue(isSaving ? "Saving" : "")
                .accessibilityIdentifier("settings-job-stage-save-stages-button")
            }
        } header: {
            Label("Stages", systemImage: "list.number")
        } footer: {
            Text("Drag stages to reorder. Swipe a stage to remove it; protected stages will remain if they are already referenced by live work.")
        }
    }

    private var templateActionsSection: some View {
        Section {
            Button { prepareRenameTemplate() } label: {
                Label("Rename Template", systemImage: "pencil")
            }
            .disabled(selectedTemplateId == nil)

            Button { prepareDuplicateTemplate() } label: {
                Label("Duplicate Template", systemImage: "plus.square.on.square")
            }
            .disabled(selectedTemplateId == nil)

            Button(role: .destructive) { showingArchiveConfirmation = true } label: {
                Label("Archive Template", systemImage: "archivebox")
            }
            .disabled(selectedTemplate?.isDefault == true || selectedTemplate == nil)
        } header: {
            Label("Template Actions", systemImage: "slider.horizontal.3")
        }
    }

    // MARK: - Loading

    private func loadTemplates(select templateId: Int64? = nil) {
        guard let service = appCore.jobsService else {
            errorMessage = "Jobs service unavailable"
            isLoading = false
            return
        }

        do {
            templates = try service.listJobStageTemplates()
            let nextSelection = templateId ?? selectedTemplateId ?? templates.first(where: { $0.isDefault })?.id ?? templates.first?.id
            selectedTemplateId = nextSelection
            if let nextSelection {
                loadStages(for: nextSelection)
            } else {
                draftStages = []
                loadedStages = []
            }
            isLoading = false
        } catch {
            errorMessage = userFriendlyError(error, context: "load job stage templates")
            isLoading = false
        }
    }

    private func loadStages(for templateId: Int64) {
        guard let service = appCore.jobsService else {
            errorMessage = "Jobs service unavailable"
            draftStages = []
            loadedStages = []
            return
        }
        do {
            draftStages = try service.listAllJobStages(templateId: templateId).map {
                StageDraft(existingId: $0.id, name: $0.name, sortOrder: $0.sortOrder)
            }
            loadedStages = draftStages
            errorMessage = nil
        } catch {
            errorMessage = userFriendlyError(error, context: "load template stages")
            draftStages = []
            loadedStages = []
        }
    }

    private func reloadSelectedStages() {
        guard let selectedTemplateId else { return }
        newStageName = ""
        loadStages(for: selectedTemplateId)
    }

    // MARK: - Template Actions

    private func prepareCreateTemplate() {
        newTemplateName = ""
        showingCreateTemplate = true
    }

    private func createTemplate() {
        guard let service = appCore.jobsService else {
            errorMessage = "Jobs service unavailable"
            return
        }
        guard canCreateTemplate else { return }
        let templateName = trimmedNewTemplateName
        do {
            let templateId = try service.createJobStageTemplate(
                name: templateName,
                stageNames: ["Rough-In", "Trim", "Final"]
            )
            successMessage = "Created \(templateName)."
            errorMessage = nil
            loadTemplates(select: templateId)
        } catch {
            errorMessage = userFriendlyError(error, context: "create job stage template")
        }
    }

    private func prepareRenameTemplate() {
        renameTemplateName = selectedTemplate?.name ?? ""
        showingRenameTemplate = true
    }

    private func renameTemplate() {
        guard let service = appCore.jobsService, let selectedTemplateId else { return }
        guard canRenameTemplate else { return }
        let templateName = trimmedRenameTemplateName
        do {
            try service.renameJobStageTemplate(templateId: selectedTemplateId, name: templateName)
            successMessage = "Renamed template."
            errorMessage = nil
            loadTemplates(select: selectedTemplateId)
        } catch {
            errorMessage = userFriendlyError(error, context: "rename job stage template")
        }
    }

    private func prepareDuplicateTemplate() {
        duplicateTemplateName = "Copy of \(selectedTemplate?.name ?? "Template")"
        showingDuplicateTemplate = true
    }

    private func duplicateTemplate() {
        guard let service = appCore.jobsService, let selectedTemplateId else { return }
        guard canDuplicateTemplate else { return }
        let templateName = trimmedDuplicateTemplateName
        do {
            let newId = try service.duplicateJobStageTemplate(templateId: selectedTemplateId, name: templateName)
            successMessage = "Duplicated template."
            errorMessage = nil
            loadTemplates(select: newId)
        } catch {
            errorMessage = userFriendlyError(error, context: "duplicate job stage template")
        }
    }

    private func archiveTemplate() {
        guard let service = appCore.jobsService, let selectedTemplateId else { return }
        do {
            try service.archiveJobStageTemplate(templateId: selectedTemplateId)
            successMessage = "Archived template."
            errorMessage = nil
            self.selectedTemplateId = nil
            loadTemplates()
        } catch {
            errorMessage = userFriendlyError(error, context: "archive job stage template")
        }
    }

    // MARK: - Stage Actions

    private func addDraftStage() {
        let trimmed = newStageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (draftStages.map(\.sortOrder).max() ?? 0) + 1
        draftStages.append(StageDraft(existingId: nil, name: trimmed, sortOrder: nextOrder))
        newStageName = ""
    }

    private func moveStage(from source: IndexSet, to destination: Int) {
        draftStages.move(fromOffsets: source, toOffset: destination)
        renumberDraftStages()
    }

    private func deleteStage(at offsets: IndexSet) {
        draftStages.remove(atOffsets: offsets)
        renumberDraftStages()
    }

    private func renumberDraftStages() {
        for index in draftStages.indices {
            draftStages[index].sortOrder = index + 1
        }
    }

    private func saveStages() {
        guard let service = appCore.jobsService, let selectedTemplateId else { return }
        let cleaned = draftStages.map { draft in
            StageDraft(
                existingId: draft.existingId,
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: draft.sortOrder
            )
        }
        guard cleaned.allSatisfy({ !$0.name.isEmpty }) else {
            errorMessage = "Every stage needs a name."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try service.applyJobStageTemplateDraft(
                templateId: selectedTemplateId,
                stages: cleaned.map { draft in
                    JobsService.JobStageTemplateDraftStage(existingId: draft.existingId, name: draft.name)
                }
            )
            successMessage = "Saved job stage workflow."
            errorMessage = nil
            loadTemplates(select: selectedTemplateId)
        } catch {
            errorMessage = userFriendlyError(error, context: "save job stage workflow")
        }
    }
}

private struct StageDraft: Identifiable, Equatable {
    let existingId: Int64?
    var name: String
    var sortOrder: Int
    private let localId = UUID()

    var id: String {
        if let existingId { return "existing-\(existingId)" }
        return "new-\(localId.uuidString)"
    }
}
