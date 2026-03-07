# People, Employees & Contacts Audit

> **Date:** 2026-03-06
> **Status:** ✅ Verified Complete (2026-03-07) — M3 gap closure: employee avatar upload UI (EmployeeDetailPage), CSV import, contact dedupe, cert document upload, billing/COI fields all implemented. Feature gaps listed below are closed.
> **Scope:** Full audit of the People module — employees, certifications, wages, notes, skills, hats/permissions, elevations, customers, general contractors, supplier contacts, contact directory

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

### Router: `backend/app/routers/people.py` (~553 lines)

Mounted in `main.py` as `app.routers.people`. Prefix: `/api/people`.

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 1 | `GET` | `/employees` | List employees (paginated, search, active filter) | `view_people` | ✅ Functional |
| 2 | `GET` | `/employees/{user_id}` | Get employee detail | `view_people` | ✅ Functional |
| 3 | `POST` | `/employees` | Create employee | `manage_people` | ✅ Functional |
| 4 | `PUT` | `/employees/{user_id}` | Update employee | `manage_people` | ✅ Functional |
| 5 | `PATCH` | `/employees/{user_id}/toggle-active` | Toggle active/inactive | `manage_people` | ✅ Functional |
| 6 | `GET` | `/employees/{user_id}/certifications` | List certifications for employee | `view_people` | ✅ Functional |
| 7 | `POST` | `/employees/{user_id}/certifications` | Add certification | `manage_people` | ✅ Functional |
| 8 | `PUT` | `/certifications/{cert_id}` | Update certification | `manage_people` | ✅ Functional |
| 9 | `DELETE` | `/certifications/{cert_id}` | Delete certification | `manage_people` | ✅ Functional |
| 10 | `GET` | `/certifications/expiring` | Certs expiring within N days | `view_people` | ✅ Functional |
| 11 | `GET` | `/employees/{user_id}/wages` | Get wage history | `show_dollar_values` | ✅ Functional |
| 12 | `POST` | `/employees/{user_id}/wages` | Add wage record | `manage_people` + `show_dollar_values` | ✅ Functional |
| 13 | `GET` | `/employees/{user_id}/notes` | List notes for employee | `view_people` | ✅ Functional |
| 14 | `POST` | `/employees/{user_id}/notes` | Add note | `manage_people` | ✅ Functional |
| 15 | `PUT` | `/notes/{note_id}` | Update note | `manage_people` | ✅ Functional |
| 16 | `DELETE` | `/notes/{note_id}` | Delete note | `manage_people` | ✅ Functional |
| 17 | `GET` | `/employees/{user_id}/skills` | List skills for employee | `view_people` | ✅ Functional |
| 18 | `POST` | `/employees/{user_id}/skills` | Add skill | `manage_people` | ✅ Functional |
| 19 | `PUT` | `/skills/{skill_id}` | Update skill | `manage_people` | ✅ Functional |
| 20 | `DELETE` | `/skills/{skill_id}` | Delete skill | `manage_people` | ✅ Functional |
| 21 | `GET` | `/hats` | List all hats (roles) | `view_people` | ✅ Functional |
| 22 | `POST` | `/hats` | Create hat | `manage_people` | ✅ Functional |
| 23 | `PUT` | `/hats/{hat_id}` | Update hat | `manage_people` | ✅ Functional |
| 24 | `DELETE` | `/hats/{hat_id}` | Delete hat | `manage_people` | ✅ Functional |
| 25 | `PUT` | `/hats/{hat_id}/permissions` | Set permissions for hat | `manage_people` | ✅ Functional |
| 26 | `GET` | `/permissions/matrix` | Full permission matrix (hats × keys) | `view_people` | ✅ Functional |
| 27 | `GET` | `/permissions/keys` | List all known permission keys | `view_people` | ✅ Functional |
| 28 | `GET` | `/employees/{user_id}/elevations` | List job-lead elevations | `view_people` | ✅ Functional |
| 29 | `POST` | `/employees/{user_id}/elevations` | Grant job-lead elevation | `manage_people` | ✅ Functional |
| 30 | `DELETE` | `/elevations/{elevation_id}` | Revoke single elevation | `manage_people` | ✅ Functional |
| 31 | `DELETE` | `/employees/{user_id}/elevations/job/{job_id}` | Revoke all elevations for user+job | `manage_people` | ✅ Functional |
| 32 | `GET` | `/cert-alerts` | Cert expiry alerts (configurable look-ahead) | `view_people` | ✅ Functional |

**Total endpoints: 32**

### Router: `backend/app/routers/contacts.py` (~407 lines)

Mounted in `main.py` as `app.routers.contacts`. Prefix: `/api/contacts`.

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 1 | `GET` | `/customers` | List customers (paginated, search, active filter) | `view_customers` | ✅ Functional |
| 2 | `GET` | `/customers/search` | Search customers by name (lightweight) | `view_customers` | ✅ Functional |
| 3 | `GET` | `/customers/{customer_id}` | Get customer detail | `view_customers` | ✅ Functional |
| 4 | `POST` | `/customers` | Create customer | `manage_customers` | ✅ Functional |
| 5 | `PUT` | `/customers/{customer_id}` | Update customer | `manage_customers` | ✅ Functional |
| 6 | `PATCH` | `/customers/{customer_id}/toggle-active` | Toggle active/inactive | `manage_customers` | ✅ Functional |
| 7 | `GET` | `/customers/{customer_id}/contacts` | List contacts for customer | `view_customers` | ✅ Functional |
| 8 | `POST` | `/customers/{customer_id}/contacts` | Add contact to customer | `manage_customers` | ✅ Functional |
| 9 | `GET` | `/customers/{customer_id}/jobs` | List jobs linked to customer | `view_customers` | ✅ Functional |
| 10 | `GET` | `/general-contractors` | List GCs (paginated, search, active filter) | `view_contractors` | ✅ Functional |
| 11 | `GET` | `/general-contractors/search` | Search GCs by name (lightweight) | `view_contractors` | ✅ Functional |
| 12 | `GET` | `/general-contractors/{gc_id}` | Get GC detail | `view_contractors` | ✅ Functional |
| 13 | `POST` | `/general-contractors` | Create GC | `manage_contractors` | ✅ Functional |
| 14 | `PUT` | `/general-contractors/{gc_id}` | Update GC | `manage_contractors` | ✅ Functional |
| 15 | `PATCH` | `/general-contractors/{gc_id}/toggle-active` | Toggle active/inactive | `manage_contractors` | ✅ Functional |
| 16 | `GET` | `/general-contractors/{gc_id}/contacts` | List contacts for GC | `view_contractors` | ✅ Functional |
| 17 | `POST` | `/general-contractors/{gc_id}/contacts` | Add contact to GC | `manage_contractors` | ✅ Functional |
| 18 | `GET` | `/general-contractors/{gc_id}/jobs` | List jobs linked to GC | `view_contractors` | ✅ Functional |
| 19 | `GET` | `/suppliers/{supplier_id}/contacts` | List contacts for supplier | `edit_parts_catalog` | ✅ Functional |
| 20 | `POST` | `/suppliers/{supplier_id}/contacts` | Add contact to supplier | `edit_parts_catalog` | ✅ Functional |
| 21 | `GET` | `/directory` | Cross-entity contact directory search | any authenticated | ✅ Functional |
| 22 | `PUT` | `/entity-contacts/{contact_id}` | Update any entity contact | varies by entity type | ✅ Functional |
| 23 | `DELETE` | `/entity-contacts/{contact_id}` | Delete any entity contact | varies by entity type | ✅ Functional |

**Total endpoints: 23**

**Combined People + Contacts: 55 endpoints**

### Service: `backend/app/services/people_service.py` (~552 lines)

Orchestrates all employee, certification, wage, note, skill, hat, permission, and elevation operations. Dependencies:
- `PeopleRepo` (CertificationRepo, EmployeeNoteRepo, UserSkillRepo, WageHistoryRepo)
- `UserRepo` (from auth) — for employee CRUD since employees are users
- `AuthService` — for PIN/password management on create

Key business logic:
- Employee create: generates unique PIN, creates user + sets initial hat
- Toggle-active: soft delete pattern (is_active flag)
- Permission matrix: aggregates hat_id → permission_key mappings into a grid
- Cert alerts: SQL join on `employee_certifications` + `users` with expiry window

### Service: `backend/app/services/contacts_service.py` (~309 lines)

Orchestrates customer, GC, entity contact, and job-linking operations. Dependencies:
- `ContactsRepo` (CustomerRepo, GeneralContractorRepo, EntityContactRepo, JobCustomerRepo, JobGCRepo)

Key business logic:
- Contact directory: searches across all entity types (customer, GC, supplier)
- Entity contact update/delete: looks up entity type from contact_id, then checks appropriate permission
- Job linking: creates `job_customers` and `job_gcs` association records

### Repository: `backend/app/repositories/people_repo.py` (~168 lines)

Contains 4 focused repos, all extending `BaseRepository`:
- `CertificationRepo` — CRUD on `employee_certifications`
- `EmployeeNoteRepo` — CRUD on `employee_notes`
- `UserSkillRepo` — CRUD on `user_skills`
- `WageHistoryRepo` — CRUD on `wage_history`

Note: Employee CRUD itself lives in `UserRepo` (auth layer), not here.

### Repository: `backend/app/repositories/contacts_repo.py` (~341 lines)

Contains 5 repos:
- `CustomerRepo` — CRUD on `customers` + search + toggle-active
- `GeneralContractorRepo` — CRUD on `general_contractors` + search + toggle-active
- `EntityContactRepo` — polymorphic contacts across customer/GC/supplier entities
- `JobCustomerRepo` — `job_customers` link table
- `JobGCRepo` — `job_gcs` link table

### Models: `backend/app/models/people.py` (~316 lines)

20+ Pydantic models organized by domain:

**Certifications:** `CertificationCreate`, `CertificationUpdate`, `CertificationResponse`
**Wages:** `WageHistoryCreate`, `WageHistoryResponse`
**Notes:** `EmployeeNoteCreate`, `EmployeeNoteUpdate`, `EmployeeNoteResponse`
**Skills:** `UserSkillCreate`, `UserSkillUpdate`, `UserSkillResponse`
**Employees:** `EmployeeCreate`, `EmployeeUpdate`, `EmployeeListItem`, `EmployeeDetail` (includes certs, wages, notes, skills as nested lists)
**Hats/Roles:** `HatSummaryResponse`, `HatCreate`, `HatUpdate`, `HatDetailResponse` (includes members + permissions)
**Permissions:** `PermissionAssignment`, `PermissionMatrixRow`
**Elevations:** `JobLeadElevationCreate`, `JobLeadElevationResponse`
**Alerts:** `CertAlertItem`

### Models: `backend/app/models/contacts.py` (~299 lines)

15+ Pydantic models with shared enums:

**Enums/Literals:** `CUSTOMER_TYPES`, `GC_TRADE_TYPES`, `ENTITY_TYPES`, `CONTACT_ROLES`, `GC_RELATIONSHIPS`
**Customers:** `CustomerCreate`, `CustomerUpdate`, `CustomerResponse`, `CustomerListItem`
**General Contractors:** `GCCreate`, `GCUpdate`, `GCResponse`, `GCListItem`
**Entity Contacts:** `EntityContactCreate`, `EntityContactUpdate`, `EntityContactResponse`
**Directory:** `DirectoryContactResult` (unified search result across entity types)
**Job Linking:** `JobCustomerCreate`, `JobCustomerResponse`, `JobGCCreate`, `JobGCResponse`

### Models: `backend/app/models/company.py` (~82 lines)

Company profile models used for PO branding and multi-branch support:
**Models:** `CompanyProfileCreate`, `CompanyProfileUpdate`, `CompanyProfileResponse`

### API Client: `frontend/src/api/people.ts` (~395 lines)

| Function | Endpoint | Returns |
|----------|----------|---------|
| `getEmployees(params)` | `GET /people/employees` | `PaginatedResponse<Employee>` |
| `getEmployee(id)` | `GET /people/employees/:id` | `EmployeeDetail` |
| `createEmployee(data)` | `POST /people/employees` | `Employee` |
| `updateEmployee(id, data)` | `PUT /people/employees/:id` | `Employee` |
| `toggleEmployeeActive(id)` | `PATCH /people/employees/:id/toggle-active` | `Employee` |
| `getEmployeeCerts(id)` | `GET /people/employees/:id/certifications` | `Certification[]` |
| `addCertification(id, data)` | `POST /people/employees/:id/certifications` | `Certification` |
| `updateCertification(id, data)` | `PUT /people/certifications/:id` | `Certification` |
| `deleteCertification(id)` | `DELETE /people/certifications/:id` | `void` |
| `getExpiringCerts(days)` | `GET /people/certifications/expiring` | `Certification[]` |
| `getWageHistory(id)` | `GET /people/employees/:id/wages` | `WageHistory[]` |
| `addWageRecord(id, data)` | `POST /people/employees/:id/wages` | `WageHistory` |
| `getEmployeeNotes(id)` | `GET /people/employees/:id/notes` | `EmployeeNote[]` |
| `addEmployeeNote(id, data)` | `POST /people/employees/:id/notes` | `EmployeeNote` |
| `updateEmployeeNote(id, data)` | `PUT /people/notes/:id` | `EmployeeNote` |
| `deleteEmployeeNote(id)` | `DELETE /people/notes/:id` | `void` |
| `getEmployeeSkills(id)` | `GET /people/employees/:id/skills` | `UserSkill[]` |
| `addSkill(id, data)` | `POST /people/employees/:id/skills` | `UserSkill` |
| `updateSkill(id, data)` | `PUT /people/skills/:id` | `UserSkill` |
| `deleteSkill(id)` | `DELETE /people/skills/:id` | `void` |
| `getHats()` | `GET /people/hats` | `HatSummary[]` |
| `createHat(data)` | `POST /people/hats` | `Hat` |
| `getHat(id)` | `GET /people/hats/:id` | `HatDetail` |
| `updateHat(id, data)` | `PUT /people/hats/:id` | `Hat` |
| `deleteHat(id)` | `DELETE /people/hats/:id` | `void` |
| `setHatPermissions(id, data)` | `PUT /people/hats/:id/permissions` | `void` |
| `getPermissionMatrix()` | `GET /people/permissions/matrix` | `PermissionMatrixRow[]` |
| `getPermissionKeys()` | `GET /people/permissions/keys` | `string[]` |
| `getElevations(id)` | `GET /people/employees/:id/elevations` | `Elevation[]` |
| `grantElevation(id, data)` | `POST /people/employees/:id/elevations` | `Elevation` |
| `revokeElevation(id)` | `DELETE /people/elevations/:id` | `void` |
| `revokeJobElevations(userId, jobId)` | `DELETE /people/employees/:id/elevations/job/:jobId` | `void` |
| `getCertAlerts()` | `GET /people/cert-alerts` | `CertAlertItem[]` |

### API Client: `frontend/src/api/contacts.ts` (~392 lines)

| Function | Endpoint | Returns |
|----------|----------|---------|
| `getCustomers(params)` | `GET /contacts/customers` | `PaginatedResponse<Customer>` |
| `searchCustomers(q)` | `GET /contacts/customers/search` | `Customer[]` |
| `getCustomer(id)` | `GET /contacts/customers/:id` | `Customer` |
| `createCustomer(data)` | `POST /contacts/customers` | `Customer` |
| `updateCustomer(id, data)` | `PUT /contacts/customers/:id` | `Customer` |
| `toggleCustomerActive(id)` | `PATCH /contacts/customers/:id/toggle-active` | `Customer` |
| `getCustomerContacts(id)` | `GET /contacts/customers/:id/contacts` | `EntityContact[]` |
| `addCustomerContact(id, data)` | `POST /contacts/customers/:id/contacts` | `EntityContact` |
| `getCustomerJobs(id)` | `GET /contacts/customers/:id/jobs` | `Job[]` |
| `getGCs(params)` | `GET /contacts/general-contractors` | `PaginatedResponse<GC>` |
| `searchGCs(q)` | `GET /contacts/general-contractors/search` | `GC[]` |
| `getGC(id)` | `GET /contacts/general-contractors/:id` | `GC` |
| `createGC(data)` | `POST /contacts/general-contractors` | `GC` |
| `updateGC(id, data)` | `PUT /contacts/general-contractors/:id` | `GC` |
| `toggleGCActive(id)` | `PATCH /contacts/general-contractors/:id/toggle-active` | `GC` |
| `getGCContacts(id)` | `GET /contacts/general-contractors/:id/contacts` | `EntityContact[]` |
| `addGCContact(id, data)` | `POST /contacts/general-contractors/:id/contacts` | `EntityContact` |
| `getGCJobs(id)` | `GET /contacts/general-contractors/:id/jobs` | `Job[]` |
| `getSupplierContacts(id)` | `GET /contacts/suppliers/:id/contacts` | `EntityContact[]` |
| `addSupplierContact(id, data)` | `POST /contacts/suppliers/:id/contacts` | `EntityContact` |
| `searchDirectory(q)` | `GET /contacts/directory` | `DirectoryContact[]` |
| `updateEntityContact(id, data)` | `PUT /contacts/entity-contacts/:id` | `EntityContact` |
| `deleteEntityContact(id)` | `DELETE /contacts/entity-contacts/:id` | `void` |

---

## 2. Frontend Inventory

### Directory: `frontend/src/features/people/pages/`

| File | Lines | Type | Status |
|------|-------|------|--------|
| `EmployeeListPage.tsx` | ~391 | Employee list + create modal | ✅ Functional |
| `EmployeeDetailPage.tsx` | ~700 | Full detail with tabs (certs, wages, notes, skills) | ✅ Functional |
| `HatsPage.tsx` | ~487 | Hat/role CRUD with permission editing | ✅ Functional |
| `PermissionsPage.tsx` | ~286 | Permission matrix grid (hats × keys) | ✅ Functional |
| `CustomersPage.tsx` | ~454 | Customer list + create modal | ✅ Functional |
| `CustomerDetailPage.tsx` | ~582 | Customer detail with contacts + linked jobs | ✅ Functional |
| `ContractorsPage.tsx` | ~457 | GC list + create modal | ✅ Functional |
| `ContractorDetailPage.tsx` | ~648 | GC detail with contacts + linked jobs | ✅ Functional |
| `ContactDirectoryPage.tsx` | ~177 | Unified contact search across entity types | ✅ Functional |

**Total: 9 pages, ~4,182 lines**

### Navigation Config (`frontend/src/lib/navigation.ts`)

```typescript
{
  id: 'people',
  label: 'People',
  icon: 'Users',
  path: '/people',
  permission: 'view_people',
  tabs: [
    { id: 'employees', label: 'Employees', path: '/people/employees' },
    { id: 'customers', label: 'Customers', path: '/people/customers', permission: 'view_customers' },
    { id: 'contractors', label: 'Contractors', path: '/people/contractors', permission: 'view_contractors' },
    { id: 'contacts', label: 'All Contacts', path: '/people/contacts' },
    { id: 'hats', label: 'Roles / Hats', path: '/people/hats' },
    { id: 'permissions', label: 'Permissions', path: '/people/permissions' },
  ],
}
```

6 tabs, gated by `view_people` at the module level, with per-tab permissions on customers and contractors.

### Page Details

**EmployeeListPage** (~391 lines):
- Paginated employee list with search input and active/all toggle
- Create Employee modal with full form (name, display name, phone, email, hat selection)
- Each row shows name, hat, phone, active/inactive badge, click → detail page
- Uses `react-query` for pagination + search debouncing

**EmployeeDetailPage** (~700 lines):
- Header with employee info, edit button, toggle-active button
- Tabbed/sectioned content:
  - **Certifications**: List with add/edit/delete modals. Shows cert name, issuer, dates, status badge (valid/expiring/expired)
  - **Wage History**: List of wage records (permission-gated: `show_dollar_values`). Add wage modal with rate, type, effective date
  - **Notes**: Timestamped notes with add/edit/delete. Shows author
  - **Skills**: Skill list with proficiency level. Add/edit/delete modals
- Largest People page by line count

**HatsPage** (~487 lines):
- Lists all hats (roles) with member count and description
- Create/Edit hat modal (name, description, color)
- Inline permission editing per hat — shows all permission keys with toggle checkboxes
- Delete hat with confirmation dialog

**PermissionsPage** (~286 lines):
- Grid/matrix view: rows = permission keys, columns = hats
- Checkbox toggles for each hat × permission intersection
- Groups permissions by category (view_*, manage_*, etc.)
- Bulk save pattern — edits are applied immediately via `setHatPermissions`

**CustomersPage** (~454 lines):
- Paginated customer list with search and active/all filter
- Create Customer modal (company name, type, address, phone, email, notes)
- Customer type filter using `CUSTOMER_TYPES` enum

**CustomerDetailPage** (~582 lines):
- Header with customer info + edit/toggle-active
- Contact list section with add-contact modal (name, role, phone, email)
- Linked jobs section showing all jobs associated with this customer
- Click contact → inline edit or delete

**ContractorsPage** (~457 lines):
- Paginated GC list with search and active/all filter
- Create GC modal (company name, trade type, relationship, address, phone, email)
- Trade type uses `GC_TRADE_TYPES` enum

**ContractorDetailPage** (~648 lines):
- Header with GC info + edit/toggle-active
- Contact list section with add-contact modal
- Linked jobs section
- Similar structure to CustomerDetailPage but with GC-specific fields (trade, relationship)

**ContactDirectoryPage** (~177 lines):
- Single search input that queries across all entity types
- Results show contact name, organization, entity type badge, role, phone, email
- Lightest page — purely a search/discovery tool

---

## 3. Feature Completeness

### Employees

| Feature | Status | Notes |
|---------|--------|-------|
| Employee list with pagination + search | ✅ Complete | Full pagination, search debounce, active filter |
| Employee CRUD | ✅ Complete | Create with PIN generation, update, soft-delete toggle |
| Certification CRUD | ✅ Complete | Full lifecycle with expiry tracking |
| Expiring cert alerts | ✅ Complete | Configurable look-ahead (days param) |
| Wage history | ✅ Complete | Permission-gated behind `show_dollar_values` |
| Employee notes | ✅ Complete | Full CRUD with author tracking |
| Skills tracking | ✅ Complete | CRUD with proficiency level |
| Responsive layout | ✅ Complete | All pages use Tailwind responsive classes |

### Hats & Permissions

| Feature | Status | Notes |
|---------|--------|-------|
| Hat CRUD | ✅ Complete | Create, edit, delete with confirmation |
| Permission assignment per hat | ✅ Complete | Toggle checkboxes per permission key |
| Permission matrix view | ✅ Complete | Full grid: hats × permissions |
| Permission keys listing | ✅ Complete | Dynamic from backend |
| Job-lead elevations | ✅ Complete | Grant per user+job, revoke single or bulk |

### Customers

| Feature | Status | Notes |
|---------|--------|-------|
| Customer list + search | ✅ Complete | Paginated with type filter |
| Customer CRUD | ✅ Complete | Full form with address, type, notes |
| Customer contacts | ✅ Complete | Polymorphic entity contacts (add, edit, delete) |
| Customer → Job linking | ✅ Complete | View jobs linked to customer |
| Toggle active/inactive | ✅ Complete | Soft-delete pattern |

### General Contractors

| Feature | Status | Notes |
|---------|--------|-------|
| GC list + search | ✅ Complete | Paginated with trade type |
| GC CRUD | ✅ Complete | Full form with trade, relationship, address |
| GC contacts | ✅ Complete | Same polymorphic entity contact system |
| GC → Job linking | ✅ Complete | View jobs linked to GC |
| Toggle active/inactive | ✅ Complete | Soft-delete pattern |

### Contacts / Directory

| Feature | Status | Notes |
|---------|--------|-------|
| Supplier contacts | ✅ Complete | Get/add contacts for suppliers |
| Cross-entity directory search | ✅ Complete | Searches customers, GCs, suppliers |
| Entity contact update/delete | ✅ Complete | Permission-checks by parent entity type |

**Overall: 100% functional — no stubs, no placeholders**

---

## 4. Cross-References

### Backend Dependencies

| People Feature | External Service/Router | Table(s) |
|----------------|------------------------|-----------|
| Employee CRUD | `UserRepo` (auth layer) | `users` |
| Employee create | `AuthService` (PIN gen) | `users` |
| Cert alerts | Direct SQL join | `employee_certifications`, `users` |
| Job-lead elevations | Direct SQL | `job_lead_elevations`, `jobs` |
| Customer/GC → Jobs | `ContactsRepo` via join | `job_customers`, `job_gcs`, `jobs` |
| Supplier contacts | `EntityContactRepo` | `entity_contacts`, `suppliers` |

### Consumers of People/Contacts Data

| External Module | How It Uses People/Contacts |
|-----------------|----------------------------|
| **Dashboard** | `PeopleService.get_cert_alerts()` — cert expiry widget |
| **Jobs** | `ContactsService` — link customers/GCs to jobs |
| **Scheduling** | `getEmployees()` API call — ScheduleConfigPage loads employee list |
| **Scheduling** | `searchGCs()` API call — SubSchedulePage searches GCs for subcontractor scheduling |

### Frontend Dependencies

| People Feature | API Client | Shared Components |
|----------------|------------|-------------------|
| Employee list | `api/people.ts` | `Card`, `Badge`, `Input`, `Spinner` |
| Employee detail | `api/people.ts` | `Card`, `Badge`, `Button`, `Dialog` |
| Hats/Permissions | `api/people.ts` | `Card`, `Checkbox`, `Dialog` |
| Customer/GC list | `api/contacts.ts` | `Card`, `Badge`, `Input`, `Spinner` |
| Customer/GC detail | `api/contacts.ts` | `Card`, `Badge`, `Button`, `Dialog` |
| Contact directory | `api/contacts.ts` | `Card`, `Input`, `Badge` |

### Navigation Cross-references

- Dashboard cert alerts link to → `/people/employees/:id`
- Job detail pages show linked customers/GCs from contacts
- Scheduling pages import from `api/people.ts` and `api/contacts.ts`

---

## 5. Issues & TODOs

### No TODO/FIXME Comments Found

Zero TODO, FIXME, HACK, or TEMP comments in any People or Contacts file (backend or frontend).

### Architectural Notes

1. **Employee CRUD split across two layers** — Employee records live in the `users` table (auth layer), so `PeopleService` delegates to `UserRepo` for create/update/toggle. The `people_repo.py` only handles supplementary entities (certs, notes, skills, wages). This is intentional — employees ARE users — but creates a dependency on the auth layer for employee management.

2. **No dedicated PeopleRepo for employees** — `people_repo.py` (168 lines) is surprisingly small because the main employee queries run through `UserRepo`. A future refactor could consolidate all employee queries into one place, but the current split works.

3. **Entity contacts are polymorphic** — The `entity_contacts` table uses `entity_type` + `entity_id` columns to associate contacts with customers, GCs, or suppliers. The update/delete endpoints look up the entity type first, then check the appropriate permission. This works but means permission checks require an extra DB read.

4. **Contact directory search is broad** — The `/directory` endpoint searches across all entity types in a single query. No permission gate beyond authentication — any logged-in user can search all contacts. This may need tightening if contact visibility should be role-restricted.

5. **Job linking is read-only from contacts side** — Customers/GCs show linked jobs but cannot create/delete the link from the contacts pages. Job linking is managed from the Jobs module. This is intentional but may confuse users who expect two-way management.

6. **Wage history is append-only** — There's no update or delete for wage records, only add. This preserves audit trail but means corrections require adding a new record.

### Feature Gaps

- **No employee photo/avatar** — Employee records have no image field. The list and detail pages show initials only.
- **No bulk employee operations** — No bulk create, bulk deactivate, or CSV import for employees.
- **No contact merge/dedup** — If the same person is added as a contact under multiple entities, there's no way to merge or detect duplicates.
- **No customer/GC import** — No CSV or batch import for customers or general contractors.
- **No certification document upload** — Certs track metadata (name, issuer, dates) but have no document/image attachment.
- **No customer billing info** — Customers have basic info but no billing address, payment terms, or tax ID fields.
- **No GC insurance tracking** — GCs don't track COI (Certificate of Insurance) or expiration, which is common in construction.
