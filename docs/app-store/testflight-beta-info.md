# WiredPart — TestFlight Beta Information

Copy into ASC → TestFlight → Test Information.

## Beta App Description
```
WiredPart is a contractor field-operations app: parts catalog and inventory,
purchasing, warehouse movements and audits, jobs with clock-in/out, fleet,
tools, scheduling, and reports — offline-first, with all data stored encrypted
on your device and synced directly between your own devices.

This beta focuses on day-to-day flows. Rough edges are expected; every crash
report and note helps.
```

## Feedback Email
```
weirdtoocompany@gmail.com
```

## What to Test (update each build)
```
Build 2+ — first public beta pass:
• First-run setup wizard and admin PIN creation
• Parts catalog: browse, search, QR scan a part label
• Warehouse: run a guided movement and an audit with search
• Jobs: clock in/out (allow location), add a note, view the daily report
• Orders: create a job parts order and walk it to a purchase order
• Report anything that loses data, blocks a flow, or looks wrong on your
  device size — screenshots welcome via TestFlight feedback
```

## Export Compliance
The app uses encryption only for data at rest (SQLCipher) and Apple-provided
TLS/Multipeer encryption — answer the ASC compliance prompt accordingly
(standard/exempt encryption; no proprietary cryptography). France-specific
declaration not required for standard exemption.

## Tester groups
- Internal: owner devices
- External: field crew (requires Beta App Review on first build — the review
  notes in `description.md` apply)
