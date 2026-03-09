"""
People routes — employees, certifications, wages, notes, skills, hats, permissions.

~28 endpoints covering full People module functionality.
Permission gates:
- view_people  → read employee list/detail
- manage_people → create/update/delete employees, certs, wages, notes, skills, hats
"""

from __future__ import annotations

import csv
import io
import uuid
from pathlib import Path
from typing import Any

import aiosqlite
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status

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
    EmployeeTeamCreate,
    EmployeeTeamUpdate,
    EmployeeUpdate,
    HatCreate,
    HatDetailResponse,
    HatUpdate,
    JobLeadElevationCreate,
    PermissionAssignment,
    TeamMemberAdd,
    TeamMemberRoleUpdate,
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


# ═════════════════════════════════════════════════════════════════
# JOB LEAD ELEVATIONS
# ═════════════════════════════════════════════════════════════════


@router.get("/employees/{user_id}/elevations")
async def get_user_elevations(
    user_id: int,
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all job-lead elevations for an employee."""
    svc = PeopleService(db)
    elevations = await svc.get_user_elevations(user_id)
    return ApiResponse(data=elevations, message=f"{len(elevations)} elevations")


@router.post("/employees/{user_id}/elevations", status_code=status.HTTP_201_CREATED)
async def grant_elevation(
    user_id: int,
    data: JobLeadElevationCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Grant a job-specific permission elevation to an employee."""
    svc = PeopleService(db)
    elevation_id = await svc.grant_elevation(
        user_id, data.job_id, data.permission_key, granted_by=user["id"],
    )
    return ApiResponse(
        data={"id": elevation_id},
        message="Elevation granted",
    )


@router.delete("/elevations/{elevation_id}")
async def revoke_elevation(
    elevation_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Revoke a single job-lead elevation."""
    svc = PeopleService(db)
    revoked = await svc.revoke_elevation(elevation_id)
    if not revoked:
        raise HTTPException(status_code=404, detail="Elevation not found")
    return ApiResponse(data={"id": elevation_id}, message="Elevation revoked")


@router.delete("/employees/{user_id}/elevations/job/{job_id}")
async def revoke_all_elevations_for_job(
    user_id: int,
    job_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Revoke all elevations for an employee on a specific job."""
    svc = PeopleService(db)
    count = await svc.revoke_all_elevations_for_job(user_id, job_id)
    return ApiResponse(
        data={"user_id": user_id, "job_id": job_id, "revoked_count": count},
        message=f"{count} elevations revoked",
    )


# ═════════════════════════════════════════════════════════════════
# CERT ALERTS
# ═════════════════════════════════════════════════════════════════


@router.get("/cert-alerts")
async def get_cert_alerts(
    days: int = Query(60, ge=1, le=365, description="Look-ahead window in days"),
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get certifications expiring within the look-ahead window.

    Returns list of { user_id, user_name, cert_name, expiry_date, days_until_expiry }.
    Red alert < 30 days, amber alert < 60 days.
    """
    svc = PeopleService(db)
    alerts = await svc.get_cert_alerts(days=days)
    return ApiResponse(data=alerts, message=f"{len(alerts)} cert alerts")


# ═════════════════════════════════════════════════════════════════
# EMPLOYEE AVATAR
# ═════════════════════════════════════════════════════════════════

UPLOAD_DIR = Path("uploads")


@router.post("/employees/{employee_id}/avatar")
async def upload_employee_avatar(
    employee_id: int,
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Upload or replace an employee's avatar photo."""
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    ext = Path(file.filename or "avatar.jpg").suffix or ".jpg"
    unique_name = f"avatar_{employee_id}_{uuid.uuid4().hex[:8]}{ext}"
    file_path = UPLOAD_DIR / unique_name

    contents = await file.read()
    file_path.write_bytes(contents)

    # Update the user's avatar_url
    await db.execute(
        "UPDATE users SET avatar_url = ? WHERE id = ?",
        (str(file_path), employee_id),
    )
    await db.commit()

    return ApiResponse(
        data={"avatar_url": str(file_path)},
        message="Avatar updated",
    )


# ═════════════════════════════════════════════════════════════════
# CERTIFICATION DOCUMENT UPLOAD
# ═════════════════════════════════════════════════════════════════


@router.post("/certifications/{cert_id}/document")
async def upload_certification_document(
    cert_id: int,
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Upload a certification document (scan, PDF, photo)."""
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    ext = Path(file.filename or "cert.pdf").suffix or ".pdf"
    unique_name = f"cert_{cert_id}_{uuid.uuid4().hex[:8]}{ext}"
    file_path = UPLOAD_DIR / unique_name

    contents = await file.read()
    file_path.write_bytes(contents)

    # Update the certification's document_path
    await db.execute(
        "UPDATE employee_certifications SET document_path = ? WHERE id = ?",
        (str(file_path), cert_id),
    )
    await db.commit()

    return ApiResponse(
        data={"document_path": str(file_path)},
        message="Certification document uploaded",
    )


# ═════════════════════════════════════════════════════════════════
# CSV IMPORT
# ═════════════════════════════════════════════════════════════════


@router.post("/employees/import")
async def import_employees_csv(
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Import employees from a CSV file.

    Expected columns: display_name, email, phone, pin (optional, auto-generated),
    certification, hire_date, pay_rate, emergency_contact_name, emergency_contact_phone.
    Returns { created, skipped, errors }.
    """
    content = await file.read()
    text = content.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))

    svc = PeopleService(db)
    created, skipped, errors = 0, 0, []

    for i, row in enumerate(reader, start=2):
        name = (row.get("display_name") or "").strip()
        if not name:
            errors.append({"row": i, "error": "Missing display_name"})
            continue

        # Check for duplicate by name
        existing = await db.execute(
            "SELECT id FROM users WHERE LOWER(display_name) = LOWER(?) AND is_active = 1",
            (name,),
        )
        if await existing.fetchone():
            skipped += 1
            continue

        try:
            emp_data = EmployeeCreate(
                display_name=name,
                email=row.get("email", "").strip() or None,
                phone=row.get("phone", "").strip() or None,
                pin=row.get("pin", "").strip() or None,
                certification=row.get("certification", "").strip() or None,
                hire_date=row.get("hire_date", "").strip() or None,
                pay_rate=float(row["pay_rate"]) if row.get("pay_rate", "").strip() else None,
                emergency_contact_name=row.get("emergency_contact_name", "").strip() or None,
                emergency_contact_phone=row.get("emergency_contact_phone", "").strip() or None,
            )
            await svc.create_employee(emp_data)
            created += 1
        except Exception as e:
            errors.append({"row": i, "error": str(e)})

    return ApiResponse(
        data={"created": created, "skipped": skipped, "errors": errors},
        message=f"{created} employees imported, {skipped} skipped",
    )


# ═════════════════════════════════════════════════════════════════
# EMPLOYEE TEAMS
# ═════════════════════════════════════════════════════════════════


@router.get("/teams")
async def list_teams(
    active_only: bool = Query(True, description="Only return active teams"),
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all employee teams with member counts."""
    svc = PeopleService(db)
    teams = await svc.list_teams(active_only=active_only)
    return ApiResponse(data=teams, message=f"{len(teams)} teams")


@router.get("/teams/{team_id}")
async def get_team(
    team_id: int,
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a team with its full member list."""
    svc = PeopleService(db)
    team = await svc.get_team(team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    return ApiResponse(data=team, message="Team loaded")


@router.post("/teams", status_code=status.HTTP_201_CREATED)
async def create_team(
    data: EmployeeTeamCreate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new employee team."""
    svc = PeopleService(db)
    try:
        team_id = await svc.create_team(data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return ApiResponse(data={"id": team_id}, message="Team created")


@router.patch("/teams/{team_id}")
async def update_team(
    team_id: int,
    data: EmployeeTeamUpdate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a team's name, description, lead, or active status."""
    svc = PeopleService(db)
    try:
        updated = await svc.update_team(team_id, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    if not updated:
        raise HTTPException(status_code=404, detail="Team not found or no changes")
    return ApiResponse(data={"id": team_id}, message="Team updated")


@router.delete("/teams/{team_id}")
async def delete_team(
    team_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a team (cascade removes all members)."""
    svc = PeopleService(db)
    deleted = await svc.delete_team(team_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Team not found")
    return ApiResponse(data={"id": team_id}, message="Team deleted")


@router.post("/teams/{team_id}/members", status_code=status.HTTP_201_CREATED)
async def add_team_member(
    team_id: int,
    data: TeamMemberAdd,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a member to a team."""
    svc = PeopleService(db)
    try:
        member_id = await svc.add_team_member(team_id, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return ApiResponse(data={"id": member_id}, message="Member added")


@router.delete("/teams/{team_id}/members/{user_id}")
async def remove_team_member(
    team_id: int,
    user_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a member from a team."""
    svc = PeopleService(db)
    removed = await svc.remove_team_member(team_id, user_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Membership not found")
    return ApiResponse(
        data={"team_id": team_id, "user_id": user_id},
        message="Member removed",
    )


@router.patch("/teams/{team_id}/members/{user_id}")
async def update_team_member_role(
    team_id: int,
    user_id: int,
    data: TeamMemberRoleUpdate,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Change a member's role within a team."""
    svc = PeopleService(db)
    updated = await svc.update_team_member_role(team_id, user_id, data.role)
    if not updated:
        raise HTTPException(status_code=404, detail="Membership not found")
    return ApiResponse(
        data={"team_id": team_id, "user_id": user_id, "role": data.role},
        message="Member role updated",
    )


@router.get("/employees/{user_id}/teams")
async def get_employee_teams(
    user_id: int,
    user: dict = Depends(require_permission("view_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all teams an employee belongs to."""
    svc = PeopleService(db)
    teams = await svc.get_user_teams(user_id)
    return ApiResponse(data=teams, message=f"{len(teams)} teams")
