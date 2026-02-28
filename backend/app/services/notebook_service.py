"""
Notebook Service — CRUD for templates, notebooks, sections, and entries.

Handles template management (Office), notebook lifecycle (job + general),
section/entry CRUD with OneNote-like permissions, task status transitions,
first-fill field logic, and cross-cutting task aggregation.
"""

from __future__ import annotations

import logging

import aiosqlite

from app.models.notebooks import (
    EntryCreate,
    EntryResponse,
    EntryUpdate,
    NotebookCreate,
    NotebookFull,
    NotebookListItem,
    NotebookResponse,
    NotebookUpdate,
    SectionCreate,
    SectionResponse,
    SectionUpdate,
    SectionWithEntries,
    TaskSummary,
    TemplateCreate,
    TemplateEntryCreate,
    TemplateEntryResponse,
    TemplateFull,
    TemplateResponse,
    TemplateSectionCreate,
    TemplateSectionResponse,
    TemplateSectionUpdate,
    TemplateSectionWithEntries,
    TemplateUpdate,
)

logger = logging.getLogger(__name__)


class NotebookService:
    """Full CRUD for notebooks, templates, sections, entries, and permissions."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ═══════════════════════════════════════════════════════════════════
    # TEMPLATES
    # ═══════════════════════════════════════════════════════════════════

    async def get_templates(self) -> list[TemplateResponse]:
        """List all notebook templates."""
        cursor = await self.db.execute(
            "SELECT * FROM notebook_templates ORDER BY is_default DESC, name ASC"
        )
        rows = await cursor.fetchall()
        return [self._row_to_template(r) for r in rows]

    async def get_template_full(self, template_id: int) -> TemplateFull | None:
        """Get a template with all sections and entries."""
        cursor = await self.db.execute(
            "SELECT * FROM notebook_templates WHERE id = ?", (template_id,)
        )
        tmpl = await cursor.fetchone()
        if not tmpl:
            return None

        # Fetch sections
        cursor = await self.db.execute(
            "SELECT * FROM template_sections WHERE template_id = ? ORDER BY sort_order",
            (template_id,),
        )
        sections = await cursor.fetchall()

        section_list: list[TemplateSectionWithEntries] = []
        for sec in sections:
            cursor = await self.db.execute(
                "SELECT * FROM template_entries WHERE section_id = ? ORDER BY sort_order",
                (sec["id"],),
            )
            entries = await cursor.fetchall()
            section_list.append(
                TemplateSectionWithEntries(
                    id=sec["id"],
                    template_id=sec["template_id"],
                    name=sec["name"],
                    section_type=sec["section_type"],
                    sort_order=sec["sort_order"],
                    is_locked=bool(sec["is_locked"]),
                    entries=[
                        TemplateEntryResponse(
                            id=e["id"], section_id=e["section_id"],
                            title=e["title"], default_content=e["default_content"],
                            entry_type=e["entry_type"], field_type=e["field_type"],
                            field_required=bool(e["field_required"]),
                            sort_order=e["sort_order"],
                        )
                        for e in entries
                    ],
                )
            )

        return TemplateFull(
            id=tmpl["id"], name=tmpl["name"],
            description=tmpl["description"], job_type=tmpl["job_type"],
            is_default=bool(tmpl["is_default"]),
            created_by=tmpl["created_by"],
            created_at=tmpl["created_at"], updated_at=tmpl["updated_at"],
            sections=section_list,
        )

    async def create_template(
        self, data: TemplateCreate, created_by: int
    ) -> TemplateResponse:
        """Create a new notebook template."""
        # If setting as default, clear existing default
        if data.is_default:
            await self.db.execute(
                "UPDATE notebook_templates SET is_default = 0"
            )

        cursor = await self.db.execute(
            """INSERT INTO notebook_templates (name, description, job_type, is_default, created_by)
               VALUES (?, ?, ?, ?, ?)""",
            (data.name, data.description, data.job_type,
             1 if data.is_default else 0, created_by),
        )
        await self.db.commit()
        return self._row_to_template(
            await self._fetch_one("notebook_templates", cursor.lastrowid)
        )

    async def update_template(
        self, template_id: int, data: TemplateUpdate
    ) -> TemplateResponse | None:
        """Update template metadata."""
        row = await self._fetch_one("notebook_templates", template_id)
        if not row:
            return None

        updates, params = self._build_updates(data)
        if data.is_default is True:
            await self.db.execute(
                "UPDATE notebook_templates SET is_default = 0"
            )

        if updates:
            updates.append("updated_at = datetime('now')")
            params.append(template_id)
            await self.db.execute(
                f"UPDATE notebook_templates SET {', '.join(updates)} WHERE id = ?",
                params,
            )
            await self.db.commit()

        return self._row_to_template(
            await self._fetch_one("notebook_templates", template_id)
        )

    async def delete_template(self, template_id: int) -> bool:
        """Delete a template (CASCADE removes sections and entries)."""
        await self.db.execute(
            "DELETE FROM notebook_templates WHERE id = ?", (template_id,)
        )
        await self.db.commit()
        return True

    # ── Template Sections ──────────────────────────────────────────

    async def add_template_section(
        self, template_id: int, data: TemplateSectionCreate
    ) -> TemplateSectionResponse:
        """Add a section to a template."""
        cursor = await self.db.execute(
            """INSERT INTO template_sections
                   (template_id, name, section_type, sort_order, is_locked)
               VALUES (?, ?, ?, ?, ?)""",
            (template_id, data.name, data.section_type,
             data.sort_order, 1 if data.is_locked else 0),
        )
        await self.db.commit()
        row = await self._fetch_one("template_sections", cursor.lastrowid)
        return self._row_to_template_section(row)

    async def update_template_section(
        self, section_id: int, data: TemplateSectionUpdate
    ) -> TemplateSectionResponse | None:
        """Update a template section."""
        row = await self._fetch_one("template_sections", section_id)
        if not row:
            return None

        updates, params = self._build_updates(data)
        if updates:
            params.append(section_id)
            await self.db.execute(
                f"UPDATE template_sections SET {', '.join(updates)} WHERE id = ?",
                params,
            )
            await self.db.commit()

        return self._row_to_template_section(
            await self._fetch_one("template_sections", section_id)
        )

    async def delete_template_section(self, section_id: int) -> bool:
        """Delete a template section (CASCADE removes entries)."""
        await self.db.execute(
            "DELETE FROM template_sections WHERE id = ?", (section_id,)
        )
        await self.db.commit()
        return True

    # ── Template Entries ───────────────────────────────────────────

    async def add_template_entry(
        self, section_id: int, data: TemplateEntryCreate
    ) -> TemplateEntryResponse:
        """Add an entry to a template section."""
        cursor = await self.db.execute(
            """INSERT INTO template_entries
                   (section_id, title, default_content, entry_type,
                    field_type, field_required, sort_order)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (section_id, data.title, data.default_content, data.entry_type,
             data.field_type, 1 if data.field_required else 0, data.sort_order),
        )
        await self.db.commit()
        e = await self._fetch_one("template_entries", cursor.lastrowid)
        return TemplateEntryResponse(
            id=e["id"], section_id=e["section_id"],
            title=e["title"], default_content=e["default_content"],
            entry_type=e["entry_type"], field_type=e["field_type"],
            field_required=bool(e["field_required"]),
            sort_order=e["sort_order"],
        )

    async def delete_template_entry(self, entry_id: int) -> bool:
        """Delete a template entry."""
        await self.db.execute(
            "DELETE FROM template_entries WHERE id = ?", (entry_id,)
        )
        await self.db.commit()
        return True

    # ═══════════════════════════════════════════════════════════════════
    # NOTEBOOKS
    # ═══════════════════════════════════════════════════════════════════

    async def create_notebook(
        self, data: NotebookCreate, created_by: int
    ) -> NotebookResponse:
        """Create a general (non-job) notebook."""
        cursor = await self.db.execute(
            """INSERT INTO notebooks (title, description, created_by)
               VALUES (?, ?, ?)""",
            (data.title, data.description, created_by),
        )
        await self.db.commit()
        return await self._get_notebook_response(cursor.lastrowid)

    async def create_job_notebook(
        self, job_id: int, user_id: int
    ) -> int:
        """Create a job notebook from the default template.

        Copies the template structure (sections + entries) into a real
        notebook. Entry content starts empty — workers fill it in.
        Returns the new notebook ID.
        """
        # Find default template
        template = await self._get_default_template()
        template_id = template["id"] if template else None

        # Get job info for the title
        cursor = await self.db.execute(
            "SELECT job_name, job_number FROM jobs WHERE id = ?", (job_id,)
        )
        job = await cursor.fetchone()
        title = f"Job Notebook"
        if job:
            title = f"{job['job_number']} — {job['job_name']}"

        # Create the notebook
        cursor = await self.db.execute(
            """INSERT INTO notebooks (title, job_id, template_id, created_by)
               VALUES (?, ?, ?, ?)""",
            (title, job_id, template_id, user_id),
        )
        nb_id = cursor.lastrowid

        # Copy template sections and entries if template exists
        if template_id:
            tmpl_full = await self.get_template_full(template_id)
            if tmpl_full:
                for sec in tmpl_full.sections:
                    sec_cursor = await self.db.execute(
                        """INSERT INTO notebook_sections
                               (notebook_id, name, section_type, sort_order, is_locked)
                           VALUES (?, ?, ?, ?, ?)""",
                        (nb_id, sec.name, sec.section_type,
                         sec.sort_order, 1 if sec.is_locked else 0),
                    )
                    new_sec_id = sec_cursor.lastrowid

                    for entry in sec.entries:
                        # Tasks start as 'planned'; fields/notes have no status
                        task_status = "planned" if entry.entry_type == "task" else None
                        await self.db.execute(
                            """INSERT INTO notebook_entries
                                   (section_id, title, content, entry_type,
                                    field_type, field_required, task_status,
                                    sort_order, created_by)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                            (new_sec_id, entry.title, entry.default_content,
                             entry.entry_type, entry.field_type,
                             1 if entry.field_required else 0,
                             task_status, entry.sort_order, user_id),
                        )

        await self.db.commit()
        return nb_id

    async def get_or_create_job_notebook(
        self, job_id: int, user_id: int
    ) -> NotebookFull:
        """Lazy-create: return existing job notebook or create from template."""
        cursor = await self.db.execute(
            "SELECT id FROM notebooks WHERE job_id = ? AND is_archived = 0",
            (job_id,),
        )
        row = await cursor.fetchone()
        if row:
            nb_id = row["id"]
        else:
            nb_id = await self.create_job_notebook(job_id, user_id)

        return await self.get_notebook_full(nb_id, user_id)

    async def get_notebook_full(
        self, notebook_id: int, user_id: int
    ) -> NotebookFull | None:
        """Get a notebook with all sections and entries.

        Computes `can_edit` per entry based on user permissions.
        """
        nb = await self._get_notebook_response(notebook_id)
        if not nb:
            return None

        is_manager = await self._user_has_permission(user_id, "manage_notebooks")

        # Fetch sections
        cursor = await self.db.execute(
            """SELECT * FROM notebook_sections
               WHERE notebook_id = ?
               ORDER BY sort_order""",
            (notebook_id,),
        )
        sections = await cursor.fetchall()

        section_list: list[SectionWithEntries] = []
        for sec in sections:
            # Fetch entries for this section (exclude soft-deleted for non-managers)
            if is_manager:
                cursor = await self.db.execute(
                    """SELECT e.*,
                              u_creator.display_name AS creator_name,
                              u_assigned.display_name AS task_assigned_to_name,
                              u_filled.display_name AS field_filled_by_name
                       FROM notebook_entries e
                       LEFT JOIN users u_creator ON u_creator.id = e.created_by
                       LEFT JOIN users u_assigned ON u_assigned.id = e.task_assigned_to
                       LEFT JOIN users u_filled ON u_filled.id = e.field_filled_by
                       WHERE e.section_id = ? AND e.is_deleted = 0
                       ORDER BY e.sort_order""",
                    (sec["id"],),
                )
            else:
                cursor = await self.db.execute(
                    """SELECT e.*,
                              u_creator.display_name AS creator_name,
                              u_assigned.display_name AS task_assigned_to_name,
                              u_filled.display_name AS field_filled_by_name
                       FROM notebook_entries e
                       LEFT JOIN users u_creator ON u_creator.id = e.created_by
                       LEFT JOIN users u_assigned ON u_assigned.id = e.task_assigned_to
                       LEFT JOIN users u_filled ON u_filled.id = e.field_filled_by
                       WHERE e.section_id = ? AND e.is_deleted = 0
                       ORDER BY e.sort_order""",
                    (sec["id"],),
                )
            entries = await cursor.fetchall()

            # Get delegated permissions for this user
            delegated_entry_ids: set[int] = set()
            if not is_manager:
                cursor = await self.db.execute(
                    """SELECT entry_id FROM notebook_entry_permissions
                       WHERE user_id = ? AND entry_id IN (
                           SELECT id FROM notebook_entries WHERE section_id = ?
                       )""",
                    (user_id, sec["id"]),
                )
                delegated_entry_ids = {r["entry_id"] for r in await cursor.fetchall()}

            entry_list = []
            for e in entries:
                can_edit = self._compute_can_edit(e, user_id, is_manager, delegated_entry_ids)
                entry_list.append(self._row_to_entry(e, can_edit))

            section_list.append(
                SectionWithEntries(
                    id=sec["id"],
                    notebook_id=sec["notebook_id"],
                    name=sec["name"],
                    section_type=sec["section_type"],
                    sort_order=sec["sort_order"],
                    is_locked=bool(sec["is_locked"]),
                    created_at=sec["created_at"],
                    entries=entry_list,
                )
            )

        return NotebookFull(notebook=nb, sections=section_list)

    async def list_notebooks(
        self,
        filter_type: str | None = None,
        search: str | None = None,
    ) -> list[NotebookListItem]:
        """List notebooks with optional filter.

        filter_type: 'job' | 'general' | None (all)
        """
        conditions = ["n.is_archived = 0"]
        params: list = []

        if filter_type == "job":
            conditions.append("n.job_id IS NOT NULL")
        elif filter_type == "general":
            conditions.append("n.job_id IS NULL")

        if search:
            conditions.append(
                "(n.title LIKE ? OR j.job_number LIKE ? OR j.job_name LIKE ?)"
            )
            term = f"%{search}%"
            params.extend([term, term, term])

        where = " AND ".join(conditions)

        cursor = await self.db.execute(
            f"""SELECT n.*,
                       j.job_name, j.job_number,
                       COALESCE(tasks.open_count, 0) AS open_task_count,
                       COALESCE(tasks.total_count, 0) AS total_task_count
                FROM notebooks n
                LEFT JOIN jobs j ON j.id = n.job_id
                LEFT JOIN (
                    SELECT s.notebook_id,
                           COUNT(CASE WHEN e.task_status != 'done' THEN 1 END) AS open_count,
                           COUNT(*) AS total_count
                    FROM notebook_sections s
                    JOIN notebook_entries e ON e.section_id = s.id
                    WHERE e.entry_type = 'task' AND e.is_deleted = 0
                    GROUP BY s.notebook_id
                ) tasks ON tasks.notebook_id = n.id
                WHERE {where}
                ORDER BY n.updated_at DESC""",
            params,
        )
        rows = await cursor.fetchall()
        return [
            NotebookListItem(
                id=r["id"], title=r["title"], description=r["description"],
                job_id=r["job_id"], job_name=r["job_name"],
                job_number=r["job_number"],
                is_archived=bool(r["is_archived"]),
                open_task_count=r["open_task_count"],
                total_task_count=r["total_task_count"],
                created_at=r["created_at"], updated_at=r["updated_at"],
            )
            for r in rows
        ]

    async def update_notebook(
        self, notebook_id: int, data: NotebookUpdate
    ) -> NotebookResponse | None:
        """Update notebook title/description."""
        updates, params = self._build_updates(data)
        if not updates:
            return await self._get_notebook_response(notebook_id)

        updates.append("updated_at = datetime('now')")
        params.append(notebook_id)
        await self.db.execute(
            f"UPDATE notebooks SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        await self.db.commit()
        return await self._get_notebook_response(notebook_id)

    async def archive_notebook(self, notebook_id: int) -> bool:
        """Archive (soft-delete) a notebook."""
        await self.db.execute(
            "UPDATE notebooks SET is_archived = 1, updated_at = datetime('now') WHERE id = ?",
            (notebook_id,),
        )
        await self.db.commit()
        return True

    # ═══════════════════════════════════════════════════════════════════
    # SECTIONS
    # ═══════════════════════════════════════════════════════════════════

    async def create_section(
        self, notebook_id: int, data: SectionCreate
    ) -> SectionResponse:
        """Workers add custom sections (notes or tasks only)."""
        # Workers can't create 'info' sections — those come from templates
        section_type = data.section_type
        if section_type == "info":
            section_type = "notes"

        # Auto sort_order at end
        sort_order = data.sort_order
        if sort_order is None:
            cursor = await self.db.execute(
                "SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_order "
                "FROM notebook_sections WHERE notebook_id = ?",
                (notebook_id,),
            )
            row = await cursor.fetchone()
            sort_order = row["next_order"]

        cursor = await self.db.execute(
            """INSERT INTO notebook_sections
                   (notebook_id, name, section_type, sort_order)
               VALUES (?, ?, ?, ?)""",
            (notebook_id, data.name, section_type, sort_order),
        )
        await self.db.commit()
        row = await self._fetch_one("notebook_sections", cursor.lastrowid)
        return self._row_to_section(row)

    async def update_section(
        self, section_id: int, data: SectionUpdate
    ) -> SectionResponse | None:
        """Rename or reorder a section."""
        row = await self._fetch_one("notebook_sections", section_id)
        if not row:
            return None

        updates, params = self._build_updates(data)
        if updates:
            params.append(section_id)
            await self.db.execute(
                f"UPDATE notebook_sections SET {', '.join(updates)} WHERE id = ?",
                params,
            )
            await self.db.commit()

        return self._row_to_section(
            await self._fetch_one("notebook_sections", section_id)
        )

    async def delete_section(self, section_id: int) -> bool:
        """Delete a section (CASCADE removes entries)."""
        # Don't allow deleting locked sections
        row = await self._fetch_one("notebook_sections", section_id)
        if row and row["is_locked"]:
            return False

        await self.db.execute(
            "DELETE FROM notebook_sections WHERE id = ? AND is_locked = 0",
            (section_id,),
        )
        await self.db.commit()
        return True

    async def reorder_sections(
        self, notebook_id: int, ordered_ids: list[int]
    ) -> list[SectionResponse]:
        """Bulk reorder sections by setting sort_order from list position."""
        for idx, sec_id in enumerate(ordered_ids):
            await self.db.execute(
                "UPDATE notebook_sections SET sort_order = ? "
                "WHERE id = ? AND notebook_id = ?",
                (idx, sec_id, notebook_id),
            )
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM notebook_sections WHERE notebook_id = ? ORDER BY sort_order",
            (notebook_id,),
        )
        rows = await cursor.fetchall()
        return [self._row_to_section(r) for r in rows]

    # ═══════════════════════════════════════════════════════════════════
    # ENTRIES
    # ═══════════════════════════════════════════════════════════════════

    async def create_entry(
        self, section_id: int, data: EntryCreate, created_by: int
    ) -> EntryResponse:
        """Create a note, task, or field entry."""
        # Default task status to 'planned' for new tasks
        task_status = data.task_status
        if data.entry_type == "task" and not task_status:
            task_status = "planned"

        # Auto sort_order
        sort_order = data.sort_order
        if sort_order is None:
            cursor = await self.db.execute(
                "SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_order "
                "FROM notebook_entries WHERE section_id = ?",
                (section_id,),
            )
            row = await cursor.fetchone()
            sort_order = row["next_order"]

        cursor = await self.db.execute(
            """INSERT INTO notebook_entries
                   (section_id, title, content, entry_type,
                    field_type, field_required, task_status,
                    task_due_date, task_assigned_to, task_parts_note,
                    sort_order, created_by)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (section_id, data.title, data.content, data.entry_type,
             data.field_type, 1 if data.field_required else 0,
             task_status, data.task_due_date, data.task_assigned_to,
             data.task_parts_note, sort_order, created_by),
        )
        await self.db.commit()

        # Touch notebook updated_at
        await self._touch_notebook_from_section(section_id)

        return await self._get_entry_response(cursor.lastrowid, created_by)

    async def update_entry(
        self, entry_id: int, data: EntryUpdate, user_id: int
    ) -> EntryResponse | None:
        """Update an entry (permission-checked)."""
        entry = await self._fetch_one("notebook_entries", entry_id)
        if not entry:
            return None

        # Permission check
        is_manager = await self._user_has_permission(user_id, "manage_notebooks")
        if not is_manager:
            can_edit = await self._can_user_edit_entry(entry_id, user_id)
            if not can_edit:
                return None

        updates, params = self._build_updates(data)
        if updates:
            updates.extend([
                "updated_by = ?",
                "updated_at = datetime('now')",
            ])
            params.extend([user_id, entry_id])
            await self.db.execute(
                f"UPDATE notebook_entries SET {', '.join(updates)} WHERE id = ?",
                params,
            )
            await self.db.commit()
            await self._touch_notebook_from_entry(entry_id)

        return await self._get_entry_response(entry_id, user_id)

    async def update_field_value(
        self, entry_id: int, value: str | None, user_id: int
    ) -> EntryResponse | None:
        """Update a field value with first-fill logic.

        - Empty field → anyone can fill (sets field_filled_by)
        - Filled field → only managers can change
        """
        entry = await self._fetch_one("notebook_entries", entry_id)
        if not entry or entry["entry_type"] != "field":
            return None

        is_manager = await self._user_has_permission(user_id, "manage_notebooks")

        # First-fill: anyone can set an empty field
        if entry["field_filled_by"] and not is_manager:
            # Field already filled, only managers can change
            return None

        filled_by = entry["field_filled_by"] or user_id
        await self.db.execute(
            """UPDATE notebook_entries
               SET content = ?, field_filled_by = ?,
                   updated_by = ?, updated_at = datetime('now')
               WHERE id = ?""",
            (value, filled_by, user_id, entry_id),
        )
        await self.db.commit()
        await self._touch_notebook_from_entry(entry_id)
        return await self._get_entry_response(entry_id, user_id)

    async def update_task_status(
        self,
        entry_id: int,
        new_status: str,
        user_id: int,
        parts_note: str | None = None,
    ) -> EntryResponse | None:
        """Transition a task's stage.

        When moving to 'parts_ordered', a parts_note is expected.
        """
        entry = await self._fetch_one("notebook_entries", entry_id)
        if not entry or entry["entry_type"] != "task":
            return None

        valid_statuses = {
            "planned", "parts_ordered", "parts_delivered", "in_progress", "done"
        }
        if new_status not in valid_statuses:
            return None

        updates = [
            "task_status = ?",
            "updated_by = ?",
            "updated_at = datetime('now')",
        ]
        params: list = [new_status, user_id]

        # Save parts note when transitioning to parts_ordered
        if new_status == "parts_ordered" and parts_note is not None:
            updates.append("task_parts_note = ?")
            params.append(parts_note)

        params.append(entry_id)
        await self.db.execute(
            f"UPDATE notebook_entries SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        await self.db.commit()
        await self._touch_notebook_from_entry(entry_id)
        return await self._get_entry_response(entry_id, user_id)

    async def assign_task(
        self, entry_id: int, target_user_id: int | None, user_id: int
    ) -> EntryResponse | None:
        """Assign a task to a user. Managers can assign anyone; workers self-assign."""
        entry = await self._fetch_one("notebook_entries", entry_id)
        if not entry or entry["entry_type"] != "task":
            return None

        is_manager = await self._user_has_permission(user_id, "manage_notebooks")

        # Workers can only self-assign
        if not is_manager and target_user_id is not None and target_user_id != user_id:
            return None

        await self.db.execute(
            """UPDATE notebook_entries
               SET task_assigned_to = ?, updated_by = ?, updated_at = datetime('now')
               WHERE id = ?""",
            (target_user_id, user_id, entry_id),
        )
        await self.db.commit()
        return await self._get_entry_response(entry_id, user_id)

    async def soft_delete_entry(self, entry_id: int, user_id: int) -> bool:
        """Creator soft-deletes (hides) their own entry."""
        entry = await self._fetch_one("notebook_entries", entry_id)
        if not entry:
            return False

        is_manager = await self._user_has_permission(user_id, "manage_notebooks")
        if not is_manager and entry["created_by"] != user_id:
            return False

        await self.db.execute(
            """UPDATE notebook_entries
               SET is_deleted = 1, deleted_by = ?, deleted_at = datetime('now')
               WHERE id = ?""",
            (user_id, entry_id),
        )
        await self.db.commit()
        return True

    async def hard_delete_entry(self, entry_id: int, user_id: int) -> bool:
        """Manager permanently deletes an entry."""
        is_manager = await self._user_has_permission(user_id, "manage_notebooks")
        if not is_manager:
            return False

        await self.db.execute(
            "DELETE FROM notebook_entries WHERE id = ?", (entry_id,)
        )
        await self.db.commit()
        return True

    # ═══════════════════════════════════════════════════════════════════
    # PERMISSIONS
    # ═══════════════════════════════════════════════════════════════════

    async def grant_edit(
        self, entry_id: int, target_user_id: int, granted_by: int
    ) -> bool:
        """Grant delegated edit access to another user."""
        try:
            await self.db.execute(
                """INSERT OR IGNORE INTO notebook_entry_permissions
                       (entry_id, user_id, granted_by)
                   VALUES (?, ?, ?)""",
                (entry_id, target_user_id, granted_by),
            )
            await self.db.commit()
            return True
        except Exception:
            return False

    async def revoke_edit(self, entry_id: int, target_user_id: int) -> bool:
        """Revoke delegated edit access."""
        await self.db.execute(
            "DELETE FROM notebook_entry_permissions WHERE entry_id = ? AND user_id = ?",
            (entry_id, target_user_id),
        )
        await self.db.commit()
        return True

    # ═══════════════════════════════════════════════════════════════════
    # TASK CROSS-CUTTING
    # ═══════════════════════════════════════════════════════════════════

    async def get_job_tasks(
        self, job_id: int, status: str | None = None
    ) -> list[EntryResponse]:
        """Get all tasks across all sections for a job's notebook."""
        conditions = [
            "n.job_id = ?",
            "e.entry_type = 'task'",
            "e.is_deleted = 0",
        ]
        params: list = [job_id]

        if status:
            conditions.append("e.task_status = ?")
            params.append(status)

        where = " AND ".join(conditions)
        cursor = await self.db.execute(
            f"""SELECT e.*,
                       u_creator.display_name AS creator_name,
                       u_assigned.display_name AS task_assigned_to_name,
                       u_filled.display_name AS field_filled_by_name
                FROM notebook_entries e
                JOIN notebook_sections s ON s.id = e.section_id
                JOIN notebooks n ON n.id = s.notebook_id
                LEFT JOIN users u_creator ON u_creator.id = e.created_by
                LEFT JOIN users u_assigned ON u_assigned.id = e.task_assigned_to
                LEFT JOIN users u_filled ON u_filled.id = e.field_filled_by
                WHERE {where}
                ORDER BY s.sort_order, e.sort_order""",
            params,
        )
        rows = await cursor.fetchall()
        return [self._row_to_entry(r, can_edit=False) for r in rows]

    async def get_open_task_count(self, job_id: int) -> int:
        """Count non-done tasks for a job."""
        cursor = await self.db.execute(
            """SELECT COUNT(*) AS cnt
               FROM notebook_entries e
               JOIN notebook_sections s ON s.id = e.section_id
               JOIN notebooks n ON n.id = s.notebook_id
               WHERE n.job_id = ? AND e.entry_type = 'task'
                     AND e.task_status != 'done' AND e.is_deleted = 0""",
            (job_id,),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_task_summary(self, job_id: int) -> TaskSummary:
        """Get task counts by status for a job."""
        cursor = await self.db.execute(
            """SELECT
                   SUM(CASE WHEN e.task_status = 'planned' THEN 1 ELSE 0 END) AS planned,
                   SUM(CASE WHEN e.task_status = 'parts_ordered' THEN 1 ELSE 0 END) AS parts_ordered,
                   SUM(CASE WHEN e.task_status = 'parts_delivered' THEN 1 ELSE 0 END) AS parts_delivered,
                   SUM(CASE WHEN e.task_status = 'in_progress' THEN 1 ELSE 0 END) AS in_progress,
                   SUM(CASE WHEN e.task_status = 'done' THEN 1 ELSE 0 END) AS done,
                   SUM(CASE WHEN e.task_status != 'done' THEN 1 ELSE 0 END) AS total_open
               FROM notebook_entries e
               JOIN notebook_sections s ON s.id = e.section_id
               JOIN notebooks n ON n.id = s.notebook_id
               WHERE n.job_id = ? AND e.entry_type = 'task' AND e.is_deleted = 0""",
            (job_id,),
        )
        row = await cursor.fetchone()
        if not row or row["planned"] is None:
            return TaskSummary()
        return TaskSummary(
            planned=row["planned"] or 0,
            parts_ordered=row["parts_ordered"] or 0,
            parts_delivered=row["parts_delivered"] or 0,
            in_progress=row["in_progress"] or 0,
            done=row["done"] or 0,
            total_open=row["total_open"] or 0,
        )

    # ═══════════════════════════════════════════════════════════════════
    # INTERNAL HELPERS
    # ═══════════════════════════════════════════════════════════════════

    async def _fetch_one(self, table: str, row_id: int) -> dict | None:
        """Fetch a single row by ID."""
        cursor = await self.db.execute(
            f"SELECT * FROM {table} WHERE id = ?", (row_id,)
        )
        return await cursor.fetchone()

    async def _get_default_template(self) -> dict | None:
        """Get the default template (is_default = 1), or first template."""
        cursor = await self.db.execute(
            "SELECT * FROM notebook_templates WHERE is_default = 1 LIMIT 1"
        )
        row = await cursor.fetchone()
        if not row:
            cursor = await self.db.execute(
                "SELECT * FROM notebook_templates ORDER BY id LIMIT 1"
            )
            row = await cursor.fetchone()
        return row

    async def _get_notebook_response(self, notebook_id: int) -> NotebookResponse | None:
        """Build a NotebookResponse with joined job info."""
        cursor = await self.db.execute(
            """SELECT n.*, j.job_name, j.job_number,
                      u.display_name AS creator_name
               FROM notebooks n
               LEFT JOIN jobs j ON j.id = n.job_id
               LEFT JOIN users u ON u.id = n.created_by
               WHERE n.id = ?""",
            (notebook_id,),
        )
        r = await cursor.fetchone()
        if not r:
            return None
        return NotebookResponse(
            id=r["id"], title=r["title"], description=r["description"],
            job_id=r["job_id"], job_name=r["job_name"],
            job_number=r["job_number"], template_id=r["template_id"],
            created_by=r["created_by"], creator_name=r["creator_name"],
            is_archived=bool(r["is_archived"]),
            created_at=r["created_at"], updated_at=r["updated_at"],
        )

    async def _get_entry_response(
        self, entry_id: int, user_id: int
    ) -> EntryResponse | None:
        """Build an EntryResponse with joined user names and can_edit."""
        cursor = await self.db.execute(
            """SELECT e.*,
                      u_creator.display_name AS creator_name,
                      u_assigned.display_name AS task_assigned_to_name,
                      u_filled.display_name AS field_filled_by_name
               FROM notebook_entries e
               LEFT JOIN users u_creator ON u_creator.id = e.created_by
               LEFT JOIN users u_assigned ON u_assigned.id = e.task_assigned_to
               LEFT JOIN users u_filled ON u_filled.id = e.field_filled_by
               WHERE e.id = ?""",
            (entry_id,),
        )
        e = await cursor.fetchone()
        if not e:
            return None

        is_manager = await self._user_has_permission(user_id, "manage_notebooks")
        delegated = set()
        if not is_manager:
            cursor = await self.db.execute(
                "SELECT entry_id FROM notebook_entry_permissions WHERE entry_id = ? AND user_id = ?",
                (entry_id, user_id),
            )
            delegated = {r["entry_id"] for r in await cursor.fetchall()}

        can_edit = self._compute_can_edit(e, user_id, is_manager, delegated)
        return self._row_to_entry(e, can_edit)

    async def _can_user_edit_entry(self, entry_id: int, user_id: int) -> bool:
        """Check if user can edit: creator OR manager OR delegated."""
        entry = await self._fetch_one("notebook_entries", entry_id)
        if not entry:
            return False

        if entry["created_by"] == user_id:
            return True

        if await self._user_has_permission(user_id, "manage_notebooks"):
            return True

        cursor = await self.db.execute(
            "SELECT 1 FROM notebook_entry_permissions WHERE entry_id = ? AND user_id = ?",
            (entry_id, user_id),
        )
        return await cursor.fetchone() is not None

    async def _user_has_permission(self, user_id: int, permission: str) -> bool:
        """Check if user has a specific permission."""
        cursor = await self.db.execute(
            """SELECT 1 FROM user_permissions up
               JOIN permissions p ON p.id = up.permission_id
               WHERE up.user_id = ? AND p.name = ?""",
            (user_id, permission),
        )
        return await cursor.fetchone() is not None

    async def _touch_notebook_from_section(self, section_id: int) -> None:
        """Update notebook's updated_at from a section ID."""
        await self.db.execute(
            """UPDATE notebooks SET updated_at = datetime('now')
               WHERE id = (SELECT notebook_id FROM notebook_sections WHERE id = ?)""",
            (section_id,),
        )
        await self.db.commit()

    async def _touch_notebook_from_entry(self, entry_id: int) -> None:
        """Update notebook's updated_at from an entry ID."""
        await self.db.execute(
            """UPDATE notebooks SET updated_at = datetime('now')
               WHERE id = (
                   SELECT s.notebook_id FROM notebook_sections s
                   JOIN notebook_entries e ON e.section_id = s.id
                   WHERE e.id = ?
               )""",
            (entry_id,),
        )
        await self.db.commit()

    def _compute_can_edit(
        self,
        entry: dict,
        user_id: int,
        is_manager: bool,
        delegated_entry_ids: set[int],
    ) -> bool:
        """Compute whether the user can edit this specific entry."""
        if is_manager:
            return True
        if entry["created_by"] == user_id:
            return True
        if entry["id"] in delegated_entry_ids:
            return True
        # For fields: anyone can fill empty fields
        if entry["entry_type"] == "field" and not entry["field_filled_by"]:
            return True
        return False

    def _row_to_entry(self, e: dict, can_edit: bool) -> EntryResponse:
        return EntryResponse(
            id=e["id"], section_id=e["section_id"],
            title=e["title"], content=e["content"],
            entry_type=e["entry_type"],
            field_type=e["field_type"],
            field_required=bool(e["field_required"]),
            field_filled_by=e["field_filled_by"],
            field_filled_by_name=e.get("field_filled_by_name"),
            task_status=e["task_status"],
            task_due_date=e["task_due_date"],
            task_assigned_to=e["task_assigned_to"],
            task_assigned_to_name=e.get("task_assigned_to_name"),
            task_parts_note=e["task_parts_note"],
            created_by=e["created_by"],
            creator_name=e.get("creator_name"),
            updated_by=e["updated_by"],
            can_edit=can_edit,
            sort_order=e["sort_order"],
            created_at=e["created_at"],
            updated_at=e["updated_at"],
        )

    def _row_to_template(self, r: dict) -> TemplateResponse:
        return TemplateResponse(
            id=r["id"], name=r["name"], description=r["description"],
            job_type=r["job_type"], is_default=bool(r["is_default"]),
            created_by=r["created_by"],
            created_at=r["created_at"], updated_at=r["updated_at"],
        )

    def _row_to_template_section(self, r: dict) -> TemplateSectionResponse:
        return TemplateSectionResponse(
            id=r["id"], template_id=r["template_id"],
            name=r["name"], section_type=r["section_type"],
            sort_order=r["sort_order"], is_locked=bool(r["is_locked"]),
        )

    def _row_to_section(self, r: dict) -> SectionResponse:
        return SectionResponse(
            id=r["id"], notebook_id=r["notebook_id"],
            name=r["name"], section_type=r["section_type"],
            sort_order=r["sort_order"], is_locked=bool(r["is_locked"]),
            created_at=r["created_at"],
        )

    def _build_updates(self, data: object) -> tuple[list[str], list]:
        """Build SET clause parts from a Pydantic model (exclude_none)."""
        updates = []
        params = []
        for field, value in data.model_dump(exclude_none=True).items():
            if isinstance(value, bool):
                updates.append(f"{field} = ?")
                params.append(1 if value else 0)
            else:
                updates.append(f"{field} = ?")
                params.append(value)
        return updates, params
