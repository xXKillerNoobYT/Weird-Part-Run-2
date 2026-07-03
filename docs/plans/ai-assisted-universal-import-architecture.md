# AI-Assisted Universal Import Architecture

> **Issue:** WEI-2812 (planning child WEI-2953)
> **Revision:** 2026-06-04.1 (landed to `docs/plans/` 2026-07-02 via the #1374 branch-disposition pass)
> **Status:** Plan of record for the parts universal-import pipeline. Stages 1–2 (shared source-adapter contract + supplier-aware dedupe) have landed on `main`; Stage 3 (digital PDF / OCR preview adapters) is partially unlanded — see [Branch Salvage Review — 2026-07](branch-salvage-review-2026-07.md).
> **Purpose:** Extend parts import from validated CSV/XLSX into a universal, preview-first, evidence-preserving import pipeline for supplier spreadsheets, digital PDFs, scanned PDFs, and visual table layouts.

---

## Scope

WEI-2812 extends the parts import path from validated CSV/XLSX into a universal import pipeline for supplier spreadsheets, digital PDFs, scanned PDFs, and visual table layouts. The feature is data-integrity sensitive: every path must preview first, preserve source evidence, support human override, and commit atomically.

This plan is for parts catalog import only. It should not broaden into generic app-wide data import until the parts flow proves the contract.

## Current Inventory

The repo already contains a useful baseline:

- `PartsImportExportPage` supports file picking, CSV/XLSX preview, editable column mapping, conflict review, and CSV commit.
- `PartsService.previewPartsImportCSV` parses rows into `PartsImportPreview`, validates required `name` and `category`, validates non-negative numeric `cost_price` and `markup_percent`, and detects conflicts by exact `code`, then case-insensitive `name`.
- `PartsService+XLSXImport` reads the first XLSX worksheet through `ZIPFoundation`, bounds archive size, normalizes rows into the same tabular preview path, and stores `sourceKind`, `sheetName`, and SHA-256 source hash metadata.
- `PartsService.commitPartsImportCSV` writes new and accepted conflict-update rows in a GRDB transaction. Validation errors stop writes. Mid-commit failures roll back the transaction.
- Migration 097 created `part_import_sessions` and `part_import_row_evidence`; tests verify committed sessions, failed sessions, rollback behavior, and row evidence.
- `PartsService+OCRImportPreview` deterministically chunks extracted OCR text, detects simple table rows, attaches page/snippet evidence and confidence, and intentionally keeps OCR commit disabled.
- `OCRProcessor` extracts business document fields from recognized text blocks and can match known suppliers and part codes from the local database.

Main gaps:

- No unified source-adapter contract across CSV, XLSX, PDF text extraction, OCR, and AI vision.
- XLSX only uses the first worksheet; there is no multi-sheet picker contract yet.
- PDF import is disabled in UI.
- OCR candidates do not flow into the canonical tabular preview/commit path.
- AI field mapping is local heuristic-only today; no structured AI proposal schema, threshold policy, saved mapping model, or privacy gate exists for import.
- Dedupe keys are too narrow for supplier data; current matching is `code` then `name`, not supplier-aware or configurable.
- Audit evidence exists, but it does not yet capture mapping version, parser kind/version, confidence, duplicate decision, source page/chunk, or per-field before/after values.

## Target Architecture

Use a three-stage pipeline:

1. Source adapters produce `PartsImportExtractedTable`.
2. Mapping converts source columns/candidates into canonical `PartsImportDraftRow`.
3. Preview/commit uses one shared dedupe, validation, conflict, audit, and transaction path.

### Source Adapter Contract

Each parser returns:

- `source`: kind (`csv`, `xlsx`, `pdf_text`, `ocr`, `vision`), filename, sheet/page range, source hash, parser version.
- `tables`: one or more tables with `tableId`, `displayName`, `rows`, source bounds, and extraction confidence.
- `columns`: raw names, normalized names, inferred types, and per-column confidence.
- `cells`: raw value, normalized value, source row/column, optional page/chunk/snippet evidence, and confidence.
- `errors`: non-fatal parser warnings and fatal parser failures.

CSV and XLSX are deterministic adapters. Digital PDF first tries text-layer/table extraction. Scanned PDF and arbitrary visual layouts are OCR/vision adapters and remain preview-only until confidence/evidence rules and UX are accepted.

### AI Field Mapping Contract

AI can propose, never write. It returns JSON only:

```json
{
  "mappingVersion": "parts-import-v1",
  "sourceFingerprint": "sha256:...",
  "supplierHint": "optional supplier name",
  "columns": [
    {
      "sourceColumn": "Part #",
      "targetField": "code",
      "confidence": 0.94,
      "reason": "Header alias matches part number"
    }
  ],
  "rowHints": [
    {
      "sourceRow": 12,
      "dedupeKey": {"code": "EMT-2", "supplierId": 4},
      "confidence": 0.88
    }
  ]
}
```

Thresholds:

- `>= 0.90`: preselect mapping, still visibly user-editable.
- `0.70-0.89`: suggest mapping with review badge; user must confirm before commit.
- `< 0.70`: leave unmapped.
- Any OCR/vision row with row confidence `< 0.85` is quarantined from commit until manually corrected.
- Numeric price/cost/stock fields are never accepted solely from AI; deterministic validation must parse the final value.

Saved mappings:

- Store by supplier, source kind, normalized header fingerprint, mapping version, target app schema version, created/updated user, and last accepted timestamp.
- Reuse only when required target fields still exist and confidence remains above threshold.
- Any user override updates saved mapping only after successful commit, not during preview.

### Dedupe and Conflict Policy

Canonical dedupe keys, in order:

1. `supplierId + supplierPartNumber/code` when supplier context exists.
2. Exact `code` when no supplier is selected.
3. Case-insensitive normalized `name + categoryId + brandId` as a fallback.
4. AI row hints are advisory only; they cannot override deterministic key matches.

Preview classifications:

- `new`: no matching part.
- `update`: deterministic match and non-conflicting field changes.
- `duplicate_skip`: incoming row is equivalent to existing data.
- `conflict_review`: deterministic match with meaningful differences, duplicate key ambiguity, or low-confidence mapping.
- `quarantined`: validation failure, low OCR/vision confidence, missing required fields, or unsupported field type.

Users can flip `new`, `update`, and `duplicate_skip` decisions before commit. Quarantined rows require correction/re-preview before they can be included.

### Atomic Write, Rollback, and Audit

Commit must happen through a single service method and GRDB transaction:

- Revalidate the final preview inside the transaction.
- Resolve or create hierarchy rows inside the same transaction.
- Write parts, supplier links, and optional stock thresholds in the same transaction.
- Roll back all writes on any validation or database error.
- Mark `part_import_sessions.status` as `committed` or `failed`; failed imports must not leave row evidence for rolled-back rows.

Audit additions:

- Extend/import a companion evidence table for parser kind/version, mapping version, saved mapping id, table id, source page/chunk/snippet, per-row confidence, dedupe key, decision, and before/after field JSON for updates.
- Keep source file hash, not file contents, unless the user explicitly saves the original document locally.
- Add a read model for import history and row evidence before exposing audit UI.

## Security and Privacy

- Default to on-device/local parsing and local Apple/Foundation Models where available.
- Cloud AI/vision must be opt-in at admin level, clearly indicated in UI, and disabled for confidential supplier/customer documents unless policy permits it.
- Send minimum necessary snippets to AI: headers, sample rows, and redacted values where possible. Do not send full documents by default.
- Never send credentials, auth tokens, local database paths, QR secrets, employee PII, customer contact details, or unrelated job notes in import prompts.
- Log AI provider, model family, request timestamp, source hash, and mapping version, but do not persist raw prompts/responses containing sensitive source data unless explicitly approved.
- AI output is untrusted input. It must pass deterministic schema validation, value parsing, permission checks, and human review before commit.

## Staged Delivery Plan

Stage 0: Plan/design/liveness gates

- WEI-2953 records this technical plan.
- WEI-2954 owns the user-facing flow and mobile/large-preview states.
- WEI-2955 restores execution liveness for plan/design children.

Stage 1: Core import contracts and deterministic adapters — **landed on `main`**

- Add core models for source adapters, extracted tables, draft rows, mapping proposals, preview decisions, and source evidence (`PartsImportSourceKind`, `PartsImportSourceEvidence`, `PartsImportExtractedTable`, `PartsImportDraftRow`).
- Refactor CSV and XLSX onto the shared contract without changing current UI behavior.
- Add multi-sheet XLSX metadata and parser tests, with first-sheet behavior preserved until UI selects a sheet.

Stage 2: Mapping and supplier-aware dedupe — **landed on `main`**

- Add saved mapping persistence and deterministic mapping aliases.
- Add supplier-aware dedupe keys and preview decision classification.
- Preserve existing CSV/XLSX import behavior through compatibility tests.

Stage 3: Digital PDF and OCR preview — **partially unlanded (WEI-2958); see [Branch Salvage Review — 2026-07](branch-salvage-review-2026-07.md)**

- Add digital PDF text/table extraction adapter.
- Bridge OCR candidates into the shared preview model while keeping commit blocked for low-confidence/uncorrected OCR rows.
- Keep scanned/vision fallback preview-only until security review and UX evidence are complete.

Stage 4: Commit and audit hardening

- Consolidate commit under a source-agnostic method.
- Extend import session/evidence audit with parser, mapping, confidence, decision, dedupe, and before/after metadata.
- Add rollback tests for creates, updates, hierarchy creation, supplier links, and evidence.

Stage 5: UI implementation and verification

- Implement the UX from WEI-2954 on `PartsImportExportPage`: source selection, sheet selection, mapping review, preview classifications, quarantined rows, confirmation, progress, and audit summary.
- Verify iOS file picker and relevant desktop/macOS surfaces if enabled.
- Run LocalFirstReviewer on code changes, then GPTReviewer/SecurityAgent for AI/privacy or audit-sensitive changes.

## Validation Gates

- Unit tests for every adapter and mapping/dedupe classification.
- Existing `PartsServiceAdvancedTests`, XLSX tests, and OCR preview tests remain green.
- New transaction tests prove failed imports do not create parts, hierarchy rows, supplier links, stock rows, or row evidence.
- UI verification captures iPhone/narrow, iPad/wide, and large-row preview states.
- Security review accepts AI data minimization, provider gating, prompt logging, and source retention behavior before cloud/vision fallback is enabled.

## Delivery Constraints

> **Historical note (2026-06-04):** the canonical repo had high branch/worktree pressure (179 remote heads, 18 open PRs). Implementation children were told to start in small batches and not open parallel branches beyond Stage 1 until branch cleanup made capacity clear.

That branch cleanup happened: the 2026-07-02 drain (#513, decided in #1348) reduced origin to a clean set, and the #1374 disposition pass landed this plan and reviewed the remaining Stage-3 / auth-hardening branches. Stage 3 implementation should resume from the salvage recommendations in [Branch Salvage Review — 2026-07](branch-salvage-review-2026-07.md) rather than from the stale `WEI-2958` branch, because that branch was cut before Stages 1–2 landed and no longer applies cleanly to `main`.
