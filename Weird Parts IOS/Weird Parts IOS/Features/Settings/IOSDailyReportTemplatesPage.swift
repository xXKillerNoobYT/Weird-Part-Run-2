import SwiftUI
import WiredPartCore

/// Daily report section template editor.
///
/// Manages which sections appear in daily reports and in what order.
/// Configuration stored as JSON in `daily_report_template` setting key.
struct IOSDailyReportTemplatesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Types

    struct ReportSection: Identifiable, Codable, Equatable {
        var id: String
        var name: String
        var enabled: Bool
        var locked: Bool  // Cannot be disabled

        init(id: String, name: String, enabled: Bool, locked: Bool = false) {
            self.id = id
            self.name = name
            self.enabled = enabled
            self.locked = locked
        }
    }

    struct DailyReportTemplate: Codable, Equatable {
        var sections: [ReportSection]
        var aiInstructions: String
    }

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var successMessage: String?
    @State private var isDirty = false
    @State private var hasLoadedSettings = false
    @State private var showDiscardConfirmation = false

    private enum ActiveSheet: Identifiable {
        case help
        case preview
        var id: String {
            switch self {
            case .help: return "help"
            case .preview: return "preview"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    @State private var sections: [ReportSection] = []
    @State private var aiInstructions: String = ""

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading template...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView("Unable to Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                templateEditor
            }
        }
        .navigationTitle("Daily Report Templates")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiscardConfirmation = true
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                NavigationStack {
                    List {
                        Section("About Daily Reports") {
                            Text("Configure which sections appear in daily reports and in what order. Mandatory sections (Hours Summary, Jobs Worked) cannot be disabled.")
                        }
                        Section("AI Summary") {
                            Text("The AI summary is generated at the end of the report. Customize the instructions to control what the AI focuses on.")
                        }
                    }
                    .navigationTitle("Template Help")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
                }
            case .preview:
                NavigationStack {
                    previewView
                        .navigationTitle("Report Preview")
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
                }
            }
        }
        .refreshable { loadSettings() }
        .task { loadSettings() }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: - Editor

    private var templateEditor: some View {
        Form {
            // Fix #244: show save success feedback (was silent before)
            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Sections
            Section {
                ForEach($sections) { $section in
                    HStack {
                        if section.locked {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .accessibilityLabel("Status: Locked")
                        }
                        Toggle(section.name, isOn: $section.enabled)
                            .disabled(section.locked)
                    }
                }
                .onMove { from, to in
                    sections.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Label("Report Sections", systemImage: "list.bullet")
            } footer: {
                Text("Long-press and drag to reorder sections. Locked sections cannot be disabled.")
            }

            // AI Instructions
            Section {
                TextField("Summarize the day's work...", text: $aiInstructions, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Label("AI Summary Instructions", systemImage: "cpu")
            } footer: {
                Text("These instructions guide the AI when generating the end-of-day summary.")
            }

            // Preview
            Section {
                Button { activeSheet = .preview } label: {
                    Label("Preview Report", systemImage: "eye")
                }
            }

            // Save
            Section {
                Button { saveSettings() } label: {
                    Label("Save Template", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        // Fix #149: dismiss keyboard when scrolling template editor
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: sections) { _, _ in markDirty() }
        .onChange(of: aiInstructions) { _, _ in markDirty() }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewView: some View {
        // Fix #147: empty state when the user has disabled all sections,
        // so the preview doesn't render an empty list with no explanation.
        let enabledSections = sections.filter(\.enabled)
        if enabledSections.isEmpty {
            ContentUnavailableView(
                "No Sections Enabled",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Enable at least one section in the template editor to preview it here.")
            )
        } else {
        List {
            ForEach(enabledSections) { section in
                Section {
                    previewContent(for: section.id)
                } header: {
                    Text(section.name)
                }
            }
        }
        }   // close `else` branch from #147 empty-state guard
    }

    @ViewBuilder
    private func previewContent(for sectionId: String) -> some View {
        switch sectionId {
        case "hours_summary":
            LabeledContent("Total Hours", value: "8.5")
            LabeledContent("Regular", value: "8.0")
            LabeledContent("Overtime", value: "0.5")
        case "jobs_worked":
            LabeledContent("Smith Residence", value: "4.0 hrs")
            LabeledContent("Johnson Office", value: "4.5 hrs")
        case "todo_progress":
            LabeledContent("Completed", value: "5 / 8")
            LabeledContent("Carry Forward", value: "3")
        case "safety_notes":
            Text("No safety incidents reported.")
                .foregroundStyle(.secondary)
        case "weather":
            LabeledContent("Conditions", value: "Clear, 72F")
        case "equipment":
            Text("Drill press, table saw")
                .foregroundStyle(.secondary)
        case "materials":
            LabeledContent("Parts used", value: "12 items")
            LabeledContent("Estimated cost", value: "$347.50")
        case "photos":
            Text("3 photos attached")
                .foregroundStyle(.secondary)
        case "worker_notes":
            Text("Finished framing, ready for inspection tomorrow.")
                .foregroundStyle(.secondary)
        case "ai_summary":
            Text("Productive day across two jobs. Smith Residence framing completed ahead of schedule. Johnson Office HVAC rough-in on track. 3 carry-forward items for tomorrow.")
                .font(.callout)
                .italic()
        default:
            Text("(preview)")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        hasLoadedSettings = false
        do {
            if let json = try service.getSettingValue("daily_report_template"),
               let data = json.data(using: .utf8) {
                let template = try JSONDecoder().decode(DailyReportTemplate.self, from: data)
                sections = template.sections
                aiInstructions = template.aiInstructions
            } else {
                sections = Self.defaultSections
                aiInstructions = Self.defaultAIInstructions
            }
        } catch {
            sections = Self.defaultSections
            aiInstructions = Self.defaultAIInstructions
        }
        isLoading = false
        isDirty = false
        Task { @MainActor in
            hasLoadedSettings = true
        }
    }

    private func markDirty() {
        guard hasLoadedSettings else { return }
        isDirty = true
    }

    private func saveSettings() {
        successMessage = nil
        guard let service = appCore.settingsService else {
            saveError = "Settings service unavailable"
            return
        }

        do {
            let template = DailyReportTemplate(sections: sections, aiInstructions: aiInstructions)
            let data = try JSONEncoder().encode(template)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            try service.upsertSetting(key: "daily_report_template", value: json, category: "templates")
            saveError = nil
            successMessage = "Template saved."
            isDirty = false
        } catch {
            saveError = userFriendlyError(error, context: "save daily report")
        }
    }

    // MARK: - Defaults

    static let defaultAIInstructions = "Summarize today's work concisely. Highlight completed tasks, any issues encountered, and work planned for tomorrow."

    static let defaultSections: [ReportSection] = [
        ReportSection(id: "hours_summary", name: "Hours Summary", enabled: true, locked: true),
        ReportSection(id: "jobs_worked", name: "Jobs Worked", enabled: true, locked: true),
        ReportSection(id: "todo_progress", name: "To-Do Progress", enabled: true),
        ReportSection(id: "safety_notes", name: "Safety Notes", enabled: false),
        ReportSection(id: "weather", name: "Weather Conditions", enabled: false),
        ReportSection(id: "equipment", name: "Equipment Used", enabled: false),
        ReportSection(id: "materials", name: "Materials Used", enabled: true),
        ReportSection(id: "photos", name: "Photos", enabled: true),
        ReportSection(id: "worker_notes", name: "Worker Notes", enabled: true),
        ReportSection(id: "ai_summary", name: "AI Summary", enabled: true),
    ]
}
