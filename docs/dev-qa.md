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
