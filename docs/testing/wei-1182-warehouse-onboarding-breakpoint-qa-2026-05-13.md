# WEI-1182 Warehouse Onboarding Breakpoint QA

Date: 2026-05-13

Scope: breakpoint and touch-only QA for the warehouse onboarding wizard after zone placement and walking-path changes landed, against `docs/plans/github-91-warehouse-zone-placement-and-walking-path.md`.

## Environment

- App: `WiredPart-iOS`
- Test: `Weird_Parts_IOSUITests/testWEI1182WarehouseWizardBreakpointWalkingPathScreenshots`
- Phone: WEI-899 iPhone 13 mini 375pt, iOS 26.4.1
- Tablet: WEI-899 iPad 9th gen 768pt, iOS 26.4.1
- Wide: iPad Pro 13-inch (M5) landscape, iOS 26.4.1

## Artifacts

- Phone screenshots: `docs/testing/artifacts/wei-1092/wei-1182-phone-375/`
- Tablet screenshots: `docs/testing/artifacts/wei-1092/wei-1182-tablet-768/`
- Wide screenshots: `docs/testing/artifacts/wei-1092/wei-1182-wide-ipadpro13-landscape/`
- Phone log: `docs/testing/artifacts/wei-1092/wei-1182-phone-375-after-wei1202-rerun.log`
- Tablet log: `docs/testing/artifacts/wei-1092/wei-1182-ipad-768-after-wei1202.log`
- Wide log: `docs/testing/artifacts/wei-1092/wei-1182-wide-ipadpro13-landscape-after-wei1202.log`
- Tablet result bundle: `.paperclip/DerivedData-WEI-1182-ipad/Logs/Test/Test-WiredPart-iOS-2026.05.13_19-40-50--0600.xcresult`
- Wide result bundle: `.paperclip/DerivedData-WEI-1182-wide/Logs/Test/Test-WiredPart-iOS-2026.05.13_19-46-20--0600.xcresult`

No simulator recordings were captured in this run. Screenshots were captured by the focused XCTest harness. iOS Accessibility Inspector was not available from the headless CLI run; hit-target checks below are based on successful touch automation plus SwiftUI frame/accessibility review.

## Results

| Spec section | Result | Evidence |
| --- | --- | --- |
| §2.4 Zone placement Phase A | Pass | All three breakpoints captured `01-zone-placement-phase-a.png` with the confirmed grid entry state. |
| §2.5 Zone placement Phase B | Fail | Storage can be placed and resized to `2x2`, but the second `Receiving` drop does not remain visible or accessibility-exposed at phone, tablet, or wide. Tracked by GitHub #463 and Paperclip `WEI-1203`. |
| §3.6 Walking-path step | Partial | Phone reached `03-walking-path-empty.png` and showed the walking-path step after touch-only navigation. Tablet and wide were blocked before walking-path by the zone-placement defect. |
| §3.7 Suggest path preview | Partial | Phone reached `04-suggest-path-preview.png`, used `Suggest path`, `Use suggested order`, and persisted `4 stops` after Save & Exit/resume in `05-walking-path-persisted-after-resume.png`. Tablet and wide were blocked before this step by `WEI-1203`. |

## Touch And Hit-Target Notes

- Touch-only controls exercised successfully on phone: `Confirm Grid`, zone palette drag, resize handle drag, `Next`, `Add Storage Unit`, `Suggest path`, `Use suggested order`, and `Save & Exit`.
- Code review found explicit minimum hit targets for the new controls:
  - `ZoneGridCanvas.swift`: resize handle is `44x44`; zone drag preview minimum is `88x44`.
  - `WizardStepZones.swift`: palette drag sources use `minHeight: 44` and accessibility labels.
  - `WizardStepWalkingPath.swift`: stop reorder controls use `minWidth: 44, minHeight: 44`.
- Residual risk: these dimensions were not independently measured with Accessibility Inspector in this headless run.

## Defects Filed

- GitHub: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/463
- Paperclip: `WEI-1203` `[Warehouse][Bug] Second zone drop disappears in onboarding wizard`

## Conclusion

The post-build-unblock QA pass is complete enough to identify the blocking product miss. Phone walking-path non-hover behavior works through suggest/save/resume, but full breakpoint acceptance cannot pass until the second zone drop persists across phone, tablet, and wide layouts.
