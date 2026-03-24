# 28D — Job Stage Planner (was Order Staging)

> **Chain position:** 28A → 28B → 28C → **28D**
> **Prerequisite:** 28C complete (PO generation)
> **Plan:** `docs/plans/ios-procurement-page.md` — Section 2, Job Stage Planner

## Instructions

Read the plan Section 2. This is a REDESIGN of `IOSOrderStagingPage.swift` into a Job Stage Planner. When done, wait for user confirmation.

## Context

Construction jobs have stages (Rough-in, Prep/Makeup, Trim-out). Parts are needed at different stages. This page shows ALL parts across ALL JPOs for a specific job, grouped by stage. Parts for future stages are "held" and auto-release when the current stage completes.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSOrderStagingPage.swift` — complete rewrite
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add stage-related methods
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — job_stages table + category mapping

## Task

### Step 1: Migration — job stages + category mapping

```swift
// New migration:
// job_stages: id, name, sort_order, created_at
// job_stage_category_map: id, stage_id, category_id
// Add stage_id column to jpo_lines (auto-assigned from category)
// Add current_stage_id to jobs table
// Seed 3 default stages: Rough-in, Prep/Makeup, Trim-out
```

### Step 2: Service methods

- `getJobStages()` — list all stages in order
- `getJobStageParts(jobId:)` — all JPO parts for a job, grouped by stage (via category→stage mapping)
- `markStageComplete(jobId:stageId:)` — marks stage done, auto-releases held parts for next stage to procurement
- `requestEarly(jpoLineId:)` — overrides the hold, releases to procurement early
- `updateCategoryStageMapping(categoryId:stageId:)` — settings CRUD

### Step 3: Rewrite IOSOrderStagingPage

- Job picker at top (or auto-fill from current job)
- Sections per stage with current stage highlighted
- Parts in current stage: show status (ordered, pending, received)
- Parts in future stages: show "HELD — releases after [stage] complete"
- [Release to Procurement] and [Request Early] buttons on held sections
- "Missing Parts" section at bottom if common parts for that stage aren't in any JPO
- Smart card filters: by stage (Stage 1 | Stage 2 | Stage 3 | All)

### Step 4: Stage settings (add to Settings area)

A settings view for configuring stages and category→stage mappings. Can be a sheet or a Settings sub-page. Allow: rename stages, reorder, add/remove, map categories to stages.

## Success Criteria

- [ ] Migration creates job_stages, category mapping, seeds 3 defaults
- [ ] Service methods for stage CRUD + parts grouping
- [ ] Page rewritten with job picker + stage sections
- [ ] Held parts show with [Request Early] button
- [ ] Auto-release when stage marked complete
- [ ] Smart card filters by stage
- [ ] Stage settings UI (at least basic CRUD)
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding.**
