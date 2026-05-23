# GH #625 — Configurable Job Stages UX Spec

Source: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/625
Paperclip: WEI-2068
Date: 2026-05-23
Owner: UXDesigner

## User request

The current job stage flow must be configurable because different jobs need different numbers of stages. Users need to add stages, rename stages, remove stages when safe, and change stage order without making the jobs screen rough or confusing.

## Existing product/code state

Current implementation is already partially stage-aware but only supports a global fixed/default stage model:

- Database migration `034_job_stages` creates `job_stages` with seeded defaults:
  - Rough-in
  - Prep/Makeup
  - Trim-out
- Jobs store `current_stage_id` on `jobs`.
- JPO lines can store `stage_id` and can also resolve stage by part category through `job_stage_category_map`.
- `OrdersService` supports:
  - `getJobStages()`
  - `getJobStageParts(jobId:)`
  - `markStageComplete(jobId:stageId:)`
  - `requestEarlyRelease(jpoLineId:)`
  - `updateCategoryStageMapping(categoryId:stageId:)`
  - `getCategoryStageMappings()`
- `JobsService.listJobStages(forJobId:)` computes completed/current/pending status from global stages.
- iOS already has `JobStageProgressBar`, but its comments/previews assume the old 3-stage default.

Dedupe check:

- GitHub search found GH #625 as the only open issue specifically about configurable/reorderable job stages.
- Related/non-duplicate references:
  - GH #69 closed: job list cards/stage bars.
  - GH #70 open: broader Jobs detail/dashboard work.
  - GH #88 open: warehouse staging, not job workflow stage configuration.
  - GH #232 closed: 1-stage progress bar crash.
- Paperclip search found no duplicate configurable-stage Paperclip child except WEI-2068.

## Minimum beta-safe UX

### Navigation

Add stage configuration in an admin/settings path, not inside every job card:

- Settings / Office Admin / Job Setup / Stages
- Job create/edit sheet: choose a stage template only when needed.
- Job detail: show current job stages and allow stage advancement, but deep editing of templates stays in admin.

### Mental model

Use templates, not one global mutable stage list only.

- A `Stage Template` is an ordered list of stages.
- Each job has exactly one template snapshot/assignment.
- Default beta template ships as existing 3-stage flow: Rough-in, Prep/Makeup, Trim-out.
- Example alternate templates:
  - Service Call: Visit, Diagnose, Repair, Invoice
  - Large Residential: Rough-in, Inspection, Makeup, Trim-out, Punch List
  - Commercial: Underground, Rough-in, Above Ceiling, Trim, Commissioning

Why templates: changing a global stage list underneath active jobs would make historical progress and part holds confusing. Templates let jobs differ safely.

### Stage list screen

For each template:

- Header: template name, job count using it, default badge if applicable.
- Ordered rows with drag handles.
- Row fields:
  - Stage name
  - Optional short code/color/icon later; do not block beta on this.
  - Count of mapped part categories / job parts affected.
- Primary actions:
  - Add Stage
  - Rename Stage
  - Reorder Stages
  - Duplicate Template
  - Archive Template

### Reorder interaction

Beta-safe iOS interaction:

- Use SwiftUI edit mode / drag handles in a List.
- Show a sticky Save / Cancel bar after order changes.
- Do not auto-save every drag; this avoids accidental workflow changes.
- On Save, display impact summary before applying when active jobs use the template:
  - “This changes the order for X active jobs using this template.”
  - “Completed/current stage markers will stay attached to their named stage.”
  - “Future/held parts will be recalculated from the new order.”

### Add stage interaction

- Add Stage opens a compact sheet:
  - Stage name, required.
  - Position: Before/After an existing stage or End.
  - Optional: copy part-category mappings from another stage? default No.
- Empty stage is allowed. It is a workflow checkpoint and may not have parts yet.

### Remove/archive stage interaction

Do not hard-delete stage rows used by active jobs.

- If no jobs/parts/history reference the stage: allow Delete.
- If referenced: allow Archive/Hide from new jobs only.
- If active jobs currently sit on that stage: block deletion and explain:
  - “Move active jobs out of this stage before archiving it.”
- If the stage has held/future parts: require reassignment target stage or block until mappings are moved.

### Per-job override

For beta, avoid full arbitrary per-job editing unless the backend already has a clean snapshot model.

Minimum:

- On job creation: choose template.
- On existing job edit: allow “Change template” only with a confirmation/preview.
- Later enhancement: “Customize this job’s stages” duplicates the template into a job-specific copy.

### Job detail display

- Progress bar must handle 1 to many stages gracefully.
- For more than 5 stages, use a horizontally scrollable stepper or compact chips instead of squeezing labels.
- The current stage card should show:
  - Current stage name
  - Completed stages count
  - Next stage
  - Button: Mark Current Stage Complete
- Stage progression should continue to work when stages are renamed or reordered because IDs, not names, drive state.

### Part/category mapping UX

Keep category mapping separate but linked:

- Template detail has “Part category mappings” section.
- Each part category can map to one stage, or “No automatic stage”.
- Show unmapped categories in a warning group because their parts will not be automatically held/released by stage.
- If a stage is archived/deleted, require moving its category mappings before saving.

## Backend implementation requirements

Current schema lacks template/snapshot ownership. Add backend model before frontend deep editing:

1. Add `job_stage_templates`:
   - id, name, is_default, archived_at, created_at, updated_at
2. Add template ownership to stages:
   - `job_stages.template_id`
   - unique/template scoped sort order
   - optional updated_at
3. Add job assignment:
   - `jobs.stage_template_id`
   - keep `jobs.current_stage_id`
4. Scope category mappings by template:
   - `job_stage_category_map.template_id` or derive through stage template but enforce uniqueness per template/category.
5. Migration/backfill:
   - create default template
   - attach existing 3 stages to it
   - assign existing jobs to default template
   - preserve `current_stage_id`
6. Service methods needed:
   - list/create/rename/archive templates
   - add/rename/archive/reorder stages transactionally
   - duplicate template
   - assign/change template for job with preview/validation
   - list category mappings for a template
7. Reorder must be transactional and preferably use sparse or normalized sort order after save.

## Frontend implementation requirements

1. Build `IOSJobStageTemplatesSettingsPage` or equivalent under admin/settings.
2. Add template list + template detail/editor.
3. Update `JobStageProgressBar` to be fully dynamic:
   - no 3-stage assumptions in comments/previews
   - compact behavior for 1, 2, 3, and many stages
4. Add job create/edit template picker.
5. Update job detail stage advancement to use the assigned template stages.
6. Add empty/loading/error states:
   - No templates: show default-template repair CTA
   - No stages in template: block assignment until at least one stage exists
   - Active jobs impacted: show confirmation sheet

## Acceptance criteria

- Admin can create a new stage template with 1+ stages.
- Admin can add, rename, and reorder stages and explicitly Save/Cancel changes.
- Existing jobs continue using the migrated default template with no visible data loss.
- A new job can be assigned a template and displays the correct number/order of stages.
- Job stage progress bar works with 1, 2, 3, 5, and 8 stages without crashes or unreadable overlap.
- Reordering stages preserves job current stage by stage ID, not by position/name.
- Attempting to remove a referenced/active stage is blocked or converted to archive with a clear explanation.
- Category-to-stage mappings are scoped to the selected template and unmapped categories are visible.
- GH #625 and Paperclip follow-up issues are referenced in implementation comments/PRs.

## Follow-up split

Recommended implementation work:

1. Backend: add stage template schema/services/migration and safe reorder/archive APIs.
2. Frontend: build admin stage template editor, job template picker, and dynamic progress bar behavior.

The backend should land first or in parallel behind feature-safe defaults. Frontend should not fake configurability by editing the global `job_stages` list without a template model, because that would make existing/active jobs unstable.
