# WiredPart — Beta Tester Guide

> Last updated: 2026-07-02 (beta completion pass)
> Audience: beta testers running WiredPart on their own iPhone or iPad.
> What the app does: see [FEATURES.md](FEATURES.md). Build-from-source details: [SETUP.md](SETUP.md).

Welcome to the WiredPart beta. WiredPart is an offline-first operations app for an electrical contracting shop — parts, warehouse, jobs, orders, scheduling, fleet, tools, people, and reports, all stored locally on your device. This guide gets you installed, through first launch, and tells you how to report what you find.

---

## 1. What You Need

| Requirement | Detail |
|-------------|--------|
| Device | iPhone or iPad on **iOS 26.2 or later** |
| Internet | Only for installing the app — WiredPart itself works fully offline |
| A second device (optional) | To try device pairing and peer-to-peer sync |

<!-- Deployment target verified: grep IPHONEOS_DEPLOYMENT_TARGET "Weird Parts IOS/Weird Parts.xcodeproj/project.pbxproj" → 26.2 -->

---

## 2. Installing the App

**TestFlight (preferred once a build is distributed):**

1. Accept the TestFlight invitation sent to your email (or open the invite link on your device).
2. Install the free **TestFlight** app from the App Store if you don't have it.
3. In TestFlight, tap **Install** next to WiredPart, then open it like any other app.
4. TestFlight builds update automatically; you can also tap **Update** in TestFlight when a new build is announced.

**Direct install from Xcode (developer path):**

If you were asked to build from source instead, follow [SETUP.md](SETUP.md) on a Mac with Xcode 26.2+, open `Weird Parts IOS/Weird Parts.xcodeproj`, select the `Weird Parts` scheme and your plugged-in device, and press Run.

---

## 3. First Launch — What to Expect

On first launch WiredPart shows a **welcome screen with two paths**:

### Path A — Create New Business
Pick this if you are the first device (or testing solo).

1. **Admin account:** enter your name and choose a PIN (4+ digits, entered twice). This creates the admin user plus the default roles ("hats"), permissions, and settings.
2. **Company setup wizard (8 steps):** company profile → add employees → configure hats → create your first job → add parts → set up the warehouse → break/lunch policy → done. Every step can be completed or skipped, and progress is shown as you go — you can finish the rest later from Settings.
3. You land on the Dashboard, signed in as admin.

### Path B — Join Existing Business
Pick this if another device already has the company data.

1. Choose **Join Existing Business** → the device pairing screen searches for nearby company devices (both devices need Bluetooth/Wi-Fi on and the app open).
2. Approve the pairing on the existing device.
3. A sync-waiting screen shows progress while your device receives the company data. When it finishes, sign in with your PIN.

After setup, sign-in is by PIN (with Face ID/Touch ID support), and an optional module tour walks you through the main areas.

---

## 4. A 10-Minute Feature Tour

Full capability list: [FEATURES.md](FEATURES.md). A quick loop to touch the main areas:

1. **Dashboard** — glance at the KPI cards; tap one for its detail sheet.
2. **Parts** — open the catalog, search for a part, peek at the category tree and pricing pages.
3. **Warehouse** — run the onboarding wizard if you haven't (zones → shelves → bins), then try the Movement Wizard to move stock between locations.
4. **Jobs** — create a job, then use the Clock page to clock in (GPS) and clock out — answer the questionnaire.
5. **Orders** — create a JPO for your job with a couple of line items; if you're feeling thorough, convert it to a PO and generate the PDF.
6. **Scheduling** — open the calendar, add a schedule entry, and try a dispatch.
7. **Scanning** — from the Dashboard, open the QR scanner; print or display a QR label from a part or tool and scan it.
8. **Reports** — open Timesheets or Spending and see your test data flow through.
9. **Settings** — try dark mode under Themes, and look at Device Management and Sync.
10. **If you have two devices** — pair them and watch a change made on one appear on the other.

---

## 5. How to Report Bugs

Bug reports go to **GitHub Issues**. Owner problem-screenshots may also be dropped in `docs/problems/` (renamed from the old misspelled `docs/Problomes ` folder), where the triage loop picks them up.

1. **Take a screenshot** (or screen recording) of the problem the moment you see it.
2. Open a new issue at <https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues> and attach the screenshot.
3. **Title format:** `[Area][Bug] short description` — e.g. `[Warehouse][Bug] Movement Wizard skips confirm step`. Area = the feature you were in (Parts, Orders, Jobs, Scheduling, ...).
4. **Include in the description:**
   - What you did (steps, in order)
   - What you expected
   - What actually happened
   - Device model + iOS version, and whether you were offline or synced with another device
   - A `Status: OPEN` line
5. Not sure if it's a bug or intended? File it anyway and say so — triage will sort it.

If you can't use GitHub, send the screenshot and the same details to the owner and they will file it.

---

## 6. Known Limitations (Beta)

- **Local-first, per-device storage.** Your data lives on your device. If you delete the app, its data goes with it — there is no cloud backup. Use Settings → Backups / Data Export before deleting or resetting.
- **Sync is nearby-only.** Devices sync peer-to-peer (Bluetooth/Wi-Fi) when they are near each other. There is no internet sync — a device that stays home does not receive changes until it's near another company device again.
- **No cloud backend.** No accounts, no server, no web version. This is by design (see [KEY-PRINCIPLES.md](KEY-PRINCIPLES.md)).
- **iOS only.** iPhone and iPad. No Android, no desktop app.
- **Sync conflict review is still being tuned.** If two devices edit the same record while apart, the app merges changes (last-writer-wins with field-level merge) and flags conflicts for review — expect rough edges here and please report them.
- **Beta data may not survive upgrades.** Between beta builds, a database reset may occasionally be required. Don't put irreplaceable data in the beta.

---

## 7. Questions

- App capabilities: [FEATURES.md](FEATURES.md)
- Design philosophy: [KEY-PRINCIPLES.md](KEY-PRINCIPLES.md)
- Anything else: open a GitHub issue titled `[Docs][Question] ...` or ask the owner directly.

Thanks for testing — every report makes the release better.


## Known Limitations (beta)

Deliberate beta-scope decisions — these are not bugs to report:

- **Payment Tracking** is hidden from Settings for beta (page returns when the feature is built — GH #851 decision).
- **Formal numbered RFIs** are descoped; informal Q&A/RFI chat flows are the supported path (GH #79 decision).
- **Parts-order bulk actions** and the **Remote Sync page controls** are hidden until their backing services ship (GH #1338).
- **Chat file attachments**: sending and receiving work, but received files show as info chips without preview/share yet (GH #1372), and attachments don't survive iOS storage-pressure cleanup (GH #1371). Don't rely on chat as file storage.
- **In-app bug reporting** (GH #574) isn't built yet — report via TestFlight feedback or GitHub as described above.
