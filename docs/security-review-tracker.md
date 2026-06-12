# Security Review Tracker

> Auto-maintained by `security-review` SKILL.md body (invoked via `/auto-go` C8 check).
> Each run logs files scanned, phases executed, findings, and any issues filed.

## Latest Run

**Date:** 2026-06-07
**Area:** AI/vision import privacy and provider gates
**Issue:** WEI-2963 / WEI-2812

### Files scanned
- `core/Sources/WiredPartCore/Services/PartsService+OCRImportPreview.swift`
- `core/Sources/WiredPartCore/OCR/OCRProcessor.swift`
- `core/Sources/WiredPartCore/OCR/OCRScannerAdapter.swift`
- `core/Sources/WiredPartCore/AI/FoundationModelsService.swift`
- `core/Sources/WiredPartCore/ImageMatch/ImageFeatureAdapter.swift`
- `Weird Parts IOS/Weird Parts IOS/Scanning/IOSOCRScanner.swift`
- `Weird Parts IOS/Weird Parts IOS/Scanning/IOSDocumentScanView.swift`
- `Weird Parts IOS/Weird Parts IOS/Scanning/IOSImageFeatureAdapter.swift`
- `Weird Parts IOS/Weird Parts IOS/PrivacyInfo.xcprivacy`
- `Weird Parts IOS/Weird-Parts-IOS-Info.plist`
- `core/Tests/WiredPartCoreTests/PartsOCRImportPreviewTests.swift`

### Phase results
- **Provider gates:** PASS — AI generation uses Apple Foundation Models behind `canImport(FoundationModels)` and OS availability checks; repo search found no OpenAI/Anthropic/Gemini/cloud AI provider calls in the AI/OCR/vision import path.
- **Vision/OCR privacy:** FIXED — camera usage disclosure now names document scanning and text recognition, matching `VNDocumentCameraViewController` use.
- **Import commit gate:** PASS — OCR parts import remains preview-only with `isCommitAllowed == false`; tests assert no parts are written by `previewPartsImportOCR`.
- **Local processing:** PASS — OCR and image matching use Apple Vision/VisionKit locally; network scan found only LAN/peer sync paths, not AI/image provider uploads.
- **Evidence handling:** PASS — OCR import candidates keep page/snippet evidence for human review; raw OCR text is displayed transiently in scan UI and accepted fields are explicitly user-confirmed.

### Findings
**0 critical, 0 high, 0 medium, 1 low fixed in-place.**

| # | Severity | Description | Resolution |
|---|----------|-------------|------------|
| 1 | Low | iOS camera permission string mentioned QR/barcodes/device pairing but not document scanning or text recognition. | Updated `NSCameraUsageDescription` to include documents, text recognition, and document scanning. |

### Verdict
**PASS** — AI/vision import paths are on-device/provider-gated and preview-only. Remote provider fallback is not enabled. Security/go/no-go criteria for enabling provider fallback are captured under the WEI-2812 AI Vision Security Gates plan/evidence set.

---

**Date:** 2026-04-24
**Area:** tools
**Iteration:** AUTO GO R4 iter 2 (C8)

### Files scanned (7 changed in last 7 days)
- `core/Sources/WiredPartCore/Services/ToolsService.swift` (1,731 lines)
- `Weird Parts IOS/.../Features/Tools/` — 6 files (Router, Dashboard, Registry, Checkouts, Detail, Maintenance, Admin, Kits)

### Phase results (OWASP checks A–G)
- **A. SQL injection (parameterization):** ✅ CLEAN — all user input bound via `StatementArguments`; 3 field-interpolation sites (lines 888/903/938) confirmed allow-list-gated by `allowedToolEditFields` (Set<String> at line 852). `'-' || ?` months interpolation (line 683) is a numeric Int, not user string — safe.
- **B. Auth / authorization (hardcoded IDs, missing role checks):** ✅ CLEAN — all write methods guard-let `currentUser?.id`; `?? 0` occurrences are row-ID defaults in result mapping, not userId fallbacks; FK-orphan guards on all 10 write paths verified by iter 1 & 2 of R4.
- **C. Mass assignment (allowedToolEditFields):** ✅ CLEAN — allow-list enforced at both `editToolWithVerification` (line 884) and `approveToolEdit` (line 934); no callsite bypasses found.
- **D. PII leakage (print / os_log):** ✅ CLEAN — zero `print()`, `NSLog`, `os_log`, or `.debug()` calls in service or iOS pages.
- **E. Race conditions (TOCTOU / non-atomic writes):** ✅ CLEAN — all checkout/return/trade/edit operations run inside a single `dbWriter.write` block; check-then-write is atomic per GRDB's serialized writer.
- **F. Path traversal / file inclusion:** ✅ CLEAN — no `FileManager` or file IO anywhere in tools area.
- **G. Secret handling:** ✅ CLEAN — no hardcoded tokens, keys, passwords, or `UserDefaults` writes of sensitive data.

### Findings
**0 critical, 0 high, 2 medium** — tools area passes for Critical/High.

| # | Severity | Description | Issue |
|---|----------|-------------|-------|
| 1 | Medium | `respondToTrade` accepts no `responderId` — service cannot enforce only the designated recipient can respond | [#271](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/271) |
| 2 | Medium/Low | `markToolMaintenance` has no `performedBy` param — status change to 'maintenance' is unattributed in audit log | [#272](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/272) |

### Verdict
**PASS** — no Critical or High findings. Two medium findings filed as GitHub issues #271 and #272.

---

## Previous Run: 2026-04-19 (chat area)

**Area:** chat
**Iteration:** AUTO GO day 2 iter 7 (C8)

### Files scanned (9 changed in last 7 days)
- `core/Sources/WiredPartCore/Services/ChatService.swift`
- `core/Tests/WiredPartCoreTests/ChatServiceTests.swift`
- `Weird Parts IOS/.../Features/Chat/` — 7 files (Channels, MessageThread, QAQuestionForm, QuestionsPage, RFIListPage, EscalationTimeline, CreateChannelSheet)

### Phase results
- **M1 Credential Misuse (UserDefaults):** ✅ CLEAN — no sensitive values stored in UserDefaults
- **M3 Auth/Authz (hardcoded user IDs):** ✅ CLEAN — all userId flows from `appCore.currentUser?.id`; guard-let pattern throughout
- **M4 Input Validation (SQL string concat):** ✅ CLEAN — all SQL uses GRDB parameterized `arguments:` arrays; no interpolated user input
- **M5 Insecure Communication (`http://`):** ✅ CLEAN
- **M8 Misconfig (`NSLog(`, `console.log()`):** ✅ CLEAN
- **M10 Weak Crypto (MD5/SHA1/DES/RC4/arc4random):** ✅ CLEAN — no crypto in chat layer

### Findings
**0 critical, 0 high, 0 medium, 0 low** — chat area passes security review.

### Noted (not findings — previous parts run)
- The 10 SQL interpolation patterns in PartsService.swift are the correct GRDB idiom and worth documenting in CLAUDE.md or a security guide: "UPDATE table SET \(setClauses.joined(\", \")) WHERE id = ?" with StatementArguments(args) is safe IFF setClauses members are compile-time whitelisted strings, never user input.

## Findings Log

| Date | Area | File:Line | Check | Description | Issue |
|------|------|-----------|-------|-------------|-------|
| 2026-04-24 | tools | ToolsService.swift:1118 | B/Auth | respondToTrade: no service-level recipient check — UI-only gate | [#271](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/271) |
| 2026-04-24 | tools | ToolsService.swift:399 | B/Audit | markToolMaintenance: no performedBy param — unattributed status change | [#272](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/272) |
