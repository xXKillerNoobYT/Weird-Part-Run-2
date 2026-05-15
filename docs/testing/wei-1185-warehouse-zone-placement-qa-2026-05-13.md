# WEI-1185 Warehouse Zone Placement QA

Date: 2026-05-13
Verifier: UIVerifier

## Scope

Validate the WEI-1169 visual zone placement flow in the warehouse onboarding wizard:

- Confirm default 3x5 grid when no saved dimensions exist.
- Drag Storage zone to R1C1.
- Tap/select, move, resize with corner handle, and verify edit/delete affordances.
- Confirm persistence after leaving and resuming the wizard.
- Capture phone, tablet, and desktop-width evidence under `docs/testing/artifacts/wei-1092/`.

## Result

Passed with one environment caveat: the exact Mac Catalyst 1280x800 destination could not be run because the local host macOS 26.4.1 does not satisfy the UI test target's macOS 26.5 deployment requirement. I used the available iPad Pro 13-inch landscape simulator as the desktop-width fallback.

Verified across the requested responsive surfaces:

- 375x812-class phone: iPhone 13 mini simulator.
- 768x1024-class tablet: iPad 9th generation simulator.
- Desktop-width fallback: iPad Pro 13-inch simulator in landscape.

No new WEI-1169 product regression was found. The flow visually confirms the 3x5 grid, drag-from-palette placement, tap selection, Edit/Delete affordances, move to R2C2, resize to 2x2, and persistence after Save & Exit/resume.

## Evidence

Final screenshot folders:

- `docs/testing/artifacts/wei-1092/wei-1185-phone-375/`
- `docs/testing/artifacts/wei-1092/wei-1185-tablet-768/`
- `docs/testing/artifacts/wei-1092/wei-1185-wide-ipadpro13-landscape/`

Each final folder contains:

- `00-before-open-warehouse-wizard.png`
- `01-zone-grid-dimensions.png`
- `02-empty-3x5-zone-grid.png`
- `03-storage-selected-edit-delete.png`
- `04-storage-moved-r2c2.png`
- `05-storage-resized-2x2.png`
- `06-storage-persisted-after-resume.png`

Successful run logs:

- `docs/testing/artifacts/wei-1092/wei-1185-phone-375-after-wei1189.log`
- `docs/testing/artifacts/wei-1092/wei-1185-ipad-768-after-wei1189.log`
- `docs/testing/artifacts/wei-1092/wei-1185-wide-ipadpro13-landscape-after-wei1189.log`

Environment caveat log:

- `docs/testing/artifacts/wei-1092/wei-1185-desktop-1280-after-wei1189.log`

## Commands

Phone:

```bash
xcodebuild test \
  -workspace 'Wierd Parts.xcworkspace' \
  -scheme 'WiredPart-iOS' \
  -destination 'id=98CEE4F6-D8F5-49C3-A1B3-0F4CD6C11EA8' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1185WarehouseZonePlacementScreenshots' \
  -derivedDataPath .paperclip/DerivedData-WEI-1185-phone
```

Tablet:

```bash
xcodebuild test \
  -workspace 'Wierd Parts.xcworkspace' \
  -scheme 'WiredPart-iOS' \
  -destination 'id=8D1472B2-D136-4ECF-9B2A-F16D62C21984' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1185WarehouseZonePlacementScreenshots' \
  -derivedDataPath .paperclip/DerivedData-WEI-1185-ipad
```

Desktop-width fallback:

```bash
WEI_1185_LANDSCAPE=1 xcodebuild test \
  -workspace 'Wierd Parts.xcworkspace' \
  -scheme 'WiredPart-iOS' \
  -destination 'id=1A0466E7-3553-4F79-AFAE-FE1490412813' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1185WarehouseZonePlacementScreenshots' \
  -derivedDataPath .paperclip/DerivedData-WEI-1185-wide-landscape
```

## Notes

- The WEI-1189 build blocker is resolved; the focused UI test now builds and passes on the verified simulator targets.
- I kept the verification change scoped to the UI test harness: artifact cleanup before capture, a landscape flag for the wide run, and a more precise placed-zone selector so the wide layout does not confuse the palette item with the dropped zone.
- No duplicate/new GitHub issue was created because no new trackable UI/UX defect was reproduced.
