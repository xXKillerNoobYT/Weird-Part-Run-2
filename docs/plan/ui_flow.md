# UI Flow Map — macOS and iOS

> Page-by-page flow map showing screens, menus, navigation, data inputs/outputs, and layout anchors for both platforms.

---

## App Shell

### macOS Layout
```
┌──────────────────────────────────────────────────────────────┐
│ Window Title Bar (native macOS)                               │
├────────────┬─────────────────────────────────────────────────┤
│            │ Module Tab Bar (horizontal)                      │
│  Sidebar   ├─────────────────────────────────────────────────┤
│  (240px)   │                                                  │
│            │  Content Area                                    │
│  14 module │  (scrollable)                                   │
│  icons +   │                                                  │
│  labels    │  - Lists, forms, detail views                   │
│            │  - Responsive grid layout                       │
│            │                                                  │
│  ─────────│                                                  │
│  Sync      │                                                  │
│  Status    │                                                  │
│  User      │                                                  │
│  Avatar    │                                                  │
├────────────┴─────────────────────────────────────────────────┤
│ Status Bar (optional): Sync indicator, notification count     │
└──────────────────────────────────────────────────────────────┘
```

### iOS Layout
```
┌──────────────────────────┐
│ Navigation Bar            │
│ Module Title    [Actions] │
├──────────────────────────┤
│ Tab Bar (horizontal,      │
│ scrollable if >5 tabs)    │
├──────────────────────────┤
│                           │
│  Content Area             │
│  (scrollable)             │
│                           │
│  - Lists, forms           │
│  - Full-width cards       │
│  - Bottom sheets for      │
│    detail/edit            │
│                           │
├──────────────────────────┤
│ Bottom Tab Bar (5 main)   │
│ [Dash][Parts][Jobs]       │
│ [Orders][More...]         │
└──────────────────────────┘
```

---

## Navigation Modules (14)

### Module 1: Dashboard

| Screen | Route | macOS Layout | iOS Layout | Data In | Data Out |
|--------|-------|-------------|------------|---------|----------|
| Dashboard | `/` | 4-column summary cards + activity feed + alerts list | Stacked cards + activity list | — | — |

**Layout anchors:**
- Summary cards: Active Jobs, Pending Sync, Stock Alerts, Cert Expiry
- Recent Activity: last 20 entries, chronological
- Quick actions: New Job, Sync Now, View Alerts

---

### Module 2: Parts & Inventory

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Catalog | `/parts/catalog` | Filterable table + card toggle | Scrollable list | search, filters | part selection |
| Part Detail | `/parts/:id` | Split: info left, stock right | Full-page detail | part ID | — |
| Part Form | `/parts/new`, `/parts/:id/edit` | Form with sections | Sheet/modal form | part data | saved part |
| Categories | `/parts/categories` | Tree editor (OutlineGroup) | Expandable list | — | category CRUD |
| Brands | `/parts/brands` | Searchable table | Searchable list | — | brand CRUD |
| Suppliers | `/parts/suppliers` | Table + detail side panel | List → detail push | — | supplier CRUD |
| Supplier Detail | `/parts/suppliers/:id` | Tabbed: info, contacts, parts, orders | Tabbed sections | supplier ID | — |
| Pricing | `/parts/pricing` | Editable table with inline editing | List with edit sheets | — | price updates |
| Companions | `/parts/companions` | Rule editor, drag-drop | Rule list + add sheet | — | rule CRUD |
| Forecasting | `/parts/forecasting` | Charts + reorder suggestions | Scrollable charts | — | — |
| Import/Export | `/parts/import-export` | File picker, preview table, confirm | Same (FileImporter) | CSV/JSON file | imported parts |

**Key SwiftUI components:**
- `CatalogView` — `List` with `.searchable`, toggle between list/grid
- `CategoriesView` — `OutlineGroup` for tree hierarchy
- `PricingView` — `Table` (macOS) or `List` (iOS) with inline editing

---

### Module 3: Warehouse

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Dashboard | `/warehouse` | Stock summary cards + low-stock alerts | Stacked cards | — | — |
| Movements | `/warehouse/movements` | Filterable table with date range | Scrollable list | date range, filters | — |
| Movement Wizard | `/warehouse/move` | Multi-step form (stepper) | Sheet with steps | — | stock movement |
| Staging | `/warehouse/staging` | Pulled items grouped by job | Grouped list | — | movement actions |
| Receiving | `/warehouse/receiving` | Session-based, QR scan + line items | Same + DataScanner | PO reference | received items |
| Returns | `/warehouse/returns` | Return sorting interface | Categorized list | — | return disposition |
| Audit | `/warehouse/audit` | Full inventory count interface | Scrollable count list | — | audit results |
| Network | `/warehouse/network` | Peer devices with sync status | Peer list | — | — |

**Key SwiftUI components:**
- `ReceivingView` — integrates `DataScannerViewController` for QR/barcode
- `MovementWizardView` — `Stepper`-style multi-step form

---

### Module 4: Jobs & Labor

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Active Jobs | `/jobs` | Table with status filters | List with status chips | filters | job selection |
| Job Detail | `/jobs/:id` | Tabbed: info, parts, labor, notes, orders | Tabbed sections | job ID | — |
| Job Form | `/jobs/new`, `/jobs/:id/edit` | Multi-section form | Sheet form | — | saved job |
| My Clock | `/jobs/my-clock` | Clock in/out + active timer + GPS | Full-page clock UI | — | labor entry |
| Clock Out | `/jobs/clock-out` | Multi-step questionnaire | Sheet with steps | — | clock-out data |
| Daily Reports | `/jobs/daily-reports` | Date-grouped report list | Date picker + list | — | — |

**Key SwiftUI components:**
- `ClockInOutView` — `CLLocationManager` for GPS, `Timer` for active clock display
- `JobDetailView` — `TabView` with 5+ tabs
- `QuestionnaireView` — dynamic form builder from template

---

### Module 5: Orders & Procurement

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| My Orders | `/orders` | Table with status tabs | Segmented list | — | — |
| Unified Order | `/orders/new` | Multi-section form: job prefs, line items, special items | Sheet form | job context | JPO |
| JPO Detail | `/orders/jpo/:id` | Split: header + line items | Tabbed detail | JPO ID | — |
| Purchase Orders | `/orders/purchase-orders` | Table with status filters | Filtered list | — | — |
| PO Detail | `/orders/po/:id` | Header + line items + actions | Tabbed detail | PO ID | — |
| Procurement | `/orders/procurement` | Planner view: suggested POs by supplier | Grouped suggestions | — | generated POs |
| Returns | `/orders/returns` | Return list + detail | List → detail | — | — |
| Return Analytics | `/orders/return-analytics` | Charts + supplier breakdown | Scrollable charts | — | — |

**Key SwiftUI components:**
- `UnifiedOrderView` — complex form with job prefs, searchable part picker, special items
- `ProcurementView` — auto-generated PO suggestions from pending JPOs
- PDF generation via `PDFKit` (replaces browser print-to-PDF)

---

### Module 6: People & Contacts

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Employees | `/people/employees` | Table with search | Searchable list | — | — |
| Employee Detail | `/people/employees/:id` | Tabbed: info, certs, wages, skills, notes | Tabbed detail | employee ID | — |
| Customers | `/people/customers` | Table + detail panel | List → detail | — | — |
| Customer Detail | `/people/customers/:id` | Info + job history | Tabbed detail | customer ID | — |
| Contractors | `/people/contractors` | Table | List | — | — |
| Contractor Detail | `/people/contractors/:id` | Info + work history | Tabbed detail | contractor ID | — |
| Contacts | `/people/contacts` | Directory with entity filter | Searchable directory | — | — |
| Teams | `/people/teams` | Team cards with member lists | Expandable cards | — | team CRUD |
| Hats | `/people/hats` | Hat list with permission editor | List → permissions | — | hat CRUD |
| Permissions | `/people/permissions` | Matrix view: hats × permissions | Grouped toggles | — | permission updates |

---

### Module 7: Scheduling

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Calendar | `/scheduling/calendar` | Week grid with job blocks | Scrollable day view | week | — |
| Daily Dispatch | `/scheduling/dispatch` | Crew assignments per job | Job cards with crew | date | dispatch updates |
| Templates | `/scheduling/templates` | Template editor | Template list + editor | — | template CRUD |
| Config | `/scheduling/config` | Settings form | Settings form | — | config updates |
| Time Off | `/scheduling/time-off` | Request list + approval | Request cards | — | approval actions |
| Availability | `/scheduling/availability` | Weekly grid per employee | Employee availability list | — | availability updates |
| Sub-Schedule | `/scheduling/sub-schedule` | Subcontractor dispatch | Contractor cards | — | — |

**Key SwiftUI components:**
- `ScheduleCalendarView` — custom `ScrollView` + `LazyVGrid` week grid, drag-and-drop via `.draggable`/`.dropDestination`

---

### Module 8: Tools & Kits

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Registry | `/tools/registry` | Searchable table | List | — | tool CRUD |
| Kits | `/tools/kits` | Kit templates + verification | Kit cards | — | kit CRUD |
| Checkout | `/tools/checkout` | Checkout/return form | QR scan + form | — | checkout record |
| Maintenance | `/tools/maintenance` | Schedule + history | Maintenance list | — | maintenance records |

---

### Module 9: Fleet/Trucks

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Vehicles | `/trucks/vehicles` | Table with status indicators | Card list | — | — |
| Vehicle Detail | `/trucks/vehicles/:id` | Tabbed: info, assignments, maintenance, fuel, inspections | Tabbed detail | vehicle ID | — |
| Fuel | `/trucks/fuel` | Entry form + history table | Entry form + list | — | fuel entry |
| Inspections | `/trucks/inspections` | Checklist form + history | Checklist + photos | — | inspection record |
| Mileage | `/trucks/mileage` | Trip log + reimbursement calc | Trip list | — | trip records |
| Deliveries | `/trucks/deliveries` | Delivery schedule + tracking | Delivery cards | — | delivery updates |

---

### Module 10: Reports

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Reports List | `/reports` | Card grid of report types | List of report types | — | — |
| Report Builder | `/reports/:type` | Parameter form + preview | Form + preview | report type | report data |
| Share/Export | `/reports/:type/share` | PDF preview + email/print | Share sheet | report data | PDF file |
| Pre-Billing | `/reports/pre-billing` | Period selector + job rollup | Period list + details | date range | billing data |

---

### Module 11: Office

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| PO Management | `/office/po-management` | Split: PO list + detail panel | List → detail | — | PO actions |
| Approvals | `/office/approvals` | Pending approval queue | Approval cards | — | approve/reject |
| PDF Bundles | `/office/pdf-bundles` | Bundle builder + preview | Bundle config | — | PDF bundle |
| Review & Send | `/office/review-send` | Email composer with PDF attachments | Compose sheet | PO data | sent email |

---

### Module 12: Chat & Q&A

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Inbox | `/chat` | Channel list + message preview | Channel list | — | — |
| Direct Message | `/chat/:channelId` | Message thread + input | Message thread | channel ID | messages |
| Q&A Board | `/chat/qa` | Question list + escalation | Question cards | — | Q&A actions |

---

### Module 13: Notebooks

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Notebooks List | `/notebooks` | Card grid | Card list | — | — |
| Notebook Detail | `/notebooks/:id` | Sections sidebar + entries | Section tabs + entries | notebook ID | entries |
| Templates | `/notebooks/templates` | Template editor | Template list | — | template CRUD |

---

### Module 14: Settings

| Screen | Route | macOS | iOS | Data In | Data Out |
|--------|-------|-------|-----|---------|----------|
| Company Profile | `/settings/company` | Form with logo upload | Form | — | profile updates |
| App Config | `/settings/config` | Grouped toggles + pickers | Settings form | — | config updates |
| AI Settings | `/settings/ai-config` | Model status, toggles, test | Settings form | — | AI config |
| Backups | `/settings/backups` | Backup list + restore + export | Backup cards | — | backup/restore |
| Security | `/settings/security` | Cert management, PIN policy | Security settings | — | security updates |
| Devices | `/settings/devices` | Device registry + trust mgmt | Device list | — | trust actions |
| Sync | `/settings/sync` | Peer list, manual sync, shop URL | Sync settings | — | sync actions |
| Data Storage | `/settings/data-storage` | Private/public toggle | Storage settings | — | storage mode |

---

## Shared SwiftUI Components

These are reusable across all modules:

| Component | Purpose | Used In |
|-----------|---------|---------|
| `SearchableList<T>` | Filterable list with `.searchable` | Catalog, Employees, Contacts, Tools |
| `DetailTabView` | Tabbed detail page | Job, Vehicle, Employee, Supplier |
| `FormSection` | Grouped form fields with header | All edit forms |
| `StatusChip` | Colored status badge | Jobs, POs, JPOs, Returns |
| `EmptyStateView` | Placeholder when list is empty | All list views |
| `ErrorView` | Error with retry button | All views with data loading |
| `LoadingView` | Spinner with optional message | All async views |
| `AITextField` | TextEditor + ghost text + enhance | All Tier-1 text fields (Phase 12) |
| `EnhancePopover` | AI enhancement options popup | Paired with AITextField |
| `QRScannerView` | Camera-based QR/barcode scan | Warehouse, Tools |
| `PDFPreview` | In-app PDF viewer | Reports, PO bundles |
| `PINPadView` | Numeric PIN entry | Login, security confirm |
| `DateRangePickerView` | Start/end date selection | Reports, movements, mileage |
| `ConfirmDialog` | Destructive action confirmation | Delete, archive actions |

---

## Navigation State Machine

```
App Launch
  ├── First Launch → BootstrapView (company setup + admin creation)
  │                    └── → LoginView
  └── Existing DB → LoginView (user picker + PIN)
                       └── → MainView (sidebar + content)
                              ├── Module selected → Module root view
                              │     └── Tab selected → Tab content view
                              │           └── Row selected → Detail view
                              │                 └── Edit → Form view (sheet/push)
                              └── Unported route → WebFallbackView (WKWebView)
```

### Deep Linking

Every screen has a unique `AppDestination` enum case with associated data:
```swift
enum AppDestination: Hashable {
    case dashboard
    case partsCatalog
    case partDetail(id: Int64)
    case partForm(id: Int64?)
    case partsCategories
    // ... all 100+ routes
    case settings(section: SettingsSection)
}
```

This enables `NavigationStack` path-based navigation on macOS and `NavigationPath` on iOS.
