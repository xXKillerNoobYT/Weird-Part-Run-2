"""
People routes — employees, certifications, wages, notes, skills, hats, permissions.

~28 endpoints covering full People module functionality.
Permission gates:
- view_people  → read employee list/detail
- manage_people → create/update/delete employees, certs, wages, notes, skills, hats
"""

from __future__ import annotations

from typing import Any

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, PaginatedData
from app.models.people import (
    CertificationCreate,
    CertificationResponse,
    CertificationUpdate,
    EmployeeCreate,
    EmployeeDetail,
    EmployeeListItem,
    EmployeeNoteCreate,
    EmployeeNoteResponse,
    EmployeeNoteUpdate,
    EmployeeUpdate,
    HatCreate,
    HatDetailResponse,
    HatUpdate,
    PermissionAssignment,
    UserSkillCreate,
    UserSkillResponse,
    UserSkillUpdate,
    WageHistoryCreate,
    WageHistoryResponse,
)
from app.services.people_service import PeopleService

router = APIRouter(prefix="/api/people", tags=["People"])


# ═════════════════════════════════════════════════════════════════
# EMPLOYEES
# ═════════════════════════════════════════════════════════════════


@router.get("/employees")
async def list_employees(
    search: str | None = Query(None, description="Search by name, email, or phone"),
    is_active: bool | None = Query(None, description="Filter by active status"),
    hat_id: int | None = Query(None, description="Filter by hat/role ID"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(50, ge=1, le=200, description="Items per page"),
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Paginated employee list with search, filters, hat names, and cert counts."""
    svc = PeopleService(db)
    result = await svc.list_employees(
        search=search, is_active=is_active, hat_id=hat_id,
        page=page, page_size=page_size,
    )
    return ApiResponse(
        data=result,
        message=f"Found {result['total']} employees",
    )


@router.get("/employees/{user_id}")
async def get_employee(
    user_id: int,
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Full employee detail with certifications, wages, notes, skills, hats."""
    svc = PeopleService(db)
    # Private notes require manage_people permission
    include_private = "manage_people" in user.get("permissions", [])
    detail = await svc.get_employee_detail(user_id, include_private_notes=include_private)
    if not detail:
        raise HTTPException(status_code=404, detail="Employee not found")
    return ApiResponse(data=detail, message="Employee detail loaded")


@router.post("/employees", status_code=status.HTTP_201_CREATED)
async def create_employee(
    data: EmployeeCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new employee. Also logs initial wage entry if pay_rate is provided."""
    svc = PeopleService(db)
    new_id = await svc.create_employee(data, created_by=user.get("id"))
    # Return the full detail so the frontend has everything
    detail = await svc.get_employee_detail(new_id, include_private_notes=True)
    return ApiResponse(data=detail, message="Employee created")


@router.put("/employees/{user_id}")
async def update_employee(
    user_id: int,
    data: EmployeeUpdate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update employee fields. Auto-logs wage history if pay_rate changes."""
    svc = PeopleService(db)
    updated = await svc.update_employee(user_id, data, changed_by=user.get("id"))
    if not updated:
        raise HTTPException(status_code=404, detail="Employee not found or no changes")
    detail = await svc.get_employee_detail(user_id, include_private_notes=True)
    return ApiResponse(data=detail, message="Employee updated")


@router.patch("/employees/{user_id}/toggle-active")
async def toggle_employee_active(
    user_id: int,
    is_active: bool = Query(..., description="New active status"),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Activate or deactivate an employee."""
    svc = PeopleService(db)
    toggled = await svc.toggle_employee_active(user_id, is_active)
    if not toggled:
        raise HTTPException(status_code=404, detail="Employee not found")
    action = "activated" if is_active else "deactivated"
    return ApiResponse(data={"user_id": user_id, "is_active": is_active}, message=f"Employee {action}")


# ═════════════════════════════════════════════════════════════════
# CERTIFICATIONS
# ═════════════════════════════════════════════════════════════════


@router.get("/employees/{user_id}/certifications")
async def get_certifications(
    user_id: int,
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all certifications for an employee."""
    svc = PeopleService(db)
    certs = await svc.get_certifications(user_id)
    return ApiResponse(data=certs, message=f"{len(certs)} certifications loaded")


@router.post("/employees/{user_id}/certifications", status_code=status.HTTP_201_CREATED)
async def add_certification(
    user_id: int,
    data: CertificationCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a certification to an employee."""
    svc = PeopleService(db)
    cert_id = await svc.add_certification(user_id, data)
    return ApiResponse(data={"id": cert_id}, message="Certification added")


@router.put("/certifications/{cert_id}")
async def update_certification(
    cert_id: int,
    data: CertificationUpdate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update an existing certification."""
    svc = PeopleService(db)
    updated = await svc.update_certification(cert_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Certification not found or no changes")
    return ApiResponse(data={"id": cert_id}, message="Certification updated")


@router.delete("/certifications/{cert_id}")
async def delete_certification(
    cert_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a certification."""
    svc = PeopleService(db)
    deleted = await svc.delete_certification(cert_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Certification not found")
    return ApiResponse(data={"id": cert_id}, message="Certification deleted")


@router.get("/certifications/expiring")
async def get_expiring_certifications(
    days: int = Query(30, ge=1, le=365, description="Lookahead window in days"),
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get certifications expiring within N days (across all employees)."""
    svc = PeopleService(db)
    certs = await svc.get_expiring_certifications(days)
    return ApiResponse(data=certs, message=f"{len(certs)} certifications expiring within {days} days")


# ═════════════════════════════════════════════════════════════════
# WAGE HISTORY
# ═════════════════════════════════════════════════════════════════


@router.get("/employees/{user_id}/wages")
async def get_wage_history(
    user_id: int,
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get full wage history for an employee."""
    # Wage data requires dollar visibility or manage_people
    perms = user.get("permissions", [])
    if "show_dollar_values" not in perms and "manage_people" not in perms:
        raise HTTPException(status_code=403, detail="Dollar values permission required")

    svc = PeopleService(db)
    wages = await svc.get_wage_history(user_id)
    return ApiResponse(data=wages, message=f"{len(wages)} wage entries loaded")


@router.post("/employees/{user_id}/wages", status_code=status.HTTP_201_CREATED)
async def add_wage_entry(
    user_id: int,
    data: WageHistoryCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a wage entry. Also updates the employee's current pay_rate."""
    svc = PeopleService(db)
    entry_id = await svc.add_wage_entry(user_id, data, changed_by=user.get("id"))
    return ApiResponse(data={"id": entry_id}, message="Wage entry recorded")


# ═════════════════════════════════════════════════════════════════
# EMPLOYEE NOTES
# ═════════════════════════════════════════════════════════════════


@router.get("/employees/{user_id}/notes")
async def get_notes(
    user_id: int,
    note_type: str | None = Query(None, description="Filter by note type"),
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get notes for an employee. Private notes require manage_people."""
    include_private = "manage_people" in user.get("permissions", [])
    svc = PeopleService(db)
    notes = await svc.get_notes(user_id, include_private=include_private, note_type=note_type)
    return ApiResponse(data=notes, message=f"{len(notes)} notes loaded")


@router.post("/employees/{user_id}/notes", status_code=status.HTTP_201_CREATED)
async def add_note(
    user_id: int,
    data: EmployeeNoteCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a note to an employee's record."""
    svc = PeopleService(db)
    note_id = await svc.add_note(user_id, data, created_by=user.get("id"))
    return ApiResponse(data={"id": note_id}, message="Note added")


@router.put("/notes/{note_id}")
async def update_note(
    note_id: int,
    data: EmployeeNoteUpdate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a note."""
    svc = PeopleService(db)
    updated = await svc.update_note(note_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Note not found or no changes")
    return ApiResponse(data={"id": note_id}, message="Note updated")


@router.delete("/notes/{note_id}")
async def delete_note(
    note_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a note."""
    svc = PeopleService(db)
    deleted = await svc.delete_note(note_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Note not found")
    return ApiResponse(data={"id": note_id}, message="Note deleted")


# ═════════════════════════════════════════════════════════════════
# SKILLS
# ═════════════════════════════════════════════════════════════════


@router.get("/employees/{user_id}/skills")
async def get_skills(
    user_id: int,
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all skills for an employee."""
    svc = PeopleService(db)
    skills = await svc.get_skills(user_id)
    return ApiResponse(data=skills, message=f"{len(skills)} skills loaded")


@router.post("/employees/{user_id}/skills", status_code=status.HTTP_201_CREATED)
async def add_skill(
    user_id: int,
    data: UserSkillCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a skill to an employee."""
    svc = PeopleService(db)
    skill_id = await svc.add_skill(user_id, data)
    return ApiResponse(data={"id": skill_id}, message="Skill added")


@router.put("/skills/{skill_id}")
async def update_skill(
    skill_id: int,
    data: UserSkillUpdate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a skill."""
    svc = PeopleService(db)
    updated = await svc.update_skill(skill_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Skill not found or no changes")
    return ApiResponse(data={"id": skill_id}, message="Skill updated")


@router.delete("/skills/{skill_id}")
async def delete_skill(
    skill_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a skill."""
    svc = PeopleService(db)
    deleted = await svc.delete_skill(skill_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Skill not found")
    return ApiResponse(data={"id": skill_id}, message="Skill deleted")


# ═════════════════════════════════════════════════════════════════
# HATS (ROLES)
# ═════════════════════════════════════════════════════════════════


@router.get("/hats")
async def list_hats(
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all hats with permissions and user counts."""
    svc = PeopleService(db)
    hats = await svc.list_hats()
    return ApiResponse(data=hats, message=f"{len(hats)} hats loaded")


@router.post("/hats", status_code=status.HTTP_201_CREATED)
async def create_hat(
    data: HatCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new hat (role)."""
    svc = PeopleService(db)
    hat_id = await svc.create_hat(data)
    hats = await svc.list_hats()
    # Return the newly created hat from the list
    new_hat = next((h for h in hats if h["id"] == hat_id), None)
    return ApiResponse(data=new_hat, message="Hat created")


@router.put("/hats/{hat_id}")
async def update_hat(
    hat_id: int,
    data: HatUpdate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a hat (name, description, level)."""
    svc = PeopleService(db)
    updated = await svc.update_hat(hat_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Hat not found or no changes")
    hats = await svc.list_hats()
    hat = next((h for h in hats if h["id"] == hat_id), None)
    return ApiResponse(data=hat, message="Hat updated")


@router.delete("/hats/{hat_id}")
async def delete_hat(
    hat_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a hat. Built-in hats cannot be deleted."""
    svc = PeopleService(db)
    deleted, error = await svc.delete_hat(hat_id)
    if error:
        raise HTTPException(status_code=400, detail=error)
    if not deleted:
        raise HTTPException(status_code=404, detail="Hat not found")
    return ApiResponse(data={"id": hat_id}, message="Hat deleted")


@router.put("/hats/{hat_id}/permissions")
async def set_hat_permissions(
    hat_id: int,
    data: PermissionAssignment,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Replace all permissions for a hat."""
    svc = PeopleService(db)
    await svc.set_hat_permissions(hat_id, data.permission_keys)
    # Return updated hat data
    hats = await svc.list_hats()
    hat = next((h for h in hats if h["id"] == hat_id), None)
    return ApiResponse(data=hat, message="Permissions updated")


# ═════════════════════════════════════════════════════════════════
# PERMISSION MATRIX
# ═════════════════════════════════════════════════════════════════


@router.get("/permissions/matrix")
async def get_permission_matrix(
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Full permission matrix: all hats × all permissions, grouped by domain."""
    svc = PeopleService(db)
    matrix = await svc.get_permission_matrix()
    return ApiResponse(data=matrix, message="Permission matrix loaded")


@router.get("/permissions/keys")
async def get_permission_keys(
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all known permission keys (for reference/autocomplete)."""
    svc = PeopleService(db)
    keys = await svc.get_all_permission_keys()
    return ApiResponse(data=keys, message=f"{len(keys)} permission keys")
