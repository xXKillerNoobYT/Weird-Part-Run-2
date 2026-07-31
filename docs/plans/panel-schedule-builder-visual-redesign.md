# Panel Schedule Builder — Visual Redesign (from Claude Design import)

**Source of truth:** owner's Claude Design project "App and plans loading"
(`d4ace6a6-ba25-40f5-9a9a-483452c9718c`), file `Panel Schedule Builder.dc.html`,
imported 2026-07-30. This plan transcribes that design's WHAT and WHY for the
Notebooks → Panel Schedule feature. Purpose (owner): *help electricians build
panel schedules easily, and print a professional company-logo version for
permanent install in a panel.*

Implementation target: `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/PanelScheduleBuilder.swift`
(+ `core` models in `PanelScheduleModels.swift`). Implement AFTER in-flight
panel PRs (#1514 space-combination validation, #1515 PDF validation) land, on
top of their final state.

## 1. Screen structure (phone)

Header: **panel name** (large, tappable → Panel setup) + `tune` icon; meta line
`Brand Model · Voltage · MainA MCB/MLO/Sub · N sp · CTL?`.

Segmented layout switcher: **Classic | List | Visual** (Visual is default).

Below the active layout, always visible:
- **Phase balance card** — per-leg bars of *used* (connected) amps with A/W
  unit toggle; "Largest leg: X · nA of MainA (p%)"; "Total connected:
  totalW · svcA service"; note explaining the calc basis (e.g. "3Ø · 2-pole
  @208V · 3-pole ×√3").
- Action row: **Print schedule** and **Add to JPO** (creates a JPO draft from
  all circuits; toast "N circuits added to a new JPO draft").

### Classic view
Two columns (odd spaces left, even right), white cells, 5px colored bar at the
left edge of each cell (breaker-type color; tie-purple for tied quads), rows:
phase dot · slot label · `20A·1P` (type color) · description + small
`used · max` footer (red when used > max). Split cells (tandem/quad) show one
sub-row per circuit with dashed separators. Empty: gray "Open".

### List view
Stat tiles (Circuits / Free spaces / Spaces) + big blue **Add Circuit** button
(opens editor at next free space) + one card per *circuit* (not per space):
type-color bar, slot, `20A · 1P`, tag chip (type name / Twin / Quad),
description, `used · max` footer, phase span on the right.

### Visual view (default)
Dark panel visualization: near-black card, header `BRAND · 200A Main`, two
columns split by a center bus line. Cells are breaker-colored (type color at
~15% bg, colored border + text), left column left-aligned, right column
mirrored (right-aligned). Phase dot per circuit; tied quads use tie-purple.

## 2. Domain model

Space entry kinds (a panel is a map of odd/even *space number* → entry):
- **full** — amps, poles (1/2/3), type, used, desc, note. Poles>1 spans
  consecutive same-side spaces (s, s+2, s+4); slot label "1–5".
- **tandem (twin)** — two halves (amps/type/used/desc each), both on the SAME
  leg (one space). Labels `6a`/`6b`. Builds like 15/15, 20/20, 15/20.
- **quad** — occupies two same-side spaces (s, s+2), three modes:
  - `four` (4×1P): four independent 120V circuits; top two on leg(s), bottom
    two on leg(s+2). Labels `8a,8b,10a,10b`.
  - `center` (120/240/120): outer singles + tied inner 2-pole (240V) —
    e.g. 20·30·20. Inner shows tie-purple, label `8–10`.
  - `double` (2×2P): two independent 2-pole breakers — e.g. 30/50 (dryer +
    range). Labels `8–10↑`, `8–10↓`.
- Saving an entry deletes any overlapping entries; `SPARE` type clears the
  space.

Breaker type catalog (color-coded everywhere):
| Key | Name | Short | Color | Use |
|---|---|---|---|---|
| STD | Standard | STD | #0A84FF | general branch |
| GFCI | GFCI | GFCI | #00B0A6 | wet locations |
| AFCI | AFCI | CAFI | #FF9F0A | dwelling living areas |
| DF | Dual-Fn | DF | #BF5AF2 | arc+ground fault |
| GFPE | GFPE | GFPE | #FF375F | equipment ground fault |
| HACR | HACR | HACR | #30D158 | HVAC |
| GEN | General | GEN | #8E8E93 | sub-feed |
| SPARE | Spare | — | #C7C7CC | reserved/empty |

Amp choices: full 15–100 (15,20,25,30,40,50,60,70,90,100); tandem halves
15/20/30 (types STD/GFCI/AFCI/DF only); quad 2-pole sections
15,20,30,40,50,60 (types STD/HACR/GFPE/GFCI).

Phases: legs A/B/C colored #0A84FF / #FF9F0A / #BF5AF2; tie color #5E5CE6.
`phaseFor(space) = legs[(ceil(space/2)-1) % legCount]` (legCount from voltage
system: 1, 2, or 3).

Panel setup sheet: brand (Square D/Eaton/Siemens/GE/Cutler-Hammer/Murray),
model text (QO/BR/PON…), type (Main Breaker/Main Lug/Sub-Panel), voltage
system (120V 1Ø 2-wire · 120/240V 1Ø 3-wire · 120/208V 3Ø · 277/480V 3Ø with
vln/vll/phase count), **CTL toggle** ("tandems any slot" vs 40/40 marked slots
only), spaces (chips 4…72 + custom stepper, even values only, clamp 4–200),
main rating (100/125/150/200/225/400).

## 3. Electrical math (all "used"/connected load based)

- `circVolts(poles) = poles>=2 ? vll : vln`.
- `watts(amps,poles) = poles>=3 ? amps*vll*√3 : amps*circVolts` (VA).
- Per-leg totals: full p-pole splits its VA evenly across its spanned legs;
  tandem halves both add to their single leg; quad by mode (center: outer
  singles to own legs + inner 2P half to each; double: each 2P half/leg;
  four: each single to its space's leg). SPARE excluded.
- Bar % = legAmps / mainAmps (cap 100). Largest-leg callout uses worst leg.
- Service amps = totalVA / (√3·vll) for 3Ø, / vll for 1Ø-3w, / vln for 1Ø-2w.
- Editor "Estimate" button = 80% of breaker size.
- Unit toggle A ↔ W converts both display and input everywhere.
- Overload: used > amps renders the footer red (#FF3B30) — advisory only.

## 4. Circuit editor (bottom sheet on space tap)

Form-factor segment: **Full | Tandem | Quad · 2sp** (switching resets draft to
that kind's defaults). Full: breaker-size chips ("max rating"), poles segment
(with span note "spans spaces 1, 3"), type chips (colored dot), connected-load
stepper (± with numeric field, unit suffix, alt-unit hint + phase span,
Estimate button), circuit name ("printed on the schedule"), description
("optional, not on legend" — surfaces in print Notes). Tandem/Quad: quad-mode
segment (4×1P / 120/240/120 / 2×2P), **common-build presets** (20/20, 15/15,
15/20, 20/30 · 20·30·20, 15·20·15… · 30/50, 20/30…), then one card per
sub-circuit (amps chips, type chips, name, load stepper) with phase labels and
tie-purple accents for 240V pairs. Footer: **Clear** (destructive) + **Save**.

## 5. Print system (the headline feature)

**Print preview sheet** — a real document, not the app UI:
- **Letterhead**: company logo (image slot — picked once in Print setup,
  persisted, printed on every schedule), company name/license/phone/address/
  email/web, right-aligned "PANEL SCHEDULE" + panel name + date.
- **Title block** (3-col grid, 12 fields): Project, Location, Voltage/Phase,
  Job No., Fed From, Main (e.g. "200A MCB"), Mounting, Enclosure, Bus/AIC
  ("200A · 22kAIC"), Spaces ("42 · 12 free"), Feeder, Rev.
- **Schedule table**: dark header (Ckt · Circuit/Load Served · [Wire] ·
  Breaker · [VA] · Ph); one row per circuit with type short-code, breaker
  `20A/1P` in type color, phase letter(s) in leg color; optional italic
  "SPACE — open" rows for empties.
- **Load summary box**: per-leg VA + amps + % (optional bars), Total
  connected VA, Service (balanced) amps, Imbalance % (amber >20%), optional
  demand row: Demand factor %, Demand load VA·A, **Min. service** (next
  standard size: 60,100,125,…,1200).
- **Notes** (optional): `#5 RTU-1 Condenser: #8 THHN, 40ft home run`.
- **Signature blocks** (optional): Drawn/Checked/Approved lines + dashed
  "P.E. Stamp" box.
- Footer: paper label · "Generated by WiredPart · Planning estimate — verify
  against NEC & local AHJ before construction." (ALWAYS printed.)
- Actions: Close · Customize (print setup) · **Print / Save PDF**.

**Print setup sheet** (persisted once, reused for every schedule): company
letterhead fields + logo; project/title-block fields (project, job #,
location, fed from, rev, drawn by, checked by); panel details (AIC kA, feeder
conductor, mounting Surface/Flush, enclosure NEMA 1/3R/12); demand factor
stepper (25–150%, default 100); show-on-schedule toggles (VA column, wire
size column, empty spaces, phase bars, demand calc, notes, signatures,
**grayscale/B&W**); paper size Letter/Legal/A4.

Wire-size auto-column (when enabled): 15A→#14 Cu, 20→#12, 30→#10, 40–50→#8,
60→#6, 70→#4, 90–100→#3, 125→#1, 150→#1/0, 175→#2/0, 200→#3/0.

iOS implementation notes: render the sheet as a real PDF (ImageRenderer or
UIGraphicsPDFRenderer) at the selected paper size; share sheet for
Print/Save PDF; company logo via PhotosPicker stored in the app's documents;
print config persisted app-wide (settings table), panel data persisted with
the notebook entry (GRDB, soft delete, `_change_log` for sync).

## 6. Reference panel (iPad/wide layouts only)

The design's left column (form-factor explainer + breaker-type legend) is a
learning aid; on iPhone omit it, on regular-width show it beside the builder.

## 7. Acceptance criteria

1. Three layout modes switchable, Visual default; state survives relaunch.
2. All four form factors placeable with overlap resolution and CTL-aware
   tandem slotting (CTL off → tandems only in marked slots — panel setup).
3. Phase totals match §3 math for all kinds/modes across 1Ø/3Ø systems.
4. Editor round-trips every entry kind; presets apply; unit toggle correct.
5. Print preview renders every optional section per toggles; PDF exports at
   Letter/Legal/A4; logo + letterhead persist across schedules; grayscale.
6. Add to JPO creates a draft JPO with one line per circuit.
7. Accessibility: 44pt targets, labels/identifiers per repo standards; the
   ampacity/phase text never conveyed by color alone (short codes present).
8. Tests: phase-total math (all kinds × modes × systems), overlap resolution,
   next-standard-size, wire-size table, print VM assembly.
