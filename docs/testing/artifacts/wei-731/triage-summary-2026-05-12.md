# WEI-731 iOS Parts/Catalog XCUITest Triage - 2026-05-12

## Scope

Reran the six Parts/Catalog failures from the WEI-730 readiness pass on a freshly created iPhone 17 Pro iOS 26.4.1 simulator:

- Simulator name: `WEI-731 iPhone 17 Pro 26.4.1`
- Simulator UDID: `3BDA50BB-36AB-4CA0-B648-23B4896FE7FE`
- Runtime build: `23E254a`

## Evidence

- Six-test rerun log: `docs/testing/artifacts/wei-731/ios-parts-catalog-six-failures-2026-05-12.log`
- Six-test rerun bundle: `docs/testing/artifacts/wei-731/ios-parts-catalog-six-failures-2026-05-12.xcresult`
- Representative single-test before-fix bundle: `docs/testing/artifacts/wei-731/ios-category-list-single-2026-05-12.xcresult`
- Representative single-test before-fix attachments: `docs/testing/artifacts/wei-731/ios-category-list-single-attachments/`
- Representative single-test after navigation-helper attempts:
  - `docs/testing/artifacts/wei-731/ios-category-list-single-after-button-fix-2026-05-12.xcresult`
  - `docs/testing/artifacts/wei-731/ios-category-list-single-after-label-fix-2026-05-12.xcresult`
  - `docs/testing/artifacts/wei-731/ios-category-list-single-after-text-fix-2026-05-12.xcresult`

## Findings

- The clean simulator still reports repeated `IDELaunchParametersSnapshot` debugger-version warnings.
- The six-test rerun reached test execution but had to be interrupted after Xcode hung during cleanup/finalization. It reported:
  - `testCatalogNLSearchShowsAndClearsAppliedFiltersBanner` passed.
  - Four Categories tests failed before interruption.
  - `testSaveButtonDisabledWhenNameEmpty` did not produce a final per-test line before interruption.
- A completed single-test rerun for `testCategoryListLoadsAllDataCorrectly` failed with:
  - `XCTAssertTrue failed - Parts Categories page should appear after navigation`
- Exported attachments show the app remaining on the `More`/`Dashboard` flow instead of reaching `partsCategoriesPage`.
- Several local UI-test navigation-helper attempts were made to tap the More-list `Parts` row by button, label, and visible text coordinate. They did not resolve the assertion in the simulator run.

## Current Assessment

This is not yet proven to be a product regression in the Parts Categories page itself. The strongest evidence points to an XCUITest navigation/helper issue under the current iPhone More-tab layout, compounded by iOS 26.4.1 simulator/xctrunner launch instability.

## Next Action

Continue with a focused fix for the iPhone More-tab navigation helper, ideally by adding a temporary diagnostic screenshot immediately after the attempted Parts row tap or by driving the app through a more stable direct launch/test hook for the Parts module. Once Categories navigation reaches `partsCategoriesPage`, rerun all five Categories tests before splitting any product-regression child issue.

## Follow-up Fix - 2026-05-12

Implemented and verified a scoped UI-test stability fix for the WEI-730 Parts/Catalog failures:

- Added a `-UITesting -UITestPrimaryModule parts` launch path so the iOS tab order can put Parts in the primary tab bar during UI tests. This avoids the iPhone More-tab `NavigationLink` tap instability while staying inactive outside UI tests.
- Added `moreModule_<id>` accessibility identifiers to the More module rows for diagnostics and fallback navigation.
- Moved the `partsCategoriesPage` accessibility identifier from the page container to a small sentinel view. The container identifier was propagating through SwiftUI and hiding child identifiers such as `createFirstCategoryButton` and `categoryFormSheet` from XCUITest.
- Changed category sheet lookup in the UI tests to use any descendant with `categoryFormSheet`. XCUITest exposes the sheet content as a `CollectionView`, not an `Other` element.

Verification:

- Single category page guard: `ios-category-list-single-page-marker-2026-05-12.xcresult` passed `testCategoryListLoadsAllDataCorrectly`.
- Focused form-sheet rerun: `ios-categories-three-form-sheet-any-descendant-2026-05-12.xcresult` passed `testCreateNewCategorySuccessfully`, `testNewCategorySheetOpensAndCloses`, and `testSaveButtonDisabledWhenNameEmpty`.
- Final WEI-730 six-test slice: `ios-parts-catalog-six-final-2026-05-12.xcresult` passed all six originally failing tests:
  - `testCatalogNLSearchShowsAndClearsAppliedFiltersBanner`
  - `testCategoryListLoadsAllDataCorrectly`
  - `testCreateNewCategorySuccessfully`
  - `testDataPersistsAndDisplaysAfterSheetDismiss`
  - `testNewCategorySheetOpensAndCloses`
  - `testSaveButtonDisabledWhenNameEmpty`

Residual risk:

- Xcode still logs `IDELaunchParametersSnapshot` / debugger-version warnings during UI-test launches on this simulator. These were noisy in the final passing run and did not block execution.
