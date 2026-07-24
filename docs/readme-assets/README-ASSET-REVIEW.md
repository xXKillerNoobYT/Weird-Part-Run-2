# README Public Asset Review — GitHub #1446 / WEI-6204

## Scope and release gate

This register governs only the bounded GitHub-visible README refresh approved for GitHub [#1446](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/1446) and Paperclip `WEI-6204`.

- Allowed: a concise README narrative and at most three **new** iOS Simulator captures made from purpose-built synthetic demo data.
- Not allowed: existing problem screenshots, raw app assets, real-device photos, live or customer data, exports, logs, filesystem or endpoint views, credentials/tokens, device identifiers, or unreviewed third-party assets.
- Public-artifact safety gate: CTO must review this register, every final image at native resolution, the metadata-stripping result, and the final README diff before PR readiness. A normal non-author review remains required after that gate.
- Image files may be committed only under `docs/readme-assets/`; no capture may be added until every item in its record is complete.

## README outline and intended reader flow

**Target surface:** repository `README.md` on GitHub.

**Primary reader goal:** quickly understand what WiredPart is, the field-to-office workflows it supports, and where to find an accurate feature, setup, or beta-testing guide.

1. **Hero:** `# WiredPart` and a one-sentence description: a native, local-first field-service operations app for an electrical contracting shop.
2. **Field-to-office narrative:** three concise workflow pillars—see work, manage material movement, and carry jobs from field activity into operational follow-up. This uses existing feature descriptions; it does not make performance, security, deployment, availability, integration, or outcome claims.
3. **Optional evidence gallery:** at most three reviewed simulator screenshots, each preceded by an informative caption. Alt text must state the screen and that visible content is synthetic demo data; it must not repeat decorative information.
4. **Start here:** retain the current feature overview, beta-guide, setup, QA, roadmap, dependency, design, and handoff links after link validation.
5. **Repository map and developer commands:** retain the current codebase orientation and locally verifiable commands.

### State and accessibility requirements

- The README is static documentation: no loading or error state is introduced. Broken image or link behavior is prevented by a relative-path check before review.
- Captions and alt text must make each screenshot understandable without relying on color, visual inference, or the image loading successfully.
- The public layout must remain legible at GitHub desktop, tablet, and mobile widths. Gallery images must use intrinsic-size PNGs and Markdown rendering that does not require side scrolling.
- Source of truth for claims: `docs/FEATURES.md`, `docs/SETUP.md`, `docs/BETA-TESTER-GUIDE.md`, and the reviewed app capture itself.

## Per-asset records

| Asset | Intended screen / user goal | Simulator context | Synthetic data confirmed | Native-resolution redaction inspection | Metadata stripped | Final repo path | CTO safety review |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dashboard/app shell | Let a new visitor orient to daily field-service operations and primary navigation. | Pending: clean iOS Simulator, version/device documented at capture. | Pending: launch only with purpose-built `-UITesting` fixture data; no production/local database. | Pending | Pending | `docs/readme-assets/wiredpart-dashboard-synthetic.png` | Pending |
| Parts or warehouse workflow | Show a material/warehouse task with an obvious operational next step. | Pending: clean iOS Simulator, version/device documented at capture. | Pending: launch only with purpose-built `-UITesting` fixture data; no production/local database. | Pending | Pending | `docs/readme-assets/wiredpart-warehouse-synthetic.png` | Pending |
| Jobs/operations workflow | Show job work progressing from field context into operational follow-up. | Pending: clean iOS Simulator, version/device documented at capture. | Pending: launch only with purpose-built `-UITesting` fixture data; no production/local database. | Pending | Pending | `docs/readme-assets/wiredpart-jobs-synthetic.png` | Pending |

## Capture and review procedure

1. Reset or use a clean simulator and launch through the deterministic `-UITesting` fixture route. Do not open an existing user database.
2. Capture only the intended screen. Ensure the navigation state and visible data communicate the stated workflow without requiring a second screenshot.
3. Inspect each image at native resolution before adding it to the repository. Reject visible names, contacts, locations, prices, identifiers, notifications, URLs/IPs, filesystem paths, tokens, device names, or other non-synthetic/sensitive material.
4. Strip all image metadata, then independently inspect the stripped file and record the result in the table.
5. Optimize only after redaction; retain visual legibility and do not use destructive cropping that hides essential context.
6. CTO reviews the resulting PNGs and README diff for technical and public-artifact safety before a PR is ready. Then route the PR through normal non-author review.

## Evidence to link at handoff

- GitHub #1446 comment containing Paperclip `WEI-6204`, bounded scope, final PR URL, and image/checklist evidence.
- Paperclip `WEI-6204` comment containing the same PR and review links.
- `git diff --check`, relative README-link validation, metadata inspection command/result, and native-resolution review evidence.

## Capture log

- 2026-07-24 — Ran the existing Warehouse dashboard UI screenshot test against deterministic `-UITesting` fixture data on a clean iOS Simulator. The selected test passed, but its optional export environment was not forwarded into the test runner; the post-test device capture was the iOS Home Screen rather than the intended application screen. It was rejected immediately and was not copied into the repository. No public image is currently approved or tracked.
