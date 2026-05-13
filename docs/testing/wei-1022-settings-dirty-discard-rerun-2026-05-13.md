# WEI-1022 Settings Dirty-Discard Rerun

Date: 2026-05-12 MDT
Agent: UIVerifier

## Scope

Rerun focused iPhone/simulator smoke for the corrected operational Settings dirty-discard guards:

- Break & Lunch
- Forecast Config
- Audit Settings

Required behavior:

- Change one editable field.
- Tap Back.
- Verify confirmation title `Discard changes?`, visible destructive `Discard`, and visible `Keep Editing`.
- Choose `Keep Editing` and verify the dirty form remains open.
- Save Settings, tap Back, and verify no confirmation appears.

## Environment

- Xcode project: `Weird Parts IOS/Weird Parts.xcodeproj`
- Scheme: `Weird Parts`
- Device: iPhone 17 Pro simulator, iOS 26.5, UDID `81B76C8A-9A4F-46CE-8A89-ED1DC5842F43`
- DerivedData: `.tmp/DerivedData-WEI1022`
- Workspace note: shared workspace had broad unrelated dirty state before this run; no product source edits were made for this verification.

## Runs

1. Existing focused UI smoke:
   - Command: `xcodebuild test -project 'Weird Parts IOS/Weird Parts.xcodeproj' -scheme 'Weird Parts' -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath .tmp/DerivedData-WEI1022 -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testSettingsDirtyDiscardGuards' -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testSettingsDirtyDiscardKeepEditingAction' -resultBundlePath docs/testing/artifacts/wei-1022/settings-dirty-guards-iphone17pro.xcresult`
   - Result: 1 passed, 1 failed.
   - Passed: `testSettingsDirtyDiscardKeepEditingAction`.
   - Failed: `testSettingsDirtyDiscardGuards`.
   - Failure: `XCTAssertTrue failed - Break & Lunch should return to Settings after saved Back`.
   - Evidence:
     - Result bundle: `docs/testing/artifacts/wei-1022/settings-dirty-guards-iphone17pro.xcresult`
     - Exported attachments: `docs/testing/artifacts/wei-1022/settings-dirty-guards-attachments`
     - Break dirty screenshot: `docs/testing/artifacts/wei-1022/settings-dirty-guards-attachments/5BE7814B-3C68-4D7D-A873-66BD19ADE6BB.png`
     - Break confirmation screenshot: `docs/testing/artifacts/wei-1022/settings-dirty-guards-attachments/23DC0312-E457-435C-B2F5-BAFBB1163C5A.png`

2. Temporary verifier-only Forecast/Audit one-page smoke:
   - Command: `xcodebuild test -project 'Weird Parts IOS/Weird Parts.xcodeproj' -scheme 'Weird Parts' -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath .tmp/DerivedData-WEI1022 -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1022ForecastDirtyDiscardGuard' -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1022AuditDirtyDiscardGuard' -resultBundlePath docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-iphone17pro.xcresult`
   - Result: passed, 2/2 tests.
   - Source note: temporary UI test additions were removed after the run.
   - Evidence:
     - Result bundle: `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-iphone17pro.xcresult`
     - Exported attachments: `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-attachments`
     - Forecast dirty screenshot: `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-attachments/01B26729-B25C-4382-96FD-0D0F4B9AD973.png`
     - Forecast confirmation screenshot: `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-attachments/41A4737A-529A-41EF-929C-B46224CC31C8.png`
     - Audit dirty screenshot: `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-attachments/08825D97-F8B9-4BB8-AB58-41E1E8BD80F8.png`
     - Audit confirmation screenshot: `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-attachments/CED91DCC-7883-4D85-9CF0-F5B1FE12ED15.png`

## Findings

- Break & Lunch: PASS for the requested user-visible guard behavior. Dirty Back shows `Discard changes?` with visible `Discard` and `Keep Editing`; `Keep Editing` leaves the form open. The dedicated Break keep-editing test passed. After Save Settings, no discard confirmation reappeared. The existing combined harness still fails on the stricter `Settings` navigation-bar lookup after saved Back, matching the prior WEI-1020 harness observation; exported hierarchy shows Settings content/search visible.
- Forecast Config: PASS. Dirty Back shows the confirmation with `Discard` and `Keep Editing`; `Keep Editing` stays on Forecast Config; Save Settings then Back does not show a discard confirmation.
- Audit Settings: PASS. Dirty Back shows the confirmation with `Discard` and `Keep Editing`; `Keep Editing` stays on Audit Settings; Save Settings then Back does not show a discard confirmation.

## Duplicate Check

Searched GitHub issues for Settings dirty-discard terms before deciding whether to file a new defect. Existing related issues include:

- GitHub #390: `[Usability][Settings] Dirty-discard confirmation omits Keep Editing cancel action on iPhone`
- GitHub #129: `[Usability][Systemic] Scanner 4: 20+ Settings forms without dirty tracking or discard confirmation`

No new product/UI defect was found in this rerun, so no new GitHub issue was filed.

## Pass/Fail Call

Pass for WEI-1022 product verification. All three requested Settings flows expose the corrected discard guard and recover correctly after `Keep Editing`; saved Back does not re-prompt.

Residual note: the existing combined UI test harness still has a navigation-bar assertion weakness after returning from Break & Lunch, but that did not reproduce as a user-facing Settings dirty-discard defect in this rerun.
