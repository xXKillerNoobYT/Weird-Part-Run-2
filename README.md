# WiredPart

Native iOS field service management app for an electrical contracting company. Manages parts inventory, warehouse operations, fleet tracking, job management, labor hours, procurement, scheduling, and reporting — all running on-device with local SQLite storage and peer-to-peer sync.

---

## Architecture

| Component | Technology |
|-----------|-----------|
| **UI** | SwiftUI (iOS 18+) |
| **Core Library** | WiredPartCore Swift Package (shared models, services, sync) |
| **Database** | GRDB.swift / SQLite |
| **Sync** | LAN HTTP (swift-nio) + MultipeerConnectivity (BT/Wi-Fi P2P) |
| **AI** | Apple Foundation Models (iOS 26+, on-device) |
| **Security** | CryptoKit (Ed25519 device trust) |
| **OCR** | Apple Vision framework |
| **QR** | AVFoundation barcode scanning |

---

## Project Structure

```
Weird-Part-Run-2/
├── Weird Parts IOS/           ← iOS app target (SwiftUI)
│   └── Weird Parts IOS/
│       ├── App/               ← AppCore, entry point
│       ├── Auth/              ← Onboarding, pairing, setup
│       ├── Features/          ← 14 feature modules
│       │   ├── Chat/
│       │   ├── Dashboard/
│       │   ├── Fleet/
│       │   ├── Jobs/
│       │   ├── Notebooks/
│       │   ├── Office/
│       │   ├── Orders/
│       │   ├── Parts/
│       │   ├── People/
│       │   ├── Reports/
│       │   ├── Scheduling/
│       │   ├── Settings/
│       │   ├── Tools/
│       │   └── Warehouse/
│       ├── Navigation/        ← Router, tab config, main view
│       ├── Scanning/          ← OCR, QR scanner adapters
│       ├── Shared/            ← Reusable components, charts
│       ├── Sync/              ← Peer browser, sync manager, status
│       └── Theme/             ← Theme manager, glass modifiers
├── core/                      ← WiredPartCore Swift Package
│   └── Sources/WiredPartCore/
│       ├── AI/                ← Foundation Models service, AI tools
│       ├── Database/          ← AppDatabase, migrations, base repo
│       ├── ImageMatch/        ← Vision-based image matching
│       ├── Models/            ← Domain models (12 modules)
│       ├── OCR/               ← OCR processor adapter
│       ├── QR/                ← QR codec, generator, scanner
│       ├── Services/          ← 15 business logic services
│       └── Sync/              ← Sync engine, peer management, crypto
└── docs/                      ← Plans, specs, architecture docs
```

---

## Modules

| Module | Description |
|--------|-------------|
| Dashboard | KPI cards, quick actions |
| Parts | Catalog, categories, brands, suppliers, pricing, companions, forecasting, import/export |
| Warehouse | Dashboard, movements, locations, staging, receiving, returns, audit, inventory grid, tools, network, settings |
| Jobs | Job list, labor, reports, clock, detail, questionnaire, daily reports |
| Orders | JPO requests, purchase orders, returns, procurement, staging, approvals |
| Fleet | Vehicles, maintenance, mileage, fuel, trailers, inspections, GPS, my truck, trailer locations, truck tools |
| People | Employees, customers, contacts, hats, teams, contractors, permissions |
| Scheduling | Calendar, dispatch, time off, templates, availability, sub schedule, config |
| Tools | Registry, checkouts, kits, dashboard, admin, maintenance |
| Notebooks | All notebooks, templates, job notebooks |
| Reports | Timesheets, spending, daily summary, profitability, pre-billing, bookkeeper, labor overview |
| Chat | Messages, Q&A, RFIs |
| Office | Manage jobs, warehouse exec, spending dashboard |
| Settings | Themes, app config, company, sync, bluetooth, AI config, devices, security, and more |

---

## Auth & Permissions

Hat-based permission system. Users wear one or more hats (roles), and their permissions are the union of all hat permissions. 7 built-in roles from Admin (full access) to Grunt (minimal access), with 30+ permission keys.

---

## Sync

Devices sync via LAN HTTP and Apple MultipeerConnectivity. Each device maintains its own SQLite database. Change tracking via `_change_log` table with last-writer-wins + field-level merge conflict resolution. Ed25519 device trust via CryptoKit.

---

## License

Private repository. All rights reserved.
