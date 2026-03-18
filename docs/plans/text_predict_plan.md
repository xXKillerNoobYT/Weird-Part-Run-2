# Intelligent Text Pre-Fill & Predictive Typing Plan

> **Created:** 2026-03-15
> **Phase:** 12+ (AI Integration Extension)
> **Dependencies:** Phase 12 (AI — Apple), Core Package (Phase 1)
> **Constraint:** Fully offline. Local-only inference. No cloud APIs. Bluetooth-only sync.

---

## Overview

Add context-aware text prediction, smart autofill, and next-word suggestions across all text input fields in WiredPart. Uses on-device language models (Apple Foundation Models primary, llama.cpp fallback) to provide intelligent suggestions based on previously entered text, known job data, parts catalog, supplier information, and truck inventory.

---

## Capabilities

### 1. Predictive Next-Word Suggestions

Real-time ghost text that appears ahead of the cursor, showing the predicted continuation. User presses Tab to accept.

| Platform | Primary Engine | Fallback |
|----------|---------------|----------|
| macOS 26+ | Foundation Models (`LanguageModelSession`) | llama.cpp local model |
| iOS 26+ | Foundation Models | llama.cpp local model |
| macOS <26 | llama.cpp | System autocorrect only |
| iOS <26 | llama.cpp | System autocorrect only |
| Windows | Copilot Runtime (Phase 13) | llama.cpp |

### 2. Smart Autofill

Pre-populate entire form fields based on context. Triggered when user opens a form — relevant fields are pre-filled with best-guess values.

| Form | Auto-Filled Fields | Context Source |
|------|-------------------|----------------|
| **Purchase Order** | Supplier, delivery address, payment terms | Recent POs to same supplier |
| **Delivery Sheet** | Driver name, vehicle, destination job | Current schedule + vehicle assignment |
| **Supplier Form** | Contact info, payment terms | Previous supplier records |
| **Job Notes** | Date header, crew present, weather | Today's date, scheduled crew, job location |
| **Inventory Descriptions** | Category, unit, typical quantities | Parts catalog patterns |
| **Daily Report** | Crew names, job name, date, hours summary | Clock-in data for today |
| **Notebook Entry** | Template-based pre-fill | Notebook template + job context |
| **Clock-Out Questionnaire** | Previously common answers | Historical questionnaire responses |

### 3. Context-Aware Suggestions

In text fields, suggestions draw from local data:

| Context Type | Data Source | Used For |
|-------------|-------------|----------|
| Part names/codes | `parts` table | Part description fields |
| Supplier names | `suppliers` table | Supplier selection, notes |
| Job names/codes | `jobs` table | Job reference fields |
| Employee names | `users` table | Crew assignment, notes |
| Bin locations | `bin_locations` table | Warehouse fields |
| Vehicle names/plates | `vehicles` table | Fleet fields |
| Tool names/serials | `tools` table | Tool checkout fields |
| Historical text | `_text_history` table | Previously typed phrases |
| Common phrases | Built-in phrase library | Professional communication |

---

## Technical Architecture

### Text Prediction Pipeline

```
User Types in TextField
         │
         ▼
┌──────────────────────────┐
│  Debounce (300ms)        │
│  Skip if < 3 chars       │
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐
│  Context Builder          │
│  - Current text           │
│  - Field type             │
│  - Form context           │
│  - Recent entries         │
│  - Related entities       │
└──────────┬───────────────┘
           │ PredictionContext
           ▼
┌──────────────────────────┐
│  TextPredictor (Core)     │
│  1. Entity lookup (fast)  │
│  2. Phrase completion     │
│  3. LLM generation (if   │
│     entity lookup empty)  │
└──────────┬───────────────┘
           │ [TextSuggestion]
           ▼
┌──────────────────────────┐
│  AITextField (SwiftUI)    │
│  - Ghost text overlay     │
│  - Tab to accept          │
│  - Arrow keys to cycle    │
│  - Esc to dismiss         │
└──────────────────────────┘
```

### Prediction Priority Chain

Predictions are generated from multiple sources, ranked by speed and relevance:

1. **Entity Lookup (< 10ms):** Direct database search for matching entities (parts, suppliers, jobs). Highest priority for entity-reference fields.

2. **Phrase Completion (< 20ms):** Match against `_text_history` table. Previous entries in the same field type that start with the current input.

3. **Template Expansion (< 5ms):** Built-in templates for common patterns (e.g., "Received delivery from ..." → fill supplier + date).

4. **LLM Generation (< 2s):** Foundation Models or llama.cpp for free-form text. Only invoked when no entity/phrase match found and field is a note/description type.

---

## Core Module: TextPredictor

**Path:** `core/Sources/WiredPartCore/AI/TextPredictor.swift`

```swift
actor TextPredictor {
    private let db: AppDatabase
    private let aiService: AIService?
    private let phraseCache: PhraseCache

    /// Generate predictions for a text field
    func predict(context: PredictionContext) async -> [TextSuggestion]

    /// Record a completed text entry for future predictions
    func recordEntry(fieldType: String, text: String, entityContext: [String: String]?) async

    /// Pre-fill a form based on context
    func generatePreFill(formType: FormType,
                         context: PreFillContext) async -> [PreFilledField]

    /// Clear prediction history for a field type
    func clearHistory(fieldType: String?) async
}
```

### Data Types

```swift
struct PredictionContext {
    let currentText: String
    let cursorPosition: Int
    let fieldType: FieldType
    let formContext: FormContext?
    let maxSuggestions: Int          // default 3
}

enum FieldType: String {
    // Entity-reference fields
    case partName, partCode, partDescription
    case supplierName, jobName, employeeName
    case binLocation, vehicleName, toolName

    // Free-text fields
    case jobNotes, dailyReportNotes, notebookEntry
    case deliveryNotes, inspectionNotes
    case chatMessage, qaQuestion
    case poNotes, returnReason
    case clockOutNotes, questionnaireAnswer
}

struct FormContext {
    let formType: FormType
    let relatedJobId: Int64?
    let relatedSupplierId: Int64?
    let relatedVehicleId: Int64?
    let currentDate: Date
    let currentUserId: Int64?
}

enum FormType: String {
    case purchaseOrder, deliverySheet, supplierForm
    case jobNotes, inventoryDescription, dailyReport
    case notebookEntry, clockOutQuestionnaire
    case chatMessage, qaResponse
}

struct TextSuggestion {
    let text: String
    let source: SuggestionSource
    let confidence: Float
    let isPartial: Bool             // true = continuation, false = full replacement
}

enum SuggestionSource {
    case entityLookup               // matched from database
    case phraseHistory              // matched from text history
    case templateExpansion          // matched from template
    case llmGeneration              // generated by AI model
}

struct PreFilledField {
    let fieldName: String
    let value: String
    let confidence: Float
    let source: SuggestionSource
    let editable: Bool              // always true — user can override
}
```

---

## Text History Table

Track previously entered text for phrase completion:

```sql
CREATE TABLE _text_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    field_type TEXT NOT NULL,        -- e.g., 'job_notes', 'po_notes'
    text_content TEXT NOT NULL,
    entity_context TEXT,             -- JSON: {"job_id": 42, "supplier_id": 7}
    usage_count INTEGER DEFAULT 1,
    last_used_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_th_field_type ON _text_history(field_type);
CREATE INDEX idx_th_last_used ON _text_history(last_used_at DESC);
```

- Entries deduplicated by (field_type, text_content)
- `usage_count` incremented on repeat use
- Entries older than 90 days with usage_count = 1 are auto-pruned
- Max 1,000 entries per field_type (LRU eviction)
- This table is **local-only** — not synced via Bluetooth (privacy)

---

## Smart Autofill Logic

### Purchase Order Autofill

```
Trigger: User opens New PO form
Context: {supplier_id (if known), job_id (if from JPO)}

1. If supplier known:
   → Fill: supplier contact, delivery address, payment terms
   → Source: most recent PO to this supplier

2. If from JPO:
   → Fill: job name, delivery address (job site)
   → Source: JPO record + job record

3. Line items:
   → Pre-populate from JPO line items
   → Prices from latest supplier price history
```

### Daily Report Autofill

```
Trigger: User opens Daily Report form for today
Context: {date: today, user_id}

1. Crew present:
   → Source: labor_entries WHERE date = today
   → Fill: list of employees who clocked in today

2. Job worked:
   → Source: labor_entries WHERE date = today, user = current
   → Fill: job name + address

3. Hours summary:
   → Source: labor_entries totals
   → Fill: total hours, overtime hours

4. Weather:
   → Not auto-filled (offline constraint — no weather API)
   → But suggest: "Clear / Cloudy / Rain / Snow" picker
```

### Job Notes Autofill

```
Trigger: User opens job notes text field
Context: {job_id, date: today}

1. Date header:
   → Auto-insert: "March 15, 2026 — "

2. Crew suggestion:
   → If crew clocked in today, suggest: "Crew: [names]"

3. Previous pattern:
   → If user typically starts notes with a pattern, suggest it
   → Source: _text_history WHERE field_type = 'job_notes'
```

---

## SwiftUI Components

### AITextField (Enhanced)

The existing `AITextField` from the Phase 12 plan is extended:

```swift
struct AITextField: View {
    @Binding var text: String
    let fieldType: FieldType
    let formContext: FormContext?
    let placeholder: String

    // AI features
    @State private var ghostText: String = ""
    @State private var suggestions: [TextSuggestion] = []
    @State private var showEnhancePopover = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Ghost text (dimmed, ahead of cursor)
            if !ghostText.isEmpty {
                Text(text + ghostText)
                    .foregroundColor(.secondary.opacity(0.4))
            }

            // Actual text editor
            TextEditor(text: $text)
                .onChange(of: text) { _, newValue in
                    Task { await updatePredictions() }
                }
                .onKeyPress(.tab) {
                    acceptGhostText()
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismissSuggestions()
                    return .handled
                }
        }
        // Enhance button (proofread, rewrite, summarize)
        .toolbar {
            if !text.isEmpty {
                EnhanceButton(text: $text, showPopover: $showEnhancePopover)
            }
        }
    }
}
```

### AutoFillBanner

Shown at the top of a form when autofill has pre-populated fields:

```swift
struct AutoFillBanner: View {
    let filledFieldCount: Int
    let onAcceptAll: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
            Text("\(filledFieldCount) fields pre-filled from recent data")
            Spacer()
            Button("Accept All", action: onAcceptAll)
            Button("Clear", action: onClearAll)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
```

---

## Platform-Specific Implementations

### macOS Predictive Text

- Foundation Models via `LanguageModelSession` (macOS 26+)
- llama.cpp via bundled GGUF model (any macOS version)
- System autocomplete via `NSTextCheckingResult` for spelling
- Keyboard: Tab = accept, Esc = dismiss, ↑↓ = cycle suggestions

### iOS Predictive Text

- Foundation Models via `LanguageModelSession` (iOS 26+)
- llama.cpp via bundled GGUF model (any iOS version)
- Integrates with iOS keyboard suggestions bar (`.autocorrectionDisabled()` for AI fields only)
- Tap ghost text to accept on mobile

### Windows Predictive Text (Phase 13)

- Copilot Runtime for text generation (Windows primary)
- llama.cpp fallback
- Same `TextPredictor` core logic
- Windows-specific keyboard handling

---

## Configuration

User-configurable settings in Settings → AI:

| Setting | Default | Options |
|---------|---------|---------|
| Enable predictive text | On | On / Off |
| Enable smart autofill | On | On / Off |
| Prediction engine | Auto | Auto / Foundation Models / llama.cpp / Off |
| Ghost text opacity | 40% | 20% / 40% / 60% |
| Suggestion delay | 300ms | 100ms / 300ms / 500ms |
| Save text history | On | On / Off |
| History retention | 90 days | 30 / 60 / 90 / 180 days |

---

## Bluetooth Sync Considerations

| Data | Syncs? | Reason |
|------|--------|--------|
| `_text_history` | **No** | Privacy — personal typing patterns are device-local |
| Form data filled by predictions | **Yes** | Normal record sync — predictions just pre-fill fields |
| AI configuration settings | **Yes** | Settings table syncs normally |
| Prediction model files | **No** | Each device downloads/bundles independently |

---

## Performance Budgets

| Operation | Target | Platform |
|-----------|--------|----------|
| Entity lookup suggestion | < 10ms | All |
| Phrase history suggestion | < 20ms | All |
| Template expansion | < 5ms | All |
| LLM ghost text generation | < 2s first token | All |
| Form autofill (all fields) | < 500ms | All |
| Text history write | < 5ms | All |
| Memory overhead (predictions) | < 20MB RSS | All |

---

## Field Type Coverage (71 Tier-1 Fields)

These fields get full AI prediction support:

| Module | Fields | Prediction Type |
|--------|--------|----------------|
| **Jobs** | Job name, job notes, daily report notes, clock-out notes, questionnaire answers | Free-text + entity |
| **Orders** | PO notes, JPO notes, line item descriptions, special item descriptions, return reasons | Free-text + entity |
| **Warehouse** | Movement notes, receiving notes, audit notes | Free-text |
| **Parts** | Part description, category notes, supplier notes | Entity + free-text |
| **People** | Employee notes, certification notes, skill descriptions | Free-text |
| **Fleet** | Inspection notes, fuel notes, maintenance notes, delivery notes | Free-text |
| **Chat** | Messages, Q&A questions, Q&A answers | Free-text |
| **Notebooks** | Entry content, section descriptions | Free-text + template |
| **Scheduling** | Dispatch notes, time-off reasons | Free-text |
| **Tools** | Checkout notes, maintenance notes | Free-text |
| **Reports** | Report comments, export notes | Free-text |

---

## Acceptance Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Entity suggestion relevance | ≥ 80% of suggestions are contextually relevant | 50-interaction test set |
| Phrase completion accuracy | ≥ 70% of accepted suggestions are correct | User acceptance rate tracking |
| LLM ghost text grammatical correctness | ≥ 95% | 100 generated completions reviewed |
| LLM ghost text no hallucination | 0% fabricated entity names | 100 completions with entity context |
| Smart autofill field accuracy | ≥ 85% of pre-filled fields are correct | 30 form-fill scenarios |
| Prediction latency (entity) | < 10ms p95 | Instrumented timing |
| Prediction latency (LLM) | < 2s first token | Instrumented timing |
| No prediction in sensitive fields | 0% predictions in PIN/password fields | Security audit |
| Graceful degradation (no AI) | All fields work as plain text when AI disabled | Toggle off test |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Predictive text hallucinations (wrong entity names) | Medium | High | Entity lookup is always preferred over LLM; LLM only for free-text |
| Autofill suggests stale data | Medium | Medium | Always show source date; user must review before submit |
| Text history leaks between users on shared device | Low | High | Text history keyed by user_id; cleared on logout |
| LLM latency too high for ghost text | Medium | Medium | Show loading indicator; fall back to entity/phrase suggestions |
| Foundation Models unavailable | High (pre-macOS 26) | Low | llama.cpp fallback covers all functionality |
| User annoyance from aggressive suggestions | Medium | Medium | Configurable: delay, opacity, on/off per field type |
