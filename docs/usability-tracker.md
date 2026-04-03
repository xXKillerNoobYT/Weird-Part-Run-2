# Usability Enforcer Tracker

**Agent:** usability-enforcer
**Schedule:** Daily at 2:00 PM
**Skill:** `xcode-ai/skills/usability-enforcer/SKILL.md`

---

## Latest Run

_No runs yet — agent scheduled 2026-04-02_

---

## Feature Completeness Matrix

| Feature | List | Create | Detail | Edit | Delete | Search | Filter | Refresh | Empty State | Error State |
|---------|------|--------|--------|------|--------|--------|--------|---------|-------------|-------------|
| Parts | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Jobs | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Employees | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Customers | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Contacts | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Teams | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Warehouse | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Orders/JPOs | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| POs | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Fleet | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Tools | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Kits | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Scheduling | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Notebooks | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |

_Legend: Pass, Fail, N/A, ? = Not yet checked_

---

## Known Issues

### From Problomes Screenshots (2026-03-28)
| # | Issue | GitHub | Status |
|---|-------|--------|--------|
| 1 | Login shows user on clean build | #18 | Open |
| 2 | Dashboard background task errors | #19 | Open |
| 3 | Clock In/Out broken | #20 | Open |
| 4 | All modals don't close (React/Tauri) | #21 | Open |
| 5 | Warehouse wizard Row 1 assumption | #22 | Open |
| 6 | Warehouse missing features | #23 | Open |
| 7 | Warehouse audit broken | #24 | Open |
| 8 | Create Job needs fields | #25 | Open |
| 9 | 10+ pages crash on empty DB | #26 | Partially fixed (service layer) |
| 10 | Trailer help incomplete | #27 | Open |
| 11 | Time Off count wrong | #28 | Open |
| 12 | Schedule Config incomplete | #29 | Open |
| 13 | Teams needs employees note | #30 | Open |
| 14 | Edit Tabs confusing | #31 | Open |
| 15 | Settings layout default | #32 | Open |

### From Core Swift Fixes (2026-04-02)
| Fix | File | What |
|-----|------|------|
| Error handling | PartsService.listCatalogParts() | Added isTableNotFoundError → empty result |
| Error handling | PeopleService.getContactsSorted() | Added isTableNotFoundError → empty tuple |
| Error handling | PeopleService.getContactTypeCounts() | Added isTableNotFoundError → empty counts |
| SQL mismatch | PeopleService.getHatMembers() | user_hats.created_at → NULL |
| SQL mismatch | PeopleService.getAvailableEmployeesForTeam() | Added status column alias |
| MainActor fix | PartsCatalogPage.loadData() | @State modified off main thread |
| Dead navigation | IOSContactsPage | Added navigationDestination + detail page |
| New method | PeopleService.updateContact() | Enables contact editing |
| Error scope | 3 services | isTableNotFoundError now catches "no such column" too |

---

## Run History

| Date | Scanners Run | Issues Found | Fixed | New GitHub Issues | New DevTODOs |
|------|-------------|-------------|-------|-------------------|--------------|
| _none yet_ | | | | | |
