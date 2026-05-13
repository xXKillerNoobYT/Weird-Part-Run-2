# Mac Catalyst Verification

Last updated: 2026-05-12

## Current Decision

Mac Catalyst XCUITest automation is environment-blocked on this machine. The
`WiredPart-iOS` UI test runner builds, signs, launches, and logs `Running
tests...`, then fails before app interaction with:

```text
Timed out while enabling automation mode.
```

Treat this as a test runner or host automation configuration blocker, not a
product UI failure. Do not mark Mac Catalyst page flows as failed from this
condition alone.

## Evidence

- GitHub tracker: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/381
- WEI-759 triage: `docs/testing/artifacts/wei-759/mac-catalyst-ui-automation-timeout-triage-2026-05-12.md`
- WEI-762 rerun log: `docs/testing/artifacts/wei-762/mac-catalyst-catalog-nl-rerun-2026-05-12.log`
- WEI-762 result bundle: `docs/testing/artifacts/wei-762/mac-catalyst-catalog-nl-rerun-2026-05-12.xcresult`
- WEI-762 passing non-UI build smoke log:
  `docs/testing/artifacts/wei-762/mac-catalyst-build-smoke-2026-05-12-035401.log`

The WEI-762 rerun used:

```sh
xcodebuild test \
  -workspace 'Wierd Parts.xcworkspace' \
  -scheme WiredPart-iOS \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -skip-testing:WiredPartCoreTests \
  -skip-testing:'Weird PartsTests' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testCatalogNLSearchShowsAndClearsAppliedFiltersBanner' \
  -resultBundlePath docs/testing/artifacts/wei-762/mac-catalyst-catalog-nl-rerun-2026-05-12.xcresult
```

## Supported Mac Smoke

Until #381 is resolved, use the direct-launch Mac Catalyst smoke when you need
stronger coverage than compile-only build verification:

```sh
scripts/mac-catalyst-launch-smoke.sh
```

The launch smoke compiles the `WiredPart-iOS` scheme for the local Mac Catalyst
destination, starts the signed app with `-UITesting -UITestPrimaryModule parts`,
verifies the app process remains alive, and writes timestamped evidence under
`docs/testing/artifacts/mac-catalyst-launch-smoke/`. It does not prove control
interaction because this host still blocks XCUITest automation mode.

Use the non-UI Mac Catalyst build smoke when launch is not required:

```sh
scripts/mac-catalyst-build-smoke.sh
```

The script compiles the `WiredPart-iOS` scheme for the local Mac Catalyst
destination and writes a timestamped log under
`docs/testing/artifacts/mac-catalyst-smoke/`. Passing this smoke means the
Catalyst app builds for the local Mac; it does not prove page reachability,
keyboard accessibility, layout quality, or XCUITest automation support.

## Unblock Criteria

Resume Mac Catalyst UI flow verification only after one of these is true:

- The isolated XCUITest command above reaches test body app interaction.
- Build/QA confirms and documents the required host permissions, signing, or
  Xcode runner configuration, then reruns the isolated command successfully.
- The team replaces Catalyst XCUITest with another supported Mac UI
  verification path and updates this document plus GitHub #381.

## WEI-783 Follow-up

WEI-783 reproduced the same pre-interaction runner failure and added the direct
launch smoke as the current replacement path. Evidence is in
`docs/testing/artifacts/wei-783/mac-catalyst-ui-automation-mode-unblock-2026-05-12.md`.
