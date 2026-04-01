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

### PE-022 — Hat Assignment & Access Control UX (GitHub #17)

**Plan:** `docs/plans/ios-hat-assignment-ux.md`
**GitHub Issue:** [#17](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/17) — "User Aces controles" (filed 2026-03-31)

**Current State:**
- `IOSHatsPage` — lists all hats with member count badge, supports create/delete. Rows are NOT tappable. No way to see which employees have a hat from this page.
- `IOSPermissionsPage` — hat × permission matrix, fully functional. Accessible via route `people-permissions` but NOT linked from the People Dashboard.
- `IOSEmployeeDetailPage` — has a "Hats" tab where you can toggle hat assignments ON/OFF per employee (requires `manage_hats` permission). Functional but buried 2 taps deep inside employee detail.
- `IOSPeopleDashboardPage` — has tiles for Employees, Customers, Contractors, Contacts, Teams. No tiles for Hats or Permissions.
- Recent fix (4e0d5e0): 10 permission keys were invisible in the Permissions UI — now fixed.

**Proposed Change:**
1. Make hat rows tappable in `IOSHatsPage` → open `HatDetailSheet` showing member list + add/remove employees
2. Add "Hats & Roles" and "Permissions" navigation tiles to the People Dashboard
3. Add `getHatMembers(hatId:)` to `PeopleService` (core Swift edit — not Xcode prompt)
4. Improve the Hats tab label in EmployeeDetailPage to show count badge

**Affected Modules:** People, Auth/Permissions
**Dependencies:** `PeopleService.toggleHatAssignment()` exists ✅; `getHatMembers()` needs to be added

#### Questions:

1. **As the Owner:** The Hats & Permissions pages exist but aren't linked from the dashboard — users can't find them easily. Should Hats and Permissions appear as top-level tiles on the People Dashboard visible to everyone with `view_people`, or only to users with `manage_people`? (Showing read-only to non-admins could help employees understand their own access level.)
   > Answer: _pending_

2. **As a Manager:** When you open a hat's detail sheet and see the member list, should there be a quick way to navigate directly to an employee's full profile from there? Or is the member list just for viewing/adding/removing hat membership?
   > Answer: _pending_

3. **As an Employee (field):** Can a regular employee see which hats they have assigned, and can they see what permissions those hats give them? Right now they can see their hats in their own Employee Detail page but can't see what permissions each hat grants. Should they be able to?
   > Answer: _pending_

4. **As a Developer:** The plan proposes adding `getHatMembers(hatId:)` to `PeopleService` as a direct Swift edit (not an Xcode prompt). It's a simple query (~5 lines). Should I do this now as part of PE-022 core prep, or wait until the Xcode prompt is written and bundle it with that?
   > Answer: _pending_

5. **As a User (UX):** The hat detail sheet proposes showing a "Permission Summary" (first few permission keys with "and N more" and an "Edit Permissions →" button). Is that the right cross-link, or would you prefer the hat detail sheet to be purely about member management, with permissions staying on the separate Permissions page?
   > Answer: _pending_

**Slots to fill:**
- [ ] Who sees Hats/Permissions tiles on dashboard? (everyone with view_people, or only manage_people?)
- [ ] Can employees see their own permissions list, or just their hat names?
- [ ] Should hat detail show a navigate-to-employee shortcut?
- [ ] Permission summary in hat detail: yes or no?

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
