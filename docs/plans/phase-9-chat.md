# Phase 9: Chat & Q&A System

> **Date:** 2026-03-07
> **Status:** 📋 Planned
> **Concept doc:** `docs/plans/Q&A Part of the App` (307 lines — escalation chain design, decision fork, RFI bridge)
> **Dependencies:** People/Contacts (Phase 7 ✅), Jobs (Phase 4 ✅), Sync (Phase 11 — chat must work offline-first)
> **Estimated work:** 10-14 days
> **Architecture:** Offline-first. Messages stored locally, synced to shop via LAN. No cloud push — uses local polling + BT mesh gossip.

---

## Vision

A unified messaging system with two distinct capabilities:

1. **Job Chat** — per-job group messaging for crews. Quick updates, photos, voice messages, @mentions.
2. **Q&A Escalation** — structured question pipeline that flows up the chain of command with audit trail and optional GC integration.

Both share the same underlying message infrastructure but serve different purposes. Chat is informal and fast. Q&A is formal and tracked.

---

## Core Architecture

### Concept: The Escalation Chain

From the concept doc, the Q&A system uses a single pipeline with defined escalation levels:

```
Worker → Lead → Foreman → Supervisor → Office/Shop
```

At each level, the person can:
- **Answer** → response flows back down the chain to the asker
- **Escalate** → question moves up to the next level
- **Comment** → add context without answering or escalating

When the question reaches the **Office/Shop**, there's a decision fork:
- **Internal answer** → answer flows back down
- **Send to GC** → creates an RFI (Request for Information) object

### Concept: The RFI Bridge (Future — Phase 13 prerequisite)

If the GC is on the same system:
- Shop packages RFI → sends to GC's shop (shop↔shop only, never device↔device)
- GC's shop injects RFI into their internal Q&A chain
- GC's chain: GC Worker → GC Lead → GC Supervisor → GC Owner
- Answer flows back: GC Shop → Your Shop → original Q&A thread

**V1.0 scope:** Internal Q&A chain only. RFI bridge is a placeholder for Phase 13 (Remote Sync).
For V1.0, "Send to GC" opens the phone's native SMS/email compose screen with a pre-formatted message.

---

## Database Schema

### Migration: `029_chat_system.sql`

```sql
-- ═══════════════════════════════════════════════════
-- Chat Channels — one per job (auto-created), plus DMs
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_channels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_type TEXT NOT NULL CHECK(channel_type IN ('job', 'dm', 'general')),
    job_id INTEGER REFERENCES jobs(id),           -- non-null for job channels
    name TEXT,                                      -- display name (null for DMs)
    created_by INTEGER REFERENCES users(id),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(channel_type, job_id)                   -- one channel per job
);

-- Channel membership (who can see what)
CREATE TABLE IF NOT EXISTS chat_channel_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id INTEGER NOT NULL REFERENCES chat_channels(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id),
    role TEXT DEFAULT 'member' CHECK(role IN ('member', 'admin')),
    muted_until TEXT,                              -- null = not muted
    joined_at TEXT DEFAULT (datetime('now')),
    UNIQUE(channel_id, user_id)
);

-- ═══════════════════════════════════════════════════
-- Messages — the core message table
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id INTEGER NOT NULL REFERENCES chat_channels(id) ON DELETE CASCADE,
    sender_id INTEGER NOT NULL REFERENCES users(id),
    message_type TEXT NOT NULL DEFAULT 'text' 
        CHECK(message_type IN ('text', 'photo', 'voice', 'file', 'system', 'qa_question', 'qa_answer', 'qa_escalation')),
    content TEXT,                                   -- text content or caption
    media_path TEXT,                                -- local path to photo/voice/file
    media_mime_type TEXT,
    media_size_bytes INTEGER,
    reply_to_id INTEGER REFERENCES chat_messages(id), -- threading
    pinned_at TEXT,                                 -- null = not pinned
    pinned_by INTEGER REFERENCES users(id),
    edited_at TEXT,                                 -- null = never edited
    deleted_at TEXT,                                -- soft delete
    created_at TEXT DEFAULT (datetime('now')),
    
    -- Q&A specific fields (null for regular chat messages)
    qa_thread_id INTEGER REFERENCES qa_threads(id),
    qa_level TEXT CHECK(qa_level IN ('worker', 'lead', 'foreman', 'supervisor', 'office'))
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_channel ON chat_messages(channel_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_qa_thread ON chat_messages(qa_thread_id);

-- ═══════════════════════════════════════════════════
-- Read receipts — who has seen what
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_read_receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id INTEGER NOT NULL REFERENCES chat_channels(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id),
    last_read_message_id INTEGER REFERENCES chat_messages(id),
    read_at TEXT DEFAULT (datetime('now')),
    UNIQUE(channel_id, user_id)
);

-- ═══════════════════════════════════════════════════
-- @Mentions
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS chat_mentions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id INTEGER NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
    mentioned_user_id INTEGER NOT NULL REFERENCES users(id),
    acknowledged_at TEXT                            -- null = unacknowledged
);

CREATE INDEX IF NOT EXISTS idx_chat_mentions_user ON chat_mentions(mentioned_user_id, acknowledged_at);

-- ═══════════════════════════════════════════════════
-- Q&A Threads — structured escalation tracking
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS qa_threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id INTEGER NOT NULL REFERENCES chat_channels(id),
    job_id INTEGER REFERENCES jobs(id),
    asked_by INTEGER NOT NULL REFERENCES users(id),
    subject TEXT NOT NULL,                          -- short summary of the question
    current_level TEXT NOT NULL DEFAULT 'worker'
        CHECK(current_level IN ('worker', 'lead', 'foreman', 'supervisor', 'office')),
    assigned_to INTEGER REFERENCES users(id),      -- who currently has it
    status TEXT NOT NULL DEFAULT 'open'
        CHECK(status IN ('open', 'escalated', 'answered', 'sent_to_gc', 'closed')),
    priority TEXT DEFAULT 'normal'
        CHECK(priority IN ('low', 'normal', 'urgent')),
    answered_by INTEGER REFERENCES users(id),
    answered_at TEXT,
    closed_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_qa_threads_job ON qa_threads(job_id, status);
CREATE INDEX IF NOT EXISTS idx_qa_threads_assigned ON qa_threads(assigned_to, status);

-- ═══════════════════════════════════════════════════
-- RFI Objects — for GC communication (placeholder for Phase 13)
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS rfi_objects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    qa_thread_id INTEGER NOT NULL REFERENCES qa_threads(id),
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    gc_contact_id INTEGER REFERENCES contacts(id),
    subject TEXT NOT NULL,
    body TEXT NOT NULL,                             -- formatted question + context
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK(status IN ('draft', 'sent_text', 'sent_email', 'sent_app', 'answered', 'closed')),
    sent_via TEXT CHECK(sent_via IN ('sms', 'email', 'app')),
    sent_at TEXT,
    response_text TEXT,
    responded_at TEXT,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Change log integration for sync
CREATE TRIGGER IF NOT EXISTS trg_chat_messages_change
AFTER INSERT ON chat_messages
BEGIN
    INSERT INTO _change_log(table_name, row_id, operation, changed_at)
    VALUES('chat_messages', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_qa_threads_change
AFTER UPDATE ON qa_threads
BEGIN
    INSERT INTO _change_log(table_name, row_id, operation, changed_at)
    VALUES('qa_threads', NEW.id, 'UPDATE', datetime('now'));
END;
```

---

## Backend Implementation

### Repository: `chat_repo.py`

```python
class ChatRepo(BaseRepo):
    TABLE = "chat_messages"
    
    # Channel operations
    async def get_or_create_job_channel(self, job_id: int) -> dict
    async def create_dm_channel(self, user_ids: list[int]) -> dict
    async def get_user_channels(self, user_id: int) -> list[dict]
    async def get_channel_members(self, channel_id: int) -> list[dict]
    async def add_channel_member(self, channel_id: int, user_id: int, role: str = "member") -> dict
    async def remove_channel_member(self, channel_id: int, user_id: int) -> None
    
    # Message operations
    async def create_message(self, channel_id: int, sender_id: int, content: str, ...) -> dict
    async def get_messages(self, channel_id: int, before_id: int = None, limit: int = 50) -> list[dict]
    async def edit_message(self, message_id: int, content: str) -> dict
    async def delete_message(self, message_id: int) -> None  # soft delete
    async def pin_message(self, message_id: int, pinned_by: int) -> dict
    async def unpin_message(self, message_id: int) -> dict
    async def get_pinned_messages(self, channel_id: int) -> list[dict]
    
    # Read receipts
    async def mark_read(self, channel_id: int, user_id: int, message_id: int) -> None
    async def get_unread_counts(self, user_id: int) -> dict  # {channel_id: count}
    
    # Mentions
    async def create_mentions(self, message_id: int, user_ids: list[int]) -> None
    async def get_unread_mentions(self, user_id: int) -> list[dict]
    async def acknowledge_mention(self, mention_id: int) -> None
```

### Repository: `qa_repo.py`

```python
class QARepo(BaseRepo):
    TABLE = "qa_threads"
    
    async def create_thread(self, channel_id: int, job_id: int, asked_by: int, subject: str, ...) -> dict
    async def get_thread(self, thread_id: int) -> dict  # includes all messages
    async def escalate_thread(self, thread_id: int, escalated_by: int) -> dict
    async def answer_thread(self, thread_id: int, answered_by: int, answer: str) -> dict
    async def close_thread(self, thread_id: int) -> dict
    async def get_job_threads(self, job_id: int, status: str = None) -> list[dict]
    async def get_assigned_threads(self, user_id: int) -> list[dict]
    async def get_escalation_target(self, thread: dict) -> int | None  # determine next person in chain
    
    # RFI operations (V1.0: basic CRUD, actual sending uses native SMS/email)
    async def create_rfi(self, qa_thread_id: int, gc_contact_id: int, subject: str, body: str, created_by: int) -> dict
    async def update_rfi_status(self, rfi_id: int, status: str, response_text: str = None) -> dict
    async def get_job_rfis(self, job_id: int) -> list[dict]
```

### Service: `chat_service.py`

```python
class ChatService:
    """Orchestrates chat operations with business logic."""
    
    async def send_message(self, channel_id, sender_id, content, message_type, media_path, reply_to_id) -> dict:
        """Send a message, parse @mentions, create mention records."""
        # 1. Validate sender is channel member
        # 2. Create message record
        # 3. Parse @mentions from content (regex: @[username])
        # 4. Create mention records for each mentioned user
        # 5. Return message with sender info
    
    async def get_channel_with_messages(self, channel_id, user_id, before_id, limit) -> dict:
        """Get channel info + paginated messages + mark as read."""
        # 1. Verify user is member
        # 2. Fetch last N messages (infinite scroll pagination)
        # 3. Mark channel as read up to latest message
        # 4. Return channel + messages + member list + pinned messages
    
    async def get_inbox(self, user_id) -> dict:
        """Get all channels with unread counts, sorted by activity."""
        # 1. Fetch user's channels
        # 2. Get unread count per channel
        # 3. Get last message preview per channel
        # 4. Get unread @mention count
        # 5. Sort by most recent activity
```

### Service: `qa_service.py`

```python
class QAService:
    """Manages Q&A escalation chain logic."""
    
    ESCALATION_CHAIN = ['worker', 'lead', 'foreman', 'supervisor', 'office']
    
    async def ask_question(self, job_id, asked_by, subject, body) -> dict:
        """Create a Q&A thread and initial message."""
        # 1. Get or create job channel
        # 2. Determine starting level based on asker's role
        # 3. Create qa_thread record
        # 4. Create initial message (type=qa_question)
        # 5. Assign to the next person up the chain
        # 6. Return thread with assignments
    
    async def escalate(self, thread_id, escalated_by, comment=None) -> dict:
        """Move question up one level in the chain."""
        # 1. Validate escalator is currently assigned
        # 2. Determine next level
        # 3. Find the person at that level (job lead, foreman, etc.)
        # 4. Update thread (current_level, assigned_to, status=escalated)
        # 5. Create system message: "Escalated by {name} to {level}"
        # 6. If optional comment, create escalation message
        # 7. Return updated thread
    
    async def answer(self, thread_id, answered_by, answer_text) -> dict:
        """Answer a Q&A thread."""
        # 1. Validate answerer is assigned or has permission
        # 2. Create answer message (type=qa_answer)
        # 3. Update thread (status=answered, answered_by, answered_at)
        # 4. Create system message: "Answered by {name}"
        # 5. Return thread with answer
    
    async def send_to_gc(self, thread_id, sent_by, gc_contact_id, via='sms') -> dict:
        """Create RFI and prepare for external sending."""
        # V1.0: Create RFI record, return pre-formatted text for SMS/email
        # Future: Send via shop↔shop if GC is on same system
        # 1. Build RFI body from thread context
        # 2. Create rfi_objects record
        # 3. Return RFI with formatted text + GC contact info (phone/email)
    
    def _get_next_level(self, current_level: str) -> str | None:
        """Return the next escalation level, or None if at top."""
        idx = self.ESCALATION_CHAIN.index(current_level)
        return self.ESCALATION_CHAIN[idx + 1] if idx < len(self.ESCALATION_CHAIN) - 1 else None
    
    async def _find_person_at_level(self, job_id: int, level: str) -> int | None:
        """Find the user assigned to this role on this job."""
        # worker → job's assigned workers (pick first)
        # lead → job's lead_user_id
        # foreman → job's foreman (from hat assignments)
        # supervisor → user with supervisor hat on this job or globally
        # office → any user with office permission
```

### Router: `chat_router.py`

```
# Channels
GET    /api/chat/channels                          — User's channels with unread counts
GET    /api/chat/channels/{id}                     — Channel detail with messages (paginated)
POST   /api/chat/channels/dm                       — Create DM channel

# Messages
POST   /api/chat/channels/{id}/messages            — Send message
PATCH  /api/chat/messages/{id}                     — Edit message
DELETE /api/chat/messages/{id}                     — Soft delete
POST   /api/chat/messages/{id}/pin                 — Pin message
DELETE /api/chat/messages/{id}/pin                 — Unpin message
POST   /api/chat/channels/{id}/read                — Mark channel as read

# Mentions
GET    /api/chat/mentions                          — Unread mentions for current user
POST   /api/chat/mentions/{id}/ack                 — Acknowledge mention

# Q&A
POST   /api/chat/qa/ask                            — Ask a question (creates thread + message)
GET    /api/chat/qa/threads?job_id={id}&status={s}  — List Q&A threads for a job
GET    /api/chat/qa/threads/{id}                   — Thread detail with all messages
POST   /api/chat/qa/threads/{id}/escalate          — Escalate to next level
POST   /api/chat/qa/threads/{id}/answer            — Answer the question
POST   /api/chat/qa/threads/{id}/close             — Close thread
POST   /api/chat/qa/threads/{id}/send-to-gc        — Create RFI for GC

# RFIs
GET    /api/chat/rfis?job_id={id}                  — List RFIs for a job
PATCH  /api/chat/rfis/{id}                         — Update RFI status (manual: "GC responded")
```

**Total endpoints: ~16**

---

## Frontend Implementation

### Navigation

Add "Chat" to the main navigation (icon: `MessageSquare`):

```
Chat module → 3 tabs:
  ├── Inbox          — All channels sorted by recent activity, unread badges
  ├── Q&A Board      — All Q&A threads across jobs, filterable by status
  └── RFIs           — All RFI objects sent to GCs (office only)
```

Also add a chat shortcut inside each Job detail page (tab or sidebar link).

### Page 1: `ChatInboxPage.tsx`

**Layout:**
- **Channel list** (left panel on desktop, full-screen on mobile):
  - Each row: Channel name (job name or DM participant), last message preview, timestamp, unread badge
  - Job channels show job icon/color
  - DM channels show user avatar
  - Sort by most recent message
  - Search/filter bar at top
- **Message view** (right panel on desktop, navigated-to on mobile):
  - Messages in chronological order (infinite scroll up for history)
  - Each message: sender avatar, name, timestamp, content
  - Reply indicator (thread line to parent message)
  - Photos render inline (tap to expand)
  - Voice messages show play button + waveform + duration
  - Pinned messages banner at top (collapsible)
  - System messages (joins, escalations) render as centered gray text

**Compose bar (bottom of message view):**
- Text input (multiline, auto-grow)
- @mention autocomplete (triggered by typing `@`)
- Buttons: 📎 Attach Photo | 🎤 Voice Message | ❓ Ask Q&A Question
- Send button (or Enter key)

**Key interactions:**
- Tap channel → open message view
- Long-press message → context menu: Reply | Pin | Edit (own) | Delete (own)
- Pull-to-refresh (mobile)
- Infinite scroll up for message history

### Page 2: `QABoardPage.tsx`

**Layout:**
- **Filter bar:** Job selector | Status filter (Open | Escalated | Answered | All) | Priority filter
- **Thread list:** Card per thread showing:
  - Subject, asker name, job name
  - Current level badge (color-coded: worker=blue, lead=green, foreman=orange, supervisor=red, office=purple)
  - Assigned to (avatar + name)
  - Status badge
  - Priority indicator (urgent = red dot)
  - Time since asked
  - Last activity preview
- **Thread detail view** (click/tap):
  - Full message history (question, comments, escalations, answer)
  - Action buttons (context-dependent):
    - Assigned to me → "Answer" | "Escalate" | "Add Comment"
    - Office level → "Answer" | "Send to GC" | "Close"
  - Escalation timeline (visual: dots connected by line showing each level)

### Page 3: `RFIListPage.tsx` (office only)

**Layout:**
- **Filter bar:** Job selector | Status filter | Date range
- **RFI table:** RFI # | Job | Subject | GC | Sent Via | Status | Sent Date | Response Date
- **RFI detail view:**
  - Full question context (original Q&A thread summary)
  - Sent message body
  - GC response (manually entered for V1.0)
  - Action buttons: "Mark as Responded" | "Re-send" | "Link to Q&A Thread"

### Component: `ChatMessageComposer.tsx`

Reusable compose bar component:
- Text input with @mention autocomplete
- Photo attachment (camera + gallery via Capacitor Camera plugin)
- Voice message recording (Capacitor plugin or MediaRecorder API)
  - Tap-and-hold to record, release to send
  - Preview before sending (play back, cancel, send)
- File attachment (documents)
- Q&A mode toggle (switches to structured question form)

### Component: `QAQuestionForm.tsx`

When asking a Q&A question (from compose bar or Q&A Board):
- Subject field (required, short text)
- Body field (required, multiline)
- Priority selector (Low | Normal | Urgent)
- Attach photos (optional)
- Submit creates thread + first message, assigns to chain

### Component: `EscalationTimeline.tsx`

Visual timeline showing Q&A escalation progress:
```
● Worker (Roy asked)  →  ● Lead (escalated by Mike)  →  ● Foreman (answered by Dave)
   Feb 1 10:00            Feb 1 10:30                     Feb 1 11:15
```
- Each dot is color-coded by level
- Shows who acted and when
- Current level is highlighted/pulsing

---

## API Client

### File: `frontend/src/api/chat.ts`

```typescript
// Channels
export function getMyChannels(): Promise<Channel[]>
export function getChannel(id: number, params?: { beforeId?: number; limit?: number }): Promise<ChannelDetail>
export function createDMChannel(userIds: number[]): Promise<Channel>

// Messages
export function sendMessage(channelId: number, data: SendMessageRequest): Promise<Message>
export function editMessage(id: number, content: string): Promise<Message>
export function deleteMessage(id: number): Promise<void>
export function pinMessage(id: number): Promise<void>
export function unpinMessage(id: number): Promise<void>
export function markChannelRead(channelId: number): Promise<void>

// Mentions
export function getUnreadMentions(): Promise<Mention[]>
export function acknowledgeMention(id: number): Promise<void>

// Q&A
export function askQuestion(data: AskQuestionRequest): Promise<QAThread>
export function getQAThreads(params?: { jobId?: number; status?: string }): Promise<QAThread[]>
export function getQAThread(id: number): Promise<QAThreadDetail>
export function escalateThread(id: number, comment?: string): Promise<QAThread>
export function answerThread(id: number, answer: string): Promise<QAThread>
export function closeThread(id: number): Promise<QAThread>
export function sendToGC(threadId: number, gcContactId: number, via: 'sms' | 'email'): Promise<RFI>

// RFIs
export function getRFIs(params?: { jobId?: number; status?: string }): Promise<RFI[]>
export function updateRFI(id: number, data: UpdateRFIRequest): Promise<RFI>
```

---

## Offline-First Considerations

Chat must work when devices are offline (the default state for field workers):

1. **Messages queue locally** — sent messages go to a local outbox, display immediately with "pending" indicator
2. **Sync on connection** — when device reaches shop (LAN) or another device (BT), messages sync
3. **Conflict handling** — messages have `created_at` timestamps, same as other sync. No real conflicts since messages are append-only.
4. **Media handling** — photos/voice attachments stored locally, synced as media blobs when bandwidth allows (Wi-Fi preferred)
5. **Read receipts sync** — `last_read_message_id` syncs with other data, may be slightly stale
6. **Q&A escalation** — works offline for viewing threads. Escalation/answer actions queue locally, execute on next sync.

**Key principle:** The chat system must never depend on real-time connectivity. Workers should be able to read all synced messages and compose new ones while completely offline.

---

## Permissions

| Permission | Who | What |
|-----------|-----|------|
| `use_chat` | All users | Send/receive messages, view channels they're members of |
| `manage_channels` | Office + Admin | Create/delete channels, manage members |
| `ask_qa` | All users | Ask Q&A questions |
| `escalate_qa` | Users at their level or above | Escalate Q&A threads |
| `answer_qa` | Users at assigned level | Answer Q&A threads |
| `send_rfi` | Office + Admin | Send RFIs to GCs |
| `view_all_qa` | Office + Admin | View all Q&A threads across all jobs |

Workers automatically become members of channels for their assigned jobs.

---

## Success Criteria

- [ ] Job channels auto-created when first message is sent for a job
- [ ] DM channels support 1:1 and small group conversations
- [ ] Messages support text, photos, voice recordings, and file attachments
- [ ] @mentions create notifications and appear in mentions inbox
- [ ] Messages paginate correctly (infinite scroll loads history)
- [ ] Pinned messages show in a collapsible header
- [ ] Read receipts track per-user, per-channel
- [ ] Unread badges show on channel list and nav icon
- [ ] Q&A threads escalate through Worker → Lead → Foreman → Supervisor → Office
- [ ] Each escalation level auto-assigns to the right person on the job
- [ ] Q&A answers flow back to the original asker's thread
- [ ] RFI objects create pre-formatted text for SMS/email (V1.0)
- [ ] All messages work offline (queue locally, sync on next connection)
- [ ] Voice messages record, play back, and sync correctly
- [ ] Chat inbox is responsive at all breakpoints (desktop, tablet, mobile)
- [ ] Dark mode works on all chat pages
- [ ] Q&A Board filters by job, status, and priority
- [ ] Escalation timeline visualizes the chain progression

---

## Execution Order

1. **Migration:** `029_chat_system.sql` — all tables, indexes, triggers
2. **Backend repos:** `chat_repo.py` + `qa_repo.py`
3. **Backend services:** `chat_service.py` + `qa_service.py`
4. **Backend router:** `chat_router.py` — all ~16 endpoints
5. **Frontend API client:** `chat.ts`
6. **Frontend:** `ChatInboxPage.tsx` — channel list + message view
7. **Frontend:** `ChatMessageComposer.tsx` — compose bar with @mentions, photos, voice
8. **Frontend:** `QABoardPage.tsx` — Q&A thread list + detail view
9. **Frontend:** `QAQuestionForm.tsx` + `EscalationTimeline.tsx`
10. **Frontend:** `RFIListPage.tsx` — RFI management (office only)
11. **Integration:** Add chat link to Job detail page
12. **Integration:** Add unread badge to main navigation
13. **Test:** Full flow — send messages, escalate Q&A, create RFI, verify offline behavior

---

## Future Extensions (Not V1.0)

- **Shop↔Shop RFI delivery** — automatic when GC is on same system (requires Phase 13 Remote Sync)
- **Push notifications** — requires Phase 10 PWA service worker or native push
- **Reactions/emoji** — low priority, easy to add later
- **Message search** — full-text search across all channels
- **Chat bots** — AI-powered responses (Phase 12)
- **Shared channels** — cross-company channels with controlled visibility (Phase 13)
