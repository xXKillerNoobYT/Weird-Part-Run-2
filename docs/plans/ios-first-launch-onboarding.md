# First-Launch Guided Onboarding — Design Spec

> **Issue:** WEI-813 ([T2-20] First-launch guided onboarding checklist — design spec)
> **Slice of:** WEI-451 / GH #42
> **Status:** APPROVED FOR IMPLEMENTATION — engineering split filed 2026-05-12
> **Owner (design):** UXDesigner
> **Created:** 2026-05-12
> **Targets:** iPhone 375×812 · iPad 768×1024 · Desktop 1280×800 (forward-looking; current build is iOS-only per `CLAUDE.md`)

---

## 1. Problem

A brand-new user installs the app and lands on the Dashboard. With no data, the Overview tab renders empty KPI cards (`0 active jobs`, `0 employees`, `$0 spent`), and no guidance tells them where to start. The app has thirteen feature areas and 87 pages; without a path, first-run users churn before reaching their first successful action (clocking in to a job).

What already exists today:

- `xcode-ai/fix-prompts/done/60H-first-launch-checklist.md` — partial implementation: a 4-step card on Dashboard, dismissable via `@AppStorage("onboarding_checklist_dismissed")`. Gaps: no full-screen welcome, no undo, no celebration on completion, navigation taps are stubbed (`TODO`), no responsive design, no copy review, no analytics, no recommended-vs-required split.
- `Weird Parts IOS/Weird Parts IOS/Shared/OnboardingTasks.swift` — a **separate** registry of per-page tutorial tasks (e.g., "Tap a KPI card", "Search for a part"). This is the per-page banner system (`OnboardingBanner`) and is **out of scope** for this spec. The two systems coexist: first-launch teaches *what to set up*; per-page teaches *how each screen works*.
- `@AppStorage("hasCompletedCompanySetup")` already exists in `DashboardView.swift` and is referenced by the company setup wizard sheet — this spec consumes that flag, does not redefine it.

---

## 2. Goals

| Goal | Why |
|------|-----|
| Get a single-person shop from cold install to "clocked into a first job" in under 60 seconds. | First success unlocks every other feature. |
| Show new users the *minimum* path; surface deeper setup as recommended, not required. | Avoid the 12-step wizard that scares people off. |
| Be dismissable without losing the work; never re-prompt unless the user asks. | Respect users who already know what they're doing (migrators, second-device installs). |
| Reach completion state with a small moment of celebration, then disappear. | Reward, don't nag. |
| Be accessible (Dynamic Type, VoiceOver, 44pt targets) at all three viewports. | Production bar per `CLAUDE.md`. |

### Non-goals

- Importing data from competitor apps (separate epic).
- Teaching the user how to *use* each page — handled by `OnboardingBanner` per-page system.
- Multi-user role-aware onboarding (e.g., different flow for "Office" vs "Tech") — v2.

---

## 3. The Setup Inventory — What a New User Actually Needs

Audited against the 22 core services and 87 pages. The **minimum** for the app to be usable:

| # | Setup Item | Why it's needed | Required? | Completes when… |
|---|------------|-----------------|-----------|-----------------|
| 1 | **Company info** | Name on reports/POs, time zone for clock math, week-start day | **Required** | `hasCompletedCompanySetup == true` (CompanySetupWizard) |
| 2 | **Add yourself / first employee** | Clock-in needs a `user_id`; reports need a name | **Required** | `SELECT COUNT(*) FROM employees WHERE deleted_at IS NULL > 0` |
| 3 | **Create your first job** | Clock-in is bound to either a job or "Shop". Without a job, the app's center of gravity (Jobs) is empty | **Required** | `stats.activeJobs > 0` |
| 4 | **Add a supplier** | Parts need a source; POs can't be drafted without one | Recommended | `SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL > 0` |
| 5 | **Add or import parts** | Catalog needs content for forecasting, ordering, scanning | Recommended | `stats.totalParts > 0` |
| 6 | **Configure your warehouse** | At least one location/bin so stock can be tracked physically | Recommended | `SELECT COUNT(*) FROM warehouse_locations WHERE deleted_at IS NULL > 0` |
| 7 | **Theme** | Personalization | Optional (skippable, never blocks completion) | User taps "Set theme" once OR taps "Skip" |

**Why this split:** the Required three are the smallest set that lets a user clock in to real work. Recommended three turn the app from "time clock" into "inventory & ordering platform". Theme is included because it's the lowest-friction tap a user can make to start owning the app, and serves as a "you can dismiss this whole thing" escape hatch.

---

## 4. Surface — Hybrid (Sheet + Persistent Card)

Three surfaces considered:

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A. Modal on every cold launch** | Hard to miss | Annoying after first session; blocks resumed work; dark-pattern-adjacent | ❌ Reject |
| **B. Dashboard card only** | Calm; in-context; easy to ignore | Easy to *miss* on first launch when user is overwhelmed | ❌ Reject as the only surface |
| **C. Hybrid: one-time welcome sheet + persistent card** | High-attention moment for first touch, low-pressure return surface | Two pieces to build | ✅ **Chosen** |

### 4.1 Welcome sheet — fires ONCE

- Trigger: `!UserDefaults.standard.bool(forKey: "firstLaunchSheetSeen")` AND `isFirstLaunchState` AND app is settled (not from a deep link, not from a sync wake).
- Presentation: `.sheet(isPresented:)` with `.interactiveDismissDisabled(false)` (swipe to dismiss is allowed — see Section 7).
- Content: greeting, three-bullet "here's what the next 60 seconds look like", a single primary CTA "Start setup" that scrolls the Dashboard to the checklist card, and a secondary "I'll explore on my own" that closes the sheet and dismisses the card too (one tap = full opt-out, per Section 7).
- Persistence: setting `firstLaunchSheetSeen = true` happens on **any** dismissal (CTA, swipe, secondary).

### 4.2 Persistent Dashboard card — until completed or dismissed

- Lives at the top of the Dashboard Overview tab, between `clockStatusBanner` and `kpiSection` (matches the slot used by prompt 60H).
- Visible while: `isFirstLaunchState && !checklistDismissed` OR `checklistProgress > 0 && checklistProgress < 1.0 && !checklistDismissed`.
  - i.e., once a user starts the checklist, it persists *even if their data crosses the "first launch" threshold* — completing step 1 shouldn't make the card vanish before they finish step 2.
- Auto-collapses to a thin "5 of 6 complete — finish setup" strip when minimized.
- On full completion: 1.5s celebration state ("You're all set up!"), then auto-fades and sets `checklistDismissed = true`.

---

## 5. States

| State | Trigger | UI |
|-------|---------|----|
| `welcome` | First cold launch, no data | Full-screen sheet (4.1) |
| `not-started` | Sheet dismissed, no steps completed | Dashboard card, all rows un-checked, progress `0 / 6` |
| `in-progress` | At least one required step done | Dashboard card, mixed rows, progress bar reflects required-weighted completion |
| `required-done-recommended-pending` | All 3 required done, recommended outstanding | Card collapses to thin strip "Required setup done · 3 optional steps left", expand to see recommended |
| `all-done` | All 6 steps done | 1.5s celebration overlay → card fades out → `checklistDismissed = true` |
| `dismissed` | User taps × on card | Card hidden; toast "Setup hidden. Re-show in Settings → Help." with **Undo** action (10s) |
| `dismissed-with-undo` (transient) | First 10s after dismissal | Toast Undo restores the card and clears `checklistDismissed` |

### Progress math

- Progress bar = `requiredCompleted / 3` (denominator is required-only; recommended steps don't gate the bar visually but do gate `all-done`).
- "X of 6 complete" caption counts everything for transparency.
- A step is `complete` strictly from data presence (Section 3 right column), never from a "user tapped here" flag. Re-deleting all data (e.g., wiping the device) re-arms that step.

---

## 6. Copy

Tone: warm, concrete, non-urgent. No exclamation marks except the celebration moment. No countdown timers. No "Don't miss out" framing.

### Welcome sheet

| Slot | Copy |
|------|------|
| Title | `Welcome to WiredPart` |
| Subtitle | `A quick setup to get you running.` |
| Body bullet 1 | `Tell us about your company` |
| Body bullet 2 | `Add yourself and your first job` |
| Body bullet 3 | `Bring in parts and a supplier when you're ready` |
| Primary CTA | `Start setup` |
| Secondary | `I'll explore on my own` |
| Tiny footer link | `You can re-open this anytime in Settings → Help.` |

### Dashboard card header

| Slot | Copy |
|------|------|
| Card title | `Get set up` |
| Card subtitle (in-progress) | `Finish 2 more steps to start tracking jobs.` (rewrites based on what's left — see table below) |
| Progress caption | `3 of 6 complete · 2 required left` |
| Dismiss button (aria) | `Hide setup checklist` |

### Row copy

| Step | Title | Helper (1 line, ≤60 chars) | Tap action |
|------|-------|----------------------------|------------|
| 1 | `Set up your company` | `Name, time zone, week start.` | Open CompanySetupWizard sheet |
| 2 | `Add yourself` | `So you can clock in and show up on reports.` | Navigate to `people-employees` with "+ Add" pre-armed |
| 3 | `Create your first job` | `Jobs are the home for time, parts, and notes.` | Open the existing `.createJob` sheet |
| 4 | `Add a supplier` | `Optional. Needed before you draft a PO.` | Navigate to `parts-suppliers` with "+ Add" pre-armed |
| 5 | `Bring in parts` | `Import a CSV or add a few by hand.` | Navigate to `parts-catalog` with bottom-sheet `Import / Add` |
| 6 | `Set up your warehouse` | `One location is enough to start.` | Navigate to `warehouse-locations` with floor-plan tutorial |

### Subtitle rewrites (in-progress)

| Remaining required | Subtitle |
|--------------------|----------|
| 3 | `Three quick steps to get going.` |
| 2 | `Two more required steps.` |
| 1 | `One required step left.` |
| 0, recommended remain | `Required setup done. Three optional steps left.` |
| 0, all done | `You're all set up.` (celebration only) |

### Toast (after dismissal)

`Setup hidden. Re-open it from Settings → Help.`  ·  **Undo**

### Anti-patterns explicitly rejected

- ❌ "Skip" labelled in red/danger styling.
- ❌ Modals that re-fire after dismissal.
- ❌ Progress bars that fill on view, not on action.
- ❌ Manipulative copy ("You're missing out", "Most users finish this", fake urgency).
- ❌ Required steps that aren't actually required (e.g., forcing "Add 5 parts" when 1 part is plenty).

---

## 7. Dismissal Rules

| User action | Effect | Reversible? |
|-------------|--------|-------------|
| Swipe down on welcome sheet | Sheet closes; card remains visible | n/a — card is the reversal |
| `Start setup` on sheet | Sheet closes; Dashboard scrolls to card; card expanded | n/a |
| `I'll explore on my own` on sheet | Sheet closes; card auto-dismissed; `firstLaunchSheetSeen = true`; `checklistDismissed = true`. Toast offers Undo for 10s. | Yes (toast Undo; or Settings → Help → "Restart setup checklist") |
| Tap × on card | Card hidden; toast Undo for 10s; `checklistDismissed = true` | Yes (toast or Settings) |
| Complete all 6 steps | Celebration 1.5s, then card fades; `checklistDismissed = true` | No (no need; data is the source of truth) |
| Wipe device / fresh install | Everything resets (no iCloud persistence of these flags by design) | n/a |

A new Settings → Help entry "Restart setup checklist" sets `checklistDismissed = false` and `firstLaunchSheetSeen = false` and pulls the user back to the Dashboard with the card expanded.

---

## 8. Accessibility

- All rows are 56pt minimum tap height; chevron and check icon both inside the row hit area.
- `accessibilityLabel` on each row reads: `<title>, <"complete" | "step X of 6, not started">, <helper>`.
- Welcome sheet uses `accessibilityAddTraits(.isHeader)` on title and supports `Dynamic Type` up to `accessibility5` (sheet body becomes scrollable when content overflows).
- Progress bar has `accessibilityValue("3 of 6 complete")`.
- Celebration overlay is not solely color-coded — uses checkmark glyph + text.
- Reduced Motion: replace fade and scale celebration with crossfade only.
- VoiceOver focus on sheet open lands on the title, not the CTA.

---

## 9. Telemetry (lightweight, local only)

Per `CLAUDE.md` the app is local-first with no remote analytics by default. Log to the existing `_change_log` and a new local `onboarding_events` debug table (off by default, on for beta testers via Settings flag):

- `onboarding.welcome_shown`, `onboarding.welcome_dismissed (reason)`, `onboarding.card_shown`
- `onboarding.step_tapped (stepId)`, `onboarding.step_completed (stepId, secondsSinceFirstLaunch)`
- `onboarding.card_dismissed (reason: x|allDone|exploreSelf, completedCount)`
- `onboarding.checklist_restarted (source: settings)`

No PII. No network. Local only. Visible to the user in Settings → Privacy → "View collected onboarding data" (Section 11 of `docs/plans/security-review.md` patterns).

---

## 10. Wireframes

ASCII wireframes for the three viewports. These are intentionally low-fidelity — they pin layout, hierarchy, and breakpoints, not pixel-perfect typography. Engineering will execute against the existing design tokens in `DS.Space.*`, `DS.Color.*`, and the standard `Card` container.

### 10.1 iPhone — 375 × 812

**Welcome sheet (first launch only)**

```
┌──────────────────────────────────┐
│  ╳                               │  ← top-right close, 44pt
│                                  │
│     ✦                            │  ← sparkles glyph, accent color
│                                  │
│   Welcome to WiredPart           │  ← .largeTitle, bold
│   A quick setup to get you       │  ← .body, secondary
│   running.                       │
│                                  │
│   •  Tell us about your company  │  ← .body, primary
│   •  Add yourself and your       │
│      first job                   │
│   •  Bring in parts and a        │
│      supplier when you're ready  │
│                                  │
│                                  │
│   ┌──────────────────────────┐   │
│   │      Start setup         │   │  ← primary, full-width, 50pt
│   └──────────────────────────┘   │
│                                  │
│   I'll explore on my own         │  ← text button, centered
│                                  │
│   You can re-open this anytime   │  ← .caption2, tertiary
│   in Settings → Help.            │
└──────────────────────────────────┘
```

**Dashboard card — in-progress state**

```
┌──────────────────────────────────┐
│  Good morning, Sam               │  ← greeting (existing)
│                                  │
│  ● Not clocked in   [Clock In]   │  ← clockStatusBanner (existing)
│                                  │
│  ┌────────────────────────────┐  │
│  │ ✦ Get set up           ╳   │  │  ← card header, × is 44pt hit area
│  │ Two more required steps.   │  │
│  │                            │  │
│  │ ▰▰▰▱▱▱  3 of 6 · 1 reqd   │  │  ← progress bar + caption
│  │                            │  │
│  │ ✓ Set up your company      │  │  ← completed: green check, strikethru
│  │   Name, time zone, …       │  │
│  │                            │  │
│  │ ✓ Add yourself             │  │
│  │   So you can clock in …    │  │
│  │                            │  │
│  │ ③ Create your first job  › │  │  ← active: numbered, accent ring
│  │   Jobs are the home for…   │  │
│  │                            │  │
│  │ ─── Optional ───           │  │  ← subtle divider
│  │                            │  │
│  │ ④ Add a supplier         › │  │
│  │ ⑤ Bring in parts         › │  │
│  │ ⑥ Set up your warehouse  › │  │
│  └────────────────────────────┘  │
│                                  │
│  [KPI cards continue below…]     │
└──────────────────────────────────┘
```

**Dashboard card — collapsed (required-done state)**

```
┌──────────────────────────────────┐
│  ┌────────────────────────────┐  │
│  │ ✓ Required setup done      │  │
│  │   3 optional steps left  › │  │  ← tap to expand
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

**Celebration (1.5s)**

```
┌──────────────────────────────────┐
│  ┌────────────────────────────┐  │
│  │           ✦                │  │
│  │   You're all set up.       │  │  ← fades in/out
│  │   Welcome aboard.          │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

### 10.2 iPad — 768 × 1024 (portrait shown; landscape uses 2-column layout, see note)

**Welcome sheet** (form sheet, not full screen)

```
┌────────────────────────────────────────────────┐
│                                                │
│   ┌─────────────────────────────────────┐      │
│   │  ╳                                  │      │
│   │                                     │      │
│   │     ✦                               │      │
│   │                                     │      │
│   │   Welcome to WiredPart              │      │
│   │   A quick setup to get you running. │      │
│   │                                     │      │
│   │   •  Tell us about your company     │      │
│   │   •  Add yourself and your first job│      │
│   │   •  Bring in parts and a supplier  │      │
│   │      when you're ready              │      │
│   │                                     │      │
│   │   ┌─────────────────────────────┐   │      │
│   │   │      Start setup            │   │      │
│   │   └─────────────────────────────┘   │      │
│   │   I'll explore on my own            │      │
│   │                                     │      │
│   │   You can re-open this anytime …    │      │
│   └─────────────────────────────────────┘      │
│                                                │
└────────────────────────────────────────────────┘
```

**Dashboard card** — same content as iPhone, wider; in landscape, render the checklist in a 2-column grid (3 required on left, 3 recommended on right) once iPad is in `regularWidth × regularHeight` size class.

```
┌────────────────────────────────────────────────┐
│  Good morning, Sam              ⋯              │
│  ● Not clocked in           [Clock In]         │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │ ✦ Get set up                         ╳   │  │
│  │ Two more required steps.                 │  │
│  │ ▰▰▰▱▱▱  3 of 6 · 1 reqd                  │  │
│  │                                          │  │
│  │ Required             │ Optional          │  │  ← 2-col when ≥768pt
│  │ ✓ Set up your company│ ④ Add a supplier› │  │
│  │ ✓ Add yourself       │ ⑤ Bring in parts› │  │
│  │ ③ Create first job  ›│ ⑥ Set up warehouse│  │
│  └──────────────────────────────────────────┘  │
│                                                │
│  [KPI grid — 4 columns on iPad…]               │
└────────────────────────────────────────────────┘
```

### 10.3 Desktop — 1280 × 800 (forward-looking)

> Current build is iOS-only (`CLAUDE.md` — Tauri/React retired). Including this layout so the spec is portable when a Mac Catalyst or future desktop target is reintroduced. Visual is identical to iPad landscape; only the navigation chrome differs.

```
┌────────────────────────────────────────────────────────────────────────┐
│  [sidebar nav]  │  Good morning, Sam                            🔔 ⚙   │
│                 │  ● Not clocked in   [Clock In]                       │
│                 │                                                      │
│                 │  ┌────────────────────────────────────────────────┐  │
│                 │  │ ✦ Get set up                              ╳    │  │
│                 │  │ Two more required steps.                       │  │
│                 │  │ ▰▰▰▱▱▱  3 of 6 · 1 reqd                        │  │
│                 │  │                                                │  │
│                 │  │ Required           │ Optional                  │  │
│                 │  │ ✓ Set up company   │ ④ Add a supplier        › │  │
│                 │  │ ✓ Add yourself     │ ⑤ Bring in parts        › │  │
│                 │  │ ③ Create job     ›│ ⑥ Set up warehouse      › │  │
│                 │  └────────────────────────────────────────────────┘  │
│                 │                                                      │
│                 │  [KPI grid — 6 columns]                              │
└────────────────────────────────────────────────────────────────────────┘
```

The welcome sheet on desktop opens as a centered modal (~620pt wide), same content. The persistent card sits at the top of the Overview tab, never sticky.

---

## 11. Engineering Hand-off Notes

CEO/CTO defaults were accepted on WEI-813 and the engineering split was filed on 2026-05-12. Each child is intended to be one engineer-day or less, with blockers wired in Paperclip so dependent work wakes automatically.

| Child | Issue | Title | Files | Notes |
|-------|-------|-------|-------|-------|
| C1 | WEI-927 | Welcome sheet shell + one-time gating | `Features/Onboarding/FirstLaunchWelcomeSheet.swift` (new), `WeirdPartIOSApp.swift` | Wire `firstLaunchSheetSeen` `@AppStorage`. |
| C2 | WEI-928 | Dashboard checklist card — refactor of prompt 60H output | `Features/Dashboard/DashboardView.swift`, new `OnboardingChecklistCard.swift` | Adopt copy from §6, progress math from §5, accessibility from §8. Critical-path foundation. |
| C3 | WEI-929 | Step tap → real navigation (replace TODO stubs) | `OnboardingChecklistCard.swift`, `IOSContentRouter.swift` | Blocked by C2. Use existing `appCore.navigate(to:)` patterns. |
| C4 | WEI-930 | Required/recommended split + collapsed strip state | `OnboardingChecklistCard.swift` | Blocked by C2. Pure SwiftUI state work. |
| C5 | WEI-931 | Celebration state + auto-fade | `OnboardingChecklistCard.swift` | Blocked by C2. 1.5s; honor Reduced Motion. |
| C6 | WEI-932 | Dismiss toast with Undo (10s) | `Shared/ToastView.swift` (existing) | Blocked by C1 and C2. Reuses existing toast infra. |
| C7 | WEI-933 | Settings → Help → "Restart setup checklist" entry | `Features/Settings/SettingsHelpPage.swift` | Resets two `@AppStorage` flags. |
| C8 | WEI-934 | iPad / regular size-class 2-column layout | `OnboardingChecklistCard.swift` | Blocked by C2. `@Environment(\.horizontalSizeClass)`. |
| C9 | WEI-935 | Telemetry hooks (local-only) | `Services/OnboardingTelemetryService.swift` (new) | Off by default; Settings toggle. |
| C10 | WEI-936 | QA pass — VoiceOver, Dynamic Type, all three viewports | n/a | Blocked by C1-C9. Run before closing parent. |

Each child should reference WEI-813 as parent and link this spec via `docs/plans/ios-first-launch-onboarding.md`.

---

## 12. Resolved CEO / CTO Questions

Defaults accepted on WEI-813 before the engineering split:

1. **"Add yourself" auto-create default:** Yes. Use the device owner name where available, then let the user edit.
2. **"Set up your warehouse" required or recommended:** Recommended.
3. **Sample data option:** Defer to v2; keep first-launch lean.
4. **Theme step:** Drop from the checklist. Theme remains available in Settings.

---

## 13. Acceptance Criteria (for the parent WEI-813)

- [x] Spec saved at `docs/plans/ios-first-launch-onboarding.md`.
- [x] Wireframes for iPhone, iPad, desktop.
- [x] States enumerated with transitions and copy.
- [x] Dismissal rules, accessibility, and telemetry covered.
- [x] CEO/CTO sign-off defaults recorded as a comment on WEI-813.
- [x] Child implementation issues C1–C10 created and linked.
- [x] Parent reassigned per project convention once children exist.
