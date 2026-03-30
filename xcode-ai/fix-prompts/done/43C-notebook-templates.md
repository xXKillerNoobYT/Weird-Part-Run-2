# 43C — Notebook Templates

> **Chain position:** 43A → 43B → **43C**
> **Prerequisite:** 43A (structure migration)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSNotebookTemplatesPage.swift`, `CreateNotebookSheet.swift`, and `NotebooksService.swift`. Add job starter templates and page templates that create pre-built notebook structures.

## Context

Every new job needs a notebook with a standard structure (safety section, materials section, daily log section, etc.). Templates automate this — "New Residential Job" creates a full notebook with 5 section groups, 15 sections, and starter pages. Page templates provide pre-built layouts for common content (safety checklist, material list, etc.). Office users manage templates.

## Task

### Step 1: Migration — Notebook Templates

```sql
CREATE TABLE notebook_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    template_type TEXT NOT NULL DEFAULT 'job',  -- 'job' (full notebook), 'page' (single page layout)
    category TEXT,  -- 'residential', 'commercial', 'service', 'general'
    template_data TEXT NOT NULL,  -- JSON structure defining groups/sections/entries
    is_default INTEGER NOT NULL DEFAULT 0,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Step 2: Template Data JSON Structure

```swift
struct NotebookTemplateData: Codable, Sendable {
    let groups: [TemplateGroup]

    struct TemplateGroup: Codable, Sendable {
        let name: String
        let sections: [TemplateSection]
    }

    struct TemplateSection: Codable, Sendable {
        let name: String
        let entries: [TemplateEntry]
    }

    struct TemplateEntry: Codable, Sendable {
        let blockType: String
        let title: String?
        let content: String?
        let headingLevel: Int?
        let checklistItems: [ChecklistItem]?
    }
}
```

### Step 3: Service Methods

```swift
// MARK: - Templates

/// Create a notebook template
func createTemplate(name: String, description: String?, templateType: String, category: String?, templateData: NotebookTemplateData, createdBy: Int64) async throws -> NotebookTemplate

/// Get all templates
func getTemplates(templateType: String?) async throws -> [NotebookTemplate]

/// Apply job template — creates full notebook with groups/sections/entries
func applyJobTemplate(templateId: Int64, notebookId: Int64) async throws

/// Apply page template — creates entries in a section
func applyPageTemplate(templateId: Int64, sectionId: Int64) async throws

/// Delete template (soft)
func deleteTemplate(templateId: Int64) async throws

/// Seed default templates
func seedDefaultTemplates() async throws
```

### Step 4: Default Templates to Seed

```swift
// Residential Job Template
let residentialTemplate = NotebookTemplateData(groups: [
    .init(name: "Safety & Compliance", sections: [
        .init(name: "Safety Checklist", entries: [
            .init(blockType: "heading", title: "Pre-Work Safety", headingLevel: 1, content: nil, checklistItems: nil),
            .init(blockType: "checklist", title: nil, content: nil, headingLevel: nil, checklistItems: [
                .init(text: "PPE verified", checked: false),
                .init(text: "Area secured", checked: false),
                .init(text: "Permits posted", checked: false),
            ])
        ]),
    ]),
    .init(name: "Materials & Parts", sections: [
        .init(name: "Material List", entries: []),
        .init(name: "Parts Used", entries: []),
    ]),
    .init(name: "Daily Log", sections: []),
    .init(name: "Photos", sections: [
        .init(name: "Progress Photos", entries: []),
        .init(name: "Issue Photos", entries: []),
    ]),
    .init(name: "Punch List", sections: []),
])
```

### Step 5: Update IOSNotebookTemplatesPage.swift

```swift
// Show available templates with categories
// Each template card shows: name, description, category badge, section count
// "Create from Template" button opens CreateNotebookSheet with template pre-selected

List {
    ForEach(groupedTemplates.keys.sorted(), id: \.self) { category in
        Section {
            ForEach(groupedTemplates[category] ?? []) { template in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(template.name).font(.headline)
                        Spacer()
                        Text(template.templateType.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if let desc = template.description {
                        Text(desc).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Use") { createFromTemplate(template) }
                        .tint(.blue)
                    Button(role: .destructive) { deleteTemplate(template) } label: {
                        Text("Delete")
                    }
                }
            }
        } header: {
            Text(category?.capitalized ?? "General")
        }
    }
}
```

### Step 6: Update CreateNotebookSheet.swift

Add template selection to the notebook creation flow:

```swift
// Template picker (optional)
Section {
    Picker("Start from Template", selection: $selectedTemplateId) {
        Text("Blank Notebook").tag(nil as Int64?)
        ForEach(jobTemplates) { template in
            Text(template.name).tag(template.id as Int64?)
        }
    }
} header: {
    Text("Template")
} footer: {
    Text("Templates create pre-built sections and pages for you")
}

// After creating the notebook, apply template if selected:
// if let templateId = selectedTemplateId {
//     try await service.applyJobTemplate(templateId: templateId, notebookId: newNotebook.id!)
// }
```

### Step 7: Template Editor (Office Section)

A simple template editor for Office users:
- List all templates with edit/delete
- Create new template by capturing current notebook structure as template
- "Save as Template" action on any notebook

### Step 8: Update ConflictResolver

Add `notebook_templates` to the whitelist.

## Important Notes
- Job templates create the FULL hierarchy (groups → sections → starter entries)
- Page templates create entries within an existing section
- Template data is JSON — flexible and easy to version
- Default templates should be seeded on first run (or migration)
- "Save as Template" captures the current notebook structure as a new template
- Templates are NOT synced per-device — they're shared company data

## Success Criteria
- [ ] Migration creates notebook_templates table
- [ ] NotebookTemplateData model with codable structure
- [ ] 5+ service methods for template CRUD and application
- [ ] Default residential template seeded
- [ ] IOSNotebookTemplatesPage shows templates by category
- [ ] "Create from Template" action works
- [ ] CreateNotebookSheet has template picker
- [ ] Template editor for Office users
- [ ] ConflictResolver updated
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 43C Results (YYYY-MM-DD)
- Migration: notebook_templates table
- Service: X template methods
- Default template seeded
- Templates page + create sheet updated
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 43D.**
