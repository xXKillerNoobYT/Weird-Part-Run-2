# WEI-1020 Settings Dirty-Discard Rerun

Date: 2026-05-13
Agent: UIVerifier

## Scope

Rerun the Settings dirty-discard guard smoke for:

- Break & Lunch
- Forecast Config
- Audit Settings

Environment:

- Xcode project: `Weird Parts IOS/Weird Parts.xcodeproj`
- Scheme: `Weird Parts`
- Device: iPhone 17 Pro simulator, iOS 26.5, UDID `81B76C8A-9A4F-46CE-8A89-ED1DC5842F43`
- DerivedData: `.tmp/DerivedData-WEI1020`

## Runs

1. Workspace scheme attempt:
   - Command: `xcodebuild test -workspace 'Wierd Parts.xcworkspace' -scheme 'WiredPart-iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'Weird Parts IOSUITests/Weird_Parts_IOSUITests/testSettingsDirtyDiscardGuards' -only-testing:'Weird Parts IOSUITests/Weird_Parts_IOSUITests/testSettingsDirtyDiscardKeepEditingAction' -resultBundlePath docs/testing/artifacts/wei-1020/settings-dirty-guards-iphone17pro.xcresult`
   - Result: blocked before execution. `WiredPart-iOS` workspace scheme does not include `Weird Parts IOSUITests`.

2. Focused project-scheme run:
   - Command: `xcodebuild test -project 'Weird Parts IOS/Weird Parts.xcodeproj' -scheme 'Weird Parts' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .tmp/DerivedData-WEI1020 -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testSettingsDirtyDiscardGuards' -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testSettingsDirtyDiscardKeepEditingAction' -resultBundlePath docs/testing/artifacts/wei-1020/settings-dirty-guards-project-iphone17pro.xcresult`
   - Result: 1 passed, 1 failed.
   - Passed: `testSettingsDirtyDiscardKeepEditingAction`
   - Failed: `testSettingsDirtyDiscardGuards`
   - Failure: `Break & Lunch should return to Settings after saved Back`
   - Evidence:
     - Result bundle: `docs/testing/artifacts/wei-1020/settings-dirty-guards-project-iphone17pro.xcresult`
     - Exported attachments: `docs/testing/artifacts/wei-1020/settings-dirty-guards-attachments`

3. Temporary verifier variant for Forecast/Audit:
   - Command: project-scheme focused run of `testSettingsDirtyDiscardKeepEditingAction` after a temporary local verifier-only edit; source file was restored after the run.
   - Result: failed at `Audit Settings should expose Save Settings`; Xcode also reported a simulator runner `NSMachErrorDomain Code=-308` after the failed test.
   - Evidence: `docs/testing/artifacts/wei-1020/settings-dirty-guards-forecast-audit-temp.xcresult`

## Observations

- Break & Lunch dirty Back shows the confirmation with visible `Keep Editing` and destructive red `Discard`; screenshot evidence is in `settings-dirty-guards-attachments/435945C2-AF0F-48B2-9362-8C4C5D63DE73.png`.
- Break & Lunch `Keep Editing` leaves the operator on the dirty form; the dedicated Break keep-editing test passed.
- The combined smoke did not complete Forecast Config or Audit Settings because the existing UI test harness fails after returning from Break & Lunch. The failure appears harness-related: after saved Back, the Settings sheet content/search is visible in the hierarchy, but the expected `Settings` navigation bar is not exposed to XCUITest.
- The temporary Forecast/Audit run reached Audit Settings and confirmed its dirty form state, but did not complete save/back verification because the test did not scroll to the below-fold Save Settings button before asserting it.

## Pass/Fail Call

Blocked for full WEI-1020 closure. Break & Lunch dirty-discard guard is verified. Forecast Config and Audit Settings still need a clean focused rerun with a hardened UI test helper or a manual simulator pass that scrolls to Save Settings before asserting the saved-back path.

No new product GitHub issue filed from this run; the observed failures are in the verification harness/simulator path, not a confirmed user-facing Settings defect.
