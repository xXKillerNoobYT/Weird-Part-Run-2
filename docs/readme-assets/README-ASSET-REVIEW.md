# README Public Asset Register

Governs images embedded in the repository `README.md` (public GitHub surface).
Successor to the bounded register drafted for GitHub #1446 / WEI-6204; this
revision was authorized directly by the owner (2026-07-30) with the README's
role expanded to a public welcome/advertising page including the TestFlight
beta link.

**Rules (carried forward):**
- Images live only under `docs/readme-assets/`.
- iOS Simulator captures with purpose-built synthetic demo data only — never
  real customer/live data, device photos, logs, endpoints, or credentials.
- Every image has an informative caption/alt text stating the screen and that
  content is synthetic.
- Metadata: captures are raw `simctl io screenshot` output re-encoded via
  `sips` resize (no EXIF/location payload).

## Registered assets (2026-07-30)

| File | Screen | Source | Data |
| --- | --- | --- | --- |
| `dashboard.png` | Dashboard (Overview tab) | iPhone 16 Pro Max simulator, iOS 26.4, UI-test auto-login route | Synthetic (`UITest Owner`, seeded QA fixtures) |
| `warehouse.png` | Warehouse dashboard | same | Synthetic |
| `dispatch.png` | Dispatch board | same | Synthetic |

Replacement cadence: refresh alongside the showcase demo dataset work (#1562);
max three images embedded in the README at any time.
