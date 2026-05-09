# WEI-134 Onboard AI Observability + Device Matrix

## Success Condition
- We can capture onboarding local-AI bootstrap latency and route outcome from app logs.
- We can verify deterministic fallback behavior for `modelUnavailable`, `timeout`, and `lowResource`.
- QA has a compact, repeatable matrix for supported device profiles.

## Metrics Hook (Current)
- Log emitted in `AppCore.evaluateOnboardAIRuntimeIfEnabled()`:
  - Prefix: `[OnboardAI]`
  - Fields: `route=<ready|modelUnavailable|timeout|lowResource> latency_ms=<int>`

## Collection Steps
1. Enable feature flag `feature_onboard_ai_mvp_enabled` in AI Config settings.
2. Fresh-launch app with onboarding path visible.
3. Collect logs filtered to `[OnboardAI]`.
4. Record route + latency in the table below.

## Representative Measurements
| Date | Device Profile | OS | Route | latency_ms | Notes |
| --- | --- | --- | --- | --- | --- |
| TBD | iPhone 15 Pro Simulator | iOS 18.x | TBD | TBD | Initial baseline |
| TBD | iPhone SE (3rd gen) Simulator | iOS 18.x | TBD | TBD | Lower-end CPU profile |

## Fallback Validation Checklist
- [ ] Model unavailable path logs `route=modelUnavailable` and onboarding remains safe/continuable.
- [ ] Timeout path logs `route=timeout` and onboarding remains safe/continuable.
- [ ] Low-resource path logs `route=lowResource` and onboarding remains safe/continuable.
- [ ] Ready path logs `route=ready` with expected latency.

## QA Handoff Notes
- Flag location: Settings -> AI Config -> Enable Onboard AI MVP.
- Functional entry screen: `OnboardAIMVPEntryView`.
- Runtime decision source: `OnboardAIRuntimeBootstrapper`.
