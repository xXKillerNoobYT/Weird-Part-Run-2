# iOS Chat Pages — Design Plan

> **Purpose:** Comprehensive design decisions for all Chat-related pages in the iOS app. Covers unified inbox, smart cards, thread info, escalation, attachments, and real-time sync.
>
> **Source:** Design conversation 2026-03-23. Implements pages in `Weird Parts IOS/Features/Chat/`.
>
> **Files:** `IOSChannelsPage`, `IOSMessageThreadView`, `CreateChannelSheet`, `IOSQuestionsPage`, `IOSQAQuestionForm`, `IOSRFIListPage`

---

## 1. Unified Inbox

All messaging is consolidated into a single sorted stream. No separate "Messages" and "Q&A" tabs at the top level — everything lives in one place with smart card filters.

### Sort Order

1. **Unread messages float to top** (most recent unread first)
2. Within read messages: most recently active first
3. Pinned channels always stay at top regardless of activity

### Stream Contents

The unified inbox contains ALL of:
- Job group chats
- Direct messages (DMs)
- Q&A threads
- RFI threads
- Supplier bridge channels
- JPO Hold chat threads (dual-homed — see Section 5)

Each item in the stream shows:
```
+--------------------------------------------------+
| [Type Badge] Channel/Thread Name          [Time]  |
| Last message preview (1 line)            [Unread] |
| Source: Job #12345 · 3 participants               |
+--------------------------------------------------+
```

---

## 2. Smart Cards (Filter Bar)

Smart cards filter the unified inbox. Tap to filter, tap again to show all. Each shows a live count.

| Card | Filter | Color | Icon |
|------|--------|-------|------|
| Unread | Has unread messages | Red | `envelope.badge.fill` |
| Messages | Type = group chat or DM | Blue | `bubble.left.and.bubble.right.fill` |
| Q&A | Type = question | Orange | `questionmark.circle.fill` |
| RFI | Type = RFI | Purple | `doc.text.fill` |
| Supplier | Type = supplier bridge | Green | `truck.box.fill` |
| DMs | Type = direct message | Teal | `person.2.fill` |
| Job | Has job association | Yellow | `hammer.fill` |
| All | No filter | Default | `tray.fill` |

---

## 3. Thread Info Panel

Thread info uses an **iMessage-style inline expandable panel** — NOT a separate page or sheet.

### How It Works

1. User taps the thread header (channel name / participant names) **inside** an open thread
2. Panel expands inline below the header, pushing messages down
3. Tap again to collapse
4. No navigation — stays in the same view

### Panel Contents

| Section | Content |
|---------|---------|
| **Source Context** | Job name, job number, customer, current stage |
| **Participants** | List of all participants with roles |
| **Escalation Ladder** | Current position in chain, up/down options |
| **Quick Actions** | Mute, Pin, Archive, Add Participant |
| **Attachments** | Grid of all shared photos/files |
| **Linked Items** | Parts, POs, JPOs referenced in this thread |

---

## 4. Escalation Ladder

Escalation is **bidirectional** — messages can go UP and DOWN the chain.

### Chain

```
Worker <-> Lead <-> Manager <-> Office
```

### Up Escalation (Worker -> Lead -> Manager -> Office)

- Any participant can escalate a message/thread to the next level
- Escalation adds the next-level person(s) to the thread
- Original context (all previous messages) is preserved
- Notification sent to escalation target with "Escalated from [Name]" banner
- Escalation reason required (dropdown: "Need Approval", "Technical Question", "Customer Issue", "Safety Concern", "Other")

### Down Escalation (Office -> Manager -> Lead -> Worker)

- Higher-level users can push information/decisions back down
- "Send to crew" action — sends a message to all workers on the job
- "Assign to [Name]" — directs a specific person to handle it
- Response tracking — can require acknowledgment from recipients

### Escalation UI

- Escalation status shown as a colored bar in the thread:
  - Green: resolved at current level
  - Yellow: escalated, waiting for response
  - Red: urgent escalation
- Timeline view shows escalation history (who escalated when, who responded)

---

## 5. Attachments

### Supported Types

| Type | How It Works |
|------|-------------|
| **Photos** | Camera or photo library. Compressed for sync. |
| **PDFs** | From Files app or generated in-app |
| **Part References** | Tappable link to part detail. Shows part name + thumbnail. |
| **PO References** | Tappable link to PO detail. Shows PO number + status. |
| **Job References** | Tappable link to job detail. Shows job name + status. |
| **Voice Memos** | Record inline (future — not v1) |

### Storage & Lifecycle

| Policy | Rule |
|--------|------|
| **Auto-save to job notebook** | All attachments in job-linked channels automatically save to the job's notebook |
| **Mobile offload** | Attachment media (not metadata) offloaded from device after **3 months** |
| **Auto-delete** | Attachments permanently deleted after **5 years** |
| **Re-download** | Offloaded attachments can be re-downloaded from shop server if still within 5-year window |

### Part/PO/Job References

When a user types `@part:`, `@po:`, or `@job:` — a picker appears to search and select the referenced item. The reference renders as a tappable card in the message:

```
+----------------------------------+
| [Part Icon] 1/2" Copper Coupling |
| SKU: COP-COUP-050 · In Stock: 24|
+----------------------------------+
```

Tapping navigates to the referenced item's detail page.

---

## 6. JPO Hold Chat Threads

When a JPO (Job Purchase Order) is placed on hold, the system creates a chat thread for discussing the hold.

### Dual-Homing Rule

JPO Hold threads appear in **both**:
1. **JPO Detail Page** — as a "Discussion" tab on the JPO
2. **Channels Page** — in the unified inbox with a "JPO Hold" badge

Messages posted in either location sync to the same thread. This ensures:
- Office staff see hold discussions in their channel inbox
- Field workers see hold discussions when viewing the JPO

### Thread Behavior

- Thread auto-created when JPO status changes to "On Hold"
- Thread includes: JPO creator, job manager, office approver
- Thread closes (archives) when JPO hold is resolved
- All messages preserved in thread history

---

## 7. Auto-Fill Job Context

**Program-wide rule:** When a user is clocked into a job, ALL new messages/threads/channels auto-fill the job context.

| Field | Auto-Fill Value |
|-------|-----------------|
| Job association | Current clocked-in job |
| Channel suggestion | Job's existing channel (if one exists) |
| Participants suggestion | Other workers clocked into same job |

The user can override any auto-filled value. This is a convenience, not a constraint.

---

## 8. Real-Time Updates

Chat uses the existing sync engine — no polling.

### How It Works

- Messages sync via the `_change_log` table (same as all other data)
- Device-to-device sync over LAN HTTP + Apple Multipeer Connectivity
- New messages trigger push-style notifications via sync events
- Unread counts update in real-time as sync completes
- No server-side push notifications (all local network)

### Conflict Resolution

- Messages are append-only (no edit/delete in v1)
- Timestamp-based ordering (LWW — Last Writer Wins for metadata like read status)
- Duplicate detection via message UUID

---

## 9. Channel Types

| Type | Created By | Participants | Job-Linked |
|------|-----------|-------------|------------|
| **Job Chat** | Auto (when job created) | All assigned workers + managers | Yes |
| **Direct Message** | Any user | 2 users | Optional |
| **Group Chat** | Any user | 2+ users | Optional |
| **Q&A Thread** | Any user | Varies (escalation adds people) | Usually yes |
| **RFI Thread** | Managers/Office | Internal + external reference | Yes |
| **Supplier Bridge** | Office | Internal users (suppliers don't have accounts) | Optional |
| **JPO Hold** | System (auto) | JPO stakeholders | Yes |

### Create Channel Sheet (`CreateChannelSheet`)

- Channel name (required for group chats, auto-generated for DMs)
- Type picker (Group Chat, Q&A, RFI)
- Participant picker (from employees list)
- Job association (optional, auto-filled if clocked in)
- Initial message (optional)

---

## 10. Q&A System

### Question Flow

1. Worker creates a Q&A question (via `IOSQAQuestionForm`)
2. Question goes to Lead (first in escalation chain)
3. Lead can: Answer, Escalate to Manager, or Request More Info
4. If escalated, Manager gets notification
5. Manager can: Answer, Escalate to Office, or Send Back to Lead
6. Answer flows back down to original asker
7. Asker can: Accept Answer or Request Clarification

### Q&A Smart Cards

On the Q&A filtered view:
| Card | Filter |
|------|--------|
| Open | Unanswered questions |
| Waiting | Escalated, waiting for response |
| Answered | Has answer, not yet accepted |
| Resolved | Accepted answer |

---

## 11. RFI System

RFIs (Requests for Information) are formal documented questions, typically sent to architects, engineers, or GCs.

### RFI Fields

- RFI number (auto-generated sequential)
- Subject
- Question (rich text)
- Job association (required)
- Directed to (person/company)
- Priority (Low, Medium, High, Critical)
- Due date
- Attachments
- Response (when received)
- Status: Open, Submitted, Responded, Closed

### RFI vs Q&A

| Aspect | Q&A | RFI |
|--------|-----|-----|
| Formality | Informal, quick | Formal, documented |
| Audience | Internal team | External parties |
| Numbering | No | Sequential (RFI-001, RFI-002, ...) |
| Due date | No | Yes |
| Tracking | In chat stream | Dedicated RFI list + chat |

---

## 12. Implementation Notes

### Service Layer Requirements

All chat operations go through `ChatService` in WiredPartCore.

Key service methods:
- `fetchChannels(filter:)` — with type and unread filters
- `fetchMessages(channelId:, limit:, before:)` — paginated message loading
- `sendMessage(channelId:, content:, attachments:)` — with auto job context
- `escalateThread(threadId:, direction:, reason:)` — bidirectional escalation
- `markRead(channelId:)` — update read status
- `fetchUnreadCounts()` — for badge updates
- `createChannel(type:, participants:, jobId:)` — channel creation

### Hat Permissions for Chat

| Hat | What It Controls |
|-----|-----------------|
| `create_rfi` | Create RFI threads |
| `manage_channels` | Archive/delete channels |
| `view_supplier_channels` | See supplier bridge channels |
| `escalate_to_office` | Bypass chain, escalate directly to office |

---

---

## 13. Current Implementation Status (added 2026-04-19)

### iOS Files

| File | Lines | Plan Section |
|------|-------|-------------|
| `IOSChannelsPage.swift` | 428 | Sections 1–2 (unified inbox, smart cards) |
| `IOSMessageThreadView.swift` | 806 | Sections 3–5 (thread view, attachments, actions) |
| `IOSMessageBubble.swift` | 55 | Section 3 (message rendering) |
| `CreateChannelSheet.swift` | 121 | Section 9 (channel creation) |
| `IOSQuestionsPage.swift` | 306 | Section 10 (Q&A thread list) |
| `IOSQAQuestionForm.swift` | 156 | Section 10 (Q&A question form) |
| `IOSRFIListPage.swift` | 338 | Section 11 (RFI list) |
| `IOSEscalationTimeline.swift` | 335 | Section 10 (escalation history) |
| `IOSChatRouter.swift` | 16 | Navigation routing |

**Note:** No dedicated Supplier Bridge list page exists yet — supplier channels are visible via `IOSChannelsPage` unified inbox filter only. Phase 2 item.

### ChatService Method Coverage

| Plan Method | Service Method | Status |
|------------|----------------|--------|
| `fetchChannels(filter:)` | `listChannels(userId:)`, `getUnifiedInbox(userId:)` | ✅ |
| `fetchMessages(channelId:, limit:, before:)` | `getMessages(channelId:, limit:)` | ✅ (no cursor pagination yet) |
| `sendMessage(channelId:, content:, attachments:)` | `sendMessage` + `sendMessageWithAttachments` | ✅ |
| `escalateThread(threadId:, direction:, reason:)` | `escalateThread` + `pushBackThread` | ✅ |
| `markRead(channelId:)` | `markRead` (inferred from unread count) | ✅ |
| `fetchUnreadCounts()` | `getTotalUnreadCount(userId:)` | ✅ |
| `createChannel(type:, participants:, jobId:)` | `createChannel(name:, type:, ...)` | ✅ |
| Auto-save to job notebook | `autoSaveToJobNotebook(channelId:, attachment:, userId:)` | ✅ |
| JPO Hold threads | `createJPOHoldThread` + `getJPOHoldThread` | ✅ |
| Supplier bridge | `createSupplierChannel` + `listSupplierChannels` + supplier messaging | ✅ |
| RFI threading | `IOSRFIListPage` + ChatService channel creation | ✅ |
| Cursor-based pagination (`before:`) | Not yet implemented — `getMessages` uses limit only | ⏳ Phase 2 |
| Voice memos | Not in v1 per plan section 5 | ❌ Out of scope |

### Test Coverage

50 ChatService tests covering: channel creation, message sending, Q&A threads, escalation, stats, office channel sync, JPO hold threads, attachments, supplier channels, unread counts.

### Security Implementation

`manage_channels`, `create_rfi`, `view_supplier_channels`, `escalate_to_office` hat permissions enforced at UI level via `IOSChannelsPage` and `IOSMessageThreadView`.

### HIG Notes

- All sheets use `NavigationStack` + `.inline` title
- Message input bar is pinned to `.safeAreaInset(edge: .bottom)` in `IOSMessageThreadView`
- Smart card filter bar uses `ScrollView(.horizontal)` with `showsIndicators: false`
- Thread view uses `LazyVStack` for message list (performance for long threads)

---

## 14. Plan-vs-Code Drift (C1b — 2026-04-19)

### Plan-ahead-of-code (acceptable future work)

- **Cursor-based pagination** (`before:` parameter for `getMessages`): Current implementation uses `limit: Int = 50` only. No cursor/offset pagination. Plan section 12 calls for `fetchMessages(channelId:, limit:, before:)`. Phase 2 item — not blocking.
- **Dedicated Supplier Bridge list page**: Plan implies a standalone page; current implementation surfaces supplier channels through the unified inbox filter only. Phase 2 item.
- **`@part:`, `@po:`, `@job:` inline picker** (plan section 5): Reference cards exist as attachment types but the `@`-trigger picker in the message input is not implemented. Phase 2 item.

### Code-ahead-of-plan (plan should acknowledge)

- **`markRead(channelId:userId:messageId:)`** was missing entirely (C1b fix, 2026-04-19). `chat_read_receipts` table had unread-count read queries but no write path. Fixed: `INSERT OR REPLACE` with monotonic `MAX()` guard. Wired into `IOSMessageThreadView.loadMessages()`.
- **`listSupplierBridges()`, `deactivateSupplierBridge()`, `createSupplierQuestion()`, `listSupplierQuestions()`** — supplier bridge admin methods not explicitly mentioned in plan section 9/12. These extend the supplier bridge design beyond what's documented.
- **`syncOfficeChannelMembers()`** — auto-syncs active employees into the office channel. Not in plan but implements the "all active users in office channel" implicit requirement.

*Last updated: 2026-04-19*
