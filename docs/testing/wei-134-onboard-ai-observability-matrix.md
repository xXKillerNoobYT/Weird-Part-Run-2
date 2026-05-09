# WEI-134 Onboard AI Observability + Device Matrix

## Success Condition
- We can capture onboarding local-AI bootstrap latency and route outcome from app logs.
- We can verify deterministic fallback behavior for `modelUnavailable`, `timeout`, and `lowResource`.
- QA has a compact, repeatable matrix for supported device profiles.

## Metrics Hook (Current)
- Log emitted in `AppCore.evaluateOnboardAIRuntimeIfEnabled()`:
  - Prefix: `[OnboardAI]`
  - Fields:
    - `route=<ready|modelUnavailable|timeout|lowResource>`
    - `latency_ms=<int>`
    - `availability=<available|modelNotReady|notSupported|none>`
    - `timeout_budget_ms=<int>`
    - `did_timeout=<true|false>`
    - `fallback_model_unavailable=<true|false>`
    - `fallback_low_resource=<true|false>`

## Collection Steps
1. Enable feature flag `feature_onboard_ai_mvp_enabled` in AI Config settings.
2. Fresh-launch app with onboarding path visible.
3. Collect logs filtered to `[OnboardAI]`.
4. Record route + latency in the table below.

## Representative Measurements
| Date | Device Profile | OS | Route | latency_ms | Notes |
| --- | --- | --- | --- | --- | --- |
| 2026-05-08 | macOS arm64 test harness (WiredPartCore) | macOS 14.x | ready | ~1 | `swift test --filter OnboardAIRuntimeBootstrapTests` |
| 2026-05-08 | macOS arm64 test harness (WiredPartCore) | macOS 14.x | modelUnavailable | ~1 | `swift test --filter OnboardAIRuntimeBootstrapTests` |
| 2026-05-08 | macOS arm64 test harness (WiredPartCore) | macOS 14.x | timeout | ~255 | Timeout route assertion run; test harness includes scheduling overhead |
| 2026-05-08 | macOS arm64 test harness (WiredPartCore) | macOS 14.x | lowResource | ~1 | Low-resource short-circuit run |
| 2026-05-09 | iPhone 17 Pro Simulator | iOS 26.4.1 | ready | 71-125 | `simctl launch ... -feature_onboard_ai_mvp_enabled YES`; repeated launches captured `route=ready` with `availability=available` |
| 2026-05-09 | iPhone 17e Simulator | iOS 26.4.1 | ready | 70 | `simctl launch ... -feature_onboard_ai_mvp_enabled YES`; lower-end profile run captured `route=ready` with `availability=available` |

## Runtime Evidence Snapshot (2026-05-09, America/Denver)
| Evidence Type | Captured Routes | Missing Routes | Source |
| --- | --- | --- | --- |
| Filtered runtime-format `[OnboardAI]` logs (macOS harness) | ready, modelUnavailable, timeout, lowResource | iOS device/simulator-native logs | `docs/testing/artifacts/wei-191/wei-191-onboardai-filtered-runtime-2026-05-08.log` |
| Filtered runtime-format `[OnboardAI]` logs (iPhone 17 Pro simulator) | ready | modelUnavailable, timeout, lowResource (not reproducible in this runtime run) | `docs/testing/artifacts/wei-245/iphone-17-pro-ios-26_4_1-onboardai-filtered.log` |
| Filtered runtime-format `[OnboardAI]` logs (iPhone 17e simulator) | ready | modelUnavailable, timeout, lowResource (not reproducible in this runtime run) | `docs/testing/artifacts/wei-245/iphone-17e-ios-26_4_1-onboardai-filtered.log` |
| macOS core bootstrap test run | ready, modelUnavailable, timeout, lowResource | n/a | `cd core && swift test --filter OnboardAIRuntimeBootstrapTests` |

Command output excerpt from latest core run:
```
✔ Test "low resource route short-circuits availability check" passed after 0.001 seconds.
✔ Test "ready route when model is available" passed after 0.001 seconds.
✔ Test "model unavailable route when model is not available" passed after 0.001 seconds.
✔ Test "timeout route when availability check exceeds timeout" passed after 0.255 seconds.
✔ Test run with 4 tests in 1 suite passed after 0.256 seconds.
```

## WEI-191 Artifact Bundle (2026-05-08)
- Bundle archive: `docs/testing/artifacts/wei-191/wei-191-artifact-bundle-2026-05-08.tgz`
- Raw test output: `docs/testing/artifacts/wei-191/wei-191-swift-test-onboard-runtime-2026-05-08.log`
- Filtered route logs (`[OnboardAI]` prefix): `docs/testing/artifacts/wei-191/wei-191-onboardai-filtered-runtime-2026-05-08.log`
- Matrix snapshot for reviewers: `docs/testing/artifacts/wei-191/wei-191-matrix-snapshot-2026-05-08.md`

## WEI-245 iOS Runtime Evidence (2026-05-09)
- Build log: `docs/testing/artifacts/wei-245/wei-245-xcodebuild.log`
- iPhone 17 Pro raw simulator log capture: `docs/testing/artifacts/wei-245/iphone-17-pro-ios-26_4_1-onboardai.log`
- iPhone 17 Pro filtered `[OnboardAI]` lines: `docs/testing/artifacts/wei-245/iphone-17-pro-ios-26_4_1-onboardai-filtered.log`
- iPhone 17e raw simulator log capture: `docs/testing/artifacts/wei-245/iphone-17e-ios-26_4_1-onboardai.log`
- iPhone 17e filtered `[OnboardAI]` lines: `docs/testing/artifacts/wei-245/iphone-17e-ios-26_4_1-onboardai-filtered.log`

## Fallback Validation Checklist
- [x] Model unavailable path telemetry includes `route=modelUnavailable`, `fallback_model_unavailable=true`, and onboarding remains safe/continuable.
- [x] Timeout path telemetry includes `route=timeout`, `did_timeout=true`, and onboarding remains safe/continuable.
- [x] Low-resource path telemetry includes `route=lowResource`, `fallback_low_resource=true`, and onboarding remains safe/continuable.
- [x] Ready path telemetry includes `route=ready` and `availability=available`.

## QA Handoff Notes
- Flag location: Settings -> AI Config -> Enable Onboard AI MVP.
- Functional entry screen: `OnboardAIMVPEntryView`.
- Runtime decision source: `OnboardAIRuntimeBootstrapper`.
- Targeted verification command used for route evidence: `cd core && swift test --filter OnboardAIRuntimeBootstrapTests`.
