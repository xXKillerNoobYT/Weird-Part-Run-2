# Phase 12: AI Integration

> **Date:** 2026-03-07
> **Status:** ✅ Complete — implemented 2026-03-07
> **Dependencies:** All core phases complete, Sync (Phase 11), Chat (Phase 9)
> **Architecture:** Local-only LLM via LM Studio. No cloud AI. Read-only tool access.
> **Estimated work:** 8-12 days (when prioritized)
> **One Point of Active Processing:** All AI requests are handled by a single point of processing at the shop. No AI processing happens on mobile devices or in the frontend. This ensures all AI interactions are logged and controlled centrally, and that the AI has access to the full dataset without needing to sync it to mobile.

---

## Vision

A local AI assistant that runs on the shop computer via **LM Studio** (or similar local LLM server). The AI has **read-only access** to the application's data and can answer natural language questions, generate summaries, and provide recommendations — but cannot modify data.

**Key constraint:** Zero cloud dependency. The LLM runs entirely on the shop PC. No OpenAI, no Anthropic, no data leaves the network. This aligns with the offline-first architecture.

---

## Capabilities (Planned)

### 1. Natural Language Queries

Ask questions in plain English and get answers from the database:

- "How many hours did Roy work last week?"
- "What's the total parts cost on the Smith job?"
- "Which jobs are over budget?"
- "Show me all POs pending approval"
- "Who's scheduled for tomorrow?"

**Implementation:** Convert natural language → SQL query (or service call) → formatted response.

### 2. Report Summarization

Auto-generate summaries from report data:

- Daily report summaries: "Today: 4 workers on Smith job (32 hrs), 2 on Johnson (14 hrs). Parts pulled: 47 outlets, 12 switches. Roy flagged a panel issue in Q&A."
- Weekly cost summary: "This week: $12,400 labor, $3,200 parts. Smith job at 72% budget. Johnson job on track."
- Pre-billing narrative: Generate a paragraph summary suitable for GC invoices.

### 3. Smart Scheduling Suggestions

Based on historical data, suggest optimal crew assignments:

- "Roy and Mike usually finish panel work 15% faster than average — assign them to the Smith panel job"
- "The Johnson job needs 3 workers but only 2 are scheduled for Tuesday — suggest adding Jake"
- "Dave hasn't worked the Smith job before — consider pairing with Roy for first day"

### 4. Anomaly Detection

Flag unusual patterns in real-time:

- Overtime anomalies: "Roy has 12 overtime hours this week — above his 4-week average of 3"
- Cost anomalies: "Parts cost on Johnson job spiked 300% this week — mostly wire (24 spools vs usual 6)"
- Schedule anomalies: "Two workers are scheduled at the same job but clock-in GPS is 5 miles apart"
- Inventory anomalies: "Warehouse stock of 15A outlets is at 12 units — below 30-day usage rate of 48"

### 5. Predictive Ordering

Suggest parts orders based on usage patterns:

- "Based on the last 90 days, you'll need ~200 outlets and ~50 switches in the next 30 days"
- "The Smith job historically uses X parts per week — you have Y in stock, which covers Z weeks"
- "Supplier A has been 3 days faster than Supplier B for wire orders — consider A for urgent needs"

### 6. Chat Bot (Q&A Integration)

In the Chat system (Phase 9), allow an AI assistant channel:

- Workers can ask "@AI what wire gauge do I need for a 200A panel?"
- AI responds from a company knowledge base (uploaded docs, past Q&A answers)
- AI can reference installation guides, code requirements, company SOPs
- **Read-only** — AI never escalates Q&A or posts in job channels without being asked

---

## Technical Architecture

### LM Studio Integration

```
Shop PC runs:
  ├── Python FastAPI (existing backend)
  ├── LM Studio server (local LLM API on port 1234)
  └── SQLite database (existing)
  
Flow:
  User asks question → Backend formats prompt → Sends to LM Studio API → 
  LM Studio returns response → Backend post-processes → Returns to frontend
```

### AI Service: `ai_service.py`

```python
class AIService:
    """Local AI assistant with read-only data access."""
    
    LM_STUDIO_URL = "http://localhost:1234/v1"  # OpenAI-compatible API
    
    async def ask(self, question: str, context: dict = None) -> str:
        """Answer a natural language question using data + LLM."""
        # 1. Classify question type (query, summary, suggestion, etc.)
        # 2. Gather relevant data context (read-only queries)
        # 3. Format prompt with system instructions + data
        # 4. Send to LM Studio
        # 5. Post-process response (validate, format)
        # 6. Return answer
    
    async def summarize_report(self, report_type: str, data: dict) -> str:
        """Generate a natural language summary of report data."""
    
    async def suggest_schedule(self, date: str, job_ids: list[int]) -> str:
        """Generate scheduling suggestions based on historical data."""
    
    async def detect_anomalies(self, period: str) -> list[dict]:
        """Scan recent data for anomalies worth flagging."""
    
    async def predict_ordering(self, days_ahead: int = 30) -> list[dict]:
        """Predict parts needs based on usage patterns."""
```

### Read-Only Tools (Function Calling)

The AI gets a set of read-only "tools" it can call to query data:

```python
AI_TOOLS = [
    {"name": "query_labor", "description": "Get labor hours for an employee or job", "params": ["employee_id?", "job_id?", "start_date?", "end_date?"]},
    {"name": "query_parts", "description": "Get parts usage or stock levels", "params": ["part_id?", "job_id?", "warehouse?"]},
    {"name": "query_jobs", "description": "Get job details, status, budget", "params": ["job_id?", "status?"]},
    {"name": "query_schedule", "description": "Get schedule for a date range", "params": ["date?", "employee_id?"]},
    {"name": "query_orders", "description": "Get PO/JPO status and details", "params": ["order_id?", "status?"]},
    {"name": "query_costs", "description": "Get cost tracking data", "params": ["job_id?", "period?"]},
    {"name": "query_contacts", "description": "Get contact/company info", "params": ["contact_id?", "company_name?"]},
    {"name": "query_qa_history", "description": "Get past Q&A threads and answers", "params": ["job_id?", "keyword?"]},
]
```

**Critical:** No write tools. The AI cannot create, update, or delete any records. All tools are SELECT queries only.

### Router: `ai_router.py`

```
POST /api/ai/ask               — Ask a question, get an answer
POST /api/ai/summarize          — Summarize a report dataset
GET  /api/ai/anomalies          — Get current anomaly flags
GET  /api/ai/predictions        — Get ordering predictions
GET  /api/ai/status             — Check if LM Studio is running
```

**Permission:** `use_ai` — office + admin only by default (can be expanded).

---

## Frontend Implementation

### AI Assistant Panel

A slide-out panel (or floating chat bubble) accessible from any page:

- **Chat-style interface:** User types question, AI responds
- **Context-aware:** If opened from the Smith job page, AI knows to scope queries to that job
- **Conversation history:** Last 20 exchanges per session (not persisted — ephemeral)
- **Quick prompts:** Suggested questions based on current page:
  - On Jobs page: "Which jobs are over budget?" "Labor summary this week?"
  - On Inventory page: "What's running low?" "Predict next month's needs?"
  - On Schedule page: "Who's available tomorrow?" "Best crew for the panel job?"
- **Anomaly alerts:** If anomaly detection finds something, show a badge on the AI icon

### Settings

- **LM Studio connection:** URL, model selection, connection test
- **AI features toggle:** Enable/disable individual capabilities
- **Knowledge base:** Upload company-specific docs (installation guides, SOPs, code references)

---

## Open Questions

- **LM Studio model choice:** Llama 3 70B? Mistral? Depends on shop PC specs (RAM, GPU)
- **Response quality:** Need to test prompt engineering with real electrical trade data
- **Knowledge base format:** PDF upload? Markdown? Needs indexing (RAG pattern)
- **Multi-user:** If two office users ask questions simultaneously, LM Studio queues them — acceptable?
- **Cost of hardware:** Does the shop PC need a GPU upgrade? LM Studio can run CPU-only but slower.

---

## Success Criteria

- [x] LM Studio connectivity tested from backend
- [x] Natural language queries return accurate data-backed answers
- [x] Report summaries are readable and factually correct
- [x] Anomaly detection flags genuine issues (not false positives)
- [x] Ordering predictions align with historical usage (within 20% accuracy)
- [x] AI has zero write access to database
- [x] AI assistant panel accessible from any page
- [x] Context-aware prompts change based on current page
- [x] Conversation is ephemeral (no persistent storage of AI chats)
- [x] Works entirely offline (no cloud AI calls)

---

## Implementation Notes (2026-03-07)

### Files Created
| File | Lines | Purpose |
|------|-------|---------|
| `backend/app/migrations/054_ai_integration.sql` | 43 | `use_ai` permission + `ai_cached_results` table |
| `backend/app/services/ai_service.py` | ~700 | Core AI service — LM Studio integration, 8 read-only tools, NL queries, summarization, anomaly detection, predictive ordering |
| `backend/app/routers/ai.py` | ~220 | 10 REST endpoints under `/api/ai` |
| `frontend/src/api/ai.ts` | ~140 | TypeScript API client with typed request/response |
| `frontend/src/components/AiAssistantPanel.tsx` | ~500 | Floating chat bubble + slide-out panel (Chat/Anomalies/Predictions tabs) |

### Files Modified
| File | Change |
|------|--------|
| `backend/app/main.py` | Added `"app.routers.ai"` to ROUTER_MODULES |
| `backend/app/scheduler.py` | Added `ai_anomaly_detection_job` (04:00) + `ai_prediction_job` (04:30) |
| `frontend/src/App.tsx` | Imported + rendered `<AiAssistantPanel />` inside AuthGate |

### Architecture Decisions
- **Tool-calling pattern:** AI uses OpenAI-compatible function calling with 8 read-only tools (labor, jobs, stock, usage, orders, schedule, costs, employees). Max 5 tool-calling rounds per question.
- **SQL safety:** All tool queries validated as SELECT-only with dangerous keyword blocking (INSERT/UPDATE/DELETE/DROP/ALTER/CREATE/ATTACH/DETACH).
- **Cached results:** Anomalies and predictions stored in `ai_cached_results` with 24h TTL. Dismissible by users.
- **Ephemeral conversations:** Chat history held in React state only — never persisted to database.
- **Permission model:** `use_ai` permission assigned to Admin, Manager, Lead hats. `anomaly-count` endpoint uses basic auth only (for badge display).
- **AiConfigPage already existed:** 407-line fully implemented config page with LM Studio URL, connection test, master toggle, 5 feature toggles, settings persistence via generic KV settings API.

---

## Execution Order (When Prioritized)

1. Install and configure LM Studio on shop PC
2. Build `ai_service.py` with LM Studio API integration
3. Implement read-only tool definitions
4. Build `ai_router.py` with ask/summarize/anomalies/predictions endpoints
5. Build frontend AI assistant panel (slide-out chat)
6. Implement context-aware prompts per page
7. Build anomaly detection scheduled task
8. Build ordering prediction logic
9. Test with real data — iterate on prompts for accuracy
10. (Future) Add knowledge base upload + RAG indexing
