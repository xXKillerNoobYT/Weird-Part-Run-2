# 45D — Warranty To-Do Classification

> **Chain position:** 45C → **45D**
> **Prerequisite:** 43A (notebook structure), 45C (warranty fields)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `NotebooksService.swift`, `JobsService.swift`, and `IOSNotebookDetailPage.swift`. Add work type classification to to-dos with manager review, reclassification tracking, and warranty timer.

## Context

When a job enters warranty, workers need to classify each to-do as "Regular Work" or "Warranty Work." This classification determines billing and reporting. Managers must review classifications. Reclassification is allowed anytime (with tracking). Each to-do gets a warranty timer that starts when the to-do is completed. New work after warranty completion goes to a dedicated warranty section in the notebook.

## Task

### Step 1: Migration — To-Do Work Classification

```swift
try db.alter(table: "notebook_entries") { t in
    t.add(column: "work_classification", .text)  // "regular", "warranty", nil
    t.add(column: "classification_reviewed", .boolean).defaults(to: false)
    t.add(column: "classification_reviewed_by", .integer)
        .references("users", onDelete: .setNull)
    t.add(column: "classification_reviewed_at", .text)
    t.add(column: "warranty_timer_start", .text)  // starts when to-do completed
    t.add(column: "warranty_timer_end", .text)     // warranty_timer_start + job.warranty_duration
    t.add(column: "is_question", .boolean).defaults(to: false)  // "Question" tag
}

CREATE TABLE classification_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    old_classification TEXT,
    new_classification TEXT NOT NULL,
    changed_by INTEGER NOT NULL REFERENCES users(id),
    reason TEXT,
    changed_at TEXT DEFAULT (datetime('now'))
);
```

### Step 2: Service Methods

```swift
// MARK: - Work Classification

/// Classify a to-do as regular or warranty work
func classifyTodoWork(entryId: Int64, classification: String, classifiedBy: Int64) async throws {
    // Update entry + log in classification_history
}

/// Manager reviews/approves a classification
func reviewClassification(entryId: Int64, reviewedBy: Int64, approved: Bool, newClassification: String?) async throws

/// Reclassify (with tracking)
func reclassifyTodoWork(entryId: Int64, newClassification: String, changedBy: Int64, reason: String?) async throws {
    // 1. Get current classification
    // 2. Log old → new in classification_history
    // 3. Update entry
    // 4. Reset reviewed flag
}

/// Get classification history for a to-do
func getClassificationHistory(entryId: Int64) async throws -> [ClassificationChange]

/// Start warranty timer when to-do is completed
func startWarrantyTimer(entryId: Int64, jobId: Int64) async throws {
    // Set warranty_timer_start = now
    // Set warranty_timer_end = now + job.warranty_duration_days
}

/// Get to-dos needing classification review
func getTodosNeedingReview(jobId: Int64) async throws -> [NotebookEntry]

struct ClassificationChange: Identifiable, Codable, Sendable {
    let id: Int64
    let entryId: Int64
    let oldClassification: String?
    let newClassification: String
    let changedBy: Int64
    let reason: String?
    let changedAt: String
}
```

### Step 3: UI — Classification on To-Do Items

In `IOSNotebookDetailPage.swift`, for to-do entries on warranty jobs:

```swift
// When displaying a to-do on a warranty job:
if job?.status == "warranty" {
    HStack {
        // Classification picker
        Picker("", selection: classificationBinding(for: entry)) {
            Text("Regular").tag("regular")
            Text("Warranty").tag("warranty")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)

        // Review status
        if entry.classificationReviewed {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else {
            Text("Needs Review")
                .font(.caption2)
                .foregroundStyle(.orange)
        }

        // Question tag
        if entry.isQuestion {
            Text("?")
                .font(.caption).bold()
                .foregroundStyle(.white)
                .padding(4)
                .background(.purple)
                .clipShape(Circle())
        }
    }
}
```

### Step 4: Manager Review Section

```swift
// For managers: list of to-dos needing review
if appCore.hasPermission("manage_jobs") && !todosNeedingReview.isEmpty {
    Section {
        ForEach(todosNeedingReview) { entry in
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.title ?? "").font(.headline)
                    Text("Classified as: \(entry.workClassification ?? "unset")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Approve") {
                    Task {
                        try? await service.reviewClassification(
                            entryId: entry.id!, reviewedBy: currentUserId,
                            approved: true, newClassification: nil
                        )
                        await loadData()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button("Change") {
                    selectedEntryForReclass = entry
                    showReclassSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    } header: {
        Text("Needs Review (\(todosNeedingReview.count))")
    }
}
```

### Step 5: Warranty Section in Notebook

When a job enters warranty and new work is done:

```swift
// Auto-create "Warranty Work" section group if it doesn't exist
func ensureWarrantySection(notebookId: Int64) async throws -> NotebookSectionGroup {
    // Check if "Warranty Work" group exists
    // If not, create it
    // Return the group
}

// New to-dos created during warranty go to this section automatically
```

### Step 6: Warranty Timer Display

```swift
// When a to-do is completed on a warranty job:
if let timerEnd = entry.warrantyTimerEnd, let endDate = parseDate(timerEnd) {
    let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
    HStack {
        Image(systemName: "timer")
        Text("Warranty: \(daysRemaining) days remaining")
            .font(.caption)
            .foregroundStyle(daysRemaining < 7 ? .red : .secondary)
    }
}
```

### Step 7: Update ConflictResolver

Add `classification_history` to the whitelist.

## Important Notes
- Classification is per-to-do, NOT per-notebook or per-section
- Manager review is required but doesn't block work
- Reclassification is allowed anytime — full history tracked
- "Question" tag is separate from classification (a warranty to-do can also be a question)
- Warranty timer starts on to-do COMPLETION, not creation
- New to-dos during warranty period auto-go to "Warranty Work" section group
- The classification picker is segmented control (Regular | Warranty)

## Success Criteria
- [ ] Migration adds classification columns to notebook_entries
- [ ] classification_history table for audit trail
- [ ] Service methods for classify, review, reclassify, timer
- [ ] Classification picker on warranty job to-dos
- [ ] Manager review section with approve/change
- [ ] Reclassification with reason tracking
- [ ] Warranty timer display (days remaining)
- [ ] Auto "Warranty Work" section group
- [ ] ConflictResolver updated
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 45D Results (YYYY-MM-DD)
- Migration: classification columns + classification_history
- Service: classify, review, reclassify, timer methods
- UI: classification picker, manager review, warranty timer
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
