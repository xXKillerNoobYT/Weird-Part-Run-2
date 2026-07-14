# iOS People Pages — Design Plan

## What This Does

The People area covers everyone the program tracks: employees (with certifications, skills, wages, hat assignments, team membership), customers (with contact preferences and billing info), contractors (with subcontractor agreements + scoring), free-form contacts (entity_contacts table — non-employee non-customer people who appear in jobs/orders/etc), teams (groups of employees with shared visibility), hats (job roles with permission bundles), and the permission catalog itself. Backed by `PeopleService.swift` (56 public methods, 2279 lines, 76 tests = 1.36× breadth) + 14 iOS pages.

## Why

The People area is identity-and-permission ground truth for the whole program. Every audit log entry references a user_id; every dispatch references a worker; every job references a customer; every contractor reference flows to billing. A bug in PeopleService propagates everywhere. Hats are the program's RBAC primitive — a "Tech" hat carries one permission bundle, "Office" carries another, "Owner" carries everything. Re-assigning a hat to an employee atomically changes their authority across the program. Teams add shared-visibility scoping (e.g. Truck-1 team sees Truck-1's calendar). Per memory, People had the highest dismiss-safety fix density of any area first rotation (9 fixes across 11 files) — every form-style sheet needs the `interactiveDismissDisabled(isDirty || isSaving)` pattern because losing a half-typed customer's phone number to an accidental swipe-down is a data-loss event in this domain. Rotation-2 sweep is now the validation that those fixes held + that no new gaps appeared.

> **Purpose:** Comprehensive design decisions for all People-related pages in the iOS app. Covers people dashboard, employees, customers, contractors, contacts, teams, hats, permissions, and payment tracking.
>
> **Source:** Design conversation 2026-03-23. Implements pages in `Weird Parts IOS/Features/People/`.
>
> **Files:** `IOSEmployeesPage`, `IOSEmployeeDetailPage`, `IOSCustomersPage`, `IOSCustomerDetailPage`, `IOSContractorsPage`, `IOSContractorDetailPage`, `IOSContactsPage`, `IOSContactDetailPage`, `IOSHatsPage`, `IOSPermissionsPage`, `IOSTeamsPage`, `PeopleRouter`
>
> **Note (2026-04-02):** `IOSContactDetailPage` was added as an unplanned improvement (plan-enforcer run 2) — it follows the same pattern as `IOSCustomerDetailPage` / `IOSContractorDetailPage` and is the natural completion of the Contacts page. `PeopleService.updateContact()` was added to support inline editing from this page. Both additions are consistent with the plan's intent and have been retroactively documented here.

---

## 1. People Dashboard

The People section opens to a dashboard overview before drilling into sub-pages.

### Dashboard Cards

| Card | Content | Tap Action |
|------|---------|------------|
| **Working Today** | Count of employees clocked in right now | Filter employee list to currently clocked-in |
| **Off Today** | Count of employees with time-off today | Filter to time-off list |
| **Certs Expiring** | Count of certifications expiring within 30 days | Navigate to cert expiration list |
| **Team Assignments** | Count of active team assignments | Navigate to Teams page |

### Quick Access

Below the cards, a list of recently viewed/edited people records for quick access.

---

## 2. Employee Detail Page (`IOSEmployeeDetailPage`)

### Full Page Layout

```
+--------------------------------------------------+
| [Back] Employee Name                   [Edit]     |
| Title · Department · Status Badge                 |
+--------------------------------------------------+
| [Photo]                                           |
|                                                   |
| CONTACT INFO                                      |
| Phone: (555) 123-4567                            |
| Email: john@company.com                          |
| Address: 123 Main St                             |
|                                                   |
| HATS & PERMISSIONS                                |
| [Hat Badge] [Hat Badge] [Hat Badge]              |
| (employees see their own hats but cannot toggle)  |
| (managers can toggle hats ON/OFF)                 |
|                                                   |
| CERTIFICATIONS                                    |
| Journeyman Electrician - Expires: 2027-03-15     |
| OSHA 30 - Expires: 2026-12-01 [WARNING]          |
|                                                   |
| SKILLS                                            |
| [Skill Badge] [Skill Badge] [Skill Badge]        |
|                                                   |
| CURRENT ASSIGNMENT                                |
| Job: Kitchen Remodel #12345                       |
| Team: Alpha Crew                                  |
| Schedule: Mon-Fri 7:00-3:30                      |
|                                                   |
| RECENT ACTIVITY                                   |
| Hours this week: 38.5                            |
| Jobs this month: 3                               |
| Last clock-in: Today 7:02 AM                     |
+--------------------------------------------------+
```

### Hat Visibility Rules

| Viewer | What They See |
|--------|--------------|
| **Employee viewing own profile** | Can see their own hats (read-only). Cannot toggle. |
| **Manager viewing employee** | Can see AND toggle hats ON/OFF (hat: `manage_hats`). |
| **Admin** | Full hat management + can create new hat types. |

### GRDB Removal Required

The current `IOSEmployeeDetailPage` has `import GRDB` and raw SQL queries. This MUST be refactored to use `PeopleService` methods exclusively. All database access through the service layer.

---

## 3. Customer Detail Page (`IOSCustomerDetailPage`)

Customers get a comprehensive detail page — they're the most important external entity.

### Full Page Layout

```
+--------------------------------------------------+
| [Back] Customer Name                   [Edit]     |
| Company Name · Status Badge                       |
+--------------------------------------------------+
|                                                   |
| CONTACT INFO                                      |
| Primary: John Smith - (555) 123-4567             |
| Email: john@customer.com                         |
| Address: 456 Oak Ave, Suite 200                  |
|                                                   |
| ADDITIONAL CONTACTS                               |
| Jane Smith (Billing) - (555) 987-6543            |
| Bob Johnson (Site Supervisor) - (555) 456-7890   |
| [+ Add Contact]                                   |
|                                                   |
| BUSINESS INFO                                     |
| Type: General Contractor                          |
| License #: GC-12345                              |
| Insurance: Verified (exp: 2027-01-01)            |
|                                                   |
| BILLING & PAYMENT [hat: view_customer_financials] |
| Payment Terms: Net 30                            |
| Payment Status: [====------] 60% on time         |
| Outstanding: $12,500                             |
| Overdue: $3,200 (45 days)                        |
|                                                   |
| JOB HISTORY                                       |
| Active Jobs: 2                                    |
| Completed Jobs: 15                               |
| Total Revenue: $1,245,000                        |
| [View All Jobs →]                                 |
|                                                   |
| COMMUNICATION HISTORY                             |
| Last Contact: March 20, 2026                     |
| Open Threads: 3                                  |
| [View Channels →]                                 |
|                                                   |
| DOCUMENTS                                         |
| Contract - Signed 2025-01-15                     |
| Insurance Certificate                            |
| W-9                                              |
| [+ Add Document]                                  |
|                                                   |
| STATS                                             |
| Avg Job Duration: 45 days                        |
| Avg Payment Speed: 28 days                       |
| Repeat Customer: Yes (since 2023)                |
+--------------------------------------------------+
```

### Payment Tracking

Payment tracking is a **company setting** — can be enabled or disabled globally.

When enabled:

| Element | Description |
|---------|-------------|
| **Payment bar** | Green-to-red gradient bar showing on-time payment percentage |
| **Color thresholds** | >90% = green, 70-90% = yellow, <70% = red |
| **Overdue alerts** | Banner on customer card when invoices are overdue |
| **Outstanding amount** | Total unpaid invoices |
| **Overdue amount** | Invoices past payment terms |
| **Hat required** | `view_customer_financials` to see payment data |

---

## 4. Contractor Detail Page (`IOSContractorDetailPage`)

### Contractor Types

| Type | Description | Rating System |
|------|-------------|---------------|
| **Subcontractor** | Does work on our jobs | Full ratings (quality, on-time, reliability) |
| **General Contractor (GC)** | Hires us for work | Notes only (no ratings) |
| **Contractor** | General business relationship | Notes only (no ratings) |

### Rating Rules

**Subcontractors get full ratings:**

| Rating | Calculation | Scale |
|--------|-------------|-------|
| **Quality** | Based on rework/callback rate | 1-5 stars |
| **On-Time** | Based on schedule adherence | 1-5 stars |
| **Reliability** | Weighted: 60% on-time + 40% quality | 1-5 stars (auto-calculated) |

**GCs and Contractors get notes only:**
- No star ratings
- Free-text notes field
- Notes visible to users with `view_contractor_notes` hat

### Qualifications Section (Optional)

Subcontractors can have a qualifications section:
- Certifications (with expiration tracking)
- Insurance info (with expiration tracking)
- License numbers
- Bond info
- This section is optional — not all subcontractors need it

### W-9 Tracking

All contractor types can have W-9 on file:
- W-9 status: On File, Requested, Expired, Not Required
- W-9 document attachment
- Annual reminder for W-9 renewal

---

## 5. Contacts Page (`IOSContactsPage`)

Unified contact list across all person types.

### Layout

```
+--------------------------------------------------+
| [Search Bar]                                      |
+--------------------------------------------------+
| ACTIVE CONTACTS                                   |
| [Smart Cards: All | Employees | Customers |       |
|  Contractors | Suppliers | Other]                  |
|                                                   |
| [Contact Card]                                    |
| [Contact Card]                                    |
| [Contact Card]                                    |
|                                                   |
| INACTIVE CONTACTS                                 |
| (collapsed section, tap to expand)                |
| [Contact Card - grayed out]                       |
+--------------------------------------------------+
```

### Smart Cards by Type

Each card shows count. Tap to filter.

### Sort Options

- **Recently Updated** (default) — most recently modified contacts first
- **Alphabetical** — A-Z by name
- **Type** — grouped by contact type
- **Company** — grouped by company/organization

### Active vs Inactive

- Active section shown first, always expanded
- Inactive section collapsed by default
- Inactive contacts shown with reduced opacity
- Toggle active/inactive via contact edit

---

## 5b. Contact Detail Page (`IOSContactDetailPage`) — Added 2026-04-02

Follows the same pattern as `IOSCustomerDetailPage` and `IOSContractorDetailPage`.

### Layout

```
+--------------------------------------------------+
| [Back] Contact Name                    [Edit]     |
+--------------------------------------------------+
| CONTACT INFORMATION                               |
| Name: First Last                                 |
| Type: [badge]                                    |
| Role / Company: Acme Corp                        |
| Phone: (555) 123-4567    [call]                  |
| Email: jane@acme.com     [mail]                  |
|                                                   |
| NOTES                                             |
| [notes text if any]                              |
+--------------------------------------------------+
```

### Edit Sheet (`EditContactSheet`)
- Inline edit: first name, last name, phone, email, role/company
- Calls `PeopleService.updateContact(id:firstName:lastName:phone:email:role:)` (added 2026-04-02)
- On save, parent page reloads via `onSave` callback

### Navigation Wiring
- `IOSContactsPage` uses `.navigationDestination(for: Int64.self)` → `IOSContactDetailPage(contactId:)`
- Contacts list passes the contact's `id` (Int64) into the navigation path

---

## 6. Teams Page (`IOSTeamsPage`)

Teams need a **full detail page**, not just a list.

### Team List

```
+--------------------------------------------------+
| TEAMS                                    [+ New]  |
+--------------------------------------------------+
| Alpha Crew                          [5 members]   |
| Currently on: Job #12345                          |
|                                                   |
| Beta Crew                          [4 members]    |
| Currently on: Job #67890                          |
|                                                   |
| Service Team                       [3 members]    |
| No current assignment                             |
+--------------------------------------------------+
```

### Team Detail Page

```
+--------------------------------------------------+
| [Back] Alpha Crew                      [Edit]     |
| Lead: John Smith · 5 Members                      |
+--------------------------------------------------+
|                                                   |
| MEMBERS                                           |
| John Smith (Lead)                                |
| Jane Doe                                         |
| Bob Wilson                                       |
| Mike Johnson                                     |
| Sarah Lee                                        |
| [+ Add Member] [- Remove Member]                 |
|                                                   |
| CURRENT ASSIGNMENT                                |
| Job: Kitchen Remodel #12345                       |
| Since: March 15, 2026                            |
| Stage: Rough-In                                  |
|                                                   |
| JOB HISTORY                                       |
| Last 5 jobs as a team:                           |
| - Job #12344 (completed Feb 2026)                |
| - Job #12340 (completed Jan 2026)                |
| - ...                                            |
|                                                   |
| TEAM STATS                                        |
| Avg job completion: 42 days                      |
| On-time rate: 87%                                |
| Together since: January 2025                     |
+--------------------------------------------------+
```

### Member Management

- Add members from employee list
- Remove members (with confirmation)
- Designate team lead
- View member availability (shows time-off conflicts)
- Permission required for every team or membership mutation: `manage_people`
- Team mutation service contracts require the acting user ID, verify `manage_people`
  inside the same database transaction as the write, and persist actor attribution.
- Users with `view_people` but without `manage_people` retain read-only access to the
  Teams list and detail pages; create/edit/delete/add/remove controls are not exposed.

---

## 7. Hats Page (`IOSHatsPage`)

Hats are the permission system — named permission bundles assigned to employees.

### Hat List

Shows all defined hats with member counts. Tap to see/edit members.

### Hat Assignment

- Managers can toggle hats on/off for employees
- Admin can create new hat types
- Hat changes are logged in audit trail
- Some hats are system-defined (cannot be deleted): Admin, Manager, Lead, Worker

---

## 8. Permissions Page (`IOSPermissionsPage`)

Fine-grained permission management.

- Shows all permissions grouped by area (Jobs, Parts, Orders, etc.)
- Each permission shows which hats include it
- Admin can customize which permissions are in which hats
- System permissions cannot be removed from Admin hat

---

## 9. Implementation Notes

### GRDB Removal Priority

The following files currently import GRDB and use raw SQL — they MUST be refactored to use service methods:

- `IOSEmployeeDetailPage.swift` — raw SQL for employee data
- Any other People files with `import GRDB`

**Rule:** All `import GRDB` must be replaced with service calls. Raw SQL edits must go through `PeopleService`.

### Service Layer Requirements

All people operations go through `PeopleService` in WiredPartCore.

Key service methods:
- `fetchEmployees(filter:)` — with active/inactive filter
- `fetchEmployeeDetail(id:)` — full employee with hats, certs, skills
- `fetchCustomerDetail(id:)` — full customer with contacts, jobs, payment
- `fetchContractorDetail(id:)` — full contractor with qualifications, ratings
- `fetchContacts(filter:, sort:)` — unified contact list
- `fetchTeams()` — team list with member counts
- `fetchTeamDetail(id:)` — full team with members, assignments, stats
- `updateHats(employeeId:, hats:)` — toggle hats (hat-gated)
- `fetchPaymentStatus(customerId:)` — payment tracking data

### Hat Permissions for People

| Hat | What It Controls |
|-----|-----------------|
| `manage_hats` | Toggle hats on/off for employees |
| `manage_people` | Create/edit/delete teams and manage team members |
| `view_customer_financials` | See payment tracking, outstanding amounts |
| `view_contractor_notes` | See contractor notes |
| `manage_certifications` | Add/edit/remove employee certifications |
| `view_wages` | See employee wage information |
| `manage_employees` | Create/edit employee records |
| `manage_customers` | Create/edit customer records |
| `manage_contractors` | Create/edit contractor records |

---

*Last updated: 2026-03-23*
