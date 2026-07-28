# AI Assistant Plan

> **Created:** 2026-03-08
> **Status:** Native iOS implementation active; legacy LM Studio sections below are retained as historical context
> **Depends on:** Phase 14 — AI Integration (`docs/plans/phase-14-ai-integration.md`)
> **Scope:** Local LLM-powered assistant for natural language queries, anomaly detection, and predictive ordering.

---

## Overview

### Native iOS help handoff and conversation resume (WEI-4986 / GitHub #1459)

The active app uses Apple Foundation Models and the local `AppDatabase`; the older LM Studio architecture below is retired. The approved native interaction contract is:

1. Every `PageHelpSheet` exposes a 44-point “Ask AI about this page” action with an explicit accessibility label.
2. Tapping it dismisses Help and posts a read-only payload containing the visible title, visible help body, suggested prompt, and canonical registry page ID when the title is known. The shell presents the assistant and forwards that payload only after the assistant is mounted.
3. The assistant immediately seeds a local user/assistant turn from that payload. This must not call a model or require network availability; canonical registry content is preferred, with the visible help body as the fallback.
4. On first presentation, the assistant adopts `FoundationModelsService.latestConversationId` when local history exists. A labeled Resume control presents `FoundationModelsService.listConversations`, with loading and empty states; a nil database or read failure safely produces an empty list.
5. Existing New, Clear, and Report a Bug controls remain intact in both sheet and overlay modes. Help-seeded turns are persisted best-effort so normal resume behavior can restore them.

### PR #1460 revision gate

Review and user-like QA found five requirements that must be satisfied before this slice can merge:

1. Help delivery is readiness-driven, not timer-driven: the shell owns a pending payload and the assistant consumes it only after initial history loading completes.
2. Help persistence and Clear are serialized so Clear cannot report success before an in-flight local Help turn finishes writing. A new Help handoff received during Clear remains queued and is consumed as soon as Clear finishes, whether deletion succeeds or reports a retryable failure.
3. Assistant messages and saved-conversation previews render supported Markdown rather than exposing formatting markers.
4. Resume controls provide a minimum 44×44-point hit target in sheet and overlay modes.
5. Persisted conversations are scoped to the authenticated user and a resumed transcript hydrates the next Foundation Models request. The durable persistence/session contract is owned by BackendCoder in WEI-5008; the frontend must fail closed until that contract is integrated.
6. Help dismissal drives assistant presentation through `PageHelpSheet.onDisappear`; no fixed delay guesses when sheet dismissal completed.
7. The actor persists and stages locally seeded Help turns before follow-up input uses the model. Markdown rendering parses each normalized message as one complete document (never pre-splitting or trimming fenced/list/code content), then restores explicit presentation-block boundaries in visible and accessibility text.
8. Clear is unavailable while a response is pending and synchronously advances a UI conversation revision before awaiting Help staging or persistent deletion. Send captures that revision and checks it both before model generation and before appending a response, so a programmatic or stale Clear cannot recreate visible or persisted history after reporting success.
9. Conversation hydration owns a visible loading state that disables both the composer and Send control. Resume starts that state synchronously, and only the matching owner/conversation/revision load may clear it, so an immediate prompt cannot create an empty model session or be overwritten by delayed persisted rows.
10. Model generation owns an actor lifecycle revision through completion. Resume, Help staging, Clear, New/logout, or switching the active model session invalidates an older generation before it can append turns to the newly staged transcript, so Conversation A cannot contaminate Conversation B's next model context. A Help handoff also advances the UI conversation revision before clearing an active processing state, preventing the older send task from appending into the newly seeded Help turn.
11. Automatic resume is attempted only after both the local database and a positive authenticated user ID are available. The assistant's initialization task is keyed by those prerequisites so a panel mounted during startup or login retries when they become ready rather than permanently skipping resume.
12. Every Help handoff carries a dedicated UUID request ID. The mounted assistant observes only that constant-size identity token; it must not rebuild an observation token from the complete visible Help body during SwiftUI updates.

Verification requires focused source-regression tests for notification wiring, help/title lookup, accessible controls, resume hooks, local-only seeding, and preservation of assistant bug-report context, followed by an iOS build and user-like iPhone/iPad verification.

The AI Assistant is a locally-hosted intelligence layer that augments the WiredPart ERP with natural language understanding and data-driven insights. It runs entirely on-premise via **LM Studio** — no cloud dependency, no data leaving the shop network.

**Core principle:** The assistant is **read-only** for all automated operations. It can query data and surface recommendations, but every write action requires explicit user confirmation.

### Current native persistence and resume contract (WEI-5008 / GitHub #1459)

The active iOS implementation uses Apple Foundation Models and local SQLite rather than the retired LM Studio/backend design below. Persisted assistant turns follow these rules:

- Every message row has an `owner_user_id`. New reads, writes, previews, latest-conversation lookup, deletes, and clears require a positive authenticated user ID and filter by that owner.
- Legacy rows created before ownership existed remain unowned and invisible. The migration does not guess an owner or expose old history to the first user who signs in.
- Resuming a conversation hydrates both the displayed rows and the Foundation Models `Transcript`; follow-up requests therefore receive the prior user/assistant turns.
- Model-response persistence is awaited. An actor-owned conversation revision invalidates a response that finishes after clear/delete began, preventing a delayed write from recreating cleared history.
- The UI consumer must pass `appCore.currentUser.id`, await clear/delete, and call the service resume API before sending a follow-up in a restored thread.
- Message timestamps remain the primary chronological key, but persisted turns also carry a monotonic `recency_order`. Reads use that value as the secondary key whenever second-resolution timestamps tie. Migration 114 backfills existing rows from SQLite insertion order, while rollback/legacy writers may continue omitting the nullable column; readers deterministically fall back to `rowid` for NULL or zero compatibility rows. This makes transcript order, latest-conversation resume, saved-conversation order, and previews reflect actual save order without weakening authenticated-owner filtering (WEI-5122 / GitHub #1464).

---

## Capabilities

### 1. Natural Language Queries

Users can ask questions in plain English instead of navigating to specific pages:

- *"How many 3/4 inch fittings do we have in stock?"*
- *"What jobs used the most material last month?"*
- *"Which employees worked overtime this week?"*
- *"Show me all POs pending approval."*
- *"What parts are below minimum stock?"*

**How it works:**
1. User types a question in the AI chat panel
2. LLM parses intent → maps to known query patterns
3. System executes the appropriate API call(s) with extracted parameters
4. LLM formats the response in natural language with links to relevant pages

**Query domains:**
- Inventory (stock levels, part lookup, audit status)
- Jobs (status, labor hours, cost summaries)
- Orders (PO status, pending approvals, delivery ETAs)
- People (who's clocked in, schedule for today, certifications expiring)
- Fleet (vehicle assignments, maintenance due, mileage tracking)
- Reports (daily summaries, billing cycles, profitability)

### 2. Anomaly Detection

Passive monitoring that flags unusual patterns:

| Anomaly Type | Example | Alert Level |
|-------------|---------|-------------|
| Unusual consumption | Part X used 3× normal rate on Job Y | ⚠️ Warning |
| Cost spike | Job Z material cost jumped 40% week-over-week | 🔴 Critical |
| Clock anomaly | Employee A clocked 14 hours without break | ⚠️ Warning |
| Stock discrepancy | Audit count differs >20% from system count | 🔴 Critical |
| Drive time outlier | Drive time is 60% of labor hours on a report | ⚠️ Warning |
| Scheduling conflict | Two jobs need the same specialist on the same day | ⚠️ Warning |

**How it works:**
1. Scheduled background analysis runs daily (via APScheduler)
2. LLM reviews aggregated metrics against historical baselines
3. Anomalies surface as notifications in the app
4. Each anomaly links to the relevant page with context

### 3. Predictive Ordering

Smart suggestions for procurement based on usage patterns:

- **Reorder predictions:** "Based on usage trends, you'll need to order Part X within 2 weeks"
- **Seasonal patterns:** "Last year you used 3× more insulation in Q4 — consider pre-ordering"
- **Job-based forecasting:** "Job Y's bill of materials suggests you'll need 50 units of Part Z"
- **Supplier lead time awareness:** "Supplier A typically takes 7 days — order by Friday to have stock for Monday's job"

**How it works:**
1. Analyzes historical order data + consumption rates + supplier lead times
2. Cross-references with active job BOMs and upcoming schedule
3. Generates a weekly "Suggested Orders" list
4. User reviews and can one-click convert suggestions into JPOs

---

## Architecture

### LM Studio Integration

```
┌──────────────┐     HTTP/REST      ┌──────────────┐
│  WiredPart   │ ←─────────────────→ │  LM Studio   │
│  Backend     │   localhost:1234    │  (Local LLM)  │
│  (Python)    │                    │  7B-13B model  │
└──────────────┘                    └──────────────┘
```

- **Model size:** 7B–13B parameter models (runs on consumer hardware with 8–16GB VRAM)
- **Recommended models:** Mistral 7B, Llama 3, Phi-3, or similar instruction-tuned models
- **Connection:** HTTP REST API on `localhost:1234` (configurable)
- **Latency target:** <3s for query responses, <30s for anomaly analysis

### Data Flow (Read-Only)

1. All AI queries go through the existing API layer — no direct DB access
2. Rate limiting prevents runaway queries (max 10 requests/minute to LLM)
3. Context window management: only send relevant data, never full DB dumps
4. Prompt templates stored in `execution/ai_prompts/` for version control

### AiConfigPage (v1.0 Scope)

The configuration page (`/settings/ai-config`) provides:

1. **LM Studio Connection**
   - Endpoint URL (default: `http://localhost:1234/v1`)
   - Model selection (dropdown populated from LM Studio's model list)
   - Connection test button
   - Status indicator (connected/disconnected/error)

2. **Feature Toggles**
   - Natural Language Queries: on/off
   - Anomaly Detection: on/off
   - Predictive Ordering: on/off
   - Each toggle independently enables/disables the feature

3. **Analysis Schedule**
   - Anomaly detection frequency (hourly/daily/weekly)
   - Predictive ordering refresh (daily/weekly)

4. **About / Planned Features**
   - Description of each capability
   - Current status (enabled/disabled/coming soon)
   - Link to documentation

---

## Implementation Phases

### Phase A: Foundation (v2.0)
- [ ] LM Studio service (`execution/ai_service.py`)
- [ ] Connection management + health check
- [ ] Prompt template system
- [ ] AiConfigPage with real settings (already has UI shell)
- [ ] Backend router: `POST /api/ai/query`, `GET /api/ai/status`

### Phase B: Natural Language Queries (v2.0)
- [ ] Intent classification (map NL → API calls)
- [ ] Query execution pipeline
- [ ] Response formatting
- [ ] Chat UI panel (slide-out or dedicated page)
- [ ] Query history

### Phase C: Anomaly Detection (v2.1)
- [ ] Baseline metrics computation
- [ ] Daily analysis scheduler job
- [ ] Anomaly → notification pipeline
- [ ] Dashboard card showing recent anomalies

### Phase D: Predictive Ordering (v2.2)
- [ ] Usage trend analysis
- [ ] Supplier lead time integration
- [ ] Weekly suggestion generation
- [ ] "Suggested Orders" page with approve/dismiss actions

---

## Security & Privacy

- **No cloud dependency.** All AI processing happens on the local network.
- **No data exfiltration.** The LLM runs locally — queries never leave the shop.
- **Read-only access.** The AI can only query existing endpoints; it cannot create, update, or delete any records.
- **Audit trail.** All AI queries are logged with timestamps and user context.
- **Model updates.** Users download models manually via LM Studio — no auto-update mechanism.

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU VRAM | 6 GB (7B model, Q4) | 12+ GB (13B model, Q5) |
| System RAM | 16 GB | 32 GB |
| Storage | 10 GB (one model) | 30 GB (multiple models) |
| OS | Windows 10/11, macOS 12+ | Same |

**Note:** The AI assistant is entirely optional. WiredPart functions fully without it. The AI features are additive quality-of-life improvements.

---

## References

- Phase 14 detailed plan: `docs/plans/phase-14-ai-integration.md`
- AiConfigPage implementation: `frontend/src/features/settings/pages/AiConfigPage.tsx`
- LM Studio: https://lmstudio.ai/
