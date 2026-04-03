# WiredPart Q&A — Requirements & Design Questions

> **Purpose:** Before building any feature, questions are generated here for the owner to answer.
> Questions are organized by feature/change with role-based perspectives.
> **Auto-maintained by:** dev-pipeline-manager scheduled task

---

## How This Works

1. When a new plan is added or a GitHub issue is filed, questions appear here
2. Each question includes context about the current build and proposed changes
3. Questions are tagged by role perspective: Owner, Manager, Employee, Developer, User
4. Answer the questions by editing this file (write answers below each question)
5. Once answered, the dev-pipeline-manager integrates answers into the plan and **removes the question from this file**
6. Unanswered questions block the feature from being auto-built
7. **This file only contains unanswered/unprocessed questions.** Once processed, they're gone — design decisions live in `docs/plans/`.

---

## Pending Questions

---

### PE-003 — Flex Pool Self-Assign on Scheduling Page

**Plan:** `docs/plans/ios-scheduling-pages.md` — Section 6: Flex Pool
**Current State:**
- `jobs` table has no `is_flex_pool` column — flex pool concept exists only in the plan spec
- `SchedulingService` has no `fetchFlexPool()` or `claimFlexJob()` methods
- `IOSSchedulingPage.swift` shows Dispatch and Calendar tabs — no flex pool section
- `self_assign_flex` permission key exists in `AuthService.defaultPermissionMap()` and in the Permissions UI (added 4e0d5e0)

**What's needed before Xcode prompt:**
1. DB migration: add `is_flex_pool BOOLEAN DEFAULT 0` to `jobs` table
2. `SchedulingService.fetchFlexPool()` — returns active jobs where `is_flex_pool = 1` and `assigned_user_id IS NULL`
3. `SchedulingService.claimFlexJob(jobId:userId:)` — sets `assigned_user_id = userId`, `is_flex_pool = 0`
4. UI section in Scheduling or Dashboard showing available flex jobs (gated on `self_assign_flex` permission)

**Affected Modules:** Scheduling, Jobs
**Dependencies:** `self_assign_flex` permission key (exists ✅); `jobs` table (needs migration)

#### Questions:

1. **As the Owner:** Should flex pool jobs be a separate tab on the Scheduling page, or a section on the employee's Dashboard? The plan says "workers see available flex pool jobs on their Dashboard" — but the Scheduling page is the natural home for dispatch/assignment UX. Where should it live?
   > Answer: _pending_

2. **As a Manager:** Who can mark a job as "flex pool"? Only the manager/dispatcher via the Job Detail page? Or is there a batch action on the Scheduling page to push jobs into the pool? And can a manager pull a flex job back out of the pool after it's been claimed?
   > Answer: _pending_

3. **As an Employee (field):** Should a worker see ALL flex pool jobs or only jobs that match their skills/location? The plan says flex jobs show "Skills needed: Journeyman" — does the app need to filter by the worker's current certifications/hats, or just show all available?
   > Answer: _pending_

4. **As a Developer:** The claim action changes `assigned_user_id` on the job. Does claiming also automatically create a `dispatch_entries` row (so it shows up on the job's dispatch history), or is it a direct job update only? Dispatch entries exist in the schema — should `claimFlexJob` write one?
   > Answer: _pending_

5. **As a User (UX):** The plan shows a "Claim" button on each flex job card. Should claiming require a confirmation ("Are you sure you want to claim this job?") or is one-tap fine since the manager can override? Also: after claiming, does the app navigate to the job detail, or stay on the flex pool list?
   > Answer: _pending_

**Slots to fill:**
- [ ] Location: Scheduling page tab OR Dashboard section?
- [ ] Who can mark a job as flex pool?
- [ ] Filter by worker skills/certs, or show all?
- [ ] Does claim write a dispatch_entry row?
- [ ] Confirmation on claim: yes or no?

---

### GitHub #46 — Part Number Location + Hierarchy Persistence

**Current State:** Part hierarchy tree collapses/resets on every data change. Part numbers are shown at the brand level but user wants them at the color level (each color variant has its own part number).

**Issues raised:**
1. Hierarchy tree state resets when any change is made (expansion state lost)
2. Part numbers should be at the color level, not the brand level
3. Each color should show its own full part number (not a constructed prefix/suffix)

#### Questions:

1. **As an Owner:** Do you want part numbers unique per color variant, OR per type within a brand? E.g., is "Romex 12/2 White" a different part number from "Romex 12/2 Gray"?
   > Answer: _pending_

2. **As a Manager:** When viewing the hierarchy tree, what level should show the part number field — Brand, Type, or Color?
   > Answer: _pending_

3. **As an Employee:** When looking up a part to order, do you search by color + part number, or by category then drill down?
   > Answer: _pending_

4. **As a Developer:** Should hierarchy tree expansion state be persisted in UserDefaults (per session) or in the database (per user)? UserDefaults is simpler but resets on app restart. DB is more work but truly persistent.
   > Answer: _pending_

---

### GitHub #47 — Brands & Suppliers Editing + Brand-Supplier Linking

**Current State:** `PartsBrandsPage.swift` and `PartsSuppliersPage.swift` exist with `BrandSupplierPickerSheet` already written. The sheet may not be triggered from the correct locations, and the full edit flow may be broken.

**Issues raised:**
1. No visible way to edit a Brand or Supplier from their respective pages
2. Need to link which brands a supplier carries (on the Supplier side)
3. Need to link which suppliers carry a brand (on the Brand side)

#### Questions:

1. **As an Owner:** On the Brands page, should you see a list of suppliers who carry that brand, OR should brand-supplier linking only be done from the Supplier side?
   > Answer: _pending_

2. **As a Manager:** When adding a new brand, should the system prompt "which suppliers carry this brand?" or leave it for later?
   > Answer: _pending_

3. **As a Developer:** `BrandSupplierPickerSheet` exists — is the intent for this to appear when tapping a Brand row (to select which suppliers carry it), or only from the Supplier detail page?
   > Answer: _pending_

---

### GitHub #48 — Parts → Pricing UI Mostly Unbuilt

**Current State:** Migration 025 added the pricing system schema. `PricingService` exists in core. The iOS Parts → Pricing page has little to no UI for editing price tiers, viewing price history, or managing margins.

**Issues raised:**
1. Can't edit prices from the UI
2. No price history view
3. No margin editor

#### Questions:

1. **As an Owner:** What's the most critical pricing function to build first: viewing current prices, editing price tiers, or seeing price history?
   > Answer: _pending_

2. **As a Manager:** Should pricing be editable from the Parts Catalog page (inline per part), OR only from the Parts → Pricing dedicated page?
   > Answer: _pending_

---

### GitHub #49 — Warehouse Setup — Optional + Incomplete

**Current State:** Warehouse Setup Wizard exists but has UX issues (assigns everything to Row 1, optional setup not truly optional).

**Issues raised:**
1. Setup should be optional — users should be able to skip it
2. Many parts of the wizard aren't finished
3. The onboarding flow forces warehouse setup when user may not need it

#### Questions:

1. **As an Owner:** Can a worker use the app (clock in, view parts, process orders) without completing warehouse setup? Or is warehouse setup a prerequisite?
   > Answer: _pending_

2. **As a Manager:** In the warehouse wizard, should the app ask users to define their row/shelf layout before placing items, or is visual drag-and-drop placement enough?
   > Answer: _pending_

---

## Question Template

When generating questions, use this format:

```
### [Feature Name] — [Brief Description]
**Plan:** `docs/plans/[file].md`
**Current State:** [What exists now]
**Proposed Change:** [What would change]

#### Questions:

1. **As an Owner:** [Business/ROI question]
   > Answer: _pending_

2. **As a Manager:** [Workflow/oversight question]
   > Answer: _pending_

3. **As an Employee:** [Daily usage question]
   > Answer: _pending_

4. **As a Developer:** [Technical/integration question]
   > Answer: _pending_

5. **As a User:** [UX/experience question]
   > Answer: _pending_
```
