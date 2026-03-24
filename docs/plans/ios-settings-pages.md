# iOS Settings Pages — Design Plan

## Navigation (Grouped like iOS Settings)
Settings:
- General (About, Themes, Notifications, App Config)
- Company (Company Profiles, Billing/Pay, PDF, Payment Tracking NEW)
- Operations (Break/Lunch Policy NEW, Tool Policies NEW, Pre-Trip Checklists NEW, Dispatch Preferences NEW)
- Warehouse (Forecast Config NEW, Organization Thresholds NEW, Audit Settings NEW)
- Sync & Devices (Sync, Bluetooth, Device Management, Bootstrap)
- Security (Security Admin, Key Management, Audit Log)
- Data (Backups, Export, Database Reset)
- AI & Integrations (AI Config, Integrations, Supplier Bridge)
- Templates (Daily Reports NEW, Job Estimation Questions NEW, Report Templates NEW, Clock-Out Questions)
- Advanced (Update Protocol, Remote Sync, Shared Channels)

## Key Design Decisions

### Settings Search
iOS-style search at top of settings list. Type "Bluetooth" → jumps to that page. Searches page names and key setting labels.

### Settings Sync Rules
- Company settings → sync to ALL devices (break policy, billing, tool policies, etc.)
- Personal settings → sync to user's devices only (themes, notifications)
- Device settings → DO NOT sync (device name, Bluetooth, local paths)

### 8 Simulated Features → Make Functional
- Backups: real file I/O, actual SQLite copy
- Data Export: real CSV/JSON file writing with share sheet
- Update Protocol: check bootstrap server for updates
- AI Config: actual Foundation Models availability detection
- Sync Now: real sync attempt when sync is configured

### New Settings Pages Needed (from design sessions)
1. Break/Lunch Policy: 4-tier state/company, bonuses, auto-fill, state presets
2. Forecast Settings: per-location ADU/APW, multipliers, free space ratings
3. Payment Tracking: enable/disable, terms default, overdue threshold
4. Dispatch Preferences: AI dispatch toggles, flex pool permissions, pipeline targets
5. Pre-Trip Checklist: customizable items per vehicle/trailer type
6. Tool Policies: max checkout duration, overdue notification, auto-maintenance, trade timeout
7. Warehouse Thresholds: confidence decay rates, audit frequency, organization targets
8. Daily Report Templates: office-configurable report sections and format
9. Job Estimation Questions: question groups with stage awareness, AI learning toggles
10. Report Templates: saved custom report configurations

### Code Quality
Settings is architecturally clean — no GRDB, all service-based. No bugs to fix, just design enhancement and new pages.
