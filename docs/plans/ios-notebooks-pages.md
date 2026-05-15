# iOS Notebooks Pages — Design Plan

> **Purpose:** Comprehensive design decisions for all Notebooks-related pages in the iOS app. Covers hierarchy, block-based editing, sync conflicts, shortcut commands, to-do types, panel schedule builder, daily reports, and templates.
>
> **Source:** Design conversation 2026-03-23. Implements pages in `Weird Parts IOS/Features/Notebooks/`.
>
> **Files:** `IOSNotebooksListPage`, `IOSNotebookDetailPage`, `IOSJobNotebooksPage`, `IOSNotebookTemplatesPage`, `AddNotebookEntrySheet`, `CreateNotebookSheet`

---

## What This Does

The Notebooks area is the freeform-knowledge-capture surface of the program — a OneNote-style hierarchical content store with block-based editing, sync-conflict resolution, to-do classification, daily reports, panel-schedule builder, and templates. Every job has its own notebook; users also have general notebooks for cross-job knowledge. Each notebook contains sections, each section contains entries (rich blocks), each entry can hold checklist items, todo classifications, headings, callouts, dividers, panel schedules, and panel-builder layouts. The area underpins the daily-report-summary feature (which reads notebook entries) and the warranty-timer + question-escalation flows.

## Why

Operators in the field need a single place to capture observations, action items, and decisions during the workday — without forcing structure that breaks flow. Notebooks succeed because they are flexible (block types match the kind of thing being recorded), durable (synced across devices via Multipeer with conflict resolution), and bridged into other workflows (todo blocks roll into the daily report; question blocks escalate to Q&A; panel schedules feed billing). Without notebooks, the program would lose the messy-but-essential operational notes that distinguish a useful tool from a pure data-entry app. Notebooks are also the long-term institutional memory for jobs that span weeks or months.

---

## 1. Notebook Hierarchy

Notebooks follow a **OneNote-style** hierarchy:

```
Notebook
  +-- Section Group (optional nesting)
  |     +-- Section
  |           +-- Page
  |           +-- Page
  +-- Section
        +-- Page
        +-- Page
```

| Level | Description | Example |
|-------|-------------|---------|
| **Notebook** | Top-level container. One per job (auto-created) + user-created general notebooks. | "Job #12345 Notebook", "Personal Notes" |
| **Section Group** | Optional grouping of sections. Collapsible. | "Electrical", "Plumbing" |
| **Section** | A named tab within a notebook. | "Rough-In Notes", "Panel Schedules" |
| **Page** | Individual content page within a section. | "Kitchen Panel Schedule", "March 15 Notes" |

### Job Notebooks

- Every job automatically gets a notebook when created
- Job notebook name = job name
- Default sections created from job template (configurable in Office → Templates)
- Chat attachments auto-save to a "Chat Attachments" section

### General Notebooks

- Users can create personal notebooks (not tied to a job)
- Shared notebooks visible to team (hat: `view_shared_notebooks`)
- Private notebooks visible only to creator

---

## 2. Block-Based Editing

Each page uses **Notion-style block-based editing**. Every block is one content type. Blocks are the unit of editing, syncing, and conflict resolution.

### Block Types

| Block Type | Description | Shortcut |
|------------|-------------|----------|
| **Text** | Plain paragraph text | (default) |
| **Heading 1** | Large section header | `/h1` |
| **Heading 2** | Medium sub-header | `/h2` |
| **Heading 3** | Small sub-header | `/h3` |
| **Checklist** | Checkbox list items | `/checklist` |
| **Photo** | Image from camera or library | `/photo` |
| **Divider** | Horizontal rule separator | `/divider` |
| **Part Reference** | Tappable link to a part | `/part` |
| **Panel Schedule** | Embedded panel schedule (see Section 6) | `/panel` |
| **Quote** | Indented quote block | `/quote` |
| **Callout** | Colored callout box (info, warning, error) | `/callout` |
| **Table** | Simple grid table | `/table` |
| **Code** | Monospace code block | `/code` |
| **To-Do** | Work item with status tracking | `/todo` |

### Block Data Model

Each block stores:
```
block_id: UUID
page_id: UUID (parent page)
block_type: String (from types above)
content: JSON (type-specific content)
position: Int (ordering within page)
created_at: DateTime
updated_at: DateTime
created_by: UUID (user)
updated_by: UUID (user)
```

### Shortcut Commands

> **Implementation note (2026-04-19):** The `/` command palette described below is the Phase 2 design target. The current implementation (Phase 4.5 complete) uses a **Picker dropdown** for block type selection + toolbar shortcut buttons for the most common types (heading, checklist, to-do, callout, divider). This is more iOS-native and is acceptable UX. The command palette can be added in a future polish pass.

Typing `/` at the start of a new block opens a command palette showing all available block types. User can:
1. Type to filter (e.g., `/h` shows h1, h2, h3)
2. Tap to select
3. Block transforms to selected type

Full shortcut list:
- `/h1`, `/h2`, `/h3` — headings
- `/checklist` — checkbox list
- `/photo` — photo picker
- `/part` — part search + reference
- `/panel` — panel schedule builder
- `/divider` — horizontal rule
- `/quote` — quote block
- `/callout` — callout box
- `/table` — table
- `/code` — code block
- `/todo` — to-do item

---

## 3. Sync Conflicts

Notebooks sync via the standard sync engine. Conflicts are resolved **per-block** (not per-page), minimizing data loss.

### Conflict Resolution Flow

> **Implementation note (2026-04-19):** Step 2 (AI Merge Attempt) is a Phase 2 design target requiring Foundation Models integration. Current implementation (Phase 4.5) skips the AI merge and goes directly to step 3 (User Review with local vs. remote choice). Foundation Models integration is planned for Phase 12 (AI Integration).

When two devices edit the same block:

1. **Detection:** Sync engine detects conflicting versions of the same `block_id`
2. **AI Merge Attempt:** Apple Foundation Models attempts to merge the two versions *(Phase 2 — not yet implemented)*
   - Shows with **Apple AI glow** (subtle animation indicating AI is working)
   - AI considers: which parts changed, context from surrounding blocks, block type
3. **User Review:** After AI merge, user sees:
   - **Merged result** (AI's best attempt)
   - **Version A** (this device's version)
   - **Version B** (other device's version)
   - **Diff view** highlighting what changed in each version
4. **User Actions:**
   - **Accept merge** — use AI's merged result
   - **Keep mine** — use this device's version
   - **Keep theirs** — use other device's version
   - **Manual rewrite** — open editor to write a new version from scratch

### Conflict Prevention

- Block-level locking: when a user starts editing a block, other devices see a "being edited" indicator
- Lock expires after 5 minutes of inactivity
- Locks are advisory (not hard locks) — editing is always possible, just flagged

---

## 4. To-Do Types

Notebooks support two to-do work types, with Question as a tag (not a separate type).

### Work Types

| Type | Icon | Color | Description |
|------|------|-------|-------------|
| **Regular Work** | `wrench.fill` | Blue | Standard work items |
| **Warranty Work** | `shield.fill` | Purple | Work covered under warranty |

### Question Tag

- **Question is a tag, not a to-do type.** Any to-do (Regular or Warranty) can be tagged as a Question.
- Question tag adds: `?` badge, escalation capability, answer tracking
- Questions flow into the Q&A system (see Chat design plan)
- When answered, the question tag shows the answer inline

### To-Do Data Model

```
todo_id: UUID
page_id: UUID (parent page)
block_id: UUID (the block this to-do lives in)
title: String
description: String?
work_type: "regular" | "warranty"
is_question: Bool
status: "open" | "in_progress" | "done"
assigned_to: UUID? (user)
due_date: Date?
priority: "low" | "medium" | "high"
warranty_ref: UUID? (reference to original to-do if warranty work)
created_at: DateTime
completed_at: DateTime?
```

---

## 5. Daily Report

Daily reports are **system-generated** documents that compile the day's activity for a job.

### Generation Process

1. **System generates** a daily report from clock data, to-do completions, parts movements, and other tracked activity
2. **AI compiles** a natural language summary using Apple Foundation Models
3. **AI self-verifies** — checks that the summary matches the raw data (counts, names, times)
4. **Template-driven layout** — Office configures report templates (Settings → Templates)
5. **User adds notes** below the system-generated section

### Report Structure

```
+--------------------------------------------------+
| DAILY REPORT — Job #12345 — March 23, 2026       |
+--------------------------------------------------+
| [SYSTEM SECTION - auto-generated, read-only]     |
|                                                   |
| AI Summary:                                       |
| "4 workers on site today. 32 total hours.         |
|  Completed rough-in for kitchen and bathrooms.    |
|  3 to-dos closed, 2 new to-dos created."          |
|                                                   |
| Workers On Site:                                  |
| - John Smith: 8:00 AM - 4:30 PM (8.5 hrs)       |
| - Jane Doe: 7:30 AM - 4:00 PM (8.5 hrs)         |
| - Bob Wilson: 9:00 AM - 5:30 PM (8.5 hrs)       |
| - Mike Johnson: 8:00 AM - 4:00 PM (8.0 hrs)     |
|                                                   |
| To-Dos Completed: 3                               |
| To-Dos Created: 2                                 |
| Parts Used: 47 items (from 3 movements)           |
|                                                   |
+--------------------------------------------------+
| [USER SECTION - editable]                         |
|                                                   |
| Notes:                                            |
| (user types notes, adds photos, etc.)             |
|                                                   |
+--------------------------------------------------+
```

### Template System

- **Office controls templates** via Settings → Templates
- Templates define: which sections appear, what data is included, formatting
- Different templates for different job types (e.g., residential vs commercial)
- Default template ships with the app

---

## 6. Panel Schedule Builder

A dedicated tool for building electrical panel schedules. This is a first-class feature, not a generic table.

### Panel Types Supported

| Type | Description | Breaker Count |
|------|-------------|---------------|
| **MDP** | Main Distribution Panel | 42+ spaces |
| **Sub Panel** | Sub-distribution panel | 20-42 spaces |
| **Load Center** | Residential panel | 20-40 spaces |
| **Small Panel** | Small sub-panel | 8-20 spaces |
| **Disconnect** | 2-space disconnect | 2 spaces |

### Builder Interface

- **Drag-and-drop circuits** onto breaker positions
- **Dual breakers** supported (two circuits sharing one space)
- **Circuit data:** circuit number, description, wire size, breaker size, load (amps)
- **Auto-numbering:** odd on left, even on right (standard panel layout)
- **Color coding:** by circuit type (lighting, receptacle, motor, etc.)

### Implementation Update — 2026-05-15

- Panel schedule validation now lives in `PanelScheduleModels.swift` so SwiftUI and tests share the same rules.
- Double breakers reserve the matching space below on the same side (`1+3`, `2+4`) and are rejected if they overlap another circuit or run past the panel.
- Panel type space constraints are enforced for MDP, Sub Panel, Load Center, Small Panel, and Disconnect.
- Circuit classification persists in panel JSON and drives builder color coding for lighting, receptacle, motor, spare, blank, and special circuits.
- Builder supports drag/drop plus a tap-based move mode and VoiceOver accessibility actions as non-drag alternatives.

### Print Layout

- **Custom paper sizes:** Letter, Legal, A4, Card Stock (various sizes)
- **Company header:** Fully customizable with **drag-drop designer**
  - Company name, logo, address, phone, license number
  - Each element can be repositioned by dragging
  - Font size and style per element
  - Save header as template for reuse
- **Panel body:** Standard panel schedule format
- **Footer:** Job info, date, prepared by

### Print Output

- Generated as PDF
- iOS native print via `UIPrintInteractionController`
- Share sheet for email/AirDrop
- Save to job notebook automatically

---

## 7. Templates

### Template Hierarchy

```
Company Templates (Office-managed)
  +-- Job Starter Templates (what sections a new job notebook gets)
  +-- Page Templates (pre-built page content)
  +-- Daily Report Templates (report format/sections)
  +-- Panel Schedule Templates (header layouts)
```

### Job Starter Templates

When a new job is created, its notebook is populated based on a **job starter template**.

| Template Type | Default Sections |
|---------------|-----------------|
| **Residential** | General Notes, Panel Schedules, Inspections, Photos, Daily Reports |
| **Commercial** | General Notes, Panel Schedules, Fire Alarm, Low Voltage, Inspections, Photos, Daily Reports, RFIs |
| **Service Call** | Work Notes, Photos, Customer Sign-Off |
| **Maintenance** | Work Log, Equipment List, Photos |

- Templates are configurable in Office → Templates
- Different templates for different job types AND job statuses
- Admin can create custom templates (hat: `manage_templates`)

### Page Templates

Pre-built page content that can be inserted into any section:

- **Inspection Checklist** — pre-populated checklist for common inspections
- **Change Order** — structured form for change orders
- **Meeting Notes** — date, attendees, agenda, action items
- **Punch List** — numbered list with location, description, status
- **Safety Report** — incident report format

### Template Configuration

- Office → Templates page manages all template types
- Templates can be: created, edited, duplicated, archived (not deleted)
- Templates have a version history (edits create new version, old versions preserved)
- Hat required: `manage_templates`

---

## 8. Implementation Notes

### Service Layer Requirements

All notebook operations go through `NotebooksService` in WiredPartCore.

Key service methods:
- `fetchNotebooks(filter:)` — with job filter
- `fetchSections(notebookId:)` — section hierarchy
- `fetchPages(sectionId:)` — pages in a section
- `fetchBlocks(pageId:)` — blocks in a page
- `createBlock(pageId:, type:, content:, position:)` — add block
- `updateBlock(blockId:, content:)` — edit block
- `deleteBlock(blockId:)` — remove block
- `resolveConflict(blockId:, resolution:)` — conflict resolution
- `generateDailyReport(jobId:, date:)` — AI-compiled daily report
- `fetchTemplates(type:)` — template listing
- `applyTemplate(notebookId:, templateId:)` — apply job starter template

### Sync Considerations

- Blocks are the sync unit (not pages or notebooks)
- Block position changes are tracked as separate sync events
- Photo blocks store image data separately (blob sync)
- Panel schedule data is stored as JSON within the block content field
- Conflict resolution metadata stored in `_conflict_log` table

---

---

## Current Implementation Status (2026-04-19, via AUTO GO C1 supplement)

**Status:** Phase 4.5 (Unified Notebook System) is marked complete in CLAUDE.md.

### iOS Files (8 total in `Features/Notebooks/`)

| File | Purpose |
|---|---|
| `IOSNotebooksRouter.swift` | Nav hub for notebooks |
| `IOSNotebooksListPage.swift` | All notebooks list with filter |
| `IOSNotebookDetailPage.swift` | Single notebook: hierarchy view + block editor |
| `IOSJobNotebooksPage.swift` | Per-job notebooks tab |
| `IOSNotebookTemplatesPage.swift` | Template management (list + apply) |
| `AddNotebookEntrySheet.swift` | Sheet to add a block entry to a section |
| `CreateNotebookSheet.swift` | Sheet to create a new notebook |
| `PanelScheduleBuilder.swift` | Dedicated panel schedule builder (section 6) |

Note: `PanelScheduleBuilder.swift` is not listed in the plan's "Files:" header but is described in section 6 and implemented.

### NotebooksService API (37 public methods, 1485 lines as of 2026-04-30)

Actual method names differ slightly from the plan's conceptual list:

| Plan concept | Actual method | Notes |
|---|---|---|
| `fetchNotebooks(filter:)` | `listNotebooks(notebookType:, jobId:)` | Job and type filters |
| `fetchSections` | `getNotebookHierarchy(notebookId:)` | Returns full hierarchy |
| `createBlock` | `createBlockEntry(sectionId:, ...)` | Block + section together |
| `updateBlock` | `updateBlockEntry(entryId:, ...)` | |
| `deleteBlock` | `deleteBlockEntry(entryId:)` | Soft-delete |
| `resolveConflict` | `resolveBlockConflict(conflictLogId:, keepVersion:)` | |
| `generateDailyReport` | `DailyReportGenerator.generateReport(...)` | Separate service |
| `fetchTemplates` | `getTemplates(templateType:)` | |
| `applyTemplate` | `applyJobTemplate` + `applyPageTemplate` | Two template levels |

Additional methods not in plan: `classifyTodoWork`, `reviewClassification`, `reclassifyTodoWork`, `getClassificationHistory`, `startWarrantyTimer`, `getTodosNeedingReview`, `ensureWarrantySection`, `detectBlockConflicts`, `resolveAllBlockConflicts`, `seedDefaultTemplates`, full section group CRUD, full section CRUD.

### Tests

`core/Tests/WiredPartCoreTests/NotebooksServiceTests.swift` — 1543 lines, extensive coverage of all major flows including hierarchy, blocks, conflict detection/resolution, templates, warranty timer, section groups/sections, classification lifecycle.

---

## Test Plan

Coverage targets (all currently tested):
- `listNotebooks` — returns all notebooks; filter by job; filter by type; hides soft-deleted job names
- `createNotebook` — creates and appears in list; with job association; throws on blank title
- `getNotebookDetail` — returns notebook with entries; throws for non-existent ID
- `createBlockEntry` + hierarchy — appears in `getNotebookHierarchy`; soft-delete removes it
- `updateBlockEntry` — content updated correctly; no-op on deleted entry
- `completeEntry` — marks entry done; no-op on deleted entry
- `applyJobTemplate` — creates groups, sections, and entries
- `getNotebooksStats` — aggregates reflect actual data
- Section group CRUD — lifecycle: create, update, delete; throws on blank name; no-op on deleted
- Section CRUD — create, update, delete; throws on blank name; no-op on deleted
- `detectBlockConflicts` + `resolveBlockConflict` + `resolveAllBlockConflicts` — full conflict lifecycle
- `classifyTodoWork` + `reviewClassification` + `reclassifyTodoWork` + `getClassificationHistory` — classification lifecycle
- `startWarrantyTimer` — throws on zero/negative duration
- `createNotebook` blank title, `addNotebookEntry` blank title, `createSectionGroup`/`Section`/`Template` blank name — input validation

---

## User Roles

| User | Access |
|------|--------|
| Any authenticated | View own notebooks + job notebooks for their jobs |
| Any authenticated | Create notebook entries (blocks) |
| Hat: `view_shared_notebooks` | View team-shared notebooks |
| Supervisor | View all job notebooks for assigned jobs |
| Hat: `manage_templates` | Create / edit / delete notebook templates |
| Admin | All notebooks + template management + delete notebooks |

Permissions enforced at UI layer (page visibility + action guards based on `appCore.currentUser?.permissions`).

---

## Security

- All NotebooksService queries use parameterized GRDB args — no SQL injection risk
- Notebooks can contain sensitive job data (photos, notes, panel schedules) — `view_shared_notebooks` gates shared access
- Template application (`applyJobTemplate`) inserts entries into the caller-supplied `notebookId` — UI must verify user has write access to the notebook before calling
- Block content is stored as freeform String (`content` column) — no XSS risk in native SwiftUI rendering, but would be a concern if content were ever rendered as HTML

---

## HIG / Accessibility

- Block type command palette (`/` shortcut): `.accessibilityLabel("Type / to insert block")` on text entry
- Block list reordering: drag handles need `.accessibilityAction(named:)` for move-up / move-down as VoiceOver alternatives to drag
- Panel schedule builder drag-drop circuits: must provide `.accessibilityAction` alternatives (tap to select breaker position)
- Section tabs: `.accessibilityAddTraits(.isSelected)` on the active section tab
- Completed/done entries: `.accessibilityValue("Completed")` on checkmark icon

*Last updated: 2026-04-19 (supplement via AUTO GO C1)*
