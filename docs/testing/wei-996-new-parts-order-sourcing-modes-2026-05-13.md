# WEI-996 New Parts Order Sourcing Modes QA

Status: Pass

## Scope

Verified the New Parts Order source-mode UI from WEI-993 on compact iPhone and regular iPad layouts.

## Environment

- App: `WiredPart-iOS`
- iPhone: `WEI-899 iPhone 11 Pro Max 414pt`, iOS Simulator 26.4.1
- iPad: `WEI-899 iPad 9th gen 768pt`, iOS Simulator 26.4.1
- Command shape:
  - `xcodebuild test -workspace 'Wierd Parts.xcworkspace' -scheme 'WiredPart-iOS' -destination 'platform=iOS Simulator,name=WEI-899 iPhone 11 Pro Max 414pt,OS=26.4.1' -only-testing:'Weird PartsUITests/WEI996NewPartsOrderSourcingVerifierUITests/testNewPartsOrderSourcingModesAreUsable' -resultBundlePath 'docs/testing/artifacts/wei-996/iphone-sourcing-modes-2026-05-13.xcresult'`
  - `xcodebuild test -workspace 'Wierd Parts.xcworkspace' -scheme 'WiredPart-iOS' -destination 'platform=iOS Simulator,name=WEI-899 iPad 9th gen 768pt,OS=26.4.1' -only-testing:'Weird PartsUITests/WEI996NewPartsOrderSourcingVerifierUITests/testNewPartsOrderSourcingModesAreUsable' -resultBundlePath 'docs/testing/artifacts/wei-996/ipad-sourcing-modes-2026-05-13.xcresult'`

## Evidence

- iPhone result: `docs/testing/artifacts/wei-996/iphone-sourcing-modes-2026-05-13.xcresult` — Passed, 1 test, 0 failures.
- iPad result: `docs/testing/artifacts/wei-996/ipad-sourcing-modes-2026-05-13.xcresult` — Passed, 1 test, 0 failures.
- Exported screenshots:
  - `docs/testing/artifacts/wei-996/iphone-attachments/`
  - `docs/testing/artifacts/wei-996/ipad-attachments/`

## Findings

- Local Catalog: Pass. Catalog search remained functional and cart action stayed reachable. The current UI-test database did not expose a matching pre-seeded catalog part for common terms, so the verifier used the screen's Fast Add path to create a placeholder catalog part, then searched `WEI996` and confirmed the catalog result/cart state.
- Supplier Websites: Pass. Selecting the segment on both layouts renders the no-bridge state with the connected-bridge explanation plus `Use Local Catalog` and `Fast Add Part`.
- Web: Pass. Selecting the segment on both layouts renders the unavailable/privacy-gated state with `Use Local Catalog` and `Fast Add Part`.
- WEI-1001 policy follow-up: Open Web remains Safari/browser-handoff only. No in-app open-web result rows, paid/credentialed search provider, search API call, or query logging path is approved by this QA evidence.
- Compact labels: Pass. iPhone compact layout uses `Catalog`, `Suppliers`, and `Web`; all were visible and reachable.
- Regular labels: Pass. iPad regular layout uses `Local Catalog`, `Supplier Websites`, and `Web`; all were visible and reachable.

## Duplicate Check

- Paperclip search for `New Parts Order sourcing` showed related completed tickets: [WEI-981](/WEI/issues/WEI-981) and [WEI-995](/WEI/issues/WEI-995), plus this QA ticket [WEI-996](/WEI/issues/WEI-996).
- GitHub search for `New Parts Order sourcing` showed existing parent issue `#400 Making New parts order`.
- No new defects found, so no new GitHub issue was filed.

## Notes

The temporary verifier XCTest used for the run was removed after producing the result bundles and exported screenshots.
