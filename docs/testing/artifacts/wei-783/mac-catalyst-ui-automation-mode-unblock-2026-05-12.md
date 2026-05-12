# WEI-783 / GitHub #381 Mac Catalyst UI Automation Mode - 2026-05-12

## Result

Mac Catalyst XCUITest remains blocked on this host before product UI
interaction. A direct Mac Catalyst launch smoke now provides stronger Mac
coverage than compile-only build smoke while the host automation permission
blocker is resolved.

## Focused XCUITest Reproduction

```sh
xcodebuild test \
  -workspace 'Wierd Parts.xcworkspace' \
  -scheme WiredPart-iOS \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -skip-testing:WiredPartCoreTests \
  -skip-testing:'Weird PartsTests' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testCatalogNLSearchShowsAndClearsAppliedFiltersBanner' \
  -resultBundlePath docs/testing/artifacts/wei-783/mac-catalyst-catalog-nl-rerun-2026-05-12.xcresult
```

Result: the runner builds, signs, launches, logs `Running tests...`, then fails
after roughly 60 seconds with:

```text
The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.)
```

Evidence:

- `docs/testing/artifacts/wei-783/mac-catalyst-catalog-nl-rerun-2026-05-12.log`
- `docs/testing/artifacts/wei-783/mac-catalyst-catalog-nl-rerun-2026-05-12.xcresult`
- `docs/testing/artifacts/wei-783/mac-catalyst-catalog-nl-rerun-summary-2026-05-12.txt`
- `docs/testing/artifacts/wei-783/mac-catalyst-showdestinations-2026-05-12.log`

## Host / Signing Checks

- Destination selection resolves to local `My Mac` arm64 Mac Catalyst.
- Codesign uses the available Apple Development identity and the UI-test runner
  has testmanager, AX server, and HID sandbox exceptions.
- Local TCC state could not be inspected from this process:
  `sqlite3 ~/Library/Application Support/com.apple.TCC/TCC.db ...` returned
  `authorization denied`.
- An Apple Events/System Events probe hung until killed, which is consistent
  with this non-interactive shell lacking the host privacy permission needed for
  UI automation inspection.
- `screencapture` produced a black screenshot during direct-launch evidence
  capture, so Screen Recording is also not usable as reliable visual evidence
  from this shell.

Entitlement evidence:

- `docs/testing/artifacts/wei-783/mac-catalyst-app-entitlements-2026-05-12.txt`
- `docs/testing/artifacts/wei-783/mac-catalyst-uitest-runner-entitlements-2026-05-12.txt`

## Replacement Mac Verification Path

Added:

```sh
scripts/mac-catalyst-launch-smoke.sh [artifact-dir]
```

This smoke builds the Mac Catalyst app, launches the signed app directly with
the same UI-test routing arguments (`-UITesting -UITestPrimaryModule parts`),
verifies the `Weird Parts` process remains alive, attempts a screenshot, then
terminates the app. It proves more than compile-only coverage because it
exercises product launch, UI-testing fixture mode, and primary-module routing
arguments without depending on XCUITest automation mode.

Manual direct run evidence from this heartbeat:

- `docs/testing/artifacts/wei-783/mac-catalyst-direct-launch-2026-05-12.log`
- `docs/testing/artifacts/wei-783/mac-catalyst-direct-launch-process-state-2026-05-12.txt`
- `docs/testing/artifacts/wei-783/mac-catalyst-direct-launch-2026-05-12.png`
- `docs/testing/artifacts/wei-783/launch-smoke-script-isolated/mac-catalyst-launch-smoke-2026-05-12-071630.log`

The screenshot artifact is retained for completeness, but it is black due to
host capture permissions and should not be used as visual UI evidence.

## Operator Action To Fully Unblock XCUITest

On the Mac host running the UI automation job, open System Settings and grant or
confirm:

- Privacy & Security > Accessibility: Xcode, Terminal or the CI shell host, and
  any XCTest runner host shown during the prompt.
- Privacy & Security > Automation: Xcode/Terminal permission to control System
  Events and the tested app if prompted.
- Privacy & Security > Screen & System Audio Recording: the shell/Xcode host, if
  screenshot evidence is required.

After those grants, rerun the focused XCUITest command above. Success means the
test reaches app interaction instead of failing during automation-mode startup.
