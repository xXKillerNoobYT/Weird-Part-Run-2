"""
Notebooks routes — Templates, notebooks, sections, entries, and permissions.

Phase 4.5 — Unified Notebook System with ~30 endpoints covering
template management (Office), notebook CRUD, section/entry CRUD,
task stage transitions, field first-fill logic, and delegated permissions.
"""

from __future__ import annotations

import logging

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage
from app.models.notebooks import (
    EntryCreate,
    EntryPermissionGrant,
    EntryResponse,
    EntryUpdate,
    FieldValueUpdate,
    NotebookCreate,
    NotebookFull,
    NotebookListItem,
    NotebookResponse,
    NotebookUpdate,
    SectionCreate,
    SectionReorderRequest,
    SectionResponse,
    SectionUpdate,
    TaskAssignRequest,
    TaskStatusUpdate,
    TaskSummary,
    TemplateCreate,
    TemplateEntryCreate,
    TemplateEntryResponse,
    TemplateFull,
    TemplateResponse,
    TemplateSectionCreate,
    TemplateSectionResponse,
    TemplateSectionUpdate,
    TemplateUpdate,
)
from app.services.notebook_service import NotebookService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api", tags=["Notebooks"])


# ═══════════════════════════════════════════════════════════════════════
# TEMPLATES (Office — manage_notebooks permission)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/notebook-templates",
    response_model=ApiResponse[list[TemplateResponse]],
    summary="List notebook templates",
)
async def list_templates(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all notebook templates."""
    svc = NotebookService(db)
    templates = await svc.get_templates()
    return ApiResponse(data=templates, message=f"{len(templates)} templates")


@router.post(
    "/notebook-templates",
    response_model=ApiResponse[TemplateResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create notebook template",
)
async def create_template(
    data: TemplateCreate,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new notebook template (Office only)."""
    svc = NotebookService(db)
    tmpl = await svc.create_template(data, user["id"])
    return ApiResponse(data=tmpl, message=f"Template '{data.name}' created")


@router.get(
    "/notebook-templates/{template_id}",
    response_model=ApiResponse[TemplateFull],
    summary="Get full template",
)
async def get_template(
    template_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a template with all sections and entries."""
    svc = NotebookService(db)
    tmpl = await svc.get_template_full(template_id)
    if not tmpl:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data=tmpl)


@router.put(
    "/notebook-templates/{template_id}",
    response_model=ApiResponse[TemplateResponse],
    summary="Update template",
)
async def update_template(
    template_id: int,
    data: TemplateUpdate,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update template metadata."""
    svc = NotebookService(db)
    tmpl = await svc.update_template(template_id, data)
    if not tmpl:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data=tmpl, message="Template updated")


@router.delete(
    "/notebook-templates/{template_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Delete template",
)
async def delete_template(
    template_id: int,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a notebook template."""
    svc = NotebookService(db)
    await svc.delete_template(template_id)
    return ApiResponse(
        data=StatusMessage(status="deleted"),
        message="Template deleted",
    )


# ── Template Sections ──────────────────────────────────────────────

@router.post(
    "/notebook-templates/{template_id}/sections",
    response_model=ApiResponse[TemplateSectionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Add template section",
)
async def add_template_section(
    template_id: int,
    data: TemplateSectionCreate,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a section to a template."""
    svc = NotebookService(db)
    sec = await svc.add_template_section(template_id, data)
    return ApiResponse(data=sec, message=f"Section '{data.name}' added")


@router.put(
    "/notebook-templates/sections/{section_id}",
    response_model=ApiResponse[TemplateSectionResponse],
    summary="Update template section",
)
async def update_template_section(
    section_id: int,
    data: TemplateSectionUpdate,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a template section."""
    svc = NotebookService(db)
    sec = await svc.update_template_section(section_id, data)
    if not sec:
        raise HTTPException(status_code=404, detail="Section not found")
    return ApiResponse(data=sec, message="Section updated")


@router.delete(
    "/notebook-templates/sections/{section_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Delete template section",
)
async def delete_template_section(
    section_id: int,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a template section."""
    svc = NotebookService(db)
    await svc.delete_template_section(section_id)
    return ApiResponse(
        data=StatusMessage(status="deleted"),
        message="Section deleted",
    )


# ── Template Entries ───────────────────────────────────────────────

@router.post(
    "/notebook-templates/sections/{section_id}/entries",
    response_model=ApiResponse[TemplateEntryResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Add template entry",
)
async def add_template_entry(
    section_id: int,
    data: TemplateEntryCreate,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add an entry to a template section."""
    svc = NotebookService(db)
    entry = await svc.add_template_entry(section_id, data)
    return ApiResponse(data=entry, message=f"Entry '{data.title}' added")


@router.delete(
    "/notebook-templates/entries/{entry_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Delete template entry",
)
async def delete_template_entry(
    entry_id: int,
    user: dict = Depends(require_permission("manage_notebooks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a template entry."""
    svc = NotebookService(db)
    await svc.delete_template_entry(entry_id)
    return ApiResponse(
        data=StatusMessage(status="deleted"),
        message="Entry deleted",
    )


# ═══════════════════════════════════════════════════════════════════════
# NOTEBOOKS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/notebooks",
    response_model=ApiResponse[list[NotebookListItem]],
    summary="List notebooks",
)
async def list_notebooks(
    filter: str | None = Query(None, description="job | general | None=all"),
    search: str | None = Query(None, description="Search title, job name/number"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List notebooks with optional filter."""
    svc = NotebookService(db)
    notebooks = await svc.list_notebooks(filter_type=filter, search=search)
    return ApiResponse(data=notebooks, message=f"{len(notebooks)} notebooks")


@router.post(
    "/notebooks",
    response_model=ApiResponse[NotebookResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create general notebook",
)
async def create_notebook(
    data: NotebookCreate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a general (non-job) notebook."""
    svc = NotebookService(db)
    nb = await svc.create_notebook(data, user["id"])
    return ApiResponse(data=nb, message=f"Notebook '{data.title}' created")


@router.get(
    "/notebooks/{notebook_id}/full",
    response_model=ApiResponse[NotebookFull],
    summary="Get full notebook",
)
async def get_notebook_full(
    notebook_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a notebook with all sections and entries."""
    svc = NotebookService(db)
    nb = await svc.get_notebook_full(notebook_id, user["id"])
    if not nb:
        raise HTTPException(status_code=404, detail="Notebook not found")
    return ApiResponse(data=nb)


@router.put(
    "/notebooks/{notebook_id}",
    response_model=ApiResponse[NotebookResponse],
    summary="Update notebook",
)
async def update_notebook(
    notebook_id: int,
    data: NotebookUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update notebook title/description."""
    svc = NotebookService(db)
    nb = await svc.update_notebook(notebook_id, data)
    if not nb:
        raise HTTPException(status_code=404, detail="Notebook not found")
    return ApiResponse(data=nb, message="Notebook updated")


@router.delete(
    "/notebooks/{notebook_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Archive notebook",
)
async def archive_notebook(
    notebook_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Archive (soft-delete) a notebook."""
    svc = NotebookService(db)
    await svc.archive_notebook(notebook_id)
    return ApiResponse(
        data=StatusMessage(status="archived"),
        message="Notebook archived",
    )


# ═══════════════════════════════════════════════════════════════════════
# SECTIONS
# ═══════════════════════════════════════════════════════════════════════

@router.post(
    "/notebooks/{notebook_id}/sections",
    response_model=ApiResponse[SectionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create section",
)
async def create_section(
    notebook_id: int,
    data: SectionCreate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Workers add custom sections (notes or tasks)."""
    svc = NotebookService(db)
    sec = await svc.create_section(notebook_id, data)
    return ApiResponse(data=sec, message=f"Section '{data.name}' created")


@router.put(
    "/notebooks/sections/{section_id}",
    response_model=ApiResponse[SectionResponse],
    summary="Update section",
)
async def update_section(
    section_id: int,
    data: SectionUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Rename or reorder a section."""
    svc = NotebookService(db)
    sec = await svc.update_section(section_id, data)
    if not sec:
        raise HTTPException(status_code=404, detail="Section not found")
    return ApiResponse(data=sec, message="Section updated")


@router.delete(
    "/notebooks/sections/{section_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Delete section",
)
async def delete_section(
    section_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a section (locked sections cannot be deleted)."""
    svc = NotebookService(db)
    success = await svc.delete_section(section_id)
    if not success:
        raise HTTPException(
            status_code=400,
            detail="Cannot delete locked section",
        )
    return ApiResponse(
        data=StatusMessage(status="deleted"),
        message="Section deleted",
    )


@router.put(
    "/notebooks/{notebook_id}/sections/reorder",
    response_model=ApiResponse[list[SectionResponse]],
    summary="Reorder sections",
)
async def reorder_sections(
    notebook_id: int,
    data: SectionReorderRequest,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Reorder sections by providing ordered list of IDs."""
    svc = NotebookService(db)
    sections = await svc.reorder_sections(notebook_id, data.ordered_ids)
    return ApiResponse(data=sections, message="Sections reordered")


# ═══════════════════════════════════════════════════════════════════════
# ENTRIES
# ═══════════════════════════════════════════════════════════════════════

@router.post(
    "/notebooks/sections/{section_id}/entries",
    response_model=ApiResponse[EntryResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create entry",
)
async def create_entry(
    section_id: int,
    data: EntryCreate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a note, task, or field entry."""
    svc = NotebookService(db)
    entry = await svc.create_entry(section_id, data, user["id"])
    return ApiResponse(data=entry, message=f"Entry '{data.title}' created")


@router.put(
    "/notebooks/entries/{entry_id}",
    response_model=ApiResponse[EntryResponse],
    summary="Update entry",
)
async def update_entry(
    entry_id: int,
    data: EntryUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update an entry (permission-checked)."""
    svc = NotebookService(db)
    entry = await svc.update_entry(entry_id, data, user["id"])
    if not entry:
        raise HTTPException(
            status_code=403,
            detail="Entry not found or you don't have edit permission",
        )
    return ApiResponse(data=entry, message="Entry updated")


@router.patch(
    "/notebooks/entries/{entry_id}/status",
    response_model=ApiResponse[EntryResponse],
    summary="Update task status",
)
async def update_task_status(
    entry_id: int,
    data: TaskStatusUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Transition a task's stage (with optional parts note)."""
    svc = NotebookService(db)
    entry = await svc.update_task_status(
        entry_id, data.status, user["id"], data.parts_note
    )
    if not entry:
        raise HTTPException(
            status_code=400,
            detail="Invalid task or status",
        )
    return ApiResponse(data=entry, message=f"Task status → {data.status}")


@router.patch(
    "/notebooks/entries/{entry_id}/field-value",
    response_model=ApiResponse[EntryResponse],
    summary="Update field value",
)
async def update_field_value(
    entry_id: int,
    data: FieldValueUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a field value (first-fill logic applies)."""
    svc = NotebookService(db)
    entry = await svc.update_field_value(entry_id, data.value, user["id"])
    if not entry:
        raise HTTPException(
            status_code=403,
            detail="Field not found or already filled (managers only)",
        )
    return ApiResponse(data=entry, message="Field updated")


@router.delete(
    "/notebooks/entries/{entry_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Delete entry",
)
async def delete_entry(
    entry_id: int,
    hard: bool = Query(False, description="Hard delete (managers only)"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete an entry (creator) or hard-delete (manager)."""
    svc = NotebookService(db)
    if hard:
        success = await svc.hard_delete_entry(entry_id, user["id"])
    else:
        success = await svc.soft_delete_entry(entry_id, user["id"])

    if not success:
        raise HTTPException(
            status_code=403,
            detail="Cannot delete: permission denied",
        )
    return ApiResponse(
        data=StatusMessage(status="deleted"),
        message="Entry deleted",
    )


@router.post(
    "/notebooks/entries/{entry_id}/assign",
    response_model=ApiResponse[EntryResponse],
    summary="Assign task",
)
async def assign_task(
    entry_id: int,
    data: TaskAssignRequest,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Assign a task to a user (managers assign anyone, workers self-assign)."""
    svc = NotebookService(db)
    entry = await svc.assign_task(entry_id, data.user_id, user["id"])
    if not entry:
        raise HTTPException(
            status_code=403,
            detail="Cannot assign: not a task or permission denied",
        )
    return ApiResponse(data=entry, message="Task assigned")


# ═══════════════════════════════════════════════════════════════════════
# PERMISSIONS
# ═══════════════════════════════════════════════════════════════════════

@router.post(
    "/notebooks/entries/{entry_id}/permissions",
    response_model=ApiResponse[StatusMessage],
    status_code=status.HTTP_201_CREATED,
    summary="Grant edit permission",
)
async def grant_edit_permission(
    entry_id: int,
    data: EntryPermissionGrant,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Grant delegated edit access to another user."""
    svc = NotebookService(db)
    success = await svc.grant_edit(entry_id, data.user_id, user["id"])
    if not success:
        raise HTTPException(status_code=400, detail="Failed to grant permission")
    return ApiResponse(
        data=StatusMessage(status="granted"),
        message="Edit permission granted",
    )


@router.delete(
    "/notebooks/entries/{entry_id}/permissions/{target_user_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Revoke edit permission",
)
async def revoke_edit_permission(
    entry_id: int,
    target_user_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Revoke delegated edit access."""
    svc = NotebookService(db)
    await svc.revoke_edit(entry_id, target_user_id)
    return ApiResponse(
        data=StatusMessage(status="revoked"),
        message="Edit permission revoked",
    )
