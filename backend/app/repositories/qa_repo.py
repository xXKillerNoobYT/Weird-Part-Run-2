"""
Q&A and RFI repositories — structured escalation chain tracking.

Separate from chat_repo.py because Q&A threads have distinct business
logic (escalation levels, assignment, RFI generation) that would clutter
the general chat repository.
"""

from __future__ import annotations

from app.repositories.base import BaseRepo


class QAThreadRepo(BaseRepo):
    """Repository for the `qa_threads` table."""
    TABLE = "qa_threads"
    HAS_UPDATED_AT = True

    async def create_thread(
        self,
        channel_id: int,
        job_id: int,
        asked_by: int,
        subject: str,
        priority: str = "normal",
        current_level: str = "worker",
        assigned_to: int | None = None,
    ) -> dict:
        """Create a Q&A thread and return it."""
        new_id = await self.insert({
            "channel_id": channel_id,
            "job_id": job_id,
            "asked_by": asked_by,
            "subject": subject,
            "priority": priority,
            "current_level": current_level,
            "assigned_to": assigned_to,
            "status": "open",
        })
        return dict(await self.get_by_id(new_id))

    async def get_thread_with_details(self, thread_id: int) -> dict | None:
        """Get a thread with user names and job info."""
        cursor = await self.db.execute(
            """
            SELECT qt.*,
                   asker.display_name  AS asker_name,
                   assignee.display_name AS assigned_name,
                   answerer.display_name AS answerer_name,
                   j.job_name, j.job_number,
                   (SELECT COUNT(*) FROM chat_messages cm
                    WHERE cm.qa_thread_id = qt.id AND cm.deleted_at IS NULL) AS message_count
            FROM qa_threads qt
            LEFT JOIN users asker    ON asker.id = qt.asked_by
            LEFT JOIN users assignee ON assignee.id = qt.assigned_to
            LEFT JOIN users answerer ON answerer.id = qt.answered_by
            LEFT JOIN jobs j         ON j.id = qt.job_id
            WHERE qt.id = ?
            """,
            (thread_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

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
        """List Q&A threads with optional filters."""
        conditions = []
        params: list = []

        if job_id:
            conditions.append("qt.job_id = ?")
            params.append(job_id)
        if status:
            conditions.append("qt.status = ?")
            params.append(status)
        if assigned_to:
            conditions.append("qt.assigned_to = ?")
            params.append(assigned_to)
        if priority:
            conditions.append("qt.priority = ?")
            params.append(priority)

        where = " AND ".join(conditions) if conditions else "1=1"
        params.extend([limit, offset])

        cursor = await self.db.execute(
            f"""
            SELECT qt.*,
                   asker.display_name AS asker_name,
                   assignee.display_name AS assigned_name,
                   answerer.display_name AS answerer_name,
                   j.job_name, j.job_number,
                   (SELECT COUNT(*) FROM chat_messages cm
                    WHERE cm.qa_thread_id = qt.id AND cm.deleted_at IS NULL) AS message_count
            FROM qa_threads qt
            LEFT JOIN users asker    ON asker.id = qt.asked_by
            LEFT JOIN users assignee ON assignee.id = qt.assigned_to
            LEFT JOIN users answerer ON answerer.id = qt.answered_by
            LEFT JOIN jobs j         ON j.id = qt.job_id
            WHERE {where}
            ORDER BY
                CASE qt.priority WHEN 'urgent' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END,
                qt.updated_at DESC
            LIMIT ? OFFSET ?
            """,
            tuple(params),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def escalate(
        self, thread_id: int, next_level: str, assigned_to: int | None
    ) -> bool:
        """Move thread to the next escalation level."""
        cursor = await self.db.execute(
            """UPDATE qa_threads
               SET current_level = ?, assigned_to = ?, status = 'escalated',
                   updated_at = datetime('now')
               WHERE id = ?""",
            (next_level, assigned_to, thread_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def answer(self, thread_id: int, answered_by: int) -> bool:
        """Mark thread as answered."""
        cursor = await self.db.execute(
            """UPDATE qa_threads
               SET status = 'answered', answered_by = ?, answered_at = datetime('now'),
                   updated_at = datetime('now')
               WHERE id = ?""",
            (answered_by, thread_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def close(self, thread_id: int) -> bool:
        """Close a thread."""
        cursor = await self.db.execute(
            """UPDATE qa_threads
               SET status = 'closed', closed_at = datetime('now'),
                   updated_at = datetime('now')
               WHERE id = ?""",
            (thread_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def mark_sent_to_gc(self, thread_id: int) -> bool:
        """Mark thread as sent to GC."""
        cursor = await self.db.execute(
            """UPDATE qa_threads
               SET status = 'sent_to_gc', updated_at = datetime('now')
               WHERE id = ?""",
            (thread_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def get_escalation_history(self, thread_id: int) -> list[dict]:
        """Get escalation timeline messages for a thread.

        Returns Q&A-typed messages (question, answer, escalation, system)
        in chronological order for the timeline visualization.
        """
        cursor = await self.db.execute(
            """
            SELECT cm.*, u.display_name AS sender_name
            FROM chat_messages cm
            JOIN users u ON u.id = cm.sender_id
            WHERE cm.qa_thread_id = ?
              AND cm.deleted_at IS NULL
              AND cm.message_type IN ('qa_question', 'qa_answer', 'qa_escalation', 'system')
            ORDER BY cm.created_at ASC
            """,
            (thread_id,),
        )
        return [dict(r) for r in await cursor.fetchall()]


class RFIRepo(BaseRepo):
    """Repository for the `rfi_objects` table."""
    TABLE = "rfi_objects"
    HAS_UPDATED_AT = True

    async def create_rfi(
        self,
        qa_thread_id: int,
        job_id: int,
        gc_contact_id: int,
        subject: str,
        body: str,
        created_by: int,
    ) -> dict:
        """Create an RFI record and return it."""
        new_id = await self.insert({
            "qa_thread_id": qa_thread_id,
            "job_id": job_id,
            "gc_contact_id": gc_contact_id,
            "subject": subject,
            "body": body,
            "status": "draft",
            "created_by": created_by,
        })
        return dict(await self.get_by_id(new_id))

    async def get_rfis_with_details(
        self,
        *,
        job_id: int | None = None,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List RFIs with joined GC contact and job info."""
        conditions = []
        params: list = []

        if job_id:
            conditions.append("r.job_id = ?")
            params.append(job_id)
        if status:
            conditions.append("r.status = ?")
            params.append(status)

        where = " AND ".join(conditions) if conditions else "1=1"
        params.extend([limit, offset])

        cursor = await self.db.execute(
            f"""
            SELECT r.*,
                   gc.company_name AS gc_name,
                   ec.phone AS gc_phone, ec.email AS gc_email,
                   ec.first_name || ' ' || ec.last_name AS gc_contact_name,
                   ec.role AS gc_contact_role,
                   j.job_name, j.job_number,
                   qt.subject AS thread_subject
            FROM rfi_objects r
            LEFT JOIN entity_contacts ec ON ec.id = r.gc_contact_id
            LEFT JOIN general_contractors gc
                   ON gc.id = ec.entity_id AND ec.entity_type = 'general_contractor'
            LEFT JOIN jobs j      ON j.id = r.job_id
            LEFT JOIN qa_threads qt ON qt.id = r.qa_thread_id
            WHERE {where}
            ORDER BY r.created_at DESC
            LIMIT ? OFFSET ?
            """,
            tuple(params),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def get_rfi_for_thread(self, qa_thread_id: int) -> dict | None:
        """Get the RFI linked to a Q&A thread (if any), with joined details."""
        cursor = await self.db.execute(
            """
            SELECT r.*,
                   gc.company_name AS gc_name,
                   ec.phone AS gc_phone, ec.email AS gc_email,
                   ec.first_name || ' ' || ec.last_name AS gc_contact_name,
                   ec.role AS gc_contact_role,
                   j.job_name, j.job_number,
                   qt.subject AS thread_subject
            FROM rfi_objects r
            LEFT JOIN entity_contacts ec ON ec.id = r.gc_contact_id
            LEFT JOIN general_contractors gc
                   ON gc.id = ec.entity_id AND ec.entity_type = 'general_contractor'
            LEFT JOIN jobs j      ON j.id = r.job_id
            LEFT JOIN qa_threads qt ON qt.id = r.qa_thread_id
            WHERE r.qa_thread_id = ?
            ORDER BY r.created_at DESC
            LIMIT 1
            """,
            (qa_thread_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def get_rfi_with_thread(self, rfi_id: int) -> dict | None:
        """Get a single RFI by ID with its linked Q&A thread info."""
        cursor = await self.db.execute(
            """
            SELECT r.*, qt.channel_id, qt.asked_by, qt.subject AS thread_subject,
                   gc.company_name AS gc_name,
                   ec.first_name || ' ' || ec.last_name AS gc_contact_name
            FROM rfi_objects r
            LEFT JOIN qa_threads qt ON qt.id = r.qa_thread_id
            LEFT JOIN entity_contacts ec ON ec.id = r.gc_contact_id
            LEFT JOIN general_contractors gc
                   ON gc.id = ec.entity_id AND ec.entity_type = 'general_contractor'
            WHERE r.id = ?
            """,
            (rfi_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def update_status(
        self,
        rfi_id: int,
        status: str,
        sent_via: str | None = None,
        response_text: str | None = None,
    ) -> bool:
        """Update RFI status and optional response."""
        data: dict = {"status": status}
        if sent_via:
            data["sent_via"] = sent_via
        if status in ("sent_text", "sent_email", "sent_app"):
            data["sent_at"] = "datetime('now')"
        if response_text:
            data["response_text"] = response_text
            data["responded_at"] = "datetime('now')"

        # Handle datetime('now') SQL expressions manually
        set_parts = []
        values = []
        for k, v in data.items():
            if v == "datetime('now')":
                set_parts.append(f"{k} = datetime('now')")
            else:
                set_parts.append(f"{k} = ?")
                values.append(v)
        set_parts.append("updated_at = datetime('now')")

        cursor = await self.db.execute(
            f"UPDATE rfi_objects SET {', '.join(set_parts)} WHERE id = ?",
            (*values, rfi_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0
