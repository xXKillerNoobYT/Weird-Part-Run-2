# WiredPart — App Store Listing

**This file is the SOURCE OF TRUTH for the App Store listing.** App Store
Connect is a rendering of it, not the other way round — edit here, then run:

```bash
~/.claude/scripts/ascenv/bin/python scripts/ci/sync-app-store-metadata.py
```

The sync is idempotent, covers **both the iOS and macOS version records**, and
refuses to write to a version that is live or in review. Add `--check` for a
read-only drift report (exit 1 when ASC differs) — safe to wire into CI.

Character limits below are enforced by the script; it fails loudly rather than
letting Apple reject the write.

**Fields the API cannot set — these stay owner/UI work:** Privacy Policy URL
(required before submission; policy text is in `privacy-labels.md`, it needs
hosting), Marketing URL, screenshots (`docs/app-store/screenshots/`),
categories, and the age-rating questionnaire.

## App Name (30 chars max)
```
WiredPart
```

## Subtitle (30 chars max)
```
Parts, Jobs & Warehouse Ops
```

## Promotional Text (170 chars max — editable without review)
```
Built for electricians on remote sites: parts, panels, jobs and purchasing that work with zero bars — everything offline, synced device to device when you're back.
```

## Description (4000 chars max)
```
WiredPart is built for electricians first — especially crews working remote sites with little or no cell or Wi-Fi service. Every feature works completely offline: the basement mechanical room, the desert substation, the cabin job at the end of a dirt road. Your catalog, your jobs, your orders — all of it lives on your device and syncs directly to your other devices when they're near each other. No cloud. No account. No signal required, ever.

PARTS & INVENTORY
• Full parts catalog with categories, brands, suppliers, and pricing tiers
• Stock levels with MIN/TARGET/MAX rules, low-stock alerts, and forecasting
• QR scanning for instant part lookup, bin locations, and companion-part rules

WAREHOUSE
• Guided movement wizard for picks, put-aways, and staging
• Warehouse dashboard, floor plans, and rolling audits with search
• Receiving sessions and return sorting

ORDERS & PURCHASING
• Job parts orders to purchase orders in one lifecycle
• Procurement planner, supplier preferences, and price history
• PDF bundles, approvals, and review-and-send workflow

JOBS & LABOR
• Job tracking with clock in/out, GPS, and questionnaires
• Daily reports, job costing rollups, and budget alerts
• Per-job notebooks, todo stages, and templates

FLEET & TOOLS
• Vehicles, assignments, deliveries, maintenance, and mileage
• Tool registry with kit verification, checkout/return, and maintenance

PEOPLE & SCHEDULING
• Employees, certifications, wages, skills, and permissions
• Scheduling, dispatch, time off, and subcontractors

REPORTS & PRE-BILLING
• Six report pages with period locking and bookkeeper exports

BUILT FOR THE FIELD
• Offline-first: every feature works with zero connectivity — designed for
  remote job sites where there is no service to lose
• Your data stays yours: stored encrypted on your device, synced directly
  between your own devices over Bluetooth and local Wi-Fi — no cloud account,
  no server, no tracking
• On-device AI assistant (Apple Intelligence) for natural-language help and
  filters — nothing sent to outside services, works with no signal
• Panel schedules, QR part labels, and printable pro documents made for
  electrical work specifically
```

## Keywords (100 chars max, comma-separated, no spaces after commas)
```
electrician,offline,parts,inventory,warehouse,panel schedule,purchase order,job costing,contractor
```

## Categories
- Primary: **Business** (matches `LSApplicationCategoryType = public.app-category.business`)
- Secondary: **Productivity**

## URLs
- Support URL: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues
- Marketing URL (optional): _pending — owner may add a site later_
- Privacy Policy URL: **required before submission** — see `privacy-labels.md`;
  a one-page policy stating data never leaves user devices satisfies this.

## Age Rating questionnaire
All content descriptors: **None** → resulting rating **4+**.
(No user-generated public content, no web browsing, no gambling, no medical.)

## App Review notes (for the reviewer)
```
WiredPart is a single-company field-operations tool. On first launch it runs a
local setup wizard (no account creation against any server — all data is
device-local). Create an admin PIN when prompted, then explore from the
dashboard. Device-to-device sync uses Apple Multipeer Connectivity between the
user's own devices only; there is no backend service.
```

## Screenshots
Stored in `docs/app-store/screenshots/` (captured from simulators at Apple's
required sizes):
- `iphone-6.9/` — iPhone 16 Pro Max (1320×2868)
- `ipad-13/` — iPad Pro 13" (2064×2752)

Order in ASC: Dashboard → Parts Catalog → Warehouse → Jobs → Orders.

## What's New template (per release)
```
Build N — beta hardening: [2–4 bullet highlights of merged fixes]
```
