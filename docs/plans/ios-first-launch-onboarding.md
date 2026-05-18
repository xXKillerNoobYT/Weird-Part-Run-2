# iOS First-Launch Guided Onboarding Checklist Spec

> Source: WEI-813 / WEI-451 / GH#42 item T2-20
>
> Status: Design spec ready for CTO/CEO sign-off. Implementation can proceed as a follow-up engineering slice after this spec is approved.

## Goal

Give a brand-new WiredPart user a clear, non-blocking path from an empty dashboard to the minimum setup needed to make the app useful, without forcing warehouse setup or hiding the normal app shell.

The checklist should answer: "What should I do first?" It should not become a tutorial wall, a dark-pattern modal, or a blocker for users who already know what they need.

## Product principles

1. Non-blocking: users can dismiss or ignore the checklist and still use the app.
2. Persistent until resolved: the dashboard card remains visible until all required tasks are complete or the user dismisses it.
3. Recoverable: dismissal shows Undo immediately and can be reset from Settings later.
4. Permission-aware: users only see setup tasks relevant to their hat/permissions.
5. Progressive: each task links to the exact app surface where the user can do the work.
6. Motivating, not nagging: copy is helpful, short, and uses plain construction/field language.
7. Accessible by default: 44pt targets, VoiceOver labels, Reduce Motion-safe progress/celebration.

## Surface decision

Use a hybrid:

- First launch after login: optional welcome sheet.
- Dashboard after first launch: persistent "Getting Started" checklist card near the top of the Dashboard.
- Per-page guidance: lightweight contextual banner / "Try This" state when a checklist task routes into a module.
- Completion: brief celebration state, then card collapses or disappears.

Why not modal-only:

- A modal blocks experienced users.
- Setup takes multiple modules; forcing it all in one session is brittle.
- The app already has useful Tier 0 workflows before full setup is complete.

Why not card-only:

- First launch needs one friendly explanation of what WiredPart is and how setup works.
- The card alone can feel like unexplained empty-dashboard noise.

## Minimum useful setup inventory

Required tasks should be the smallest set that makes the app useful for a new company. Optional tasks unlock deeper workflows but should not block "done".

### Required tasks

1. Review company profile
   - Purpose: confirm company name/timezone/basic identity.
   - Route: Settings -> Company.
   - Completion signal: company profile opened once, or required fields saved when missing.

2. Add or confirm first job
   - Purpose: clock-in, orders, notes, and reports need a job context.
   - Route: Jobs -> Add Job / Jobs list.
   - Completion signal: at least one active job exists, or user confirms existing seeded job.

3. Add or confirm first part
   - Purpose: parts catalog is the heart of WiredPart.
   - Route: Parts -> Add Part / Parts list.
   - Completion signal: at least one part exists, or user confirms existing seeded part.

4. Add or confirm first supplier
   - Purpose: purchasing/receiving requires a supplier.
   - Route: Suppliers/Procurement settings.
   - Completion signal: at least one supplier exists.

5. Try one workflow action
   - Purpose: user learns how tasks become real work.
   - Route: one of: create JPO, scan barcode, clock in, or create notebook entry depending on permissions.
   - Completion signal: action launched or completed; if launched but cancelled, task can still count as "tried".

### Optional tasks

1. Configure warehouse layout
   - Route: Warehouse -> Configure Your Warehouse.
   - Rationale: useful, but not required for Tier 0 app use.

2. Invite team member
   - Route: People -> Employees / invite.
   - Rationale: only relevant for managers/admins.

3. Set notification preferences
   - Route: Settings -> Notifications.
   - Rationale: quality-of-life setup.

4. Explore AI assistant
   - Route: AI panel.
   - Rationale: tutorial/discovery, not required setup.

## Checklist states

### 1. Welcome sheet

Trigger:
- User is authenticated.
- `hasCompletedOnboarding` or equivalent setup flag is false.
- User has not explicitly skipped the welcome sheet.

Behavior:
- Shows once per user/profile unless reset.
- Primary action: "Show my checklist".
- Secondary action: "Skip for now".
- Does not mark the checklist dismissed; it only closes the welcome sheet.

Copy:
- Title: "Welcome to WiredPart"
- Body: "Set up the basics now, or jump in and come back anytime. We’ll keep your checklist on the Dashboard."
- Primary: "Show my checklist"
- Secondary: "Skip for now"

### 2. Not started dashboard card

Trigger:
- Required tasks incomplete.
- Checklist not dismissed.

Behavior:
- Appears above secondary dashboard content and below any urgent safety/account alerts.
- Shows progress count, first recommended task, and list of required tasks.
- Primary CTA routes to the next incomplete task.
- Secondary menu provides Dismiss, Reset, and Learn more.

Copy:
- Eyebrow: "Getting Started"
- Title: "Set up the basics"
- Body: "Do these first so jobs, parts, and ordering have enough information to work."
- CTA: "Start next step"
- Dismiss accessibility label: "Dismiss checklist"

### 3. In progress dashboard card

Trigger:
- At least one task completed and at least one required task incomplete.

Behavior:
- Shows completed count and remaining count.
- Highlights "Try This" next action.
- Uses determinate progress, not confetti.

Copy:
- Title: "You’re making progress"
- Body: "Next up: {task title}."
- CTA: "Continue setup"

### 4. Per-page guidance banner

Trigger:
- User arrives on a module from a checklist task.
- Task is incomplete.

Behavior:
- Banner is contextual and collapsible.
- No blocking overlay.
- Completion can be automatic if data exists, or manual with "I did this" for exploratory tasks.

Copy:
- Eyebrow: "Try This"
- Body examples:
  - Jobs: "Create or confirm one active job so time, notes, and orders have a place to land."
  - Parts: "Add or confirm one part so the catalog is ready for requests and receiving."
  - Warehouse: "Warehouse setup is optional. Start it when you’re ready to map shelves, bins, and zones."

### 5. Dismissed state with Undo

Trigger:
- User taps Dismiss on the checklist card.

Behavior:
- Card disappears.
- Toast/snackbar appears for at least 5 seconds with Undo.
- Settings exposes a reset path.
- Dismissal does not mark tasks complete.

Copy:
- Toast: "Checklist dismissed"
- Action: "Undo"

### 6. Completion state

Trigger:
- All required tasks complete.

Behavior:
- Shows celebration card once.
- Avoid spring animation when Reduce Motion is enabled.
- After acknowledgement, collapses to a small "Setup complete" affordance or disappears.

Copy:
- Title: "You’re All Set!"
- Body: "The basics are ready. You can keep exploring or adjust setup anytime in Settings."
- CTA: "Go to Dashboard"

## Viewport wireframes

These are text wireframes for layout intent. Exact visual styling should use existing app card, spacing, and typography tokens.

### iPhone 375 x 812

```text
┌───────────────────────────────────────┐
│ Dashboard                         ⚙︎  │
├───────────────────────────────────────┤
│ [Urgent alerts if any]                │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Getting Started              2/5 │ │
│ │ Set up the basics                 │ │
│ │ Do these first so jobs, parts,    │ │
│ │ and ordering can work.            │ │
│ │                                   │ │
│ │ ███████░░░ 40%                   │ │
│ │                                   │ │
│ │ ✓ Company profile                 │ │
│ │ ✓ First job                       │ │
│ │ ○ First part                      │ │
│ │ ○ First supplier                  │ │
│ │ ○ Try one workflow                │ │
│ │                                   │ │
│ │ [Continue setup]      [Dismiss]   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ KPI cards / Quick actions             │
│ ...                                   │
└───────────────────────────────────────┘
```

Rules:
- Card width follows standard dashboard margin.
- Buttons stack if localization/dynamic type needs space.
- Every tap target is at least 44pt high.

### iPad 768 x 1024

```text
┌────────────────────────────────────────────────────────────┐
│ Dashboard                                            ⚙︎    │
├────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────┐ ┌────────────────────────┐ │
│ │ Getting Started        2/5 │ │ Today / KPIs           │ │
│ │ Set up the basics          │ │                        │ │
│ │ ███████░░░ 40%            │ │                        │ │
│ │                             │ │                        │ │
│ │ ✓ Company profile          │ │                        │ │
│ │ ✓ First job                │ │                        │ │
│ │ ○ First part               │ │                        │ │
│ │ ○ First supplier           │ │                        │ │
│ │ ○ Try one workflow         │ │                        │ │
│ │                             │ │                        │ │
│ │ [Continue setup] [Dismiss] │ │                        │ │
│ └─────────────────────────────┘ └────────────────────────┘ │
│ Quick Actions / Recent Activity                            │
└────────────────────────────────────────────────────────────┘
```

Rules:
- Checklist can sit in the leading dashboard column.
- Keep progress and next CTA visible without scrolling.
- Secondary dashboard content must not jump dramatically when the card completes/dismisses.

### Desktop / Catalyst 1280 x 800

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ Sidebar        │ Dashboard                                           ⚙︎   │
│                ├──────────────────────────────────────────────────────────┤
│ Dashboard      │ ┌──────────────────────────────────────────────────────┐ │
│ Jobs           │ │ Getting Started                                  2/5 │ │
│ Parts          │ │ Set up the basics                                    │ │
│ Warehouse      │ │ Do these first so jobs, parts, and ordering work.    │ │
│ Orders         │ │ ███████░░░ 40%                                      │ │
│ Settings       │ │ ✓ Company profile  ✓ First job  ○ First part        │ │
│                │ │ ○ First supplier   ○ Try one workflow               │ │
│                │ │ [Continue setup]                         [Dismiss]  │ │
│                │ └──────────────────────────────────────────────────────┘ │
│                │ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐     │
│                │ │ KPI / Action │ │ KPI / Action │ │ KPI / Action │     │
│                │ └──────────────┘ └──────────────┘ └──────────────┘     │
└────────────────────────────────────────────────────────────────────────────┘
```

Rules:
- Checklist spans the main content width only, not the sidebar.
- Keyboard focus order enters the checklist after page title and before lower cards.
- Dismiss/Undo must be reachable by keyboard and VoiceOver.

## Data and state model

Use a small local state model backed by existing app storage/database patterns:

- `welcomeSeenAt`: Date?
- `checklistDismissedAt`: Date?
- `completedTaskIds`: Set<String>
- `lastFocusedTaskId`: String?
- `hasShownCompletion`: Bool

Task completion should prefer real data-derived checks over manual flags:

- Company profile exists and required fields valid.
- Active job count > 0.
- Part count > 0.
- Supplier count > 0.
- Workflow action launched/completed marker exists.

Manual flags are acceptable for exploratory tasks where "looked at this page" is the intended outcome.

## Accessibility requirements

- All buttons 44pt minimum.
- Progress has VoiceOver text: "2 of 5 setup steps complete".
- Checklist rows expose completion status: "Complete, Company profile" / "Incomplete, First part".
- Dismiss button label: "Dismiss checklist".
- Undo toast label: "Checklist dismissed. Undo."
- Completion animation respects Reduce Motion.
- Dynamic Type: list wraps cleanly at accessibility sizes; CTAs stack vertically if needed.
- Color is never the only state indicator.

## Analytics / diagnostics

If analytics hooks exist, record only product-safe events:

- onboarding_welcome_seen
- onboarding_checklist_started
- onboarding_task_completed(task_id)
- onboarding_checklist_dismissed
- onboarding_checklist_undo_dismiss
- onboarding_required_complete

Do not log part names, job names, supplier names, employee names, or free-text user input.

## Engineering implementation slices after sign-off

1. State model and task definitions
   - Add/confirm task IDs and completion resolvers.
   - Unit-test data-derived completion.

2. Welcome sheet
   - Render first-launch welcome with skip/show actions.
   - Add UI fixture for welcome state.

3. Dashboard checklist card
   - Render not-started, in-progress, dismissed, and complete states.
   - Add UI fixture for each state.

4. Route actions
   - Wire each task to the target app surface.
   - Add fallback behavior if a module is hidden by permissions.

5. Per-page guidance banner
   - Show contextual "Try This" banner for launched tasks.
   - Persist manual/exploratory completion.

6. Accessibility and screenshot verification
   - Verify iPhone 375x812, iPad 768x1024, desktop/Catalyst 1280x800.
   - Verify VoiceOver labels and Reduce Motion behavior.

## Acceptance criteria

1. A new user sees an optional welcome sheet on first launch.
2. Dashboard shows a persistent Getting Started card until required tasks are done or dismissed.
3. Checklist includes required tasks for company profile, first job, first part, first supplier, and one workflow action.
4. Warehouse setup is presented as optional, not a blocker.
5. User can dismiss the checklist and immediately undo dismissal.
6. User can reset/reopen onboarding from Settings.
7. Completion state appears after all required tasks are complete.
8. Three viewport layouts are verified: iPhone 375x812, iPad 768x1024, desktop/Catalyst 1280x800.
9. VoiceOver, Dynamic Type, 44pt targets, and Reduce Motion are verified.
10. Implementation follow-up issue(s) reference this spec and WEI-813.

## Sign-off recommendation

Approve this design for engineering if the owner agrees with the required task set. If the owner wants a shorter first-run path, remove supplier from required and leave it optional; otherwise this is the smallest useful business setup path for jobs, parts, and ordering.
