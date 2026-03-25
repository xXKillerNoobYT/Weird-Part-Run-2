# Pre-Release Testing Checklist — WiredPart iOS

> **Purpose:** Every item on this list must PASS before the app ships. Each item is testable — you can verify it by running the app and checking specific behavior.
>
> **How to use:** Go through each section. For each item, mark PASS/FAIL. Any FAIL gets a fix prompt.

---

## A. APP LAUNCH & BOOTSTRAP (10 items)

- [ ] A1. Fresh install: app launches without crash
- [ ] A2. Fresh install: bootstrap flow completes (create admin, company profile)
- [ ] A3. Database migrations run successfully (all 56 migrations, 000-055)
- [ ] A4. No "Failed to load database" error on launch
- [ ] A5. Login screen appears after bootstrap
- [ ] A6. Can create first admin user with PIN
- [ ] A7. Can log in with created PIN
- [ ] A8. After login, Dashboard loads with no errors
- [ ] A9. Sidebar navigation appears with all modules
- [ ] A10. `eraseDatabaseOnSchemaChange` is `#if DEBUG` only (no production data loss)

## B. NAVIGATION & ROUTING (15 items)

- [ ] B1. Every sidebar module expands to show sub-tabs
- [ ] B2. Every sub-tab navigates to a real page (no "Coming Soon" for shipped features)
- [ ] B3. Back button works on every detail page
- [ ] B4. Sheet dismiss works on every popup (Done/Cancel/Close buttons)
- [ ] B5. No multiple `.sheet()` modifiers causing popups to not open
- [ ] B6. Tab order makes sense (daily use first, admin last)
- [ ] B7. `/orders/parts` route resolves (Parts Management page)
- [ ] B8. `/orders/wishlist` route resolves (Wishlist page)
- [ ] B9. People Dashboard is reachable from navigation
- [ ] B10. All orphaned pages are either wired up or removed
- [ ] B11. NavigationLinks don't go to bare `Text()` placeholders
- [ ] B12. Deep links work (scan QR → opens correct page)
- [ ] B13. Module order: Dashboard, Jobs, Chat, Parts, Warehouse, Orders, Fleet, Scheduling, Tools, Notebooks, People, Office, Settings
- [ ] B14. Edit Tabs feature works (user can customize visible tabs)
- [ ] B15. Account menu works (user menu sheet opens/closes)

## C. PROGRAM-WIDE STANDARDS (15 items)

- [ ] C1. Smart card filters on EVERY list page (no old-style chips)
- [ ] C2. Help/Info button on EVERY feature page (questionmark.circle in toolbar)
- [ ] C3. Standard filter bar on EVERY date-relevant page (This Week/Last Week/etc.)
- [ ] C4. Priority colors consistent: Green=ok, Yellow=4d, Orange=24h, Red=overdue, Gray=done
- [ ] C5. 44px minimum touch targets on all tappable elements
- [ ] C6. ONE AI button per page (bottom-right floating orange circle, no duplicates)
- [ ] C7. Single `.sheet(item:)` with ActiveSheet enum on every page
- [ ] C8. Error visibility: every loadData() shows errors via ErrorStateView
- [ ] C9. No `import GRDB` in any Features file
- [ ] C10. Hat-based permissions (no hardcoded "Admin"/"Manager" role checks)
- [ ] C11. Auto-fill job context when clocked in (JPO, chat, notebooks auto-fill job)
- [ ] C12. `.refreshable` (pull-to-refresh) on every List view
- [ ] C13. `.searchable` on every list page with 10+ items
- [ ] C14. Empty state views (icon + message + action) on every page with no data
- [ ] C15. Loading state (ProgressView) on every page while data loads

## D. DASHBOARD (8 items)

- [ ] D1. Dashboard Overview loads with KPI cards
- [ ] D2. Clock tab shows clock-in/out functionality
- [ ] D3. Daily Report tab loads system-generated report
- [ ] D4. QR Scanner tab opens camera and scans
- [ ] D5. Clock status banner shows on Overview when clocked in
- [ ] D6. KPI detail sheets open when tapping cards
- [ ] D7. Background tasks card shows (if designed)
- [ ] D8. Chart data loads (not permanent empty state)

## E. CLOCK IN/OUT (12 items)

- [ ] E1. Can clock in to a job
- [ ] E2. Can clock in to Shop/Warehouse
- [ ] E3. Job picker shows active jobs
- [ ] E4. GPS location captured on clock in
- [ ] E5. Can clock out
- [ ] E6. Clock-out questionnaire appears
- [ ] E7. Break button works (changes clock state)
- [ ] E8. Lunch button works
- [ ] E9. Supply run button works (stays clocked in)
- [ ] E10. Live elapsed timer shows and updates
- [ ] E11. Today's hours section shows accurate time
- [ ] E12. Switch Job works (clock out A → clock in B in one action)

## F. PARTS (14 items)

- [ ] F1. Catalog: can search parts by name/code
- [ ] F2. Catalog: can filter by category/brand/type/color
- [ ] F3. Catalog: can view part detail sheet
- [ ] F4. Catalog: NL search works ("red copper fittings")
- [ ] F5. Categories: tree view loads and expands
- [ ] F6. Categories: can add/edit/delete categories, styles, types, brands, colors
- [ ] F7. Categories: Smart Delete checks inventory before deleting
- [ ] F8. Brands: list loads, can add/edit/delete
- [ ] F9. Suppliers: list loads, can add/edit/delete, performance scores show
- [ ] F10. Pricing: pricing page loads with tier information
- [ ] F11. Companions: rules page loads, can view rules
- [ ] F12. Forecasting: forecast data loads with urgency indicators
- [ ] F13. Forecasting: recalculate button works
- [ ] F14. Import/Export: can export parts data

## G. ORDERS (12 items)

- [ ] G1. PO List: loads with status filter cards and counts
- [ ] G2. PO List: can create new PO
- [ ] G3. PO List: swipe-to-cancel with AI summary works
- [ ] G4. PO Detail: shows line items, status, supplier info
- [ ] G5. PO Detail: can change status (submit, mark ordered, etc.)
- [ ] G6. JPO List: loads with status cards
- [ ] G7. JPO List: can create new JPO
- [ ] G8. JPO Detail: per-part approve/reject/hold works
- [ ] G9. Procurement: demand consolidation shows grouped parts
- [ ] G10. Receiving: can start a receiving session
- [ ] G11. Returns: returns page loads
- [ ] G12. Parts Management: page loads, shows parts by supplier

## H. WAREHOUSE (14 items)

- [ ] H1. Dashboard: loads with smart cards and activity feed
- [ ] H2. Movements: list loads, can start movement wizard
- [ ] H3. Movement Wizard: can select source, destination, parts, quantities
- [ ] H4. Movement Wizard: verification step works
- [ ] H5. Locations: page loads with location groups
- [ ] H6. Staging: shows staged items by job
- [ ] H7. Receiving: can process incoming shipments
- [ ] H8. Audit: loads with confidence cards
- [ ] H9. Audit: can start a count audit
- [ ] H10. Audit: can enter counts (system count hidden)
- [ ] H11. Inventory Grid: shows parts with stock levels
- [ ] H12. Returns: shows what goes back to suppliers
- [ ] H13. Tools: shows tools in warehouse
- [ ] H14. Settings: warehouse settings load and save

## I. JOBS (10 items)

- [ ] I1. Jobs List: loads with status cards and AI summaries
- [ ] I2. Jobs List: can create new job
- [ ] I3. Job Detail: Overview tab loads as dashboard
- [ ] I4. Job Detail: all tabs load (Team, Parts, Orders, Notebook, etc.)
- [ ] I5. Job Detail: can edit job info
- [ ] I6. Labor page: shows time entries
- [ ] I7. Daily Reports page: loads reports
- [ ] I8. Questionnaire: works for clock-out questions
- [ ] I9. Job Reports: page loads
- [ ] I10. Create/Edit job sheets open and save properly

## J. PEOPLE (8 items)

- [ ] J1. Employees: list loads, can add/edit
- [ ] J2. Employee Detail: shows hats, contact info, job history
- [ ] J3. Customers: list loads, can add/edit
- [ ] J4. Contractors: list loads, can add/edit
- [ ] J5. Contacts: unified list loads with active/inactive sections
- [ ] J6. Teams: list loads, can manage team members
- [ ] J7. Hats: list loads, can view permissions
- [ ] J8. Permissions: page loads, shows permission matrix

## K. CHAT (6 items)

- [ ] K1. Channels list loads
- [ ] K2. Can create a new channel
- [ ] K3. Can send a message in a channel
- [ ] K4. Message thread loads with bubbles
- [ ] K5. Q&A page loads
- [ ] K6. RFI list loads

## L. SCHEDULING (8 items)

- [ ] L1. Calendar: week view loads
- [ ] L2. Calendar: can create schedule entries
- [ ] L3. Dispatch: dispatch board loads
- [ ] L4. Dispatch: can create dispatch assignments
- [ ] L5. Time Off: requests list loads
- [ ] L6. Time Off: can submit time-off request
- [ ] L7. Availability: weekly grid loads
- [ ] L8. Config: schedule settings load and save

## M. TOOLS (6 items)

- [ ] M1. Dashboard: loads with smart cards and quick actions
- [ ] M2. Registry: tool list loads, can view detail
- [ ] M3. Checkouts: active checkouts list loads
- [ ] M4. Maintenance: maintenance records load
- [ ] M5. Kits: kit list loads
- [ ] M6. Admin/Management: bulk operations page loads

## N. FLEET (8 items)

- [ ] N1. Dashboard: loads with vehicle status and KPIs
- [ ] N2. My Truck: shows assigned vehicle with parts/tools
- [ ] N3. Vehicles: list loads, can create vehicle
- [ ] N4. Vehicle Detail: all tabs load (Overview, Assignments, Maintenance, etc.)
- [ ] N5. Trailers: list loads, can create trailer
- [ ] N6. Fuel/Mileage: logs load
- [ ] N7. Inspections: inspection records load
- [ ] N8. Maintenance: maintenance records load

## O. REPORTS (6 items)

- [ ] O1. Reports hub loads with categories
- [ ] O2. Timesheets page loads
- [ ] O3. Labor Overview loads
- [ ] O4. Pre-Billing page loads
- [ ] O5. Spending page loads
- [ ] O6. Bookkeeper Export page loads

## P. NOTEBOOKS (6 items)

- [ ] P1. Notebooks list loads
- [ ] P2. Can create a new notebook
- [ ] P3. Notebook detail loads with entries
- [ ] P4. Can add entries (text, checklist, photo)
- [ ] P5. Job notebooks page shows notebooks for a job
- [ ] P6. Templates page loads

## Q. OFFICE (6 items)

- [ ] Q1. Office dashboard loads with briefing
- [ ] Q2. Approvals page loads with unified queue
- [ ] Q3. Manage Jobs page loads
- [ ] Q4. Spending Dashboard loads
- [ ] Q5. Warehouse Exec page loads
- [ ] Q6. Deletion Approvals loads

## R. SETTINGS (8 items)

- [ ] R1. Settings page loads with grouped sections
- [ ] R2. Theme settings load and save
- [ ] R3. Company profile can be edited
- [ ] R4. Billing/Pay settings load
- [ ] R5. Clock-out questions CRUD works
- [ ] R6. AI Config page loads
- [ ] R7. About page shows version info
- [ ] R8. Database Reset page has proper safeguards

## S. AI ASSISTANT (5 items)

- [ ] S1. AI button (floating orange circle) appears on every page
- [ ] S2. Tapping AI button opens assistant panel
- [ ] S3. Can type a question and get a response
- [ ] S4. AI knows about current page context
- [ ] S5. AI can activate filters/cards on the current page

## T. QR & SCANNING (5 items)

- [ ] T1. QR Scanner opens camera
- [ ] T2. Scanning a part QR navigates to part detail
- [ ] T3. Scanning a PO QR navigates to PO detail
- [ ] T4. QR Label Print sheet opens and generates PDF
- [ ] T5. QR scan from Dashboard works in continuous mode

## U. DATA INTEGRITY (8 items)

- [ ] U1. Pre-migration backup is created before schema changes
- [ ] U2. Backup files are stored in Documents/WiredPart/Backups/
- [ ] U3. Old backups are pruned (max 5 kept)
- [ ] U4. Restore from backup works
- [ ] U5. All services nil'd properly on database reset
- [ ] U6. Schema version (56) matches migration count
- [ ] U7. `isTableNotFoundError` fallback on all later-migration queries
- [ ] U8. No force unwraps that could crash on nil data

## V. SYNC & OFFLINE (4 items)

- [ ] V1. App works fully offline (no network required for core features)
- [ ] V2. Change log accumulates changes while offline
- [ ] V3. Sync status indicator shows current state
- [ ] V4. Settings sync scope works (company vs personal vs device)

## W. BUTTONS & ACTIONS (8 items)

- [ ] W1. Every visible button does something when tapped
- [ ] W2. No TODO stub buttons visible to users
- [ ] W3. No "Coming Soon" text on shipped features
- [ ] W4. Delete actions have confirmation dialogs
- [ ] W5. Save actions show success/failure feedback
- [ ] W6. Cancel buttons actually dismiss sheets
- [ ] W7. Swipe actions work where implemented
- [ ] W8. All toolbar buttons are functional

---

**TOTAL: 196 test items across 23 categories**

Each FAIL generates a specific fix prompt for Xcode.
