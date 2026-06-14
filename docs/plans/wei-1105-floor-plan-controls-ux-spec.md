# WEI-1105 Floor Plan Unit Types and Front-Face Controls UX Spec

## Context

GitHub #88 defines the warehouse floor plan as the entry point for placing and configuring physical storage units. `WarehouseLocationsPage` already supports drag/drop placement, rotation, hierarchy drill-in, sticker checklist access, movable storage, and add/edit sheets with a `frontFace` state backed by the existing `front_face` field. The current visible unit toolbar still presents only the older subset of unit types.

This spec completes the controls model for the required #88 unit set and keeps the add/edit flow usable at iPhone width.

## Unit Type Model

Use a single ordered unit-type catalog for toolbar buttons, add/edit display, icons, colors, defaults, and movable defaults:

| Display label | Stored `unit_type` | Icon | Default size cells | Default hierarchy | Default movable | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Shelving | `shelving` | `cabinet.fill` | 2 x 1 | Levels + areas | Off | Rename the toolbar label from "Shelf" to "Shelving" to match #88. |
| Gang Box | `gang_box` | `shippingbox.fill` | 2 x 1 | Trays + boxes | On | Movable by default; still placeable on the floor plan. |
| Pipe Rack | `pipe_rack` | `lines.measurement.horizontal` | 3 x 1 | Tiers + areas | Off | Horizontal orientation should be visually clear. |
| Pallet Rack | `pallet_rack` | `square.stack.3d.up.fill` | 3 x 2 | Levels + areas | Off | Larger default footprint than shelving. |
| Wall Mount | `wall_mount` | `rectangle.portrait.and.arrow.right` | 1 x 2 | Sections + areas | Off | Designed for wall/pegboard zones. |
| Floor Area | `floor_area` | `square.dashed` | 3 x 2 | Zones + areas | Off | Used for staging, incoming, returns, and other open zones. |
| Cabinet | `cabinet` | `cabinet.fill` | 1 x 1 | Drawers + areas | Off | Compact placed unit. |
| Packout Set | `packout` | `archivebox.fill` | 1 x 1 | Modules + compartments | On | Movable and job-ready candidate. |
| Tool Bag | `tool_bag` | `bag.fill` | 1 x 1 | Compartments | On | Movable by default. |
| Parts Bin | `parts_bin` | `tray.full.fill` | 1 x 1 | Compartments | On | Movable by default. |
| Crate/Tote | `crate` | `shippingbox` | 1 x 1 | Single open container | On | Label should show "Crate/Tote" while storage remains `crate`. |
| Custom | `custom` | `plus.square` | 1 x 1 | User-selected | Off | Keep as an escape hatch after the required #88 types. |

The catalog should replace scattered switch statements where practical so the toolbar, color/icon helpers, add title, and future wizard surfaces cannot drift.

## Add/Edit Flow

### Toolbar

- Keep the existing horizontal scroll toolbar pattern, but show all required unit types before Custom.
- Buttons must keep a minimum 44 pt hit target. At 375 px width, labels may remain full text inside the horizontal scroll; do not collapse into ambiguous icons only.
- Preserve current floor plan scrolling, drag/drop, drop highlight, context menu, and movable storage list behavior.

### Add Storage Unit Sheet

The sheet should remain a `NavigationStack` with a `Form`, but the configuration should be grouped by user decision order:

1. Identity: name, row, unit number.
2. Type summary: read-only selected unit type with icon and one-line hierarchy pattern, since type is chosen from the toolbar.
3. Dimensions and grid footprint: width/depth/height and grid X/Y/width/height.
4. Orientation: front-face segmented/picker control.
5. Structure: type-aware level/module/tray/compartment counts.
6. Options: movable and job-ready toggles.

Type-aware defaults should prefill the sheet when opened from a toolbar type. Users can override dimensions, grid footprint, hierarchy counts, and movable/job-ready flags before create.

### Edit Storage Unit Sheet

- Continue editing name, row, unit number, grid placement, and `front_face`.
- Add the same type summary shown in Add so users know what kind of unit they are editing.
- If implementation allows changing `unit_type`, changing type must recalculate defaults only after explicit confirmation; otherwise keep type read-only for this slice.

## Front-Face Control

Use the existing `front_face` field with values `north`, `south`, `east`, and `west`.

Control behavior:

- Label: "Front face".
- Helper text: "Side with stickers and aisle access."
- Preferred presentation: four-option segmented picker on wider sheets; standard wheel/menu picker is acceptable where SwiftUI Form constraints make segmented cramped.
- Options should display as `North`, `South`, `East`, `West`; stored values remain lowercase.
- Default remains `south` when the existing value is nil.
- Create must pass `frontFace` to `WarehouseService.addStorageUnit`.
- Edit must pass `frontFace` to `WarehouseService.updateStorageUnit`.

Floor-plan tile behavior:

- Add a small directional marker on each unit tile, such as a thin highlighted edge or arrow, derived from `front_face`.
- The marker must rotate independently from the tile footprint so users can distinguish "this object is rotated" from "the accessible/sticker face is on this side".
- Context-menu rotation must keep working and must not mutate `front_face` unless the user explicitly changes the front-face control.

## Existing Behaviors to Preserve

- Drag/drop placement on the grid, including the visible drop-target state.
- Context-menu rotate, edit, drill-in/details, sticker checklist, and remove confirmation.
- Hierarchy drill-in: Unit -> Level/Module/Tray -> Area/Compartment/Bin as currently supported by service APIs.
- Sticker checklist entry point for placed units.
- Movable storage section, with Packout Set, Tool Bag, Parts Bin, Crate/Tote, and Gang Box defaulting to movable but still placeable.
- Empty, loading, and error states currently present on the page.

## Mobile Quality Bar

At 375 x 812:

- Toolbar remains horizontally scrollable and each unit-type button remains at least 44 pt tall.
- Add and edit sheets require no horizontal scrolling.
- Picker labels and stepper values do not truncate important numbers or type names.
- `Crate/Tote`, `Packout Set`, and `Pallet Rack` labels fit without overlapping icons.
- Form sections stay in decision order; the front-face control appears before Create/Save.

## Acceptance Criteria for Implementation

- `WarehouseLocationsPage` exposes all required #88 unit types: Shelving, Gang Box, Pipe Rack, Pallet Rack, Wall Mount, Floor Area, Cabinet, Packout Set, Tool Bag, Parts Bin, and Crate/Tote.
- Add and edit flows use the existing `front_face` storage field with `north`, `south`, `east`, and `west`.
- Floor-plan tiles provide visible front-face direction without breaking rotation.
- Type labels, icons, colors, add-sheet defaults, and movable defaults are consistent from one unit-type catalog.
- Existing drag/drop, rotation, hierarchy drill-in, sticker checklist, and movable-storage behavior still works.
- Empty, loading, and error states remain non-raw and unchanged unless improved.
- Verification includes at least one focused iOS compile/build check for changed warehouse files.
- Manual or screenshot verification is recorded for 1280 x 800, 768 x 1024, and 375 x 812 showing that every required unit type can be created and front face can be changed.
