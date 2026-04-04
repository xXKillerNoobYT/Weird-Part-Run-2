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

> *(None — all questions answered as of 2026-04-04)*
>
> Answers integrated into plan docs:
> - **#26 (Fresh DB crash)** → `docs/plans/ios-fresh-install-resilience.md`
> - **#20 (Clock In/Out bug)** → `docs/plans/ios-clock-fix.md` + Xcode prompt PE-031
> - **#29 (Schedule Config)** → `docs/plans/ios-schedule-config-redesign.md` + Xcode prompt PE-032
> - **PE-003 (Flex pool)** → `docs/plans/ios-flex-pool.md` (needs DB migration before Xcode prompt)
> - **#46 (Part number hierarchy)** → `docs/plans/ios-part-number-hierarchy.md` + Xcode prompt PE-027
> - **#47 (Brands/Suppliers editing)** → `docs/plans/ios-brands-suppliers-editing.md` + Xcode prompt PE-028
> - **#48 (Pricing UI)** → `docs/plans/ios-pricing-ui.md` + Xcode prompt PE-029
> - **#49 (Warehouse setup)** → `docs/plans/ios-warehouse-setup-redesign.md` + Xcode prompt PE-030
> - **#50/#51 (Badge counts + visibility)** → `docs/plans/ios-badge-counts.md` + Xcode prompt PE-026

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
