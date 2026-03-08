"""
Chat routes — channels, messages, mentions, Q&A escalation, and RFIs.

Phase 9 — ~16 endpoints covering job-based group chat, DMs,
Q&A escalation chain (worker→lead→foreman→supervisor→office),
and RFI management for GC communication.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.chat import (
    AnswerRequest,
    AskQuestionRequest,
    ChannelCreate,
    ChannelDetailResponse,
    ChannelResponse,
    EditMessageRequest,
    EscalateRequest,
    InboxResponse,
    MarkReadRequest,
    MentionResponse,
    MessageResponse,
    QAThreadDetailResponse,
    QAThreadResponse,
    RFIResponse,
    SendMessageRequest,
    SendToGCRequest,
    UpdateRFIRequest,
)
from app.models.common import ApiResponse, StatusMessage
from app.services.chat_service import ChatService
from app.services.qa_service import QAService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/chat", tags=["Chat"])


# ── Channels ───────────────────────────────────────────────────────

@router.get("/channels", response_model=InboxResponse)
async def get_inbox(
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Get user's inbox — all channels with unread counts."""
    svc = ChatService(db)
    return await svc.get_inbox(user["id"])


@router.get("/channels/{channel_id}")
async def get_channel_detail(
    channel_id: int,
    before_id: int | None = Query(None, description="Cursor for pagination"),
    limit: int = Query(50, ge=1, le=100),
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Get channel with paginated messages. Auto-marks as read."""
    svc = ChatService(db)
    try:
        return await svc.get_channel_detail(
            channel_id, user["id"], before_id=before_id, limit=limit
        )
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.post("/channels/dm", response_model=ChannelResponse)
async def create_dm_channel(
    body: ChannelCreate,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Create or find a DM channel between users."""
    svc = ChatService(db)
    # Include current user in the channel
    user_ids = list(set(body.user_ids + [user["id"]]))
    return await svc.create_dm_channel(user_ids, user["id"])


@router.post("/channels/job/{job_id}", response_model=ChannelResponse)
async def get_or_create_job_channel(
    job_id: int,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Get or create a job channel with auto-enrollment."""
    svc = ChatService(db)
    return await svc.get_or_create_job_channel(job_id, user["id"])


# ── Messages ───────────────────────────────────────────────────────

@router.post("/channels/{channel_id}/messages", response_model=MessageResponse)
async def send_message(
    channel_id: int,
    body: SendMessageRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Send a message to a channel."""
    svc = ChatService(db)
    try:
        return await svc.send_message(
            channel_id=channel_id,
            sender_id=user["id"],
            content=body.content,
            message_type=body.message_type,
            media_path=body.media_path,
            media_mime_type=body.media_mime_type,
            media_size_bytes=body.media_size_bytes,
            reply_to_id=body.reply_to_id,
            mention_ids=body.mention_ids or [],
        )
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.patch("/messages/{message_id}", response_model=StatusMessage)
async def edit_message(
    message_id: int,
    body: EditMessageRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Edit a message (only sender can edit)."""
    svc = ChatService(db)
    try:
        ok = await svc.edit_message(message_id, body.content, user["id"])
        return {"ok": ok, "message": "Message updated" if ok else "Not found"}
    except (PermissionError, ValueError) as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.delete("/messages/{message_id}", response_model=StatusMessage)
async def delete_message(
    message_id: int,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Soft-delete a message (only sender can delete)."""
    svc = ChatService(db)
    try:
        ok = await svc.delete_message(message_id, user["id"])
        return {"ok": ok, "message": "Deleted" if ok else "Not found"}
    except (PermissionError, ValueError) as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.post("/messages/{message_id}/pin", response_model=StatusMessage)
async def pin_message(
    message_id: int,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Pin a message."""
    svc = ChatService(db)
    ok = await svc.pin_message(message_id, user["id"])
    return {"ok": ok, "message": "Pinned" if ok else "Not found"}


@router.delete("/messages/{message_id}/pin", response_model=StatusMessage)
async def unpin_message(
    message_id: int,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Unpin a message."""
    svc = ChatService(db)
    ok = await svc.unpin_message(message_id)
    return {"ok": ok, "message": "Unpinned" if ok else "Not found"}


# ── Read Receipts ──────────────────────────────────────────────────

@router.post("/channels/{channel_id}/read", response_model=StatusMessage)
async def mark_read(
    channel_id: int,
    body: MarkReadRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Mark a channel as read up to a specific message."""
    svc = ChatService(db)
    await svc.mark_read(channel_id, user["id"], body.last_read_message_id)
    return {"ok": True, "message": "Marked as read"}


# ── Mentions ───────────────────────────────────────────────────────

@router.get("/mentions", response_model=list[MentionResponse])
async def get_mentions(
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Get all unread @mentions for the current user."""
    svc = ChatService(db)
    return await svc.get_unread_mentions(user["id"])


@router.post("/mentions/{mention_id}/ack", response_model=StatusMessage)
async def ack_mention(
    mention_id: int,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Acknowledge a mention."""
    svc = ChatService(db)
    ok = await svc.acknowledge_mention(mention_id)
    return {"ok": ok, "message": "Acknowledged" if ok else "Not found"}


# ── Badge Count ────────────────────────────────────────────────────

@router.get("/badge")
async def get_badge(
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Get unread count for the chat nav badge."""
    svc = ChatService(db)
    return await svc.get_badge_count(user["id"])


# ── Q&A Threads ────────────────────────────────────────────────────

@router.post("/qa/ask", response_model=QAThreadResponse)
async def ask_question(
    body: AskQuestionRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Ask a Q&A question on a job."""
    svc = QAService(db)
    result = await svc.ask_question(
        job_id=body.job_id,
        asked_by=user["id"],
        subject=body.subject,
        body=body.body,
        priority=body.priority,
        media_path=body.media_path,
    )
    return result


@router.get("/qa/threads", response_model=list[QAThreadResponse])
async def list_threads(
    job_id: int | None = Query(None),
    status: str | None = Query(None),
    assigned_to: int | None = Query(None),
    priority: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """List Q&A threads with optional filters."""
    svc = QAService(db)
    return await svc.get_threads(
        job_id=job_id,
        status=status,
        assigned_to=assigned_to,
        priority=priority,
        limit=limit,
        offset=offset,
    )


@router.get("/qa/threads/{thread_id}")
async def get_thread_detail(
    thread_id: int,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Get thread detail with messages and escalation timeline."""
    svc = QAService(db)
    result = await svc.get_thread_detail(thread_id)
    if not result:
        raise HTTPException(status_code=404, detail="Thread not found")
    return result


@router.post("/qa/threads/{thread_id}/escalate", response_model=QAThreadResponse)
async def escalate_thread(
    thread_id: int,
    body: EscalateRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Escalate a Q&A thread to the next level."""
    svc = QAService(db)
    try:
        return await svc.escalate(thread_id, user["id"], body.comment)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/qa/threads/{thread_id}/answer", response_model=QAThreadResponse)
async def answer_thread(
    thread_id: int,
    body: AnswerRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Answer a Q&A thread."""
    svc = QAService(db)
    try:
        return await svc.answer_thread(thread_id, user["id"], body.answer)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/qa/threads/{thread_id}/close", response_model=StatusMessage)
async def close_thread(
    thread_id: int,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Close a Q&A thread."""
    svc = QAService(db)
    try:
        await svc.close_thread(thread_id)
        return {"ok": True, "message": "Thread closed"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/qa/threads/{thread_id}/send-to-gc", response_model=RFIResponse)
async def send_to_gc(
    thread_id: int,
    body: SendToGCRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Create RFI and prepare for GC communication."""
    svc = QAService(db)
    try:
        return await svc.send_to_gc(
            thread_id, user["id"], body.gc_contact_id, body.via
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ── RFIs ───────────────────────────────────────────────────────────

@router.get("/rfis", response_model=list[RFIResponse])
async def list_rfis(
    job_id: int | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """List RFIs with optional filters."""
    svc = QAService(db)
    return await svc.get_rfis(
        job_id=job_id, status=status, limit=limit, offset=offset
    )


@router.patch("/rfis/{rfi_id}", response_model=StatusMessage)
async def update_rfi(
    rfi_id: int,
    body: UpdateRFIRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Update RFI status (e.g., mark as responded)."""
    svc = QAService(db)
    ok = await svc.update_rfi(
        rfi_id,
        status=body.status,
        sent_via=body.sent_via,
        response_text=body.response_text,
        updated_by=user["id"],
    )
    return {"ok": ok, "message": "Updated" if ok else "Not found"}
