# 43B — Notebook Detail Page Rebuild

> **Chain position:** 43A → **43B** → 43C
> **Prerequisite:** 43A (structure migration)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets

## Instructions

**IMPORTANT:** Before implementing, read `IOSNotebookDetailPage.swift` and `AddNotebookEntrySheet.swift`. Then rebuild the detail page to show the section group → section → page hierarchy with block-based editing.

## Context

The current notebook detail page shows a flat list of entries. With the new hierarchy from 43A, it needs to display collapsible section groups containing sections containing pages. Each page has block-based content with shortcut commands for quick entry (/h1, /h2, /checklist, etc.). The two `showXxx` Bool states need to become an ActiveSheet enum.

## Task

### Step 1: Fix ActiveSheet Pattern

```swift
// BEFORE:
@State private var showAddEntry = false
@State private var showEditEntry = false

// AFTER:
private enum ActiveSheet: Identifiable {
    case addEntry(sectionId: Int64)
    case editEntry(NotebookEntry)
    case addSection(groupId: Int64?)
    case addGroup
    case editSection(NotebookSection)
    case editGroup(NotebookSectionGroup)

    var id: String {
        switch self {
        case .addEntry(let id): return "addEntry-\(id)"
        case .editEntry(let entry): return "editEntry-\(entry.id ?? 0)"
        case .addSection(let id): return "addSection-\(id ?? 0)"
        case .addGroup: return "addGroup"
        case .editSection(let s): return "editSection-\(s.id ?? 0)"
        case .editGroup(let g): return "editGroup-\(g.id ?? 0)"
        }
    }
}
@State private var activeSheet: ActiveSheet?
```

### Step 2: Hierarchical Layout

```swift
var body: some View {
    List {
        if let error = loadError {
            Section { Text(error).foregroundStyle(.red) }
        }

        // Section Groups (collapsible)
        ForEach(hierarchy.groups) { groupItem in
            Section {
                DisclosureGroup(isExpanded: binding(for: groupItem.group)) {
                    ForEach(groupItem.sections) { sectionItem in
                        sectionRow(sectionItem)
                    }
                    // Add section button
                    Button {
                        activeSheet = .addSection(groupId: groupItem.group.id)
                    } label: {
                        Label("Add Section", systemImage: "plus")
                            .font(.caption)
                    }
                } label: {
                    HStack {
                        Text(groupItem.group.name).font(.headline)
                        Spacer()
                        Text("\(groupItem.sections.count) sections")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        // Ungrouped sections
        if !hierarchy.ungroupedSections.isEmpty {
            Section {
                ForEach(hierarchy.ungroupedSections) { sectionItem in
                    sectionRow(sectionItem)
                }
            } header: {
                Text("Pages")
            }
        }

        // Add group/section buttons
        Section {
            Button { activeSheet = .addGroup } label: {
                Label("Add Section Group", systemImage: "folder.badge.plus")
            }
            Button { activeSheet = .addSection(groupId: nil) } label: {
                Label("Add Page", systemImage: "doc.badge.plus")
            }
        }
    }
}

func sectionRow(_ sectionItem: SectionWithEntries) -> some View {
    DisclosureGroup {
        ForEach(sectionItem.entries) { entry in
            entryRow(entry)
        }
        Button {
            activeSheet = .addEntry(sectionId: sectionItem.section.id!)
        } label: {
            Label("Add Block", systemImage: "plus.circle")
                .font(.caption)
        }
    } label: {
        HStack {
            Text(sectionItem.section.name).font(.subheadline)
            Spacer()
            Text("\(sectionItem.entries.count)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
```

### Step 3: Block Entry Display

```swift
func entryRow(_ entry: NotebookEntry) -> some View {
    Group {
        switch BlockType(rawValue: entry.blockType ?? "text") ?? .text {
        case .heading:
            Text(entry.title ?? "")
                .font(headingFont(level: entry.headingLevel ?? 1))
                .bold()

        case .text:
            Text(entry.content ?? "")
                .font(.body)

        case .checklist:
            if let items = decodeChecklistItems(entry.checklistItems) {
                ForEach(items.indices, id: \.self) { idx in
                    HStack {
                        Image(systemName: items[idx].checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(items[idx].checked ? .green : .secondary)
                        Text(items[idx].text)
                            .strikethrough(items[idx].checked)
                    }
                }
            }

        case .photo:
            if let path = entry.photoPath {
                AsyncImage(url: URL(fileURLWithPath: path)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    ProgressView()
                }
            }

        case .partReference:
            HStack {
                Image(systemName: "shippingbox.fill").foregroundStyle(.blue)
                Text(entry.title ?? "Part Reference")
                    .foregroundStyle(.blue)
            }
            .padding(8)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .divider:
            Divider()

        case .callout:
            HStack {
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 4)
                Text(entry.content ?? "")
                    .font(.callout)
                    .italic()
            }
            .padding(.vertical, 4)

        case .table:
            Text("[Table]").foregroundStyle(.secondary)

        case .todo:
            HStack {
                Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.isComplete ? .green : .secondary)
                Text(entry.title ?? "").font(.body)
            }
        }
    }
    .contextMenu {
        Button { activeSheet = .editEntry(entry) } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            Task { await deleteEntry(entry) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
```

### Step 4: Block Entry Editor with Shortcut Commands

Update `AddNotebookEntrySheet.swift` with shortcut command support:

```swift
// Shortcut commands in the text field
// When user types "/h1 Title", create a heading block
// When user types "/checklist", create a checklist block

@State private var inputText = ""

func processShortcutCommand(_ text: String) -> (BlockType, String)? {
    if text.hasPrefix("/h1 ") { return (.heading, String(text.dropFirst(4))) }
    if text.hasPrefix("/h2 ") { return (.heading, String(text.dropFirst(4))) }
    if text.hasPrefix("/h3 ") { return (.heading, String(text.dropFirst(4))) }
    if text.hasPrefix("/checklist") { return (.checklist, "") }
    if text.hasPrefix("/photo") { return (.photo, "") }
    if text.hasPrefix("/part") { return (.partReference, "") }
    if text.hasPrefix("/panel") { return (.callout, "") }
    if text.hasPrefix("/divider") { return (.divider, "") }
    if text.hasPrefix("/todo ") { return (.todo, String(text.dropFirst(6))) }
    return nil
}

// Show shortcut hints when "/" is typed
if inputText.hasPrefix("/") {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack {
            ForEach(["/h1", "/h2", "/checklist", "/photo", "/part", "/panel", "/divider", "/todo"], id: \.self) { cmd in
                Button(cmd) { inputText = cmd + " " }
                    .buttonStyle(.bordered)
                    .font(.caption)
            }
        }
    }
}
```

### Step 5: Add/Reorder/Delete Sections and Pages

- Sections and groups support swipe-to-delete with confirmation
- Long-press to reorder (or drag handles)
- Delete cascades to children (with confirmation showing count)

## Important Notes
- The hierarchy is: Notebook → Section Groups (optional) → Sections → Entries (blocks)
- DisclosureGroup handles the collapse/expand state
- Shortcut commands are processed on submit — not as the user types (for performance)
- Block types render differently — each has its own view
- Context menu on entries for edit/delete
- Entries without a section_id should appear in an "Unsorted" section

## Success Criteria
- [ ] showXxx Bools converted to ActiveSheet enum
- [ ] Hierarchical layout: Groups → Sections → Entries
- [ ] Collapsible sections with DisclosureGroup
- [ ] Block-based content rendering (text, heading, photo, checklist, part ref, divider, callout, todo)
- [ ] Shortcut command support (/h1, /h2, /checklist, /photo, /part, /panel, /divider, /todo)
- [ ] Add/reorder/delete sections and groups
- [ ] Context menus for edit/delete on entries
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 43B Results (YYYY-MM-DD)
- IOSNotebookDetailPage: hierarchical layout with collapsible groups
- ActiveSheet conversion from 2 Bools
- Block rendering for X block types
- Shortcut commands: /h1, /h2, /checklist, /photo, /part, /panel, /divider, /todo
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 43C.**
