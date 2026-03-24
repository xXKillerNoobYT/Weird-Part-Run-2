# 32E — Remove Platform Guards Batch 2: Non-Features (57 files)

> **Chain position:** 32D → **32E**
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. This app is iOS ONLY. Remove ALL `#if os(iOS)` / `#elseif os(macOS)` / `#endif` blocks.
2. Keep the iOS code, delete the macOS code and the guards.
3. DO NOT change any other code — ONLY remove platform guards.

## Instructions

Search ALL files in these directories for `#if os(iOS)`:
- `Weird Parts IOS/Weird Parts IOS/AI/`
- `Weird Parts IOS/Weird Parts IOS/Auth/`
- `Weird Parts IOS/Weird Parts IOS/App/`
- `Weird Parts IOS/Weird Parts IOS/Navigation/`
- `Weird Parts IOS/Weird Parts IOS/Scanning/`
- `Weird Parts IOS/Weird Parts IOS/Sync/`
- `Weird Parts IOS/Weird Parts IOS/Shared/`
- `Weird Parts IOS/Weird Parts IOS/DesignSystem/`

Same rules as 32D: keep iOS code, delete guards + macOS code.

**EXCEPTION:** Do NOT touch files in `core/Sources/WiredPartCore/` — the core library may support macOS for testing. Only touch files in the iOS app target.

Also check for `#if canImport(UIKit)` guards in `core/` files — those should stay because the core library compiles for both platforms.

## Success Criteria

- [ ] Zero `#if os(iOS)` in any iOS app target file
- [ ] Core library `#if canImport()` guards preserved
- [ ] Project builds with no errors
