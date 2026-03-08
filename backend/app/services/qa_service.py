"""
Q&A escalation service — manages the question escalation chain and RFI bridge.

Escalation chain: Worker → Lead → Foreman → Supervisor → Office

Each level maps to job-specific roles:
  - worker:     job_team_members (role='member') or job_dispatch (role='worker')
  - lead:       jobs.lead_user_id or job_team_members (role='lead')
  - foreman:    job_dispatch (role_on_job='lead') or hat level 3
  - supervisor: job_dispatch (role_on_job='supervisor') or hat level ≤1
  - office:     any user with hat level ≤2

If nobody is found at a level, we skip to the next level.
"""

from __future__ import annotations

import logging

import aiosqlite

from app.repositories.chat_repo import (
    ChatChannelRepo,
    ChatMemberRepo,
    ChatMessageRepo,
)
from app.repositories.qa_repo import QAThreadRepo, RFIRepo
from app.services.notification_service import NotificationService

logger = logging.getLogger(__name__)

ESCALATION_CHAIN = ["worker", "lead", "foreman", "supervisor", "office"]


class QAService:
    """Manages Q&A escalation chain logic."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.thread_repo = QAThreadRepo(db)
        self.rfi_repo = RFIRepo(db)
        self.channel_repo = ChatChannelRepo(db)
        self.member_repo = ChatMemberRepo(db)
        self.message_repo = ChatMessageRepo(db)
        self.notif_service = NotificationService(db)

    # ── Ask ─────────────────────────────────────────────────────────

    async def ask_question(
        self,
        job_id: int,
        asked_by: int,
        subject: str,
        body: str,
        *,
        priority: str = "normal",
        media_path: str | None = None,
    ) -> dict:
        """Create a Q&A thread, initial message, and assign to chain.

        Steps:
        1. Get or create the job channel
        2. Determine starting level (always 'worker' — the asker)
        3. Find the next person up the chain (lead)
        4. Create the qa_thread record
        5. Create the initial question message
        6. Notify the assigned person
        """
        # 1. Get/create job channel
        channel = await self.channel_repo.get_or_create_job_channel(
            job_id, asked_by
        )
        channel_id = channel["id"]

        # Ensure asker is a channel member
        if not await self.member_repo.is_member(channel_id, asked_by):
            await self.member_repo.add_member(channel_id, asked_by)

        # 2-3. Find who to assign to (next level above worker)
        assigned_to = await self._find_person_at_level(job_id, "lead")
        starting_level = "worker"

        # If no lead found, try foreman, then supervisor, then office
        if assigned_to is None:
            for fallback_level in ["foreman", "supervisor", "office"]:
                assigned_to = await self._find_person_at_level(
                    job_id, fallback_level
                )
                if assigned_to is not None:
                    starting_level = self._get_level_before(fallback_level)
                    break

        # 4. Create thread
        thread = await self.thread_repo.create_thread(
            channel_id=channel_id,
            job_id=job_id,
            asked_by=asked_by,
            subject=subject,
            priority=priority,
            current_level=starting_level,
            assigned_to=assigned_to,
        )

        # Ensure assigned person is a channel member
        if assigned_to and not await self.member_repo.is_member(
            channel_id, assigned_to
        ):
            await self.member_repo.add_member(channel_id, assigned_to)

        # 5. Create initial question message
        message_content = body
        if media_path:
            message_content = f"{body}\n[attachment: {media_path}]"

        await self.message_repo.create_message(
            channel_id=channel_id,
            sender_id=asked_by,
            content=message_content,
            message_type="qa_question",
            media_path=media_path,
            qa_thread_id=thread["id"],
            qa_level=starting_level,
        )

        # 6. Notify assigned person
        if assigned_to:
            await self.notif_service.notify(
                "qa_assigned",
                f"New Q&A: {subject}",
                message=body[:100],
                link=f"/chat/qa-board?thread={thread['id']}",
                entity_type="qa_thread",
                entity_id=thread["id"],
                target_user_ids=[assigned_to],
            )

        return await self.thread_repo.get_thread_with_details(thread["id"])

    # ── Escalate ───────────────────────────────────────────────────

    async def escalate(
        self,
        thread_id: int,
        escalated_by: int,
        comment: str | None = None,
    ) -> dict:
        """Move a question up one level in the escalation chain.

        Steps:
        1. Get current thread and validate
        2. Determine next level
        3. Find person at next level (skip empty levels)
        4. Update thread
        5. Create system message + optional comment
        6. Notify new assignee
        """
        thread = await self.thread_repo.get_thread_with_details(thread_id)
        if not thread:
            raise ValueError("Thread not found")

        if thread["status"] in ("closed", "answered"):
            raise ValueError(f"Cannot escalate a {thread['status']} thread")

        current_level = thread["current_level"]
        next_level = self._get_next_level(current_level)

        if next_level is None:
            raise ValueError("Already at highest escalation level")

        # Find person at next level, skip empty levels
        assigned_to = None
        target_level = next_level
        while target_level is not None and assigned_to is None:
            assigned_to = await self._find_person_at_level(
                thread["job_id"], target_level
            )
            if assigned_to is None:
                logger.warning(
                    "No person found at level '%s' for job %d, skipping",
                    target_level,
                    thread["job_id"],
                )
                target_level = self._get_next_level(target_level)

        if target_level is None:
            # Reached top of chain with nobody found
            target_level = "office"
            logger.warning(
                "Escalation reached top with no assignee for thread %d",
                thread_id,
            )

        # Update thread
        await self.thread_repo.escalate(thread_id, target_level, assigned_to)

        # Ensure new assignee is channel member
        channel_id = thread["channel_id"]
        if assigned_to and not await self.member_repo.is_member(
            channel_id, assigned_to
        ):
            await self.member_repo.add_member(channel_id, assigned_to)

        # Get escalator's name
        cursor = await self.db.execute(
            "SELECT display_name FROM users WHERE id = ?", (escalated_by,)
        )
        user_row = await cursor.fetchone()
        escalator_name = user_row["display_name"] if user_row else "Someone"

        # System message
        await self.message_repo.create_message(
            channel_id=channel_id,
            sender_id=escalated_by,
            content=f"Escalated to {target_level} by {escalator_name}",
            message_type="system",
            qa_thread_id=thread_id,
            qa_level=target_level,
        )

        # Optional comment message
        if comment:
            await self.message_repo.create_message(
                channel_id=channel_id,
                sender_id=escalated_by,
                content=comment,
                message_type="qa_escalation",
                qa_thread_id=thread_id,
                qa_level=target_level,
            )

        # Notify new assignee
        if assigned_to:
            await self.notif_service.notify(
                "qa_escalated",
                f"Q&A escalated: {thread['subject']}",
                message=comment or f"Escalated from {current_level}",
                link=f"/chat/qa-board?thread={thread_id}",
                entity_type="qa_thread",
                entity_id=thread_id,
                target_user_ids=[assigned_to],
            )

        return await self.thread_repo.get_thread_with_details(thread_id)

    # ── Answer ─────────────────────────────────────────────────────

    async def answer_thread(
        self, thread_id: int, answered_by: int, answer_text: str
    ) -> dict:
        """Answer a Q&A thread.

        Steps:
        1. Validate thread exists and is not closed
        2. Create answer message
        3. Mark thread as answered
        4. Create system message
        5. Notify the original asker
        """
        thread = await self.thread_repo.get_thread_with_details(thread_id)
        if not thread:
            raise ValueError("Thread not found")

        if thread["status"] == "closed":
            raise ValueError("Cannot answer a closed thread")

        channel_id = thread["channel_id"]

        # Answer message
        await self.message_repo.create_message(
            channel_id=channel_id,
            sender_id=answered_by,
            content=answer_text,
            message_type="qa_answer",
            qa_thread_id=thread_id,
            qa_level=thread["current_level"],
        )

        # Mark answered
        await self.thread_repo.answer(thread_id, answered_by)

        # Get answerer name
        cursor = await self.db.execute(
            "SELECT display_name FROM users WHERE id = ?", (answered_by,)
        )
        user_row = await cursor.fetchone()
        answerer_name = user_row["display_name"] if user_row else "Someone"

        # System message
        await self.message_repo.create_message(
            channel_id=channel_id,
            sender_id=answered_by,
            content=f"Answered by {answerer_name}",
            message_type="system",
            qa_thread_id=thread_id,
            qa_level=thread["current_level"],
        )

        # Notify original asker
        if thread["asked_by"] != answered_by:
            await self.notif_service.notify(
                "qa_answered",
                f"Q&A answered: {thread['subject']}",
                message=answer_text[:100],
                link=f"/chat/qa-board?thread={thread_id}",
                entity_type="qa_thread",
                entity_id=thread_id,
                target_user_ids=[thread["asked_by"]],
            )

        return await self.thread_repo.get_thread_with_details(thread_id)

    # ── Close ──────────────────────────────────────────────────────

    async def close_thread(self, thread_id: int) -> dict:
        """Close a Q&A thread."""
        thread = await self.thread_repo.get_thread_with_details(thread_id)
        if not thread:
            raise ValueError("Thread not found")

        await self.thread_repo.close(thread_id)
        return await self.thread_repo.get_thread_with_details(thread_id)

    # ── Send to GC (RFI) ──────────────────────────────────────────

    async def send_to_gc(
        self,
        thread_id: int,
        sent_by: int,
        gc_contact_id: int,
        via: str = "sms",
    ) -> dict:
        """Create an RFI from a Q&A thread for the GC.

        V1.0: Creates an RFI record with pre-formatted text.
        The frontend uses native SMS (sms:) or email (mailto:) to send.
        """
        thread = await self.thread_repo.get_thread_with_details(thread_id)
        if not thread:
            raise ValueError("Thread not found")

        # Build RFI body from thread messages
        messages = await self.thread_repo.get_escalation_history(thread_id)
        body_parts = [f"RE: {thread['subject']}\n"]
        for msg in messages:
            if msg["message_type"] in ("qa_question", "qa_answer"):
                sender = msg.get("sender_name", "Unknown")
                body_parts.append(f"{sender}: {msg.get('content', '')}")

        rfi_body = "\n\n".join(body_parts)

        rfi = await self.rfi_repo.create_rfi(
            qa_thread_id=thread_id,
            job_id=thread["job_id"],
            gc_contact_id=gc_contact_id,
            subject=f"RFI: {thread['subject']}",
            body=rfi_body,
            created_by=sent_by,
        )

        # Mark thread as sent to GC
        await self.thread_repo.mark_sent_to_gc(thread_id)

        # Get GC contact info for the response
        cursor = await self.db.execute(
            """SELECT ec.*, gc.company_name
               FROM entity_contacts ec
               LEFT JOIN general_contractors gc
                      ON gc.id = ec.entity_id AND ec.entity_type = 'general_contractor'
               WHERE ec.id = ?""",
            (gc_contact_id,),
        )
        gc = await cursor.fetchone()

        rfi["gc_phone"] = gc["phone"] if gc else None
        rfi["gc_email"] = gc["email"] if gc else None
        rfi["gc_name"] = gc["company_name"] if gc else None

        return rfi

    # ── RFI Management ─────────────────────────────────────────────

    async def get_rfis(
        self,
        *,
        job_id: int | None = None,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List RFIs with optional filters."""
        return await self.rfi_repo.get_rfis_with_details(
            job_id=job_id, status=status, limit=limit, offset=offset
        )

    async def update_rfi(
        self,
        rfi_id: int,
        *,
        status: str | None = None,
        sent_via: str | None = None,
        response_text: str | None = None,
        updated_by: int | None = None,
    ) -> bool:
        """Update RFI status (e.g., mark as responded).

        When a response_text is provided, the GC's answer is written back
        into the original Q&A thread as a message and the thread is marked
        as 'answered'. This fulfills the concept-doc requirement:
        "Every external answer, no matter the channel, is written back into
        the same internal Q&A thread."
        """
        ok = await self.rfi_repo.update_status(
            rfi_id, status=status, sent_via=sent_via, response_text=response_text
        )
        if not ok:
            return False

        # ── Write GC response back into Q&A thread ─────────────────
        if response_text:
            rfi = await self.rfi_repo.get_rfi_with_thread(rfi_id)
            if rfi and rfi.get("qa_thread_id") and rfi.get("channel_id"):
                channel_via = sent_via or rfi.get("sent_via") or "external"
                gc_label = rfi.get("gc_name") or "GC"
                contact_name = rfi.get("gc_contact_name") or ""
                if contact_name:
                    gc_label = f"{gc_label} ({contact_name})"

                # Inject the GC response as a message in the thread
                sender_id = updated_by or rfi.get("created_by") or 1
                await self.message_repo.create_message(
                    channel_id=rfi["channel_id"],
                    sender_id=sender_id,
                    content=(
                        f"**Answer from {gc_label} (via {channel_via}):**\n\n"
                        f"{response_text}"
                    ),
                    message_type="qa_answer",
                    qa_thread_id=rfi["qa_thread_id"],
                    qa_level="office",
                )

                # System message noting the external response
                await self.message_repo.create_message(
                    channel_id=rfi["channel_id"],
                    sender_id=sender_id,
                    content=f"GC response received from {gc_label} via {channel_via}",
                    message_type="system",
                    qa_thread_id=rfi["qa_thread_id"],
                    qa_level="office",
                )

                # Mark the Q&A thread as answered
                await self.thread_repo.answer(
                    rfi["qa_thread_id"], sender_id
                )

                # Notify original asker
                if rfi.get("asked_by"):
                    await self.notif_service.notify(
                        "qa_answered",
                        f"GC responded: {rfi.get('thread_subject', 'Q&A')}",
                        message=response_text[:100],
                        link=f"/chat/qa-board?thread={rfi['qa_thread_id']}",
                        entity_type="qa_thread",
                        entity_id=rfi["qa_thread_id"],
                        target_user_ids=[rfi["asked_by"]],
                    )

        return True

    # ── Q&A Thread Queries ─────────────────────────────────────────

    async def get_threads(
        self,
        *,
        job_id: int | None = None,
        status: str | None = None,
        assigned_to: int | None = None,
        priority: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List Q&A threads with filters."""
        return await self.thread_repo.get_threads(
            job_id=job_id,
            status=status,
            assigned_to=assigned_to,
            priority=priority,
            limit=limit,
            offset=offset,
        )

    async def get_thread_detail(self, thread_id: int) -> dict | None:
        """Get a thread with all details, messages, escalation timeline, and linked RFI."""
        thread = await self.thread_repo.get_thread_with_details(thread_id)
        if not thread:
            return None

        # Get all messages in the thread
        cursor = await self.db.execute(
            """SELECT cm.*, u.display_name AS sender_name, u.username AS sender_username
               FROM chat_messages cm
               JOIN users u ON u.id = cm.sender_id
               WHERE cm.qa_thread_id = ? AND cm.deleted_at IS NULL
               ORDER BY cm.created_at ASC""",
            (thread_id,),
        )
        messages = [dict(r) for r in await cursor.fetchall()]

        # Build escalation timeline from system/escalation messages
        timeline = self._build_timeline(thread, messages)

        # Fetch linked RFI (if thread was sent to GC)
        rfi = await self.rfi_repo.get_rfi_for_thread(thread_id)

        return {
            "thread": thread,
            "messages": messages,
            "timeline": timeline,
            "rfi": rfi,
        }

    # ── Internal Helpers ───────────────────────────────────────────

    def _get_next_level(self, current_level: str) -> str | None:
        """Return the next escalation level, or None if at top."""
        try:
            idx = ESCALATION_CHAIN.index(current_level)
            return (
                ESCALATION_CHAIN[idx + 1]
                if idx < len(ESCALATION_CHAIN) - 1
                else None
            )
        except ValueError:
            return None

    def _get_level_before(self, level: str) -> str:
        """Return the level just before the given one."""
        try:
            idx = ESCALATION_CHAIN.index(level)
            return ESCALATION_CHAIN[max(0, idx - 1)]
        except ValueError:
            return "worker"

    async def _find_person_at_level(
        self, job_id: int, level: str
    ) -> int | None:
        """Find the user assigned to this role on this job.

        Mapping:
          worker     → first job_team_member with role='member'
          lead       → jobs.lead_user_id, fallback job_team_members role='lead'
          foreman    → job_dispatch role_on_job='lead', fallback hat level 3
          supervisor → job_dispatch role_on_job='supervisor', fallback hat level ≤1
          office     → any user with hat level ≤2
        """
        if level == "worker":
            cursor = await self.db.execute(
                """SELECT user_id FROM job_team_members
                   WHERE job_id = ? AND role = 'member' LIMIT 1""",
                (job_id,),
            )
            row = await cursor.fetchone()
            return row["user_id"] if row else None

        if level == "lead":
            # Primary: job's lead
            cursor = await self.db.execute(
                "SELECT lead_user_id FROM jobs WHERE id = ?", (job_id,)
            )
            job = await cursor.fetchone()
            if job and job["lead_user_id"]:
                return job["lead_user_id"]

            # Fallback: team member with role='lead'
            cursor = await self.db.execute(
                """SELECT user_id FROM job_team_members
                   WHERE job_id = ? AND role = 'lead' LIMIT 1""",
                (job_id,),
            )
            row = await cursor.fetchone()
            return row["user_id"] if row else None

        if level == "foreman":
            # Dispatched lead for this job
            cursor = await self.db.execute(
                """SELECT user_id FROM job_dispatch
                   WHERE job_id = ? AND role_on_job = 'lead'
                   AND dispatch_date >= date('now', '-7 days')
                   ORDER BY dispatch_date DESC LIMIT 1""",
                (job_id,),
            )
            row = await cursor.fetchone()
            if row:
                return row["user_id"]

            # Fallback: user with hat level 3
            cursor = await self.db.execute(
                """SELECT u.id FROM users u
                   JOIN user_hats uh ON uh.user_id = u.id
                   JOIN hats h ON h.id = uh.hat_id
                   WHERE h.level = 3 AND u.is_active = 1
                   LIMIT 1""",
            )
            row = await cursor.fetchone()
            return row["id"] if row else None

        if level == "supervisor":
            # Dispatched supervisor for this job
            cursor = await self.db.execute(
                """SELECT user_id FROM job_dispatch
                   WHERE job_id = ? AND role_on_job = 'supervisor'
                   AND dispatch_date >= date('now', '-7 days')
                   ORDER BY dispatch_date DESC LIMIT 1""",
                (job_id,),
            )
            row = await cursor.fetchone()
            if row:
                return row["user_id"]

            # Fallback: user with hat level ≤1 (admin or top manager)
            cursor = await self.db.execute(
                """SELECT u.id FROM users u
                   JOIN user_hats uh ON uh.user_id = u.id
                   JOIN hats h ON h.id = uh.hat_id
                   WHERE h.level <= 1 AND u.is_active = 1
                   LIMIT 1""",
            )
            row = await cursor.fetchone()
            return row["id"] if row else None

        if level == "office":
            # Any user with hat level ≤2 (admin, manager, office)
            cursor = await self.db.execute(
                """SELECT u.id FROM users u
                   JOIN user_hats uh ON uh.user_id = u.id
                   JOIN hats h ON h.id = uh.hat_id
                   WHERE h.level <= 2 AND u.is_active = 1
                   LIMIT 1""",
            )
            row = await cursor.fetchone()
            return row["id"] if row else None

        return None

    def _build_timeline(
        self, thread: dict, messages: list[dict]
    ) -> list[dict]:
        """Build escalation timeline from thread + messages."""
        timeline = []

        # Starting point: question asked
        timeline.append({
            "level": "worker",
            "action": "asked",
            "user_name": thread.get("asker_name"),
            "user_id": thread.get("asked_by"),
            "timestamp": thread.get("created_at"),
            "comment": thread.get("subject"),
        })

        # Extract escalation/answer/close events from messages
        for msg in messages:
            if msg["message_type"] == "system":
                content = msg.get("content", "")
                if "Escalated" in content:
                    timeline.append({
                        "level": msg.get("qa_level", "unknown"),
                        "action": "escalated",
                        "user_name": msg.get("sender_name"),
                        "user_id": msg.get("sender_id"),
                        "timestamp": msg.get("created_at"),
                        "comment": content,
                    })
                elif "Answered" in content:
                    timeline.append({
                        "level": msg.get("qa_level", "unknown"),
                        "action": "answered",
                        "user_name": msg.get("sender_name"),
                        "user_id": msg.get("sender_id"),
                        "timestamp": msg.get("created_at"),
                        "comment": content,
                    })

        # Closing event
        if thread.get("status") == "closed" and thread.get("closed_at"):
            timeline.append({
                "level": thread.get("current_level", "unknown"),
                "action": "closed",
                "user_name": None,
                "user_id": None,
                "timestamp": thread.get("closed_at"),
                "comment": None,
            })

        # Sent to GC event
        if thread.get("status") == "sent_to_gc":
            timeline.append({
                "level": "office",
                "action": "sent_to_gc",
                "user_name": None,
                "user_id": None,
                "timestamp": thread.get("updated_at"),
                "comment": None,
            })

        return timeline
