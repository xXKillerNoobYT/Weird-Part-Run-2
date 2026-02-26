"""
Questionnaire Service — Global clock-out questions, one-time per-job questions,
and clock-out bundle assembly.

Handles:
- CRUD for global questions (boss manages via Settings)
- Drag-to-reorder support
- One-time question creation/answering
- Bundle assembly for clock-out flow (all questions in one payload)
"""

from __future__ import annotations

import logging

import aiosqlite

from app.models.jobs import (
    ClockOutBundle,
    ClockOutQuestionCreate,
    ClockOutQuestionResponse,
    OneTimeQuestionCreate,
    OneTimeQuestionResponse,
)

logger = logging.getLogger(__name__)


class QuestionnaireService:
    """Clock-out question management and response capture."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Global Questions ──────────────────────────────────────────

    async def get_global_questions(self, active_only: bool = True) -> list[ClockOutQuestionResponse]:
        """List all global clock-out questions, ordered by sort_order."""
        condition = "WHERE is_active = 1" if active_only else ""
        cursor = await self.db.execute(
            f"SELECT * FROM clock_out_questions {condition} ORDER BY sort_order ASC"
        )
        rows = await cursor.fetchall()
        return [self._question_row_to_response(r) for r in rows]

    async def create_global_question(
        self, data: ClockOutQuestionCreate, created_by: int
    ) -> ClockOutQuestionResponse:
        """Create a new global clock-out question."""
        # Auto-assign sort_order as max + 1
        cursor = await self.db.execute(
            "SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_order FROM clock_out_questions"
        )
        row = await cursor.fetchone()
        sort_order = data.sort_order or row["next_order"]

        cursor = await self.db.execute(
            """INSERT INTO clock_out_questions (
                question_text, answer_type, is_required, sort_order, created_by
            ) VALUES (?, ?, ?, ?, ?)""",
            (data.question_text, data.answer_type, int(data.is_required), sort_order, created_by),
        )
        await self.db.commit()
        return await self._get_question(cursor.lastrowid)

    async def update_global_question(
        self, question_id: int, data: ClockOutQuestionCreate
    ) -> ClockOutQuestionResponse:
        """Update an existing global question."""
        await self.db.execute(
            """UPDATE clock_out_questions SET
                question_text = ?, answer_type = ?, is_required = ?,
                sort_order = ?, updated_at = datetime('now')
            WHERE id = ?""",
            (data.question_text, data.answer_type, int(data.is_required),
             data.sort_order, question_id),
        )
        await self.db.commit()
        return await self._get_question(question_id)

    async def deactivate_global_question(self, question_id: int) -> None:
        """Soft-delete a global question (set is_active = 0)."""
        await self.db.execute(
            "UPDATE clock_out_questions SET is_active = 0, updated_at = datetime('now') WHERE id = ?",
            (question_id,),
        )
        await self.db.commit()

    async def reorder_questions(self, ordered_ids: list[int]) -> None:
        """Reorder global questions by applying sort_order from the list position."""
        for idx, q_id in enumerate(ordered_ids):
            await self.db.execute(
                "UPDATE clock_out_questions SET sort_order = ? WHERE id = ?",
                (idx + 1, q_id),
            )
        await self.db.commit()

    # ── One-Time Questions ────────────────────────────────────────

    async def create_one_time_question(
        self, job_id: int, data: OneTimeQuestionCreate, created_by: int
    ) -> OneTimeQuestionResponse:
        """Boss sends a one-time question for a specific job/worker."""
        cursor = await self.db.execute(
            """INSERT INTO one_time_questions (
                job_id, target_user_id, question_text, answer_type, created_by
            ) VALUES (?, ?, ?, ?, ?)""",
            (job_id, data.target_user_id, data.question_text, data.answer_type, created_by),
        )
        await self.db.commit()
        return await self._get_one_time_question(cursor.lastrowid)

    async def get_one_time_questions_for_job(
        self, job_id: int, pending_only: bool = False
    ) -> list[OneTimeQuestionResponse]:
        """Get all one-time questions for a job."""
        condition = "AND otq.status = 'pending'" if pending_only else ""
        cursor = await self.db.execute(
            f"""SELECT otq.*,
                       tu.display_name AS target_user_name,
                       cu.display_name AS created_by_name
                FROM one_time_questions otq
                LEFT JOIN users tu ON tu.id = otq.target_user_id
                LEFT JOIN users cu ON cu.id = otq.created_by
                WHERE otq.job_id = ? {condition}
                ORDER BY otq.created_at DESC""",
            (job_id,),
        )
        rows = await cursor.fetchall()
        return [self._otq_row_to_response(r) for r in rows]

    async def get_pending_one_time_for_user(
        self, job_id: int, user_id: int
    ) -> list[OneTimeQuestionResponse]:
        """Get pending one-time questions for a specific user on a job.

        Returns questions targeted at this user OR at everyone (target_user_id IS NULL).
        """
        cursor = await self.db.execute(
            """SELECT otq.*,
                      tu.display_name AS target_user_name,
                      cu.display_name AS created_by_name
               FROM one_time_questions otq
               LEFT JOIN users tu ON tu.id = otq.target_user_id
               LEFT JOIN users cu ON cu.id = otq.created_by
               WHERE otq.job_id = ?
                 AND otq.status = 'pending'
                 AND (otq.target_user_id = ? OR otq.target_user_id IS NULL)
               ORDER BY otq.created_at ASC""",
            (job_id, user_id),
        )
        rows = await cursor.fetchall()
        return [self._otq_row_to_response(r) for r in rows]

    async def answer_one_time_question(
        self, question_id: int, answer_text: str | None, user_id: int,
        photo_path: str | None = None,
    ) -> OneTimeQuestionResponse:
        """Answer a one-time question."""
        await self.db.execute(
            """UPDATE one_time_questions SET
                status = 'answered',
                answered_by = ?,
                answer_text = ?,
                answer_photo_path = ?,
                answered_at = datetime('now')
            WHERE id = ? AND status = 'pending'""",
            (user_id, answer_text, photo_path, question_id),
        )
        await self.db.commit()
        return await self._get_one_time_question(question_id)

    # ── Clock-Out Bundle ──────────────────────────────────────────

    async def get_clock_out_bundle(self, job_id: int, user_id: int) -> ClockOutBundle:
        """Assemble everything needed for the clock-out flow.

        Returns global questions (active, sorted) + pending one-time questions
        for this user on this job.
        """
        global_questions = await self.get_global_questions(active_only=True)
        one_time_questions = await self.get_pending_one_time_for_user(job_id, user_id)
        return ClockOutBundle(
            global_questions=global_questions,
            one_time_questions=one_time_questions,
        )

    # ── Helpers ───────────────────────────────────────────────────

    async def _get_question(self, question_id: int) -> ClockOutQuestionResponse:
        cursor = await self.db.execute(
            "SELECT * FROM clock_out_questions WHERE id = ?", (question_id,)
        )
        row = await cursor.fetchone()
        return self._question_row_to_response(row)

    async def _get_one_time_question(self, question_id: int) -> OneTimeQuestionResponse:
        cursor = await self.db.execute(
            """SELECT otq.*,
                      tu.display_name AS target_user_name,
                      cu.display_name AS created_by_name
               FROM one_time_questions otq
               LEFT JOIN users tu ON tu.id = otq.target_user_id
               LEFT JOIN users cu ON cu.id = otq.created_by
               WHERE otq.id = ?""",
            (question_id,),
        )
        row = await cursor.fetchone()
        return self._otq_row_to_response(row)

    def _question_row_to_response(self, row: aiosqlite.Row) -> ClockOutQuestionResponse:
        return ClockOutQuestionResponse(
            id=row["id"],
            question_text=row["question_text"],
            answer_type=row["answer_type"],
            is_required=bool(row["is_required"]),
            sort_order=row["sort_order"],
            is_active=bool(row["is_active"]),
            created_at=row["created_at"],
        )

    def _otq_row_to_response(self, row: aiosqlite.Row) -> OneTimeQuestionResponse:
        return OneTimeQuestionResponse(
            id=row["id"],
            job_id=row["job_id"],
            target_user_id=row["target_user_id"],
            target_user_name=row["target_user_name"],
            question_text=row["question_text"],
            answer_type=row["answer_type"],
            status=row["status"],
            created_by=row["created_by"],
            created_by_name=row["created_by_name"],
            answered_by=row["answered_by"],
            answer_text=row["answer_text"],
            answer_photo_path=row["answer_photo_path"],
            created_at=row["created_at"],
            answered_at=row["answered_at"],
        )
