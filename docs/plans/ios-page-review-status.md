# iOS Page-by-Page Review Status

> **Date started:** 2026-03-19
> **Approach:** Review each page in the app for design, functionality, bugs, missing UI elements. Write Xcode AI prompts for all fixes.

## Review Progress

| Page Area | Pages | Status | Prompts |
|-----------|-------|--------|---------|
| **Foundation fixes** | All pages | DONE | 01-05 (sheet, errors, spinners, sync stubs, AppCore) |
| **CRUD gaps** | Jobs, People, Orders, Warehouse, Scheduling, Chat | DONE | 06-08 |
| **Security** | Auth, tokens | DONE | 09 |
| **Service bugs** | All services | DONE | 10 |
| **Brand-Supplier links** | Brands, Suppliers | DONE | 11A-11C |
| **Dashboard** | Overview, Clock, QR, Daily Report | DONE | 12A-12F |
| **Catalog** | Parts Catalog | DONE | 13A-13E |
| **Categories** | Tree editor, forms, delete | DONE | 14A-14G |
| **Brands + Suppliers cleanup** | Service layer, errors, sheets | DONE | 15A-15C |
| **Pricing** | Pricing page | PLANNED | 16A-16I |
| **Suppliers** | Suppliers page | PLANNED | 17A-17H |
| **Review cleanup** | Category components, imports | PLANNED | 18A |
| **Brands** | Brands page (full review) | NOT STARTED | — |
| **People** | Employees, Customers, Contractors, Contacts, Teams, Hats | NOT STARTED | — |
| **Jobs** | Job list, detail tabs, clock | NOT STARTED | — |
| **Orders** | POs, JPOs, Procurement, Returns, Receiving | NOT STARTED | — |
| **Warehouse** | Audit, Staging, Settings | NOT STARTED | — |
| **Scheduling** | Calendar, Dispatch, Time Off | NOT STARTED | — |
| **Chat** | Channels, Questions, RFIs | NOT STARTED | — |
| **Tools** | Registry, Checkouts, Maintenance, Admin | NOT STARTED | — |
| **Reports** | Spending, Public Reports | NOT STARTED | — |
| **Settings** | All settings pages | NOT STARTED | — |
| **Office** | Deletion Approvals, Spending Dashboard | NOT STARTED | — |

## Code Review Findings (2026-03-19)

Comprehensive review of all modified files found 17 issues:

### Already Covered by Prompts
- BrandDetailSheet double .sheet → 17G
- supplierCount: 0 hardcoded → 17G
- partCount: item.brandCount wrong field → 17F
- SupplierDetailSheet nested sheet → 15C (DONE)

### Net-New Issues (Prompt 18A)
- Error only logged in CategoriesBrandSection, CategoriesColorPicker, TypeBrandColorSection
- Unused GRDB imports in 6+ files
- Color picker hasColor init mismatch
- BrandSupplierPickerSheet no loading state during save

### Low Priority (No Prompt Yet)
- DashboardView timers not cancelled (memory leak)
- mfrPartNumbers in TypeBrandColorSection never saved to DB
- CategoriesBrandSection no validation after unlink

## Key Patterns Established

All pages must have:
1. Single `.sheet(item:)` with enum (no multiple .sheet modifiers)
2. `@State private var loadError: String?` with visible error display
3. Service methods (no `import GRDB` in UI files)
4. AI integration (sparkles button, context method, read-only where appropriate)
5. Error feedback on save operations (saveError + isSaving + ProgressView)
6. Delete confirmation alerts
7. Tappable phone/email links (tel:/mailto:)
8. 44px min touch targets
