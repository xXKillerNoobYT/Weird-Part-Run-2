# WEI-1016 Notebook Sidebar/Layout QA Evidence

Date: 2026-05-13
Agent: UIVerifier

## Scope

Verified the first slice of notebook sidebar/layout behavior for:

- Compact iPhone notebook detail and common action targets.
- Regular-width iPad/Mac persistent notebook sidebar.
- Job notebook row deep-linking.
- Job Detail > Notebooks linked notebook and missing-notebook recovery.

## Commands Run

Initial scheme check:

```sh
xcodebuild test -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -destination 'id=98CEE4F6-D8F5-49C3-A1B3-0F4CD6C11EA8' -only-testing:"Weird Parts IOSUITests/Weird_Parts_IOSUITests/testWEI1016NotebookCompactLayoutAndTapTargets" -resultBundlePath docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-2026-05-13.xcresult
```

Result: failed before execution because the real UI test target name is `Weird PartsUITests`, not `Weird Parts IOSUITests`.

Compact iPhone reruns:

```sh
xcodebuild test -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -destination 'id=98CEE4F6-D8F5-49C3-A1B3-0F4CD6C11EA8' -only-testing:"Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1016NotebookCompactLayoutAndTapTargets" -resultBundlePath docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-target-rerun-2026-05-13.xcresult
xcodebuild test -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -destination 'id=98CEE4F6-D8F5-49C3-A1B3-0F4CD6C11EA8' -only-testing:"Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1016NotebookCompactLayoutAndTapTargets" -resultBundlePath docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-rerun2-2026-05-13.xcresult
xcodebuild test -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -destination 'id=98CEE4F6-D8F5-49C3-A1B3-0F4CD6C11EA8' -only-testing:"Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1016NotebookCompactLayoutAndTapTargets" -resultBundlePath docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-rerun3-debug-2026-05-13.xcresult
```

Result: executed, but failed before completing the notebook detail path. The debug run captured useful UI evidence before failure.

Fresh simulator rerun:

```sh
xcodebuild test -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -destination 'id=81B76C8A-9A4F-46CE-8A89-ED1DC5842F43' -only-testing:"Weird PartsUITests/Weird_Parts_IOSUITests/testWEI1016NotebookCompactLayoutAndTapTargets" -resultBundlePath docs/testing/artifacts/wei-1016/iphone17pro-compact-notebook-layout-2026-05-13.xcresult
```

Result: blocked by Xcode/simulator launch failure: `NSMachErrorDomain Code=-308 "(ipc/mig) server died"` while launching `Weird PartsUITests.xctrunner`.

## Evidence Captured

- `docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-rerun3-debug-2026-05-13.xcresult`
- Exported attachments: `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/`
- Key accessibility tree: `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/BC762C09-77CA-4B7D-92B7-F5C68DC4E27D.txt`
- Key screenshot: `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/51B9DF4D-D93E-41E4-A0AB-B340F9896AD7.png`

## Findings

1. New issue filed: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/410

   Compact iPhone sync conflict banner consumes most of the screen before notebook content. The captured tree shows `3 sync conflicts auto-resolved` at `{{64.7, 56.0}, {131.0, 306.3}}`; Notebooks content begins around y=368.3 on an 812 pt-tall screen. This leaves only a small usable notebook-list region before the tab bar.

## Status By Acceptance Area

- Compact iPhone notebook list: partially verified. The Notebooks module loaded and showed seeded job notebooks, but the conflict banner severely reduced usable space.
- Compact iPhone notebook detail: not completed. Automation failed before the filtered WEI-1016 row could be opened after verifier adjustment.
- Compact iPhone tap targets: not completed. The test code now measures Notebook sections, Add content, Create job notebook, and Retry, but Xcode simulator launch instability blocked a clean run.
- Regular iPad/Mac sidebar: not completed. Additional simulator runs were stopped after repeated Xcode launch failures.
- Job notebook row deep-link: not completed in this heartbeat.
- Job Detail > Notebooks linked notebook and missing-notebook recovery: not completed in this heartbeat.

## Duplicate Check

Searched existing GitHub issues with:

```sh
gh issue list --repo xXKillerNoobYT/Weird-Part-Run-2 --search "sync conflict banner mobile viewport notebook" --state all --limit 20 --json number,title,state,url,labels
```

Result: no matching issue found before filing #410.

## Blocker

Further live QA is blocked by local Xcode/simulator instability. Both the iPhone 13 mini iOS 26.4.1 simulator and a fresh iPhone 17 Pro iOS 26.5 simulator failed with Mach `-308` during UI-test launch after the initial debug run.

Next action: rerun the two WEI-1016 UI tests after resetting the simulator service or using a clean runner, then attach the passing/failing result bundles for iPhone and iPad regular width.
