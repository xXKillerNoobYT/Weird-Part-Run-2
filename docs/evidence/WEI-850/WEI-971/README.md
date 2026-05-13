# WEI-971 macOS coverage gate evidence

## Commands

```sh
xcodebuild -list -workspace 'Wierd Parts.xcworkspace'
xcodebuild test -workspace 'Wierd Parts.xcworkspace' -scheme 'WiredPart-macOS' -destination 'platform=macOS,arch=arm64' -resultBundlePath docs/evidence/WEI-850/WEI-971/WiredPart-macOS.xcresult
```

## Result

- `xcodebuild -list` advertises `WiredPart-iOS`, `WiredPart-macOS`, and `WiredPartCore`.
- `WiredPart-macOS` completed successfully on macOS arm64.
- XCTest executed 5 tests with 0 failures.

## Artifacts

- `WiredPart-macOS.log`
- `WiredPart-macOS.xcresult`
