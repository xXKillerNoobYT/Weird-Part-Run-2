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
| Pending QA | iPhone 17 Pro Simulator | iOS 26.4.1 | ready + fallbacks | TBD | Capture via app log filter `[OnboardAI]` |
| Pending QA | iPhone 17e Simulator | iOS 26.4.1 | ready + fallbacks | TBD | Lower-end profile in current runtime image |

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
