# Job-Type Notebook Templates Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Make every newly-created job reliably receive exactly one linked job notebook, populated from the clearest matching job-type template, while keeping existing job notebooks recoverable without bulk migration risk.

**Architecture:** Reuse the current Swift/GRDB local-first notebook system instead of adding a parallel template model. `JobsService.createJob` should own atomic job + notebook creation, and `NotebooksService` should own template lookup/application. The iOS job detail Notebooks tab should deep-link to the job notebook, create/recover only when missing, and show the selected job-type template clearly.

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing, WiredPartCore, iOS local SQLite.

---

## Dedupe and Current-State Findings

Source issue: GitHub #626 / Paperclip WEI-2070.

Prior related work:
- GitHub #398 is closed.
- PR #482 was merged and claimed to create linked notebooks in `JobsService.createJob`, add job detail notebook deep-linking, and add atomic rollback tests.

Current code checked on this workspace after `git fetch origin main`:
- `core/Sources/WiredPartCore/Services/JobsService.swift:513-576` still inserts only into `jobs` and returns the job id. It does not create a notebook or apply a template in the current local branch or `origin/main` snapshot checked during planning.
- `core/Sources/WiredPartCore/Services/NotebooksService.swift:1068-1343` already has the key pieces: `getTemplates(templateType:)`, `createTemplate`, `applyJobTemplate`, `applyPageTemplate`, and seeded default templates for `residential`, `commercial`, and `service` categories.
- `docs/plans/ios-notebooks-pages.md:299-313` already defines job starter templates by job type and says templates are configurable in Office -> Templates.
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift:861-887` currently sends the user to the general Job Notebooks module instead of opening/recovering this job's notebook inline.

Conclusion: do not duplicate the notebook system. Implement a narrow recovery of the intended #398/#482 behavior plus the missing job-type template selection/default content UX.

---

## Acceptance Criteria

1. Creating a job creates exactly one `notebooks` row with:
   - `notebook_type = 'job'`
   - `job_id = new job id`
   - `template_id = selected template id` when a matching template exists
   - title derived from the job name, e.g. `"<Job Name> Notebook"` or the current preferred naming pattern.
2. The job notebook is populated by the best matching job template:
   - exact normalized category match against `jobs.job_type`, e.g. `residential`, `commercial`, `service`
   - fallback to the `service` default template
   - final fallback to a minimal General / Daily Log / Photos structure if default templates are missing.
3. Job creation stays atomic: if notebook/template application fails, the job insert rolls back and the caller receives an error.
4. Re-opening the job detail Notebooks tab for existing jobs with no notebook offers or performs a safe one-click recovery without creating duplicates.
5. The Templates page makes it obvious which templates are job-type starter templates and which job type/category they map to.
6. Tests prove job+notebook creation, template matching, fallback, no duplicates, and rollback.

---

## Task 1: Add a NotebooksService job-template selector

**Objective:** Centralize job-type template lookup so `JobsService` and iOS recovery UI do not duplicate SQL or matching rules.

**Files:**
- Modify: `core/Sources/WiredPartCore/Services/NotebooksService.swift`
- Test: `core/Tests/WiredPartCoreTests/NotebooksServiceTests.swift`

**Step 1: Write failing tests**

Add tests near existing template tests:

```swift
@Test("findBestJobTemplate matches normalized job type category")
func testFindBestJobTemplateMatchesJobType() throws {
    let env = try E2ETestHelpers.setUp()
    try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

    let template = try env.notebooks.findBestJobTemplate(jobType: "Commercial")

    #expect(template?.name == "Commercial Job")
    #expect(template?.category == "commercial")
}

@Test("findBestJobTemplate falls back to service template")
func testFindBestJobTemplateFallsBackToService() throws {
    let env = try E2ETestHelpers.setUp()
    try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

    let template = try env.notebooks.findBestJobTemplate(jobType: "unknown-special")

    #expect(template?.name == "Service Call")
    #expect(template?.category == "service")
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd core
swift test --filter NotebooksServiceTests.testFindBestJobTemplate
```

Expected: FAIL because `findBestJobTemplate(jobType:)` does not exist.

**Step 3: Implement selector**

Add a public method to `NotebooksService`:

```swift
public func findBestJobTemplate(jobType: String?) throws -> NotebookTemplateItem? {
    let normalized = (jobType ?? "service")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")

    let templates = try getTemplates(templateType: "job")
    if let exact = templates.first(where: { ($0.category ?? "").lowercased() == normalized }) {
        return exact
    }
    if let service = templates.first(where: { ($0.category ?? "").lowercased() == "service" }) {
        return service
    }
    return templates.first(where: { $0.isDefault }) ?? templates.first
}
```

**Step 4: Run tests to verify pass**

Run:

```bash
cd core
swift test --filter NotebooksServiceTests.testFindBestJobTemplate
```

Expected: PASS.

---

## Task 2: Add a NotebooksService job-notebook creator/recovery helper

**Objective:** Provide one safe method for "ensure this job has a notebook" that avoids duplicates and applies the selected template.

**Files:**
- Modify: `core/Sources/WiredPartCore/Services/NotebooksService.swift`
- Test: `core/Tests/WiredPartCoreTests/NotebooksServiceTests.swift`

**Step 1: Write failing tests**

Add tests:

```swift
@Test("ensureJobNotebook creates one linked notebook with matching template")
func testEnsureJobNotebookCreatesFromTemplate() throws {
    let env = try E2ETestHelpers.setUp()
    try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)
    let jobId = try E2ETestHelpers.seedJob(env, jobType: "commercial")

    let notebookId = try env.notebooks.ensureJobNotebook(
        jobId: jobId,
        jobName: "Office Buildout",
        jobType: "commercial",
        createdBy: env.adminUserId
    )

    let detail = try env.notebooks.getNotebookDetail(id: notebookId)
    #expect(detail.jobId == jobId)
    #expect(detail.notebookType == "job")

    let templates = try env.notebooks.getTemplates(templateType: "job")
    let commercial = try #require(templates.first { $0.category == "commercial" })
    let templateId = try env.db.writer.read { db in
        try Int64.fetchOne(db, sql: "SELECT template_id FROM notebooks WHERE id = ?", arguments: [notebookId])
    }
    #expect(templateId == commercial.id)

    let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: notebookId)
    #expect(!hierarchy.groupedSections.isEmpty || !hierarchy.ungroupedSections.isEmpty)
}

@Test("ensureJobNotebook returns existing linked notebook without duplicate")
func testEnsureJobNotebookNoDuplicate() throws {
    let env = try E2ETestHelpers.setUp()
    let jobId = try E2ETestHelpers.seedJob(env)

    let first = try env.notebooks.ensureJobNotebook(jobId: jobId, jobName: "Job A", jobType: "service", createdBy: env.adminUserId)
    let second = try env.notebooks.ensureJobNotebook(jobId: jobId, jobName: "Job A", jobType: "service", createdBy: env.adminUserId)

    #expect(first == second)
    let count = try env.db.writer.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notebooks WHERE job_id = ? AND deleted_at IS NULL", arguments: [jobId]) ?? 0
    }
    #expect(count == 1)
}
```

If `E2ETestHelpers.seedJob` cannot accept `jobType`, create the job directly with `env.jobs.createJob(..., jobType: "commercial", createdBy: env.adminUserId)`.

**Step 2: Run tests to verify failure**

Run:

```bash
cd core
swift test --filter NotebooksServiceTests.testEnsureJobNotebook
```

Expected: FAIL because `ensureJobNotebook` does not exist.

**Step 3: Implement helper**

Add a method that:
1. Checks `notebooks` for an existing active row where `job_id = ? AND notebook_type = 'job' AND deleted_at IS NULL`.
2. If found, returns that id.
3. Calls `seedDefaultTemplates(createdBy:)` if no job templates exist.
4. Calls `findBestJobTemplate(jobType:)`.
5. Inserts a `notebooks` row with `template_id` and `notebook_type = 'job'`.
6. Calls `applyJobTemplate(templateId:notebookId:createdBy:)` if a template was found.
7. Creates a minimal `General` section if no template was found.

Keep the insert + template application in one write transaction if practical. If `applyJobTemplate` currently starts its own transaction, either create a private transaction-aware helper or keep the public method transactional by inlining the small insert loops; do not leave half-created empty job notebooks.

**Step 4: Run tests to verify pass**

Run:

```bash
cd core
swift test --filter NotebooksServiceTests.testEnsureJobNotebook
```

Expected: PASS.

---

## Task 3: Make JobsService.createJob atomically create the notebook

**Objective:** Restore/ship the #398/#482 intended behavior in current code: a job cannot be created without its linked notebook.

**Files:**
- Modify: `core/Sources/WiredPartCore/Services/JobsService.swift`
- Test: `core/Tests/WiredPartCoreTests/JobsServiceTests.swift`

**Step 1: Write failing tests**

Add tests near create-job tests:

```swift
@Test("createJob creates a linked job notebook")
func testCreateJobCreatesLinkedNotebook() throws {
    let env = try E2ETestHelpers.setUp()
    try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

    let jobId = try env.jobs.createJob(
        jobNumber: "JN-AUTO-NB",
        jobName: "Auto Notebook Job",
        jobType: "residential",
        createdBy: env.adminUserId
    )

    let notebooks = try env.notebooks.listNotebooks(notebookType: "job", jobId: jobId)
    #expect(notebooks.count == 1)
    #expect(notebooks[0].title.contains("Auto Notebook Job"))
}
```

Add a rollback test only if you can inject a deterministic template failure without brittle hacks; otherwise test duplicate prevention in Task 2 and rely on transaction structure review.

**Step 2: Run test to verify failure**

Run:

```bash
cd core
swift test --filter JobsServiceTests.testCreateJobCreatesLinkedNotebook
```

Expected: FAIL; current `createJob` only inserts into `jobs`.

**Step 3: Implement atomic creation**

Inside the existing `db.writer.write` in `JobsService.createJob`:
1. Insert the job as today.
2. Capture `let jobId = dbConn.lastInsertedRowID`.
3. Create/apply the matching notebook before returning `jobId`.
4. Do not swallow errors; throwing inside the transaction rolls the job back.

Prefer sharing the same transaction with NotebooksService private helpers. Avoid calling a public method that starts a nested write transaction if GRDB does not allow it cleanly.

**Step 4: Run focused tests**

Run:

```bash
cd core
swift test --filter JobsServiceTests.testCreateJobCreatesLinkedNotebook
swift test --filter NotebooksServiceTests.testEnsureJobNotebook
```

Expected: PASS.

---

## Task 4: Update the iOS job detail Notebooks tab UX

**Objective:** Replace the generic "go to Notebooks module" dead-end with a direct, reassuring path to this job's notebook.

**Files:**
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift`
- Optionally modify: `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSJobNotebooksPage.swift`

**Step 1: Define UI states**

The Notebooks tab should show:
- Loading: "Checking job notebook..."
- Found: card with notebook title, template/category label, section/entry count if available, and primary button "Open Job Notebook".
- Missing: warning card "This older job does not have a notebook yet" with primary button "Create Job Notebook" that calls `ensureJobNotebook`.
- Error: retry button, with user-friendly error.

**Step 2: Implement state**

Add state to `IOSJobDetailTabView`:

```swift
@State private var jobNotebook: NotebooksService.NotebookListItem?
@State private var isLoadingJobNotebook = false
@State private var jobNotebookError: String?
```

Add loader:

```swift
private func loadJobNotebook(for job: JobsService.JobDetail) {
    guard let service = appCore.notebooksService else { return }
    isLoadingJobNotebook = true
    jobNotebookError = nil
    do {
        jobNotebook = try service.listNotebooks(notebookType: "job", jobId: job.id).first
    } catch {
        jobNotebookError = userFriendlyError(error, context: "load job notebook")
    }
    isLoadingJobNotebook = false
}
```

Add recovery action using Task 2 helper:

```swift
private func createMissingJobNotebook(for job: JobsService.JobDetail) {
    guard let service = appCore.notebooksService,
          let userId = appCore.currentUser?.id else { return }
    do {
        let id = try service.ensureJobNotebook(
            jobId: job.id,
            jobName: job.jobName,
            jobType: job.jobType,
            createdBy: userId
        )
        jobNotebook = try service.listNotebooks(notebookType: "job", jobId: job.id).first
        // Navigate to `IOSNotebookDetailPage(notebookId: id)` or set NavigationLink state.
    } catch {
        jobNotebookError = userFriendlyError(error, context: "create job notebook")
    }
}
```

**Step 3: Navigation**

Use a `NavigationLink` directly to `IOSNotebookDetailPage(notebookId: notebook.id)` for found notebooks. Avoid module-level routing when the user is already inside a specific job.

**Step 4: Build verification**

Run:

```bash
xcodebuild -workspace 'Wierd Parts.xcworkspace' -scheme 'WiredPart-iOS' -destination 'generic/platform=iOS Simulator' -derivedDataPath .paperclip/DerivedData-WEI-2070 build
```

Expected: build succeeds.

---

## Task 5: Clarify Templates page copy and grouping

**Objective:** Make job-type template mapping visible to office/admin users.

**Files:**
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebookTemplatesPage.swift`

**Step 1: Update row metadata**

On each job template row, show:
- `Job Starter` badge when `template.templateType == "job"`
- `Job Type: Residential/Commercial/Service` based on category
- `Default` badge as today

**Step 2: Update help copy**

Replace the current generic help text with explicit job starter language:

```swift
("Job Starter Templates", "These templates are automatically applied when a new job is created. The template category maps to the job type, so a Commercial job gets the Commercial Job starter template, Residential gets Residential Job, and unknown types fall back to Service Call."),
("Recovery", "If an older job is missing its notebook, open the job's Notebooks tab and tap Create Job Notebook. The app uses the same job-type matching rules.")
```

**Step 3: Visual verification**

Open Notebooks -> Templates and confirm a non-coder office user can answer: "Which template will my commercial job use?"

---

## Task 6: Add regression notes to the existing design plan

**Objective:** Keep design docs aligned with the actual implementation rules.

**Files:**
- Modify: `docs/plans/ios-notebooks-pages.md`

**Add under Template System / Current Implementation Status:**

```markdown
### Job-Type Starter Template Rule

New jobs must receive exactly one linked job notebook during `JobsService.createJob`. The starter template is selected by `notebook_templates.template_type = 'job'` and `category == jobs.job_type` after normalization. Unknown job types fall back to the Service Call template. Older jobs missing notebooks are recovered from the job detail Notebooks tab via the same selector; recovery must not create duplicates.
```

---

## Implementation Split Recommendation

Smallest beta-safe split:

1. BackendCoder: Tasks 1-3 + tests. This fixes the data invariant and template application.
2. FrontendCoder: Tasks 4-5 after BackendCoder lands or in parallel if using the planned `ensureJobNotebook` signature.
3. UXDesigner or reviewer: Task 6 plus visual acceptance review.

Do not start with visual polish. The data invariant is the beta blocker: every job must have exactly one notebook.

---

## Verification Checklist

Run before marking implementation done:

```bash
cd core
swift test --filter NotebooksServiceTests.testFindBestJobTemplate
swift test --filter NotebooksServiceTests.testEnsureJobNotebook
swift test --filter JobsServiceTests.testCreateJobCreatesLinkedNotebook
cd ..
xcodebuild -workspace 'Wierd Parts.xcworkspace' -scheme 'WiredPart-iOS' -destination 'generic/platform=iOS Simulator' -derivedDataPath .paperclip/DerivedData-WEI-2070 build
```

Manual checks:
- Create a residential job; Notebooks tab opens a residential starter notebook.
- Create a commercial job; Notebooks tab opens a commercial starter notebook with panel schedule sections.
- Create a service/unknown job type; it falls back to Service Call.
- Open an old job with no notebook; recovery creates one notebook, and tapping recovery again does not duplicate it.
