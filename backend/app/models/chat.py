"""
Pydantic models for Chat, Q&A Escalation, and RFI objects.

Covers all request/response shapes for Phase 9 endpoints.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


# ── Channels ─────────────────────────────────────────────────────────

class ChannelCreate(BaseModel):
    """Create a DM or general channel."""
    channel_type: str = Field("dm", pattern="^(dm|general)$")
    name: str | None = None
    user_ids: list[int] = Field(..., min_length=1)


class ChannelResponse(BaseModel):
    """Channel summary (inbox row)."""
    id: int
    channel_type: str
    job_id: int | None = None
    name: str | None = None
    created_by: int | None = None
    created_at: str | None = None
    updated_at: str | None = None
    # Computed
    member_count: int = 0
    unread_count: int = 0
    last_message: MessagePreview | None = None
    job_name: str | None = None
    job_number: str | None = None
    members: list[ChannelMemberResponse] | None = None


class ChannelDetailResponse(BaseModel):
    """Channel with messages + member list."""
    channel: ChannelResponse
    messages: list[MessageResponse] = []
    members: list[ChannelMemberResponse] = []
    pinned_messages: list[MessageResponse] = []
    has_more: bool = False


class ChannelMemberResponse(BaseModel):
    """Channel member info."""
    id: int
    channel_id: int
    user_id: int
    role: str = "member"
    muted_until: str | None = None
    joined_at: str | None = None
    # Joined from users
    display_name: str | None = None
    username: str | None = None


# ── Messages ─────────────────────────────────────────────────────────

class SendMessageRequest(BaseModel):
    """Send a message to a channel."""
    content: str | None = None
    message_type: str = "text"
    media_path: str | None = None
    media_mime_type: str | None = None
    media_size_bytes: int | None = None
    reply_to_id: int | None = None
    mention_ids: list[int] = []


class EditMessageRequest(BaseModel):
    """Edit message content."""
    content: str = Field(..., min_length=1)


class MessageResponse(BaseModel):
    """A single chat message."""
    id: int
    channel_id: int
    sender_id: int
    message_type: str = "text"
    content: str | None = None
    media_path: str | None = None
    media_mime_type: str | None = None
    media_size_bytes: int | None = None
    reply_to_id: int | None = None
    pinned_at: str | None = None
    pinned_by: int | None = None
    edited_at: str | None = None
    deleted_at: str | None = None
    created_at: str | None = None
    qa_thread_id: int | None = None
    qa_level: str | None = None
    # Joined
    sender_name: str | None = None
    sender_username: str | None = None
    # Reply preview (if reply_to_id set)
    reply_preview: str | None = None
    reply_sender_name: str | None = None


class MessagePreview(BaseModel):
    """Short preview for inbox channel row."""
    id: int
    content: str | None = None
    message_type: str = "text"
    sender_name: str | None = None
    created_at: str | None = None


# ── Read Receipts & Mentions ─────────────────────────────────────────

class MarkReadRequest(BaseModel):
    """Mark a channel as read up to a message."""
    last_read_message_id: int


class MentionResponse(BaseModel):
    """An @mention for the current user."""
    id: int
    message_id: int
    mentioned_user_id: int
    acknowledged_at: str | None = None
    # Joined
    channel_id: int | None = None
    channel_name: str | None = None
    job_id: int | None = None
    sender_name: str | None = None
    content: str | None = None
    created_at: str | None = None


class InboxResponse(BaseModel):
    """Full inbox for a user."""
    channels: list[ChannelResponse] = []
    total_unread: int = 0
    unread_mentions: int = 0


# ── Q&A Threads ──────────────────────────────────────────────────────

class AskQuestionRequest(BaseModel):
    """Ask a Q&A question on a job."""
    job_id: int
    subject: str = Field(..., min_length=1, max_length=200)
    body: str = Field(..., min_length=1)
    priority: str = "normal"
    media_path: str | None = None


class EscalateRequest(BaseModel):
    """Escalate a Q&A thread with optional comment."""
    comment: str | None = None


class AnswerRequest(BaseModel):
    """Answer a Q&A thread."""
    answer: str = Field(..., min_length=1)


class QAThreadResponse(BaseModel):
    """Q&A thread summary."""
    id: int
    channel_id: int
    job_id: int | None = None
    asked_by: int
    subject: str
    current_level: str
    assigned_to: int | None = None
    status: str
    priority: str = "normal"
    answered_by: int | None = None
    answered_at: str | None = None
    closed_at: str | None = None
    created_at: str | None = None
    updated_at: str | None = None
    # Joined
    asker_name: str | None = None
    assigned_name: str | None = None
    answerer_name: str | None = None
    job_name: str | None = None
    job_number: str | None = None
    message_count: int = 0


class QAThreadDetailResponse(BaseModel):
    """Q&A thread with full message history + escalation timeline + linked RFI."""
    thread: QAThreadResponse
    messages: list[MessageResponse] = []
    timeline: list[EscalationStep] = []
    rfi: RFIResponse | None = None


class EscalationStep(BaseModel):
    """One step in the escalation timeline."""
    level: str
    action: str  # 'asked', 'escalated', 'answered', 'sent_to_gc', 'closed'
    user_name: str | None = None
    user_id: int | None = None
    timestamp: str | None = None
    comment: str | None = None


# ── RFIs ─────────────────────────────────────────────────────────────

class SendToGCRequest(BaseModel):
    """Send a Q&A thread to a GC as an RFI."""
    gc_contact_id: int
    via: str = Field("sms", pattern="^(sms|email)$")


class RFIResponse(BaseModel):
    """An RFI sent to a GC."""
    id: int
    qa_thread_id: int
    job_id: int
    gc_contact_id: int | None = None
    subject: str
    body: str
    status: str
    sent_via: str | None = None
    sent_at: str | None = None
    response_text: str | None = None
    responded_at: str | None = None
    created_by: int
    created_at: str | None = None
    updated_at: str | None = None
    # Joined
    gc_name: str | None = None
    gc_phone: str | None = None
    gc_email: str | None = None
    job_name: str | None = None
    job_number: str | None = None
    thread_subject: str | None = None


class UpdateRFIRequest(BaseModel):
    """Update RFI status (mark as responded, etc.)."""
    status: str | None = None
    response_text: str | None = None
    sent_via: str | None = None


# ── Rebuild forward refs (ChannelResponse uses MessagePreview) ───────
ChannelResponse.model_rebuild()
ChannelDetailResponse.model_rebuild()
QAThreadDetailResponse.model_rebuild()
