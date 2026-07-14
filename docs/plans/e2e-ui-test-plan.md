# End-to-End UI Test Plan — WiredPart iOS ("Click Every Button")

> **Purpose:** A complete, walk-the-whole-app test plan that exercises **every screen, every button, every sheet, and every theme setting** across all devices and appearance modes. Where the existing [`pre-release-testing-checklist.md`](pre-release-testing-checklist.md) checks *whether features behave correctly*, this plan checks that *every interactive element is reachable, tappable, and does something sane* — the literal "click every button" sweep.
>
> **Companion docs:** [`pre-release-testing-checklist.md`](pre-release-testing-checklist.md) (behavior checklist), [`testing-strategy.md`](testing-strategy.md) (Swift-core unit tests), [`cross-platform-qa.md`](cross-platform-qa.md).
>
> **Scale of the target:** 13 navigation modules · 89 sub-tabs/pages · ~197 sheets/modals · ~2,122 buttons in code · 4 onboarding wizards. Source of truth for the screen list is [`NavigationConfig.swift`](../../Weird%20Parts%20IOS/Weird%20Parts%20IOS/Navigation/NavigationConfig.swift).

---

> ## ⚠️ VERIFICATION STANDARD — read before marking anything
> **Nothing in this plan is "verified" until an AI agent has driven the actual running app like a real user and hit zero issues.**
>
> - Reading the code, inspecting a view file, or reasoning that "this button should work" is **NOT verification** — it is, at most, `UNVERIFIED / looks-plausible`.
> - A checkbox may only be marked `PASS` after an agent (or a human) has, **in the live app on a real device/simulator**: navigated to the screen, performed the actual tap/gesture/input as a user would, and observed the correct, issue-free result (right screen loaded, sheet dismissed, data saved, no crash, no glitch, no dead control).
> - If the app wasn't actually run and driven, the honest status is **`UNVERIFIED`** — say so plainly. Do not report "done/verified/passing" for anything that was only read or assumed. (See CLAUDE.md: report outcomes faithfully.)
> - **Default state of every item below is `UNVERIFIED`.** It flips to `PASS`/`FAIL` only through hands-on-the-app driving. An automated test counts as verification only when it actually launched the app and exercised the flow (XCUITest driving the UI) — a unit test asserting on a model does not verify the button.
> - Tooling for "drive it like a user": XCUITest (in-app UI driving), and for exploratory passes an agent using computer-use / the iOS simulator to tap through screens. The bar is the same either way: real interaction, observed result, no issues.

## 0. How To Use This Plan

There are **two tracks**. Do the manual track first (it needs no code changes and finds the most bugs fastest); stand up the automated track in parallel so regressions are caught forever.

| Track | Who/what | What it covers | Where |
|-------|----------|----------------|-------|
| **A — Manual sweep** | A human tester with a device | Every screen, every button, visual/theme/responsive correctness, "feels right" | Sections 3–9 checklists |
| **B — Automated (XCUITest)** | CI + local Mac runner | Navigation reachability, every button *tappable without crash*, screenshot capture per screen × theme | Section 10 |

**Definition of "a button is tested" (the bar every element must clear):**
1. It is **reachable** — you can get to it by normal navigation on the smallest supported screen (iPhone 375pt) without off-screen scrolling traps.
2. It is a **valid touch target** — ≥ 44×44 pt.
3. **Tapping it does the expected thing** — navigates, opens a sheet, performs an action, or shows a clear disabled/empty state. It never no-ops silently and never crashes.
4. If it opens a sheet, the sheet can be **dismissed by every dismiss control it offers** (Done, Cancel, Close, swipe-down) — and a dirty form warns before discarding.
5. It behaves in **Light and Dark**, at **default and largest Dynamic Type**, on **iPhone, iPad, and Mac**.

**Marking:** each row is `[ ]` and **starts as `UNVERIFIED`**. It becomes `PASS` **only** after the button was actually driven in the running app with an issue-free result (see the Verification Standard above), `FAIL` if driving it surfaced any issue, or `N/A`. A row that was only code-reviewed stays `UNVERIFIED` — never `PASS`. Every `FAIL` becomes a GitHub issue with the `[Area][Type]` prefix (see CLAUDE.md issue policy) — or gets checked off an existing umbrella issue. Track overall progress in Section 11.

---

## 1. The Test Matrix (5 dimensions)

"Click every button" is not one pass — it is one pass per relevant combination of these dimensions. You do **not** run the full Cartesian product (that's thousands of runs); you run the **full button sweep once per role** on the **primary device**, then run the lighter **global sweeps** (theme/responsive/type) sampled across screens.

| Dimension | Values | Why it matters here |
|-----------|--------|---------------------|
| **Device / viewport** | iPhone (375×812), iPad portrait (768×1024), iPad landscape (1024×768), Mac desktop (1280×800, Catalyst) | Horizontal tab bars, sheet dismiss traps, and 44pt targets differ per size. CLAUDE.md mandates all four. |
| **Appearance** | Light, Dark, System | Theme is per-device (`ThemesPage`). Dark mode regressions are common. |
| **Dynamic Type** | Default (L), Largest accessibility (AX5) | Buttons/labels must not clip or become untappable at AX5. |
| **Role / permissions** | Admin (all perms), Office/Manager, Warehouse, Field Tech, No-perms user | Tabs are permission-gated in `NavigationConfig.swift`. A tech never sees Office/Pricing — so "every button" is role-scoped. |
| **Data state** | Empty (fresh install), Typical, Large (100s of rows) | Empty-state buttons, pagination, search, and performance only show up with the right data volume. |

### Role → visible modules (from `NavigationConfig.swift` permission gates)

| Module | Gate | Admin | Office/Mgr | Warehouse | Field Tech |
|--------|------|:-:|:-:|:-:|:-:|
| Dashboard | none | ✅ | ✅ | ✅ | ✅ |
| Jobs | `view_jobs` | ✅ | ✅ | ○ | ✅ |
| Chat | `view_chat` | ✅ | ✅ | ✅ | ✅ |
| Scheduling | `view_scheduling` | ✅ | ✅ | ○ | ✅ |
| Warehouse | `view_warehouse` | ✅ | ✅ | ✅ | ○ |
| Orders | `view_orders` | ✅ | ✅ | ○ | ○ |
| Fleet | `view_fleet` | ✅ | ✅ | ○ | ✅ |
| Tools | `view_tools` | ✅ | ✅ | ✅ | ○ |
| Notebooks | none | ✅ | ✅ | ✅ | ✅ |
| Parts | `view_parts_catalog` | ✅ | ✅ | ○ | ○ |
| People | `view_people` | ✅ | ✅ | ○ | ○ |
| Office | `approve_orders` | ✅ | ✅ | ○ | ○ |
| Settings | `manage_settings` | ✅ | ○ | ○ | ○ |

✅ = expected visible · ○ = should be hidden (verify it IS hidden — negative test). Confirm the gates against `AuthService.defaultPermissionMap()` for your exact seed roles.

---

## 2. Pre-Flight Setup (once per test cycle)

- [ ] 2.1 Build a **fresh debug install** to each target device/simulator (iPhone, iPad, Mac).
- [ ] 2.2 Confirm `eraseDatabaseOnSchemaChange` is `#if DEBUG` only (no prod data loss) — see checklist A10.
- [ ] 2.3 Prepare **4 seed accounts**, one per role (Admin, Office, Warehouse, Tech), each with a known PIN.
- [ ] 2.4 Prepare **3 data snapshots**: empty, typical, large. (A large-seed script belongs in `execution/`.)
- [ ] 2.5 Enable **Accessibility Inspector** (Mac) / on-device Accessibility settings for 44pt-target and AX5 checks.
- [ ] 2.6 Have a **second device** available for Sync / Bluetooth pairing tests.
- [ ] 2.7 Camera-capable device available for QR scanning tests.
- [ ] 2.8 Screenshot folder ready for evidence per screen × theme.

---

## 3. Global Sweeps — Run On EVERY Screen

These are the elements the app's own standards (checklist section C) say appear on **every** page. Rather than repeat them 89 times below, verify them once per screen as you walk Section 5. This is the master "universal button set."

### 3.1 The Universal Button Set (present on essentially every feature page)
For each page you land on, confirm and click:
- [ ] **Help button** — `questionmark.circle` in the top-right toolbar → opens `PageHelpSheet` → sheet dismisses cleanly.
- [ ] **AI assistant button** — single floating orange circle, bottom-right → opens AI panel → panel closes. Exactly **one** (checklist C6 — no duplicates).
- [ ] **Search bar** (`.searchable`) — present on any list of 10+ items; typing filters; clearing restores.
- [ ] **Filter cards / smart filters** — each filter card toggles; combined filters behave; "clear/all" resets.
- [ ] **Pull-to-refresh** (`.refreshable`) — on every List; spinner shows; data reloads.
- [ ] **Add / "+" button** — where creation is supported → opens create form/sheet.
- [ ] **Back button** — returns to prior screen with state intact (checklist B3).
- [ ] **Row tap** — every list row navigates to its detail OR opens its editor; no dead rows (checklist B11 — no bare `Text()` placeholders).
- [ ] **Empty-state action** — with empty data, the empty view shows icon + message + a working action button (checklist C14).
- [ ] **Overflow / context menus** — any `•••`, long-press, or swipe actions fire their listed actions.

### 3.2 Theme Test Suite — `ThemesPage` (`/settings/themes`)
The theme page (`ThemesPage.swift`) is the single control surface for appearance. Test **every control**:
- [ ] 3.2.1 **Appearance Mode** segmented picker → tap **System**, **Light**, **Dark** — each applies app-wide on this device.
- [ ] 3.2.2 **Primary Color** — tap all **6** presets (Blue, Green, Purple, Red, Orange, Teal); selected ring shows; accent propagates to buttons/links after Save.
- [ ] 3.2.3 **Font Family** picker → select each of **Inter, System, SF Pro, Menlo**; text re-renders.
- [ ] 3.2.4 **Save Theme** button → shows "Saved!" for ~2s, then reverts label; setting persists across app relaunch.
- [ ] 3.2.5 **Help** toolbar button → Themes help sheet opens/dismisses.
- [ ] 3.2.6 **Error path** — with settings service unavailable, an "Error" alert appears with a working **OK**.
- [ ] 3.2.7 Changing color/font does **not** silently fail if Save isn't tapped (confirm expected apply-on-Save behavior).

### 3.3 Dark-Mode Sweep
- [ ] Set Dark mode, then re-walk a representative screen from **each of the 13 modules**. Verify: no black-on-black or white-on-white text, cards/dividers visible, icons legible, charts readable, sheets/alerts themed.

### 3.4 Per-Device Sweep — Mac, Tablet, Phone (each fails differently)
The app ships to three form factors. **Run the full button sweep once per device class**, because the failure modes don't overlap. Do the primary role-scoped sweep (§5) on **iPhone** (smallest, most constrained), then re-walk a representative screen from every module on **iPad** and **Mac** for the device-specific concerns below.

**📱 iPhone (phone) — 375×812, primary target**
- [ ] **No horizontal overflow** anywhere (AppShell uses `overflow-hidden` ancestors — a single wide row breaks the whole page).
- [ ] Header action rows **wrap** (`flex-wrap gap-3`); no buttons pushed off-screen.
- [ ] Horizontal **tab bars scroll** — every sub-tab reachable by scrolling (Warehouse has 12; Audit is kept front-of-bar for this reason).
- [ ] Wide tables/charts scroll inside their own `overflow-x-auto` container, not the page.
- [ ] Long button labels collapse to **icon-only** (`hidden sm:inline` pattern).
- [ ] Bottom **TabView + "More"** overflow works; nothing hidden under the home indicator / notch.
- [ ] 44×44pt targets hold even at this width.

**📲 iPad (tablet) — 768×1024 portrait AND 1024×768 landscape**
- [ ] **Sidebar layout** renders; sidebar expand/collapse; selection persists across rotation.
- [ ] **Split view / multi-column** (if used) behaves; detail pane updates with list selection.
- [ ] **Rotate portrait↔landscape** on a screen from each module — no layout break, no lost state, no clipped content.
- [ ] Adaptive columns/grids reflow (e.g. KPI cards, parts grid, floor plan canvas).
- [ ] Sheets present at correct detents (`.medium`/`.large`) and are dismissible.
- [ ] iPad multitasking (Split View / Slide Over ⅓ width) — degrades gracefully, no overflow.

**💻 Mac (Catalyst desktop) — 1280×800, highest-risk**
- [ ] **Sheet dismiss traps** — open every sheet/modal (~197): each has a **visible, working Cancel/Close/Done**. No swipe-to-dismiss exists on Catalyst, so a sheet without a button is a hard trap (§3.6; prior audit #1388–#1392).
- [ ] **Wizard escape** present on every multi-step flow (recent `fix(ui): add wizard escape controls`).
- [ ] **Window resize** small↔large — layout reflows, no overflow, no frozen scroll.
- [ ] **Pointer interactions** — hover states where expected; **right-click** context menus (if relied upon) have a visible-button equivalent; drag-and-drop (calendar, dispatch, kanban) works with a mouse.
- [ ] **Keyboard** — Tab moves focus, Esc dismisses, Return submits; text fields accept typing.
- [ ] Menu bar / window chrome doesn't hide primary actions.

### 3.5 Dynamic Type / Touch Targets
- [ ] Set **AX5** (largest) — no clipped labels, no overlapping controls, all buttons still tappable; scrollable where needed.
- [ ] Every tappable element ≥ **44×44 pt** (checklist C5). Use Accessibility Inspector to measure the smallest icon buttons (toolbar icons, color swatches, close "X"s).

### 3.6 Sheet-Dismiss Safety (Mac Catalyst trap — HIGH RISK)
> Memory flag: *Mac Catalyst has no swipe-to-dismiss.* Sheets that set `interactiveDismissDisabled` without an always-visible Cancel become **hard traps** on desktop (audit filed #1388–#1392).
- [ ] On **Mac**, open every sheet/modal (there are ~197) and confirm each has a **visible, working Cancel/Close/Done** — you must never be stuck.
- [ ] Dirty-form sheets warn before discarding (per-sheet `isDirty` + confirmation) — see [`dismiss-safety-campaign.md`](dismiss-safety-campaign.md).
- [ ] Wizard/escape controls present (recent fix `fix(ui): add wizard escape controls`).

---

## 4. Journey 0 — Onboarding & Auth (linear, first-run)

Walk the entire first-run chain on a fresh install and click every button. Files under `Weird Parts IOS/Weird Parts IOS/Auth/`.

- [ ] 4.1 **BootstrapView** — launches without crash; migrations complete (all 76); "Get Started"/continue button.
- [ ] 4.2 **CompanySetupWizard** — every step's Next/Back/Skip; can't advance with invalid input; final Create.
- [ ] 4.3 **AdminAccountSetupView** — create first admin, set PIN; validation on empty/mismatch; submit.
- [ ] 4.4 **BusinessProfileSetupView** — all fields, image/logo picker if present, Save.
- [ ] 4.5 **OnboardingWelcomeView / OnboardingWalkthroughView / ModuleTourView** — Next/Prev/Skip/Done through every slide; **escape control** works (recent wizard-escape fix); no dead-end.
- [ ] 4.6 **NewUserWelcomeView / OnboardingCompleteView** — finish buttons route to app.
- [ ] 4.7 **LoginView** — PIN entry pad (every digit + delete + submit), wrong-PIN error, lockout behavior.
- [ ] 4.8 **BiometricAuthService / Face ID-Touch ID** — enable/disable, success and fallback-to-PIN.
- [ ] 4.9 **DevicePairingView / SyncWaitingView** — pair start/cancel, waiting state, timeout/cancel returns cleanly.
- [ ] 4.10 **OnboardAIMVPEntryView** — AI onboarding entry opens/closes (recent `fix(ai): expose overlay bug reporter`, `add overlay bug report entry point`).
- [ ] 4.11 **Account menu / UserMenuSheet** — open, every item, Logout → `appDidLogout` clears state and returns to Login (checklist B15).
- [ ] 4.12 **TabBarEditorView** ("Edit Tabs") — reorder, show/hide tabs, save; hidden tabs disappear, restore works (checklist B14).

---

## 5. Per-Module Screen-By-Screen Button Sweep

For **each tab below**: (a) navigate to it — confirm the correct page loads (no "Coming Soon", no placeholder), (b) run the **Universal Button Set** from §3.1, then (c) click the **page-specific buttons** listed. Loading spinner shows while data loads (C15); errors surface via `ErrorStateView` (C8). Where a tab has **detail pages** (drill-in from a row), walk each detail page and its inner tabs/sheets too — these are not in the tab bar but hold most of the app's buttons.

> Legend: 🔒 = permission-gated tab (also run the negative test: confirm it's hidden for roles lacking the permission).

### 5.0 Navigation shell — run the whole sweep in BOTH layout modes
`IOSMainView` presents navigation two ways; the same screens have different reachability in each, so verify both:
- [ ] **Bottom Tab layout** (iPhone default): 4 primary modules as tabs + **"More"** tab. Open **More** and confirm every remaining module is listed and opens. Less-used modules (Office, People, Parts, Settings) live here — the easiest to leave untested.
- [ ] **Sidebar layout** (iPad / preference): every module in the sidebar, sub-tabs expand/collapse, selection persists.
- [ ] **Edit Tabs** (`TabBarEditorView`) — reorder primary tabs, hide/show, save; hidden modules move to More, restore works.

### 5.1 Dashboard (`square.grid.2x2`)
- [ ] **Overview** `/dashboard` — KPI cards tap through to their sources; date/filter bar; charts render.
- [ ] **Clock** `/dashboard/clock` 🔒`clock_in_out` — Clock In, Clock Out, job picker, GPS prompt, break/lunch start/stop, clock-out questionnaire (every question control + submit). See Journey in checklist E/X.
- [ ] **Daily Report** `/dashboard/report` — generate, view sections, export/share.
- [ ] **QR Scanner** `/dashboard/scanner` — camera permission prompt, scan success routes to entity, manual-entry fallback, torch/flip buttons, cancel.

### 5.2 Jobs 🔒`view_jobs` (`hammer`)
- [ ] **All Jobs** `/jobs/list` — filter cards, search, add job (+), row → **Job Detail tab view** (walk each inner tab: Overview, Parts/JPO, Notebook, Labor, Reports, Chat — every tab's buttons).
- [ ] **Labor** `/jobs/labor` 🔒`view_labor` — filters, row detail, edit/adjust entries.
- [ ] **Reports** `/jobs/reports` — generate, filter, open a report, export.

### 5.3 Chat 🔒`view_chat` (`bubble.left.and.bubble.right`)
- [ ] **Messages** `/chat/channels` — channel list row → thread; compose, send, attachment import, new-channel (+). (Remember: messages render `.reversed()`; opening marks read.)
- [ ] **Q&A** `/chat/questions` — new question (subject passed as `subject:`), answer, escalate, resolve.
- [ ] **RFIs** `/chat/rfis` 🔒`manage_jobs` — create RFI, respond, close.

### 5.4 Scheduling 🔒`view_scheduling` (`calendar`)
- [ ] **Calendar** `/scheduling/calendar` — day/week/month toggle, prev/next, tap slot → create/edit, drag if supported.
- [ ] **Dispatch** `/scheduling/dispatch` 🔒`manage_dispatch` — assign, multi-job dispatch, reassign, notify.
- [ ] **Flex Pool** `/scheduling/flex-pool` 🔒`self_assign_flex` — self-assign, release, session controls.
- [ ] **Time Off** `/scheduling/time-off` — request (+), approve/deny, cancel.
- [ ] **Templates** `/scheduling/templates` 🔒`manage_scheduling` — create/edit/apply/delete.
- [ ] **Availability** `/scheduling/availability` — set/clear per-day availability, save.
- [ ] **Sub Schedule** `/scheduling/sub-schedule` 🔒`manage_subcontractors` — add sub, assign, remove.
- [ ] **Pipeline** `/scheduling/pipeline` 🔒`manage_dispatch` — stage filters, drag/advance.
- [ ] **Long-Term** `/scheduling/long-pipeline` 🔒`manage_dispatch` — horizon controls, item detail.
- [ ] **Config** `/scheduling/config` 🔒`manage_scheduling` — every toggle/field + save.

### 5.5 Warehouse 🔒`view_warehouse` (`building`)
- [ ] **Dashboard** `/warehouse/dashboard` — KPI cards, activity feed, quick actions.
- [ ] **Audit** `/warehouse/audit` 🔒`perform_audit` — start audit, scan/count each item, discrepancy flow, submit. (Kept front of tab bar for 375pt reach.)
- [ ] **Sorting/Receiving** `/warehouse/receiving` — start session, sort item, box assign, complete.
- [ ] **Staging** `/warehouse/staging` — staged items/boxes, pick, stage, clear.
- [ ] **Movements** `/warehouse/movements` — filters, **Guided Movement Wizard** (see §6.2), row detail.
- [ ] **Inventory** `/warehouse/inventory` — `IOSInventoryGridPage`: grid cell tap, manual quantity adjustment, filters, search.
- [ ] **Audit detail** — after an audit: `IOSAuditSummaryView` (discrepancies, accept/adjust) and `IOSMyVerificationsPage` (my completed items).
- [ ] **Locations** `/warehouse/locations` — floor plan interactions, add/edit bin, **Warehouse Onboarding Wizard** (see §6.3).
- [ ] **Returns** `/warehouse/returns` — sort return, disposition buttons.
- [ ] **Tools** `/warehouse/tools` — checkout/return from warehouse view.
- [ ] **Leaderboard** `/warehouse/leaderboard` 🔒`manage_warehouse` — period toggle, row detail.
- [ ] **Network** `/warehouse/network` 🔒`manage_devices` — device list, pair, disconnect, sync now.
- [ ] **Settings** `/warehouse/settings` — every toggle/field + save.

### 5.6 Orders 🔒`view_orders` (`cart`)
- [ ] **Job Orders (JPOs)** `/orders/jpos` — create JPO (full form + line items + submit), row → JPO detail (approve/edit/cancel/convert).
- [ ] **Procurement** `/orders/procurement` — demand view, generate PO, supplier select.
- [ ] **Purchase Orders** `/orders/purchase-orders` — create PO, row → PO detail (send, receive shipment flow, PDF bundle, close).
- [ ] **Parts Mgmt** `/orders/parts` — supplier/PO management actions.
- [ ] **Stage Planner** `/orders/staging` — plan by job, stage actions.
- [ ] **Approvals** `/orders/approvals` — approve/deny/batch.
- [ ] **Returns** `/orders/returns` — create/process return.
- [ ] **Wishlist** `/orders/wishlist` — add/remove/convert to order.

### 5.7 Fleet 🔒`view_fleet` (`car`)
- [ ] **Dashboard** `/fleet/dashboard` — KPI cards, alerts.
- [ ] **Vehicles** `/fleet/vehicles` — add vehicle, row → **Vehicle Detail** (VIN, registration, maintenance schedule, assign/unassign driver sheet).
- [ ] **Trailers** `/fleet/trailers` — add, row → **Trailer Detail** (specs, attached vehicle, holds) and **Trailer Locations** (GPS history/current), empty-state action.
- [ ] **Maintenance** `/fleet/maintenance` — log service, schedule, complete.
- [ ] **Mileage** `/fleet/mileage` — log trip, edit, reimbursement.
- [ ] **Fuel** `/fleet/fuel` — log fill-up, receipt.
- [ ] **Inspections** `/fleet/inspections` — start checklist (every item), pass/fail, submit.
- [ ] **Tracking** `/fleet/tracking` — map controls, vehicle select.
- [ ] **My Truck** `/fleet/my-truck` — my assignment, report issue, checklist.

### 5.8 Tools 🔒`view_tools` (`wrench.adjustable`)
- [ ] **Dashboard** `/tools/dashboard` — KPIs, alerts.
- [ ] **All Tools** `/tools/registry` — add tool, row detail, QR.
- [ ] **Checkouts** `/tools/checkouts` — check out, check in, transfer.
- [ ] **Kits** `/tools/kits` — build kit, verify kit (every item check), issue.
- [ ] **Maintenance** `/tools/maintenance` — log, schedule, complete.
- [ ] **Admin** `/tools/admin` 🔒`manage_tools` — settings/toggles.

### 5.9 Notebooks (`note.text`)
- [ ] **All Notebooks** `/notebooks/all` — create, open, todo-stage controls, add note, attach.
- [ ] **Templates** `/notebooks/templates` 🔒`manage_templates` — create/edit/apply/delete.
- [ ] **Job Notebooks** `/notebooks/job-notebooks` — open by job, auto-fill job context when clocked in (checklist C11).

### 5.10 Parts 🔒`view_parts_catalog` (`wrench.and.screwdriver`)
- [ ] **Catalog** `/parts/catalog` — filters, search, add part, row → part detail (variants/SKU, edit, companions). **Parts Flow Wizard** (§6.4).
- [ ] **Categories** `/parts/categories` — tree editor: add/rename/reparent/delete, type-color links.
- [ ] **Brands** `/parts/brands` — CRUD.
- [ ] **Suppliers** `/parts/suppliers` — CRUD (no pricing on supplier page per design), portal notes.
- [ ] **Pricing** `/parts/pricing` 🔒`show_dollar_values` — edit price, price history, manual-pricing validator paths.
- [ ] **Companions** `/parts/companions` — add/remove companion rules, alternatives.
- [ ] **Forecasting** `/parts/forecasting` — MIN/TARGET/MAX rules, wishlist gen, procurement handoff, filters.
- [ ] **Import/Export** `/parts/import-export` — pick file, map columns, run import, export/share.

### 5.11 People 🔒`view_people` (`person.2`)
- [ ] **Dashboard** `/people/dashboard` — workforce KPIs.
- [ ] **Employees** `/people/employees` 🔒`view_people` — add, detail (certs, wages, skills, hats), edit.
- [ ] **Customers** `/people/customers` 🔒`view_customers` — CRUD; row → **Customer Detail** (balance, order history, contacts).
- [ ] **Contacts** `/people/contacts` — CRUD; row → **Contact Detail** (phone/email tap-to-call/mail).
- [ ] **Contractors** `/people/contractors` 🔒`view_contractors` — CRUD; row → **Contractor Detail** (rate, W9, availability, assignments).
- [ ] **Teams** `/people/teams` — build team, row → **Team Detail** (members, assignments, schedule), add/remove members.
- [ ] **Hats & Roles** `/people/hats` 🔒`manage_people` — create hat, assign permissions.
- [ ] **Permissions** `/people/permissions` 🔒`manage_people` — toggle per-permission; verify a change actually gates a tab (ties to §8).

### 5.12 Office 🔒`approve_orders` (`briefcase`)
- [ ] **Dashboard** `/office/dashboard` 🔒`approve_orders` — command-center cards.
- [ ] **Approvals** `/office/approvals` 🔒`approve_orders` — unified approve/deny/batch.
- [ ] **Manage Jobs** `/office/manage-jobs` 🔒`manage_jobs` — job admin actions.
- [ ] **Warehouse (Exec)** `/office/warehouse-exec` 🔒`manage_warehouse` — exec view actions.
- [ ] **Estimation** `/office/estimation-settings` 🔒`manage_jobs` — estimation questionnaire + review controls.
- [ ] **Pipeline** `/office/pipeline` 🔒`manage_jobs` — stage controls.
- [ ] **Spending** `/office/spending` 🔒`show_dollar_values` — budget alerts, drill-down.
- [ ] **Teams** `/office/teams` — team admin.
- [ ] **Reports** `/office/reports` 🔒`view_reports` — via `IOSReportsRouter` hub. Walk every report page: **Pre-Billing, Profitability, Spending, Labor Overview, Timesheets, Daily Reports Summary, Bookkeeper Export, Data Export, Public Report View** — each: date-range picker, filter menu, column-sort, generate, chart tap/zoom, export-format selector (PDF/XLSX/CSV), share, period lock. Also the module-specific report builders: **Fleet** (Fuel Cost, Maintenance Trends, Mileage Summary, Utilization), **Warehouse** (Backorder, Inventory Value, Turnover), **Scheduling** (Crew Utilization, Dispatch Efficiency, Pipeline) — generate + export each.

### 5.13 Settings 🔒`manage_settings` (`gearshape`)
- [ ] **Themes** `/settings/themes` — full §3.2 suite.
- [ ] **App Config** `/settings/app-config` — every toggle/field + save; data-directory config (desktop only — N/A on iOS).
- [ ] **Notifications** `/settings/notifications` — sound toggles, per-type toggles, test.
- [ ] **Sync** `/settings/sync` — Multipeer/BT pairing start/stop, conflict resolution UI, sync now.
- [ ] **Security** `/settings/security` 🔒`manage_devices` — device reset (destructive — see §9), biometric toggle, device list.
- [ ] **Audit Log** `/settings/audit` 🔒`view_activity_log` — filter, row detail, export.

#### 5.13b Extended Settings / Admin pages (via `SettingsRouter` — ~70 pages, NOT in the tab bar)
These drill-in pages are reachable from the Settings module / user menu and are a large, easily-missed surface. For each: open it, exercise every toggle/field/picker, Save (with unsaved-change guard), and confirm destructive actions confirm. Group by concern:
- [ ] **Sync & data:** `SyncPage`, `IOSRemoteSyncPage`, `IOSBackupsPage` (backup/restore + schedule), `IOSDataExportPage`, `IOSDatabaseResetPage` (nuclear — §9).
- [ ] **Devices & connectivity:** `IOSDeviceManagementPage` (remote wipe), `BluetoothPage` (pair scanners/printers), `AppConfigPage` (auto-lock, thresholds), `IOSUpdateProtocolPage`.
- [ ] **Notifications & AI:** `NotificationPrefsPage`, `IOSAIConfigPage` (assistant toggles, model select).
- [ ] **Security & identity:** `SecurityAdminPage` (2FA, device keys, sessions), `IOSKeyManagementPage` (API key rotation, webhook tokens), `IOSBootstrapAdminPage`.
- [ ] **Company & org rules:** `CompanyProfilesPage` (multi-company switch), `IOSOrganizationThresholdsPage` (order min, hold limits), `IOSBreakSettingsPage`, `IOSClockOutQuestionsPage`.
- [ ] **Templates & workflow:** `IOSDailyReportTemplatesPage`, `IOSJobStageTemplatesSettingsPage`, `IOSReportTemplatesPage`, `IOSPreTripChecklistPage`, `IOSForecastSettingsPage`, `IOSDispatchPreferencesPage`, `IOSToolPoliciesPage`.
- [ ] **Integrations:** `IOSIntegrationsPage` (OAuth/API keys), `IOSSupplierBridgePage` (EDI/API), `IOSSharedChannelsPage` (cross-org chat), `BillingPayPage` (subscription/payment — do not submit real payment).
- [ ] **Info & support:** `AboutPage` (version/legal links), `ReportABugPage` (in-app bug form → submits), `IOSAuditSettingsPage`.

> Because there are ~70 pages here, build a checklist row per page in the tracker; this is the single largest "forgotten buttons" risk in the app.

---

## 6. Wizards & Multi-Step Flows (deep, every step's buttons)

Wizards are the highest-risk "trap" surface — a broken Next/Back or a disabled dismiss strands the user. Test **Next, Back, Skip, Cancel/Escape, and validation gating** at every step, plus the final commit.

- [ ] **6.1 Company Setup Wizard** (`CompanySetupWizard.swift`) — every step, invalid-input gating, final Create.
- [ ] **6.2 Guided Movement Wizard** (`IOSMovementWizard.swift`) — source → part → qty → destination → confirm; back-navigation preserves entries; cancel mid-flow discards safely.
- [ ] **6.3 Warehouse Onboarding Wizard** (`WarehouseOnboardingWizard.swift` + `WarehouseWizardStep2–6`, `WizardStepAreas/Zones/Shelves/Bins/Placement/WalkingPath`) — walk all 6 steps and every sub-step editor; progress step buttons (`WarehouseWizardProgressStepButton`) jump correctly; each add/remove within a step; final save builds the floor plan.
- [ ] **6.4 Parts Flow Wizard** (`PartsFlowWizard.swift`) — each step, variant/SKU creation, commit.
- [ ] **6.5 Clock-Out Questionnaire & Estimation Questionnaire** — every question input type (toggle, text, picker, number), required-field gating, submit; review screen edit/confirm.
- [ ] **6.6 Receiving Routing Flow** (`ReceivingRoutingFlow.swift`) — inbound item → bin-assignment steps → confirm; back preserves; cancel discards safely.
- [ ] **6.7 Panel Schedule Builder** (`PanelScheduleBuilder.swift`, Notebooks) — the electrical-panel canvas: add/remove circuits, assign breakers, edit labels, every canvas control, then `PanelScheduleExport` → PDF preview + share. High interactive-element density — treat as its own mini-app.

**For every wizard, on Mac:** confirm an always-visible escape (no `interactiveDismissDisabled` trap) — §3.6.

---

## 7. Cross-Cutting Feature Tests

- [ ] **7.0 Scanning & Capture module** (`Features/Scanning/`) — a full subsystem, test each capture surface: `IOSQRScanner`/`QRScanSheet` (torch, flip camera, gallery import, frame guides, cancel), `IOSOCRScanner` (receipt/text extraction), `IOSDocumentScanView` (capture, crop, rotate, multi-page), `IOSCameraMatchView` (image→part AI match, accept/reject), `IOSAutoFillBanner` (apply/dismiss recent scan), `QRLabelPrintSheet` (generate + print/share labels). Verify camera-permission request and denied-permission fallback.
- [ ] **7.1 QR / Deep Links** — scan each entity type (part, bin, PO, job, vehicle, trailer, tool) → routes to the right page landed on the scanned entity (issue #700 behavior); bad/foreign QR shows a clear error.
- [ ] **7.2 Global Search** — from each searchable list; no-results state; special characters.
- [ ] **7.3 Bulk Actions** — select-multiple toolbars (Parts, Orders, etc.): select all, deselect, bulk apply, undo.
- [ ] **7.4 AI Assistant** — the one floating button per page: open, ask, it reads page context (via `...PageActive` notifications), apply-to-filters actions (e.g. catalog/pricing), close. Overlay **bug reporter** entry point works (recent fixes).
- [ ] **7.5 Notifications & Sounds** — trigger each notification type; sound plays if enabled; badge counts update (`BadgeCountService`).
- [ ] **7.6 Sync / Bluetooth** — pair two devices, make a change on A, confirm it appears on B; conflict UI (LWW + field merge); disconnect mid-sync recovers.
- [ ] **7.7 Export / Share** — every export button (reports, parts, audit log): share sheet opens, file is valid, filtered rows respected (regression-tested area).
- [ ] **7.8 Offline** — airplane mode: reads work from local SQLite; writes queue; no crash; clear offline indicator.

---

## 8. Role / Permission Matrix Tests (negative testing)

For each of the 4 seed roles, log in and confirm:
- [ ] 8.1 Only the **expected modules/tabs** appear (cross-check §1 table). Gated tabs are **absent**, not just disabled.
- [ ] 8.2 No hardcoded "Admin"/"Manager" checks leak a control the hat system should hide (checklist C10).
- [ ] 8.3 Financial values (`show_dollar_values`) hidden for roles without it — Pricing tab gone, dollar figures masked on shared pages.
- [ ] 8.4 Changing a permission in **People → Permissions** immediately (or on relaunch) changes visibility — proves the gate is live, not cosmetic.
- [ ] 8.5 Deep-linking (QR) to a gated page as an unauthorized role is denied gracefully.

---

## 9. Data Integrity & Destructive Actions (handle with care)

- [ ] 9.1 **Device Reset** (Settings → Security) — confirmation required; cancel aborts; confirm wipes only intended data; app returns to bootstrap.
- [ ] 9.2 **Delete** on any entity — soft-delete (row disappears, `is_active`+`deleted_at`), not hard-delete; undo/restore where offered.
- [ ] 9.3 **Period Lock** (Reports) — locking prevents edits to locked periods; unlock path gated.
- [ ] 9.4 **Cancel/Discard** on any dirty form warns before losing data.
- [ ] 9.5 No silent failures — every `loadData()`/save surfaces success or a real error (checklist C8; ties to memory on silent-error handling).

---

## 10. Track B — Automated XCUITest Strategy

### 10.1 The prerequisite gap (do this first)
Only **56 files / 223 `accessibilityIdentifier`s** exist today — far short of ~2,122 buttons. Reliable "click every button" automation needs stable identifiers.
- [ ] 10.1.1 Adopt a **naming convention**: `"<module>.<page>.<control>"` (e.g. `themes.save`, `jobs.list.add`).
- [ ] 10.1.2 Add identifiers **module by module**, starting with the highest-traffic pages (Dashboard, Jobs, Warehouse, Orders). File as an umbrella issue: `[Testing][Infra] Accessibility identifiers for E2E automation`.
- [ ] 10.1.3 Give the **Universal Button Set** (Help, AI, Add, Search, Refresh) consistent identifiers so one helper can find them on any page.

### 10.2 Reachability test (data-driven from `NavigationConfig`)
Because `appModules` is one enumerable array, one parameterized test can visit **every** tab:
- [ ] 10.2.1 For each `AppModule` → each `AppTab`: navigate by `path`, assert the destination page rendered (assert on the tab's `...PageActive` notification or a page-root identifier), assert **no** "Coming Soon"/placeholder, capture a screenshot.
- [ ] 10.2.2 Run this suite in **Light and Dark** and at **AX5** — screenshots become a visual-regression baseline.

### 10.3 "Tap every button" smoke per page (page objects)
- [ ] 10.3.1 One **page-object** per screen exposing its buttons; a generic driver taps each, asserts no crash and that a sheet/nav/change resulted, then returns to a known state.
- [ ] 10.3.2 Sheet-dismiss assertion: after opening, a dismiss control exists and works (guards the Mac-Catalyst trap in code).

### 10.4 Extend what already exists
Build on the current UITests rather than starting over: `Weird_Parts_IOSUITests.swift`, `WEI3900ClockFlowQATests.swift`, `WEI936OnboardingQAUITests.swift`, `WarehouseDashboardScreenshotUITests.swift`, `ConflictScreenshotCaptureUITests.swift`, `Weird_Parts_IOSUITestsLaunchTests.swift`.
- [ ] 10.4.1 Generalize the screenshot UITests into the per-tab loop (§10.2).
- [ ] 10.4.2 Add the onboarding/auth journey (§4) as an ordered UITest.
- [ ] 10.4.3 Wire into CI on the **local self-hosted Mac runner** (Xcode required — per CLAUDE.md runner policy); non-Xcode gates stay on `ubuntu-latest`.

---

## 11. Sign-Off Tracker

Fill per test cycle. **Every cell starts `UNVERIFIED`** and only turns green when the screen was driven in the live app like a user with no issues (§ Verification Standard) — not from code review. "Click-every-button" is DONE when every module column below is 100% verified-green and every `FAIL` is either fixed or tracked in a GitHub issue.

| Area | Manual (Light) | Manual (Dark) | Responsive (iPhone/iPad/Mac) | AX5 | Role matrix | Automated | Notes / Issues |
|------|:-:|:-:|:-:|:-:|:-:|:-:|----|
| Onboarding & Auth | ☐ | ☐ | ☐ | ☐ | — | ☐ | |
| Dashboard | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Jobs | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Chat | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Scheduling | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Warehouse | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Orders | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Fleet | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Tools | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Notebooks | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Parts | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| People | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Office | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Settings (+ Themes) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Extended Settings/Admin (~70 pages §5.13b) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Detail pages (Job/PO/JPO/entity drill-ins) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Scanning & Capture (§7.0) | ☐ | ☐ | ☐ | ☐ | — | ☐ | |
| Wizards & deep flows (incl. Panel Schedule) | ☐ | ☐ | ☐ | ☐ | — | ☐ | |
| Cross-cutting (QR/Sync/AI/Export) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |

**Every FAIL →** GitHub issue `[Area][Type]` per CLAUDE.md, or a check-off on an umbrella issue. Group duplicate-class findings (e.g. all Mac dismiss traps under one umbrella).

---

## Appendix — Coverage Accounting

- **Total screens:** ~150+ (navigable tabs + detail pages + ~70 settings/admin pages + scanning surfaces). **Nav modules:** 13 · **Nav tabs/pages:** 89 (per `NavigationConfig.swift`) · **Extended settings/admin pages:** ~70 (§5.13b) · **Sheets/modals:** ~197 · **Buttons in code:** ~2,122 · **Wizards/deep flows:** 6 (+ 2 questionnaires).
- This plan reaches every one of the 89 tabs explicitly (§5), the extended admin pages (§5.13b), the scanning subsystem (§7.0), every wizard/deep flow (§6), entity detail pages (drill-in bullets per module), and every button *class* via the Universal Button Set (§3.1) applied per screen. Individual buttons inside detail pages/sheets are covered by "open the sheet, click each of its controls, dismiss each way."
- **Shared components appear on every screen** (`Shared/`, `DesignSystem/`): `ConfirmationSheet`, `EmptyStateView`, `ErrorStateView`, `LoadingState`, `AlertBanner`, `FilterChip`/`StandardFilterBar`, `MailComposerSheet`, `PageHelpSheet`, `QuickActionButton`, charts (tap/zoom). Verifying these once per screen (§3.1) covers them globally — a bug in one is a bug everywhere, so a single failure here is high-priority.
- **Source-of-truth for the nav screen list** is one array — when a screen is added to `appModules`, add a row here and an entry in the §10.2 automated loop so coverage never drifts. Detail pages and settings pages are NOT in that array, so keep §5.13b and the drill-in bullets updated by hand as pages are added.
