# Apple Foundation Models Integration Plan

> **Phase:** Post-V1.0 Enhancement
> **Status:** Planning
> **Created:** 2026-03-14
> **Prerequisites:** iOS 26+ / macOS 26+ (ships fall 2026), Tauri migration complete
> **Prior art:** Phase 14 AI Integration (LM Studio), existing `AiAssistantPanel.tsx`

---

## 1. Executive Summary

Integrate Apple's on-device Foundation Models framework into the Wired Part app to provide intelligent text assistance across all ~333 text fields in 14 feature areas. The on-device model runs privately with no data leaving the device, making it ideal for a trade-business app handling customer data, pricing, and job details.

### What the user gets

- **Autocomplete/suggestions** as they type in notes, descriptions, and messages
- **Smart field pre-fill** based on context (e.g., dispatch notes auto-suggest based on job + crew)
- **Text refinement** — proofread, rewrite, summarize long notes
- **Q&A answers** from local data via Tool calling (e.g., "What's the delivery lead time for supplier X?")
- **Apple Writing Tools** — system-level proofread/rewrite/summarize on all textareas (free with UITextView/UITextField in native — requires explicit bridge for WebView)

### What makes this different from the existing AI panel

The existing `AiAssistantPanel` is a floating chat panel backed by LM Studio (an external LLM server). It's shop-only and requires network access. Foundation Models is:
- **On-device, always available** — no server, no internet, works offline
- **Inline** — suggestions appear in/near the text field, not in a separate panel
- **System-level** — Apple Intelligence features (Writing Tools) integrate at the OS level
- **Private** — data never leaves the device, critical for customer PII and pricing data

---

## 2. Architecture Overview

### 2.1 The Bridge Problem

Foundation Models is a **Swift-only framework** (iOS 26+ / macOS 26+). Our app is a **React + TypeScript WebView** inside a **Tauri (Rust)** shell. We need a bridge:

```
React (TypeScript in WKWebView)
  → Tauri invoke() IPC
  → Rust #[tauri::command]
  → C FFI (extern "C")
  → Swift @_cdecl functions
  → FoundationModels framework
  → Swift → C → Rust → Tauri → React
```

### 2.2 Recommended Bridge: Swift `@_cdecl` via `build.rs`

This follows the exact same pattern as the existing Multipeer Connectivity bridge (`objc/MultipeerBridge.m` → `multipeer.rs`), but in Swift instead of Objective-C.

**Why this approach:**
- Proven pattern already in the codebase (Multipeer)
- Minimal build system changes (add Swift compilation to `build.rs`)
- Clean separation: Swift handles Apple frameworks, Rust handles IPC, TypeScript handles UI
- No new dependencies or plugin systems needed

**Alternatives considered:**

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **A. Swift `@_cdecl` (recommended)** | Same pattern as Multipeer, minimal changes | Must compile Swift from build.rs | **Best fit** |
| **B. ObjC wrapper around Swift** | cc crate compiles ObjC perfectly | Extra indirection, ObjC can't call Swift async directly | Too complex |
| **C. Full Tauri Swift Plugin** | Official Tauri 2 pattern | Much heavier setup, needs Package.swift + swift-rs | Overkill |
| **D. WKWebView message handler** | Bypasses Rust entirely | Tauri owns the WKWebView internally, can't intercept it | Not viable |

### 2.3 Async Handling

Foundation Models APIs are Swift `async`. The C FFI boundary is synchronous. Solution: **polling queue pattern** (same as Multipeer's `_receiveQueue`).

```
TypeScript                    Rust                    Swift
─────────                    ────                    ─────
llm_request(prompt, id) →   wp_llm_submit()    →   queue task, return immediately
  ↓ poll
llm_poll_result(id)     →   wp_llm_poll()      →   check queue, return JSON or null
  ↓ (repeat until result)
  result ← ────────────────  JSON string ← ──────  completed generation
```

This is non-blocking: the TypeScript side uses `setInterval` or `requestAnimationFrame` to poll, keeping the UI responsive.

### 2.4 System Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│ React Frontend (WebView)                                  │
│                                                           │
│  ┌─────────────────┐  ┌────────────────────────────────┐ │
│  │ useAITextField() │  │ AiSuggestionPopover component  │ │
│  │ React hook       │  │ (floating suggestions UI)       │ │
│  └────────┬────────┘  └──────────────┬─────────────────┘ │
│           │                           │                    │
│  ┌────────▼───────────────────────────▼────────────────┐  │
│  │ src/lib/foundation-models.ts                         │  │
│  │ TypeScript service: submit, poll, availability check │  │
│  └────────────────────────┬────────────────────────────┘  │
│                            │ invoke('llm_*')               │
└────────────────────────────┼──────────────────────────────┘
                             │ Tauri IPC
┌────────────────────────────┼──────────────────────────────┐
│ Rust (src-tauri/)          │                               │
│  ┌─────────────────────────▼───────────────────────────┐  │
│  │ src/foundation_models.rs                             │  │
│  │ #[tauri::command] functions + extern "C" FFI         │  │
│  └─────────────────────────┬───────────────────────────┘  │
│                             │ C FFI                        │
│  ┌─────────────────────────▼───────────────────────────┐  │
│  │ swift/FoundationModelsBridge.swift                   │  │
│  │ @_cdecl functions                                    │  │
│  │ LanguageModelSession + Tools + queue management      │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ Apple FoundationModels.framework (on-device LLM)    │  │
│  └─────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

---

## 3. Foundation Models Capabilities & Limitations

### 3.1 What the model CAN do well

| Capability | Relevance to Wired Part |
|-----------|------------------------|
| **Summarization** | Summarize long job notes, chat threads, notebook entries |
| **Entity extraction** | Pull part numbers, addresses, phone numbers from freeform text |
| **Text refinement** | Improve grammar/clarity in notes, emails, Q&A answers |
| **Creative writing** | Draft dispatch notes, time-off request reasons, supplier emails |
| **Classification** | Categorize Q&A questions, triage anomalies |
| **Dialog generation** | Chat-like responses for the AI assistant |
| **Tag generation** | Auto-tag notebook entries, job types |
| **Tool calling** | Query local SQLite for parts, contacts, jobs — feed results into generation |
| **Guided generation** | Return structured Swift types (e.g., parsed part requests, structured addresses) |

### 3.2 What the model CANNOT do well

| Limitation | Impact |
|-----------|--------|
| **Math / calculations** | Don't use for cost calculations, pricing, quantity math |
| **Code generation** | Not relevant to this app |
| **Logical reasoning** | Don't rely on for complex business rule evaluation |
| **4096 token context window** | Limits how much context we can provide per request |
| **Single request per session** | Can't have concurrent requests on the same session |
| **Latency** | On-device generation takes a few seconds — must be async with loading indicators |

### 3.3 Model Availability

The model requires:
1. **Device supports Apple Intelligence** — iPhone 15 Pro+, iPad with M1+, Mac with M1+
2. **Apple Intelligence enabled** in Settings
3. **Model downloaded** — may take time after first enable

**Fallback is mandatory.** ~30-40% of devices in a typical trade company fleet won't have Apple Intelligence capability (older iPhones, iPads). The app must work identically without AI assistance — it's an enhancement, never a requirement.

---

## 4. Text Field Classification & AI Integration Strategy

### 4.1 Field Categories

We classify the ~333 text fields into 5 tiers based on how much value AI adds:

#### Tier 1: High-Value Long-Form Text (~71 textareas) — FULL AI INTEGRATION

These are multiline text fields where users write freeform content. AI can help most here.

| Feature Area | Fields | AI Features |
|-------------|--------|-------------|
| Chat messages | ChatMessageComposer | Autocomplete, tone refinement, summarize thread |
| Q&A questions/answers | QAQuestionForm, QABoardPage | Auto-draft answers from local data, refine text |
| Job notes | ActiveJobsPage, EditJobModal, ClockOutFlow | Pre-fill from job context, summarize daily work |
| Dispatch notes | DailyDispatchPage, SubSchedulePage | Auto-suggest from job + crew context |
| Notebook entries | NoteEntryCard, TaskEntryCard, CreateEntryModal | Autocomplete, expand bullet points |
| Supplier emails | SendEmailModal | Draft email body from PO data |
| Order notes | UnifiedOrderPage, ConversationThread | Pre-fill from order context |
| Time-off reasons | TimeOffPage | Suggest professional phrasing |
| Part descriptions | CatalogPage, PartDetailPanel | Generate from category + brand |
| Report annotations | ReportAnnotations | Summarize data being annotated |
| Approval comments | ApprovalsTab | Suggest approval/rejection language |
| Clock-out questionnaire | ClockOutFlow | Autocomplete from prior answers |

**AI Features for Tier 1:**
- Inline autocomplete (ghost text that completes on Tab)
- "Enhance" button (proofread/rewrite/summarize)
- Context-aware suggestions (uses Tool calling to pull relevant local data)
- Apple Writing Tools integration (proofread, rewrite, summarize in system UI)

#### Tier 2: Medium-Value Short Inputs (~40 fields) — CONTEXTUAL SUGGESTIONS

Short text fields where AI can suggest completions based on existing data.

| Feature Area | Fields | AI Features |
|-------------|--------|-------------|
| Job name/number | ActiveJobsPage, EditJobModal | Suggest next number in sequence |
| Customer name | Job forms | Autocomplete from contacts DB |
| Supplier notes | SupplierFormModal | Draft from supplier history |
| Vehicle descriptions | Maintenance forms | Suggest from make/model |
| Template names | DispatchTemplatesPage | Suggest from existing templates |
| Employee skill names | EmployeeDetailPage | Suggest from known skill list |

**AI Features for Tier 2:**
- Dropdown suggestions from local data (no LLM needed — SQLite query)
- Smart autocomplete for names/codes (fuzzy match from DB)

#### Tier 3: Search Fields (~45 fields) — NO AI (already fast)

Search inputs that filter existing data. These are already instant with client-side filtering.

| Examples | Rationale |
|----------|-----------|
| All "Search..." inputs | Already filter in <50ms, AI adds no value |
| Command palette | Already indexed with cmdk library |

**AI Features for Tier 3:** None. These are optimally served by existing client-side search.

#### Tier 4: Numeric/Code Fields (~80 fields) — NO AI

Number inputs, prices, quantities, dates, PINs, VINs, license plates.

| Examples | Rationale |
|----------|-----------|
| Quantity inputs, price fields | Math accuracy required — AI hallucination risk |
| PIN entry | Security — AI should never assist with credentials |
| Odometer readings | Exact values required |

**AI Features for Tier 4:** None. These require exact values; AI would introduce errors.

#### Tier 5: Contact Info Fields (~50 fields) — AUTOCOMPLETE FROM DB ONLY

Phone, email, address fields where we autocomplete from the contacts database.

| Examples | Rationale |
|----------|-----------|
| Phone, email fields | Autocomplete from contacts DB (no LLM) |
| Address fields | Autocomplete from known addresses (no LLM) |

**AI Features for Tier 5:** Database-powered autocomplete only. No LLM involvement.

### 4.2 Summary

| Tier | Fields | AI Type | LLM Required |
|------|--------|---------|-------------|
| 1. Long-form text | ~71 | Full AI (autocomplete, enhance, Writing Tools) | Yes |
| 2. Short contextual | ~40 | Context suggestions from DB | Partial (for drafting) |
| 3. Search fields | ~45 | None | No |
| 4. Numeric/code | ~80 | None | No |
| 5. Contact info | ~50 | DB autocomplete only | No |
| **Total** | **~333** | | |

**Only Tier 1 (~71 fields) and partially Tier 2 (~40 fields) use the Foundation Models LLM.** The rest use existing patterns or no AI at all.

---

## 5. Custom Tools (Foundation Models Tool Protocol)

The on-device model's biggest power is **Tool calling** — it can query your app's data to answer questions or pre-fill context. We define 3-5 tools (the recommended max for the 4096-token context window).

### 5.1 Tool Definitions

#### Tool 1: `SearchParts`
```swift
struct SearchParts: Tool {
    let name = "searchParts"
    let description = "Search the parts catalog by name, code, or category"

    @Generable struct Arguments {
        @Guide(description: "Search term") var query: String
        @Guide(description: "Max results", .range(1...5)) var limit: Int
    }

    func call(arguments: Arguments) async throws -> [String] {
        // Query local SQLite: parts table
        // Return formatted strings: "PART-001: 3/4 EMT Connector ($2.50)"
    }
}
```

#### Tool 2: `SearchContacts`
```swift
struct SearchContacts: Tool {
    let name = "searchContacts"
    let description = "Find employees, customers, or contractors by name"

    @Generable struct Arguments {
        @Guide(description: "Name to search for") var name: String
        @Guide(description: "Contact type: employee, customer, contractor") var contactType: String
    }

    func call(arguments: Arguments) async throws -> [String] {
        // Query local SQLite: users, customers, general_contractors
        // Return: "John Smith (Electrician) — 555-0123"
    }
}
```

#### Tool 3: `GetJobInfo`
```swift
struct GetJobInfo: Tool {
    let name = "getJobInfo"
    let description = "Get details about a job by name or number"

    @Generable struct Arguments {
        @Guide(description: "Job name or number") var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        // Query local SQLite: jobs table + related dispatch, notes
        // Return formatted job summary
    }
}
```

#### Tool 4: `GetSupplierInfo`
```swift
struct GetSupplierInfo: Tool {
    let name = "getSupplierInfo"
    let description = "Get supplier details including lead times and contacts"

    @Generable struct Arguments {
        @Guide(description: "Supplier name") var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        // Query local SQLite: suppliers table + contacts
        // Return formatted supplier summary
    }
}
```

### 5.2 Tool Implementation Notes

- Tools query the **same local SQLite database** used by the TS data layer
- The Swift bridge opens a read-only SQLite connection directly (not through Tauri's SQL plugin)
- Tool descriptions are kept short to conserve the 4096-token context window
- Tools are provided selectively based on the field context (e.g., parts search only when in a parts-related field)

---

## 6. UI/UX Design

### 6.1 Inline Autocomplete (Tier 1 Textareas)

```
┌─────────────────────────────────────────────────┐
│ Notes                                            │
│ ┌───────────────────────────────────────────────┐│
│ │ Installed 200A panel in garage. Need to │      ││
│ │ run conduit to the main breaker box and       ││ ← ghost text (gray)
│ │                                               ││
│ │                                               ││
│ └───────────────────────────────────────────────┘│
│ [Tab to accept] [Esc to dismiss]   ✨ Enhance ▾ │
└─────────────────────────────────────────────────┘
```

- **Ghost text:** Light gray text after the cursor showing the model's completion
- **Tab:** Accept the suggestion
- **Esc / keep typing:** Dismiss and continue typing
- **Debounce:** 800ms after last keystroke before requesting a completion
- **Enhance button:** Opens a popover with "Proofread", "Rewrite", "Summarize" options

### 6.2 Enhance Popover

```
┌────────────────────┐
│ ✨ Enhance Text    │
│                    │
│ 📝 Proofread      │ ← Fix grammar & spelling
│ ✏️ Rewrite        │ ← Improve clarity
│ 📋 Summarize      │ ← Condense long text
│ 📖 Expand         │ ← Add detail to bullet points
│ 🎯 Professional   │ ← Make tone more professional
│                    │
│ ─────────────────  │
│ ❌ Cancel          │
└────────────────────┘
```

### 6.3 Context-Aware Pre-fill

When a user opens a new note/dispatch/entry, the AI can pre-fill based on context:

```
┌─────────────────────────────────────────────────┐
│ Dispatch Notes for Job #J-2024-042              │
│ ┌───────────────────────────────────────────────┐│
│ │                                               ││
│ │                                               ││
│ └───────────────────────────────────────────────┘│
│                                                  │
│  💡 AI can pre-fill from job context:           │
│  ┌────────────────────────────────────────────┐  │
│  │ Smith Residence — 123 Main St              │  │
│  │ Panel upgrade, 200A service                │  │
│  │ Crew: John D., Mike R.                     │  │
│  │                         [Use this draft]   │  │
│  └────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### 6.4 Availability Indicators

```
When AI is available:
  ✨ icon in the field corner (subtle, non-intrusive)

When AI is unavailable:
  No indicator — field works exactly as before

When generating:
  ⟳ spinner replacing the ✨ icon
```

### 6.5 Error States

- **Model not ready:** "Apple Intelligence is setting up. AI suggestions will be available soon."
- **Device not eligible:** No AI UI shown at all (graceful degradation)
- **Generation failed:** Toast notification "AI suggestion failed" — field continues to work normally
- **Context window exceeded:** Silently retry with reduced context, or skip suggestion

---

## 7. Safety & Privacy Considerations

### 7.1 Built-in Guardrails

Apple's Foundation Models has built-in safety:
- Blocks harmful content generation
- Blocks personally harmful content
- Blocks hateful/violent/sexual content
- Cannot be jailbroken or overridden by app developers

### 7.2 App-Level Safety

| Concern | Mitigation |
|---------|-----------|
| **PII exposure in prompts** | Data stays on-device — Foundation Models is local-only, no cloud |
| **Pricing data in suggestions** | AI can reference prices for context but we don't auto-insert prices into fields |
| **Customer data** | All queries are against local SQLite — same data the user already has access to |
| **Hallucinated part numbers** | Tool calling returns real data; freeform suggestions clearly marked as AI-generated |
| **Wrong autocomplete accepted** | User must explicitly Tab to accept — no auto-insertion |
| **Offensive language in notes** | Apple's built-in guardrails prevent this |

### 7.3 Data Flow (What Goes to the Model)

```
Prompt to model:
  "You are helping an electrician write job notes.
   Current job: Smith Residence (J-2024-042), 200A panel upgrade.
   Complete the following text: [user's partial text]"

→ All data is LOCAL. The model runs on the device's Neural Engine.
→ No data is sent to Apple servers, the internet, or any cloud.
→ Apple's privacy guarantee: Foundation Models data stays on-device.
```

### 7.4 Permission Model

- **Per-field opt-out:** Users can disable AI for any specific field via long-press → "Turn off AI suggestions"
- **Global toggle:** Settings → AI Config → "Apple Intelligence assistance" on/off
- **Per-user:** Respects the existing `use_ai` permission from the hats system
- **Admin control:** Shop admin can disable AI features for all users via company settings

---

## 8. Implementation Phases

### Phase A: Native Bridge (Swift + Rust FFI)

**Goal:** Get Foundation Models accessible from TypeScript via Tauri IPC.

#### A1. Swift Bridge File

Create `src-tauri/swift/FoundationModelsBridge.swift`:
- `wp_llm_check_availability() -> Int32` — returns availability status code
- `wp_llm_submit_request(id, prompt, instructions, tools_json) -> Int32` — queue a request
- `wp_llm_poll_result(id) -> *mut c_char` — poll for completed result (JSON or null)
- `wp_llm_cancel_request(id)` — cancel pending request
- Internal: `LanguageModelSession`, request queue, result storage

#### A2. Rust FFI Module

Create `src-tauri/src/foundation_models.rs`:
- `extern "C"` declarations for the Swift functions
- `#[tauri::command]` wrappers: `llm_check_availability`, `llm_request`, `llm_poll_result`, `llm_cancel`
- `#[cfg(any(target_os = "macos", target_os = "ios"))]` guards (same as multipeer.rs)
- Non-Apple platforms return "unavailable" gracefully

#### A3. Build System

Update `src-tauri/build.rs`:
- Compile `swift/FoundationModelsBridge.swift` using `swiftc` via `Command` in build.rs
- Link `FoundationModels.framework` on iOS 26+ / macOS 26+
- Use weak linking for backward compatibility with iOS < 26

#### A4. Register Commands

Update `src-tauri/src/lib.rs`:
- Add `foundation_models` module
- Register commands in `generate_handler![]`

### Phase B: TypeScript Service Layer

**Goal:** Clean TypeScript API for the frontend to call the LLM.

#### B1. Foundation Models Service

Create `src/lib/foundation-models.ts`:
- `checkAvailability(): Promise<'available' | 'not_eligible' | 'not_enabled' | 'not_ready' | 'not_native'>`
- `generateCompletion(text, context, options): Promise<string>`
- `enhanceText(text, mode: 'proofread' | 'rewrite' | 'summarize' | 'expand' | 'professional'): Promise<string>`
- `generateWithTools(prompt, instructions, tools): Promise<string>`
- Internal polling loop with timeout
- Automatic session management (new session per request to avoid context window issues)

#### B2. React Hook

Create `src/hooks/useAITextField.ts`:
- `useAITextField(fieldId, options)` — returns `{ suggestion, isLoading, accept, dismiss, enhance }`
- Handles debouncing (800ms), cancellation, ghost text state
- Context-aware: accepts `fieldContext` prop with relevant data (job info, part info, etc.)
- Graceful fallback: returns no-ops when AI is unavailable

### Phase C: UI Components

**Goal:** Reusable AI-enhanced text components.

#### C1. AiTextarea Component

Create `src/components/ui/AiTextarea.tsx`:
- Wraps standard `<textarea>` with AI overlay
- Shows ghost text completion
- "Enhance" button (conditional on AI availability)
- Tab-to-accept, Esc-to-dismiss
- Falls back to plain textarea when AI unavailable

#### C2. AiSuggestionPopover

Create `src/components/ui/AiSuggestionPopover.tsx`:
- Floating popover for enhance options
- Proofread, Rewrite, Summarize, Expand, Professional tone
- Shows loading state during generation
- Before/after preview for rewrites

#### C3. AiPreFill Component

Create `src/components/ui/AiPreFill.tsx`:
- Shows contextual draft suggestion above/below a textarea
- "Use this draft" button to populate the field
- "Dismiss" to hide

### Phase D: Integration Across Features

**Goal:** Replace standard textareas with AiTextarea in Tier 1 fields.

This is a **mechanical replacement** — swap `<textarea>` for `<AiTextarea>` with appropriate context props. No business logic changes.

#### D1. Chat (3 fields)
- ChatMessageComposer: message input
- QAQuestionForm: question body
- QABoardPage: answer text

#### D2. Jobs (5 fields)
- ActiveJobsPage: job notes
- EditJobModal: job notes
- ClockOutFlow: questionnaire answers (2), end-of-day notes

#### D3. Scheduling (8 fields)
- DailyDispatchPage: dispatch notes
- SubSchedulePage: scope of work, additional notes (x2 for create + edit)
- TimeOffPage: reason, additional notes, adjustment reason

#### D4. Notebooks (8 fields)
- CreateEntryModal: entry body
- NoteEntryCard: note body
- TaskEntryCard: task notes
- InfoFieldRenderer: long text fields
- TaskStageSelector: parts needed notes

#### D5. Orders (5 fields)
- UnifiedOrderPage: order notes
- ConversationThread: conversation notes
- SendEmailModal: email body
- NewReturnPage: return notes

#### D6. People (8 fields)
- EmployeeDetailPage: employee notes
- CustomersPage: customer notes
- CustomerDetailPage: customer notes, contact notes
- ContractorsPage: contractor notes
- ContractorDetailPage: contractor notes, contact notes

#### D7. Parts & Warehouse (10 fields)
- PartDetailPanel: part notes
- CreateForm: description
- EditCategoryPanel: category description
- RuleFormModal: companion rule description
- LinkAlternativeModal: alternative reason
- StepNotesReason: movement notes
- AddStockModal: stock notes
- AuditCard: discrepancy notes
- ReceivingPage: delivery notes

#### D8. Fleet (5 fields)
- OverviewTab: vehicle notes
- CreateTrailerModal: trailer notes
- TrailerDetailPage: trailer notes
- MaintenanceTab: service description

#### D9. Office & Settings (6+ fields)
- ApprovalsTab: approval comments
- WarehouseLocationsPage: access notes
- JobNotebookTemplatePage: template description
- PDFSettingsPage: dynamic section text
- SupplierPortalPage: order notes
- ReportAnnotations: annotation text

### Phase E: Custom Tools Integration

**Goal:** Wire up the 4 custom tools so the model can query local data.

#### E1. SQLite Read-Only Access from Swift

The Swift bridge opens the same SQLite database file used by the TS data layer:
- Read-only connection (WAL mode compatible)
- Used only by Tool implementations
- No writes — the model can only read data

#### E2. Tool Registration Per Context

Different field contexts get different tool subsets:
- **Parts context:** SearchParts, GetSupplierInfo
- **Job context:** GetJobInfo, SearchContacts, SearchParts
- **Scheduling context:** SearchContacts, GetJobInfo
- **General:** SearchContacts, GetJobInfo

This keeps tool definitions small (saves context window tokens).

### Phase F: Settings & Controls

#### F1. Settings Page

Update `src/features/settings/pages/AiConfigPage.tsx`:
- Add "Apple Intelligence" section (separate from LM Studio section)
- Toggle: "Enable AI text suggestions" (global)
- Toggle: "Show inline completions"
- Toggle: "Enable Enhance button"
- Status indicator: shows model availability
- Device compatibility notice

#### F2. Per-Field Controls

- Long-press on any AiTextarea shows "Turn off AI for this field"
- Preference stored in localStorage per field ID
- Can be re-enabled from Settings

---

## 9. Pros and Cons Analysis

### 9.1 Pros

| Pro | Impact |
|-----|--------|
| **Completely on-device** | Zero privacy risk, no cloud dependency, works offline |
| **Free** | No API costs, no tokens to purchase, no LM Studio server to run |
| **Fast** | Neural Engine acceleration, ~1-3 second generation |
| **Apple-native UX** | Consistent with iOS/macOS patterns, feels natural |
| **Tool calling** | Can query local DB for real data, reducing hallucination |
| **Guided generation** | Can return structured data (parsed addresses, categorized items) |
| **Writing Tools built-in** | System-level proofread/rewrite for free on native text views |
| **Safety guardrails** | Apple's built-in content filtering, can't be circumvented |
| **Progressive enhancement** | App works identically without it — no degraded experience |

### 9.2 Cons

| Con | Mitigation |
|-----|-----------|
| **iOS 26+ only** | Wrap everything in availability checks; graceful fallback |
| **4096 token limit** | Keep prompts short; use tools sparingly; fresh session per request |
| **Not available on all devices** | Feature detection + fallback; never require AI for any workflow |
| **Model quality unknown** | Apple's model may not be as capable as GPT-4 / Claude for trade domain |
| **WebView complicates Writing Tools** | Writing Tools works on native UITextView/UITextField but not WKWebView content; we must build our own UI |
| **Latency** | 1-3 seconds per generation; use debouncing + loading indicators |
| **No streaming in initial API** | Can't show token-by-token streaming; must wait for full response |
| **Build complexity** | Must compile Swift from build.rs; adds to build chain |
| **Testing** | Can only test on real Apple Intelligence devices (no simulator support likely) |
| **Single session per request** | Can't have concurrent generations; queue requests |

### 9.3 Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| iOS 26 not available until fall 2026 | Certain | Medium | Plan for it; implement when SDK is available |
| Model quality insufficient for trade domain | Medium | Low | Custom adapter training available; Tool calling compensates |
| Users find suggestions annoying | Low | Medium | Default to subtle; easy to disable per-field or globally |
| Performance impact on older eligible devices | Medium | Low | Debounce aggressively; cancel on navigation |
| Build system complexity | Low | Medium | Follow proven Multipeer pattern exactly |

---

## 10. Testing Strategy

### 10.1 Unit Tests

- TypeScript service: mock Tauri invoke, test polling logic, timeout handling
- React hook: test debouncing, acceptance, dismissal, availability gating
- UI components: render tests for all states (loading, suggestion, error, unavailable)

### 10.2 Integration Tests

- Swift bridge: test on real device with Apple Intelligence enabled
- Tool calling: verify SQLite queries return correct data
- End-to-end: type in a field → see suggestion → accept → verify field value

### 10.3 Fallback Tests

- Test on device without Apple Intelligence → no AI UI shown
- Test on browser → no AI UI shown
- Test with AI disabled in settings → no AI UI shown
- Test with `use_ai` permission revoked → no AI UI shown

---

## 11. Dependencies & Prerequisites

| Dependency | Status | Notes |
|-----------|--------|-------|
| iOS 26 SDK (Xcode 17) | Not yet released | Expected WWDC 2025 announcement, fall 2025/2026 release |
| macOS 26 SDK | Not yet released | Same timeline |
| Apple Intelligence device | Required for testing | iPhone 15 Pro+, M1+ iPad/Mac |
| Tauri 2.0 migration | ✅ Complete | Already done (see tauri-migration-plan.md) |
| Swift compilation from build.rs | New requirement | Follow swift-rs pattern |
| `@_cdecl` Swift support | Available | Used by swift-rs internally |

---

## 12. Estimated Scope

| Phase | Files Created | Files Modified | Complexity |
|-------|--------------|----------------|-----------|
| A. Native Bridge | 2 (Swift + Rust) | 2 (build.rs, lib.rs) | High |
| B. TS Service | 2 (service + hook) | 0 | Medium |
| C. UI Components | 3 (AiTextarea, Popover, PreFill) | 0 | Medium |
| D. Integration | 0 | ~45 feature files | Low (mechanical) |
| E. Tools | 1 (tool definitions in Swift) | 1 (Swift bridge) | Medium |
| F. Settings | 0 | 1 (AiConfigPage.tsx) | Low |
| **Total** | **8 new files** | **~49 modified files** | |

---

## 13. Open Questions

1. **When will iOS 26 SDK be available?** — Implementation depends on this. Plan now, implement when SDK drops.
2. **Can `swiftc` be called from build.rs reliably?** — Need to prototype the Swift compilation step.
3. **Does the Foundation Models simulator support work?** — May need real device for all testing.
4. **Should we train a custom adapter for electrical trade terminology?** — Requires the `com.apple.developer.foundation-model-adapter` entitlement and Apple approval.
5. **How does WKWebView interact with Writing Tools?** — Need to investigate if Tauri's WKWebView gets system Writing Tools integration for free, or if it needs explicit support.

---

## 14. Implementation Order

```
1. Phase A: Native Bridge (Swift + Rust FFI)
   ├── A1. Write Swift bridge file
   ├── A2. Write Rust FFI module
   ├── A3. Update build system
   └── A4. Register commands + test on device

2. Phase B: TypeScript Service Layer
   ├── B1. Foundation Models service
   └── B2. useAITextField hook

3. Phase C: UI Components
   ├── C1. AiTextarea component
   ├── C2. AiSuggestionPopover
   └── C3. AiPreFill component

4. Phase D: Feature Integration (largest phase — ~45 files)
   ├── D1-D9: Replace textareas with AiTextarea
   └── (Can be done incrementally, feature by feature)

5. Phase E: Custom Tools
   ├── E1. SQLite read-only access
   └── E2. Tool registration per context

6. Phase F: Settings & Controls
   ├── F1. Update AiConfigPage
   └── F2. Per-field controls
```

---

## 15. Related Documents

- `docs/plans/phase-14-ai-integration.md` — LM Studio / local LLM integration plan
- `docs/plans/tauri-migration-plan.md` — Tauri 2.0 migration (complete)
- `docs/plans/frontend-to-root-restructure.md` — Cross-platform alignment (complete)
- `src/components/AiAssistantPanel.tsx` — Existing AI panel (LM Studio-backed)
- `src-tauri/src/multipeer.rs` — Multipeer bridge (pattern to follow)
- `src-tauri/objc/MultipeerBridge.m` — ObjC FFI bridge (pattern to follow)
