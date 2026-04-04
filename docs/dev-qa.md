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

### GitHub #26 — Fresh DB Crash: 10+ Pages Show "Something Went Wrong" on First Launch

**Plan:** *(none yet — needs plan document after Q&A answered)*
**Current State:**
- On a fresh install (empty SQLite database, no migrations run yet), 10+ iOS pages crash with a generic "Something went wrong" error
- Services assume data exists and fail to handle empty result sets gracefully
- `isTableNotFoundError` helper exists in most services (catches "no such table" / "no such column") but empty-result crashes are a different failure mode — they happen when migrations have run but no seed data exists yet
- Examples: Dashboard KPI tiles crash when no jobs/parts exist; Clock page crashes when no users are in the dispatch system; Warehouse pages crash when no locations are configured
- This blocks ALL first-launch testing and makes the app unusable out of the box

**What's needed (proposed):**
- Audit every service method to ensure it returns `[]` or a sensible default when DB is empty
- Pages should show empty states ("No jobs yet — tap + to create your first job") instead of error screens
- The onboarding wizard should prevent accessing crash-prone pages until minimal setup is done

**Affected Modules:** All — Dashboard, Jobs, Clock, Warehouse, Parts, Orders, People, Fleet, Chat, Reports, Settings, Notebooks, Tools

#### Questions:

1. **As the Owner:** Should the app be fully usable (all pages browsable) on a fresh install with no data, even if everything shows empty states? Or is it acceptable to lock certain sections behind a "setup required" gate until basic configuration is done?
   > Answer:Rewuired set is is good for some pages and having a gide that gose over that and asking Questions is good this will help make sure im setting up the app proprly for the companys use and to beable to go throw the gide agian at a later date trow the help menue to change settings would be good 

2. **As a Manager:** After a fresh install, what's the minimum setup needed before the app is useful? (e.g., must add at least 1 employee, 1 job category, or configure warehouse) — or should the app work "browse first, setup later"?
   > Answer: it should work Browse first set up later as long as theres working gide to do so that will walk me as a new user trow the prosses 

3. **As a Developer:** The safest fix is to audit all service methods that return arrays and ensure they return `[]` on empty DB instead of crashing. The more aggressive fix is to also audit single-entity fetches (getJob by ID) and ensure they return `nil` instead of crashing. Which scope is correct — just lists, or also single-item fetches?
   > Answer: (getJob by ID) and ensure they return `nil` instead of crashing. lets make sure that thing are working proply 

**Slots to fill:**
- [ ] Full browse on fresh install, or gated behind setup? gated behind setup not all pages are usable tell somthing is done I want the pages that cant be used locked tell the setup is done for them to work if the setup need's to be done on that page that's fine as well and not every page need's to be fully setup before it can be used like the wharehouse for exsample we may start having to put thing on the shelf and want to know that we have surten part's then we will be wanting to get counts later on, then later on well be wanting to set target levels, then later on well want the audit certinty high for that part, then well want that part auto added to the wish list as thing progres throw the level systome.
- [ ] Scope of fix: list methods only, or also single-entity fetches? Every thing full fixing 
- [ ] Should onboarding wizard prevent navigation to unready pages? Yes it should if the thing's havent been done to make that page ready yet are not yet done then the page should be unacsesable.

---

### GitHub #20 — Clock In/Out Completely Non-Functional

**Plan:** `docs/plans/ios-clock-page-redesign.md` *(exists — covers redesign; bug cause unknown)*
**Current State:**
- `IOSClockPage.swift` exists and has a clock in/out UI
- Users report the entire Clock In/Out flow is non-functional — nothing happens when tapping Clock In
- Likely causes: (1) fails silently on empty DB (#26 related — no dispatch entries), (2) GPS permission not granted, (3) questionnaire flow not wired, (4) service method returning error that's swallowed
- `IOSClockPage` has a flex pool dispatch failure path that shows `errorMessage` — so some error handling exists
- Clock data goes to `clock_entries` table; `JobsService.clockIn()` / `clockOut()` methods exist in core
- The existing plan (`ios-clock-page-redesign.md`) covers UI prompts 40A-B (to-do picker, live timer) — but the root bug needs fixing before UI enhancements

**What's needed (proposed):**
- Diagnose why `clockIn()` fails silently — add proper error surfacing to UI
- Verify `clock_entries` table is accessible on both fresh and seeded DB
- Fix the button action wiring if the tap target isn't connected to the service call
- This is separate from the redesign prompts (40A-B) — fix the bug first

**Affected Modules:** Jobs (Clock), Scheduling (dispatch entries)

#### Questions:

1. **As an Employee:** When you tap "Clock In", what should happen step by step? (Does it immediately clock you in, or does it prompt for job selection first? Is GPS required or optional?)
   > Answer: if GPS is not there it should ask for permishion the procice locashin is reqierd by Company opshins when the company is getting set up by the admin, it should sujest a job based of locashion and promt have an opshion to change the job if thats the case and the prompt is worng.

2. **As a Developer:** Should we investigate the bug by adding `print()` / `Logger` calls to the Clock In button action and service method to trace where it fails? Or is there already a known root cause from prior investigation?
   > Answer: yes do a deep dive investigasion this need's to be done proprly.
   
3. **As the Owner:** Is this blocking real users in production, or is it a QA-only issue? This affects priority — if workers can't clock in, it's emergency priority.
   > Answer: Users cant clock in it makes it hard to track time if this is not working.
   
**Slots to fill:**
- [ ] Root cause: empty DB, GPS, wiring, or service error?
- [ ] Fix scope: debug+fix only, or also wire the redesign prompts (40A-B)?
- [ ] Priority: emergency (workers blocked) or normal queue?

---

### GitHub #29 — Schedule Config Page Missing Critical Fields

**Plan:** *(none yet — needs plan document after Q&A answered)*
**Current State:**
- `IOSScheduleConfigPage.swift` exists
- Users report it's missing critical scheduling configuration fields
- Likely missing: per-role shift templates, holiday calendar input, shift start/end time definitions, overtime rules
- `SchedulingService` has basic config methods but the scope of the Config page is unclear
- This is a complex redesign — touching multiple areas of the scheduling system

**Affected Modules:** Scheduling, People (roles/shifts)

#### Questions:

1. **As the Owner:** What are the 3 most critical missing config fields in the Schedule Config page? (e.g., defining shift hours, setting holiday dates, assigning shift templates to job roles)
   > Answer: well every thing realy it's just an unusable calinder at this point.

2. **As a Manager:** Should Schedule Config be role-aware (different shift templates for different job hats)? Or is it one global schedule that applies to everyone?
   > Answer: it should be Role-aware

3. **As a Developer:** Should this be a full-page redesign (new UI layout), or additive (add the missing fields to the existing page)? A redesign would need a new Xcode prompt; additive could be done directly.
   > Answer: it more additive the base layout we have is good but it's missing almost every thing in the plan.
   
**Slots to fill:**
- [ ] Top 3 missing fields (from owner)
- [ ] Per-role shifts or global schedule?
- [ ] Redesign or additive?

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
   > Answer: separate tab on the Scheduling page. that put evey thing in one place and need's spacel reqiermints for making sure thing are gone over in detail. 

2. **As a Manager:** Who can mark a job as "flex pool"? Only the manager/dispatcher via the Job Detail page? Or is there a batch action on the Scheduling page to push jobs into the pool? And can a manager pull a flex job back out of the pool after it's been claimed?
   > Answer: yes only mangers and they should be able to filter the opsions to teams or people that can take the job not every job is good for every person or team. and once it's clamed it becomes an ative job and can still be put on holed or canseled at that point by a person with proper prmishions.

3. **As an Employee (field):** Should a worker see ALL flex pool jobs or only jobs that match their skills/location? The plan says flex jobs show "Skills needed: Journeyman" — does the app need to filter by the worker's current certifications/hats, or just show all available?
   > Answer: All Available to them the manger will filter it for them when adding a job to the pool

4. **As a Developer:** The claim action changes `assigned_user_id` on the job. Does claiming also automatically create a `dispatch_entries` row (so it shows up on the job's dispatch history), or is it a direct job update only? Dispatch entries exist in the schema — should `claimFlexJob` write one?
   > Answer: it should mack the person / team the clamed it the lead for the job that should be an opshion that can be changed later.

5. **As a User (UX):** The plan shows a "Claim" button on each flex job card. Should claiming require a confirmation ("Are you sure you want to claim this job?") or is one-tap fine since the manager can override? Also: after claiming, does the app navigate to the job detail, or stay on the flex pool list?
   > Answer: yes it should ask are you sure then navigate to that job page with the dashborad the details the job notebook order histry and all the info tied to that job. NOTE: this can be overriden by the manger and the company can set a manger must approve first opshion that why, and when that happen it should show a message pending aprovel.

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
   > Answer: Per a color varoant, each color has it's own part number from the supplyer and we should as well.

2. **As a Manager:** When viewing the hierarchy tree, what level should show the part number field — Brand, Type, or Color?
   > Answer: Color do to that being the point that part number's are done by the manfaters and what the supplyer use. and there should be an opsionel Supplyer Part number for each supplyer at this level as well it would make ording easyer.

3. **As an Employee:** When looking up a part to order, do you search by color + part number, or by category then drill down?
   > Answer: Any of the above and somtimes not in order for esample [GFIC red outlet] or use shorts like RD for red or even traid names sometimes.

4. **As a Developer:** Should hierarchy tree expansion state be persisted in UserDefaults (per session) or in the database (per user)? UserDefaults is simpler but resets on app restart. DB is more work but truly persistent.
   > Answer: per session
---

### GitHub #47 — Brands & Suppliers Editing + Brand-Supplier Linking

**Current State:** `PartsBrandsPage.swift` and `PartsSuppliersPage.swift` exist with `BrandSupplierPickerSheet` already written. The sheet may not be triggered from the correct locations, and the full edit flow may be broken.

**Issues raised:**
1. No visible way to edit a Brand or Supplier from their respective pages
2. Need to link which brands a supplier carries (on the Supplier side)
3. Need to link which suppliers carry a brand (on the Brand side)

#### Questions:

1. **As an Owner:** On the Brands page, should you see a list of suppliers who carry that brand, OR should brand-supplier linking only be done from the Supplier side?
   > Answer: On the Brands page there should be a list of suppliers that carry that brand and the list should be editable that way its easy to update.

2. **As a Manager:** When adding a new brand, should the system prompt "which suppliers carry this brand?" or leave it for later?
   > Answer: Should prompt "which suppliers carry this brand?" and have the list avable to pick the supplyer that are in the list but should let me leave for later if i want to make it ornge if theres not at least one supplyer picked.
   
3. **As a Developer:** `BrandSupplierPickerSheet` exists — is the intent for this to appear when tapping a Brand row (to select which suppliers carry it), or only from the Supplier detail page?
   > Answer: On the Brands page I want the supplyer listed and the rever on the the supplyer page to show the brands that they cary with opshins like need to order or cary on the shelf NOTE: this is an over all for the brand but as parts are orderd that should be bilt up in the parts histry.
   
---

### GitHub #48 — Parts → Pricing UI Mostly Unbuilt

**Current State:** Migration 025 added the pricing system schema. `PricingService` exists in core. The iOS Parts → Pricing page has little to no UI for editing price tiers, viewing price history, or managing margins.

**Issues raised:**
1. Can't edit prices from the UI
2. No price history view
3. No margin editor

#### Questions:

1. **As an Owner:** What's the most critical pricing function to build first: viewing current prices, editing price tiers, or seeing price history?
   > Answer: viewing current prices + setting the gennrol cost Pluse the ablity to add a difrint cost per a supplyer. 

2. **As a Manager:** Should pricing be editable from the Parts Catalog page (inline per part), OR only from the Parts → Pricing dedicated page?
   > Answer: should be editable in the parts catalog page inline per a part using the castscading methoted from as high up as type down to color. NOTE: this is for setting the inisel price the systome will start bilding and getting prices when updating at the color level.

---

### GitHub #49 — Warehouse Setup — Optional + Incomplete

**Current State:** Warehouse Setup Wizard exists but has UX issues (assigns everything to Row 1, optional setup not truly optional).

**Issues raised:**
1. Setup should be optional — users should be able to skip it
2. Many parts of the wizard aren't finished
3. The onboarding flow forces warehouse setup when user may not need it

#### Questions:

1. **As an Owner:** Can a worker use the app (clock in, view parts, process orders) without completing warehouse setup? Or is warehouse setup a prerequisite?
   > Answer: yes they should be able to clock in view part's & process order's befor the full setup there are 2 flows that need to work together before the full setup is done.
   
   the Part's flow!
   1. the part's list. NOTE: the locashions can be assied once this much is known 
   2. then the count for each part.
   3. the locashion NOTE: this is where it ties into the other flow and should work satndalown with out the other flow it just provides more info and helps the app work better.

   Wharehouse Floor plan!
   1. The Size
   2. the Arias/Zones inside. + zone type Such as staging, storage, returns, and so on. there more in the plans.
   3. the units for storage and sorting in the zones.
   4. the Placmint this is very inprotant and has not been done as for as i can tell in the code, we need to know the row in the zone for that unit have it placed on the floor paln and have the full floor paln layed out before this continues.
   5. then we need to know the shelvs for each unit or eqwvlint for the storge type.
   6. then on the storge types that this applys to such as shelves we need to know the aria on each self for exsample.
   7. then the type of thing being stroed there such as a kit, tool, part's, & supplys for mantnice or what ever. this is per an aria on the shelfs.
   8. once that is done if its kits or tools those will need to be asinable for that info and tied to that systome. if its for parts we need to know if open storage or bins.
   9. if it's bins we will want a count for the bins included.
   10. then adding the the Listed part from the parts catalog to the bin or open aria an open aria may have severl part's NOTE: this is where if we have parts on the parts list well want to get lost tied to an open aria or a bin.
   11. after all that well want to make sure we have a count of the parts and every thing done once thats been done for every storage unit in the shop the setup is compleat we want to be able to stop at any time save and resome working the way down from an over view to detaild layout and the curent wixerd is too pushy and dousnt work it's way throw enufe details to have proper sorting. 
   12. NOTE: we want to be able to go back and edit at any point.
   13. NOTE: part's get assiend to a bin or open aria but can get moved at any time.
   14. NOTE: bins are a small box that sits on the shelf there not locashion locked and I want to be able to move them at any time to idetify them we need a bin number.

1. **As a Manager:** In the warehouse wizard, should the app ask users to define their row/shelf layout before placing items, or is visual drag-and-drop placement enough?
   > Answer: I want this to work as a visel drage and drop metoed from placing the shelfs on the wharehouse floor paln to other aria but when it comes to more detailed work like bin Number= aria I weant that to be more of a menue and to have a holing mode for sevel bins/parts if there getting moved called a cart saying this is is going to the cart. then when removing from the cart haveing where that's placed the shelf the row the aria is very inportant. 
   1. we have a wharhouse that is setup patly but is a mess we need to be able to add and sort things as need so we can take are time getting the wharehouse intergrated proply that whay we are not rushed and make mustakes that could easly be avoided by taking are time.

---

### GitHub #50 + #51 — Badge Counts + App-Wide Action Visibility

**Current State:** No badge counts on nav tabs. Action buttons (accept/reject, approve, clock out) are styled uniformly with no extra prominence for pending-action items. Users have no visual thread from nav → list → action.

**Issues raised:**
1. Nav tabs should show badge counts for pending items
2. List rows with pending actions should have a visual indicator (red border/number badge)
3. Action buttons should be more visually prominent — circled, bordered, or color-emphasized
4. A consistent 'action required' visual language is needed across the entire app

#### Questions:

1. **As an Owner:** Which tabs/sections should show badge counts? (e.g., Approvals, Scheduling, Orders, Warehouse Receiving — or all of them?)
   > Answer: all of them? updated pages in the notebook on a project that i am part of all of it i know there's a lot but it needs to be done mably have the newer ones look green and the oldest one be red?

2. **As a Manager:** Should badge counts be real-time (live DB query on each tab view) or periodic (refreshed every X minutes via background task)?
   > Answer: real-time (live DB query on each tab view) allway up to date.

3. **As a Developer:** Should badge rendering use SwiftUI native `.badge()` on `TabItem`/`NavigationLink` rows, or custom red circle overlays? Native is simpler but limited; custom allows full design control (borders, animation).
   > Answer: Native is good as long as there is numbers and cloror control 

4. **As a User:** For action buttons (accept/reject/approve), should the visual prominence be: (a) bold red/green border ring around the button, (b) larger button size, (c) fill color instead of tinted outline, or (d) all three?
   > Answer: A

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
