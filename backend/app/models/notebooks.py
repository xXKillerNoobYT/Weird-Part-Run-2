"""
Pydantic models for the Unified Notebook System.

Covers templates, notebooks, sections, entries (notes/tasks/fields),
permissions, and all request/response shapes.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


# ── Template Models ──────────────────────────────────────────────────

class TemplateEntryCreate(BaseModel):
    """Add an entry to a template section."""
    title: str = Field(..., min_length=1, max_length=200)
    default_content: str | None = None
    entry_type: str = "note"  # note | task | field
    field_type: str | None = None  # text | checkbox | textarea
    field_required: bool = False
    sort_order: int = 0


class TemplateEntryResponse(BaseModel):
    """Entry inside a template section."""
    id: int
    section_id: int
    title: str
    default_content: str | None = None
    entry_type: str
    field_type: str | None = None
    field_required: bool = False
    sort_order: int = 0


class TemplateSectionCreate(BaseModel):
    """Add a section to a template."""
    name: str = Field(..., min_length=1, max_length=100)
    section_type: str = "notes"  # info | notes | tasks
    sort_order: int = 0
    is_locked: bool = False


class TemplateSectionUpdate(BaseModel):
    """Update a template section."""
    name: str | None = Field(None, min_length=1, max_length=100)
    sort_order: int | None = None
    is_locked: bool | None = None


class TemplateSectionResponse(BaseModel):
    """Section inside a template."""
    id: int
    template_id: int
    name: str
    section_type: str
    sort_order: int = 0
    is_locked: bool = False


class TemplateSectionWithEntries(BaseModel):
    """Template section with its entries for full template view."""
    id: int
    template_id: int
    name: str
    section_type: str
    sort_order: int = 0
    is_locked: bool = False
    entries: list[TemplateEntryResponse] = Field(default_factory=list)


class TemplateCreate(BaseModel):
    """Create a new notebook template."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    job_type: str | None = None
    is_default: bool = False


class TemplateUpdate(BaseModel):
    """Update template metadata."""
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    job_type: str | None = None
    is_default: bool | None = None


class TemplateResponse(BaseModel):
    """Template list item."""
    id: int
    name: str
    description: str | None = None
    job_type: str | None = None
    is_default: bool = False
    created_by: int | None = None
    created_at: str | None = None
    updated_at: str | None = None


class TemplateFull(BaseModel):
    """Full template with nested sections and entries."""
    id: int
    name: str
    description: str | None = None
    job_type: str | None = None
    is_default: bool = False
    created_by: int | None = None
    created_at: str | None = None
    updated_at: str | None = None
    sections: list[TemplateSectionWithEntries] = Field(default_factory=list)


# ── Notebook Models ──────────────────────────────────────────────────

class NotebookCreate(BaseModel):
    """Create a general (non-job) notebook."""
    title: str = Field(..., min_length=1, max_length=200)
    description: str | None = None


class NotebookUpdate(BaseModel):
    """Update notebook title/description."""
    title: str | None = Field(None, min_length=1, max_length=200)
    description: str | None = None


class NotebookResponse(BaseModel):
    """Notebook header info."""
    id: int
    title: str
    description: str | None = None
    job_id: int | None = None
    job_name: str | None = None
    job_number: str | None = None
    template_id: int | None = None
    created_by: int
    creator_name: str | None = None
    is_archived: bool = False
    created_at: str | None = None
    updated_at: str | None = None


class NotebookListItem(BaseModel):
    """Lightweight notebook for list views."""
    id: int
    title: str
    description: str | None = None
    job_id: int | None = None
    job_name: str | None = None
    job_number: str | None = None
    is_archived: bool = False
    open_task_count: int = 0
    total_task_count: int = 0
    created_at: str | None = None
    updated_at: str | None = None


# ── Section Models ───────────────────────────────────────────────────

class SectionCreate(BaseModel):
    """Workers add custom sections (notes or tasks only)."""
    name: str = Field(..., min_length=1, max_length=100)
    section_type: str = "notes"  # notes | tasks (info only from templates)
    sort_order: int | None = None


class SectionUpdate(BaseModel):
    """Rename or reorder a section."""
    name: str | None = Field(None, min_length=1, max_length=100)
    sort_order: int | None = None


class SectionResponse(BaseModel):
    """Section inside a notebook."""
    id: int
    notebook_id: int
    name: str
    section_type: str
    sort_order: int = 0
    is_locked: bool = False
    created_at: str | None = None


class SectionReorderRequest(BaseModel):
    """Reorder sections by providing ordered list of IDs."""
    ordered_ids: list[int]


# ── Entry Models ─────────────────────────────────────────────────────

class EntryCreate(BaseModel):
    """Create a note, task, or field entry."""
    title: str = Field(..., min_length=1, max_length=200)
    content: str | None = None
    entry_type: str = "note"  # note | task | field
    # Field-specific
    field_type: str | None = None  # text | checkbox | textarea
    field_required: bool = False
    # Task-specific
    task_status: str | None = None
    task_due_date: str | None = None
    task_assigned_to: int | None = None
    task_parts_note: str | None = None
    sort_order: int | None = None


class EntryUpdate(BaseModel):
    """Update an entry (permission-checked)."""
    title: str | None = Field(None, min_length=1, max_length=200)
    content: str | None = None
    task_status: str | None = None
    task_due_date: str | None = None
    task_assigned_to: int | None = None
    task_parts_note: str | None = None
    sort_order: int | None = None


class EntryResponse(BaseModel):
    """Full entry detail with computed fields."""
    id: int
    section_id: int
    title: str
    content: str | None = None
    entry_type: str
    # Field-specific
    field_type: str | None = None
    field_required: bool = False
    field_filled_by: int | None = None
    field_filled_by_name: str | None = None
    # Task-specific
    task_status: str | None = None
    task_due_date: str | None = None
    task_assigned_to: int | None = None
    task_assigned_to_name: str | None = None
    task_parts_note: str | None = None
    # Authorship
    created_by: int
    creator_name: str | None = None
    updated_by: int | None = None
    # Permission (computed per-request)
    can_edit: bool = False
    # Ordering & timestamps
    sort_order: int = 0
    created_at: str | None = None
    updated_at: str | None = None


class TaskStatusUpdate(BaseModel):
    """Update task status with optional parts note."""
    status: str  # planned | parts_ordered | parts_delivered | in_progress | done
    parts_note: str | None = None  # required when transitioning to parts_ordered


class FieldValueUpdate(BaseModel):
    """Update a field value (first-fill logic applies)."""
    value: str | None = None


class TaskAssignRequest(BaseModel):
    """Assign a task to a user (managers) or self-assign."""
    user_id: int | None = None  # NULL = unassign


class EntryPermissionGrant(BaseModel):
    """Grant edit access to another user."""
    user_id: int


# ── Nested Response (full notebook) ──────────────────────────────────

class SectionWithEntries(BaseModel):
    """Section with its entries for full notebook view."""
    id: int
    notebook_id: int
    name: str
    section_type: str
    sort_order: int = 0
    is_locked: bool = False
    created_at: str | None = None
    entries: list[EntryResponse] = Field(default_factory=list)


class NotebookFull(BaseModel):
    """Complete notebook with all sections and entries."""
    notebook: NotebookResponse
    sections: list[SectionWithEntries] = Field(default_factory=list)


# ── Task Summary (for job list views) ────────────────────────────────

class TaskSummary(BaseModel):
    """Task count summary for a job."""
    planned: int = 0
    parts_ordered: int = 0
    parts_delivered: int = 0
    in_progress: int = 0
    done: int = 0
    total_open: int = 0
