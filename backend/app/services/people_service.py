"""
People service — orchestrates employee, certification, wage, note, skill, and hat operations.

This is the business-logic layer between the router and the repositories.
It handles cross-repo operations (e.g., creating an employee also logs an
initial wage history entry), permission checks, and data assembly.
"""

from __future__ import annotations

import math
from typing import Any

import aiosqlite

from app.models.people import (
    CertificationCreate,
    CertificationUpdate,
    EmployeeCreate,
    EmployeeNoteCreate,
    EmployeeNoteUpdate,
    EmployeeUpdate,
    HatCreate,
    HatUpdate,
    UserSkillCreate,
    UserSkillUpdate,
    WageHistoryCreate,
)
from app.repositories.people_repo import (
    CertificationRepo,
    EmployeeNoteRepo,
    UserSkillRepo,
    WageHistoryRepo,
)
from app.repositories.user_repo import HatRepo, UserRepo
from app.services.auth_service import hash_pin


# ── Known permission keys (grouped by domain) ─────────────────────
# Used by the permission matrix to display ALL possible permissions,
# even if no hat currently has them assigned.

PERMISSION_DOMAINS: dict[str, list[str]] = {
    "warehouse": [
        "view_warehouse", "manage_warehouse", "perform_audit", "manage_stock",
    ],
    "orders": [
        "view_orders", "manage_orders", "approve_orders",
    ],
    "people": [
        "view_people", "manage_people",
    ],
    "contacts": [
        "view_customers", "manage_customers",
        "view_contractors", "manage_contractors",
    ],
    "jobs": [
        "view_jobs", "manage_jobs",
    ],
    "scheduling": [
        "view_schedule", "manage_schedule",
        "request_time_off", "approve_time_off",
        "dispatch_employees",
    ],
    "fleet": [
        "view_trucks", "manage_fleet",
    ],
    "parts": [
        "view_parts_catalog", "edit_pricing", "show_dollar_values",
    ],
    "reports": [
        "view_reports", "export_reports",
    ],
    "notebooks": [
        "manage_notebooks",
    ],
    "settings": [
        "manage_settings", "manage_devices",
    ],
    "tools": [
        "view_tools", "manage_tools", "checkout_tools",
    ],
}


class PeopleService:
    """Stateless service — instantiate with a DB connection per request."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.user_repo = UserRepo(db)
        self.hat_repo = HatRepo(db)
        self.cert_repo = CertificationRepo(db)
        self.wage_repo = WageHistoryRepo(db)
        self.note_repo = EmployeeNoteRepo(db)
        self.skill_repo = UserSkillRepo(db)

    # ── Employees ──────────────────────────────────────────────────

    async def list_employees(
        self,
        *,
        search: str | None = None,
        is_active: bool | None = None,
        hat_id: int | None = None,
        page: int = 1,
        page_size: int = 50,
    ) -> dict[str, Any]:
        """Paginated employee list with hat names and cert counts.

        Returns: { items, total, page, page_size, total_pages }
        """
        offset = (page - 1) * page_size
        items = await self.user_repo.list_employees(
            search=search, is_active=is_active, hat_id=hat_id,
            limit=page_size, offset=offset,
        )
        total = await self.user_repo.count_employees(
            search=search, is_active=is_active, hat_id=hat_id,
        )
        return {
            "items": items,
            "total": total,
            "page": page,
            "page_size": page_size,
            "total_pages": max(1, math.ceil(total / page_size)),
        }

    async def get_employee_detail(
        self,
        user_id: int,
        *,
        include_private_notes: bool = False,
    ) -> dict | None:
        """Assemble the full employee detail with all related data."""
        user = await self.user_repo.get_by_id_with_hats(user_id)
        if not user:
            return None

        # Fetch all related data in parallel (sequential for SQLite)
        certs = await self.cert_repo.get_for_user(user_id)
        wages = await self.wage_repo.get_for_user(user_id)
        notes = await self.note_repo.get_for_user(
            user_id, include_private=include_private_notes,
        )
        skills = await self.skill_repo.get_for_user(user_id)

        user["certifications"] = certs
        user["wage_history"] = wages
        user["notes"] = notes
        user["skills"] = skills
        return user

    async def create_employee(self, data: EmployeeCreate, *, created_by: int | None = None) -> int:
        """Create a new employee.

        Also creates an initial wage history entry if pay_rate is provided.
        Returns the new user ID.
        """
        pin_hashed = hash_pin(data.pin)

        extra: dict[str, Any] = {}
        if data.certification:
            extra["certification"] = data.certification
        if data.hire_date:
            extra["hire_date"] = data.hire_date
        if data.pay_rate is not None:
            extra["pay_rate"] = data.pay_rate
        if data.emergency_contact_name:
            extra["emergency_contact_name"] = data.emergency_contact_name
        if data.emergency_contact_phone:
            extra["emergency_contact_phone"] = data.emergency_contact_phone

        user_id = await self.user_repo.create_user(
            display_name=data.display_name,
            pin_hash=pin_hashed,
            email=data.email,
            phone=data.phone,
            hat_ids=data.hat_ids,
            **extra,
        )

        # Log initial wage entry
        if data.pay_rate is not None:
            await self.wage_repo.insert({
                "user_id": user_id,
                "pay_rate": data.pay_rate,
                "effective_date": data.hire_date or "now",
                "reason": "hire",
                "changed_by": created_by,
            })

        return user_id

    async def update_employee(
        self,
        user_id: int,
        data: EmployeeUpdate,
        *,
        changed_by: int | None = None,
    ) -> bool:
        """Update employee fields.

        If pay_rate changes, automatically logs a wage history entry.
        """
        update_dict: dict[str, Any] = {}
        for field in (
            "display_name", "email", "phone", "certification",
            "hire_date", "emergency_contact_name", "emergency_contact_phone",
        ):
            value = getattr(data, field, None)
            if value is not None:
                update_dict[field] = value

        # Handle pay_rate change → log wage history
        if data.pay_rate is not None:
            current_user = await self.user_repo.get_by_id(user_id)
            if current_user and current_user.get("pay_rate") != data.pay_rate:
                update_dict["pay_rate"] = data.pay_rate
                await self.wage_repo.insert({
                    "user_id": user_id,
                    "pay_rate": data.pay_rate,
                    "effective_date": "now",
                    "reason": "adjustment",
                    "changed_by": changed_by,
                })

        if not update_dict:
            return False

        return await self.user_repo.update(user_id, update_dict)

    async def toggle_employee_active(self, user_id: int, is_active: bool) -> bool:
        """Activate or deactivate an employee."""
        return await self.user_repo.toggle_active(user_id, is_active)

    # ── Certifications ─────────────────────────────────────────────

    async def get_certifications(self, user_id: int) -> list[dict]:
        """Get all certifications for an employee."""
        return await self.cert_repo.get_for_user(user_id)

    async def add_certification(self, user_id: int, data: CertificationCreate) -> int:
        """Add a certification to an employee. Returns new cert ID."""
        return await self.cert_repo.insert({
            "user_id": user_id,
            "cert_type": data.cert_type,
            "cert_name": data.cert_name,
            "issuing_authority": data.issuing_authority,
            "cert_number": data.cert_number,
            "issued_date": data.issued_date,
            "expiry_date": data.expiry_date,
            "notes": data.notes,
        })

    async def update_certification(self, cert_id: int, data: CertificationUpdate) -> bool:
        """Update a certification."""
        update_dict = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
        if not update_dict:
            return False
        return await self.cert_repo.update(cert_id, update_dict)

    async def delete_certification(self, cert_id: int) -> bool:
        """Delete a certification."""
        return await self.cert_repo.delete(cert_id)

    async def get_expiring_certifications(self, days: int = 30) -> list[dict]:
        """Get certifications expiring within N days (all employees)."""
        return await self.cert_repo.get_expiring_soon(days)

    # ── Wage History ───────────────────────────────────────────────

    async def get_wage_history(self, user_id: int) -> list[dict]:
        """Get full wage history for an employee."""
        return await self.wage_repo.get_for_user(user_id)

    async def add_wage_entry(
        self,
        user_id: int,
        data: WageHistoryCreate,
        *,
        changed_by: int | None = None,
    ) -> int:
        """Add a wage entry AND update the user's current pay_rate.

        Returns the new wage_history row ID.
        """
        entry_id = await self.wage_repo.insert({
            "user_id": user_id,
            "pay_rate": data.pay_rate,
            "effective_date": data.effective_date,
            "reason": data.reason,
            "changed_by": changed_by,
        })

        # Also update the user's current pay_rate
        await self.user_repo.update(user_id, {"pay_rate": data.pay_rate})

        return entry_id

    # ── Notes ──────────────────────────────────────────────────────

    async def get_notes(
        self,
        user_id: int,
        *,
        include_private: bool = False,
        note_type: str | None = None,
    ) -> list[dict]:
        """Get notes for an employee."""
        return await self.note_repo.get_for_user(
            user_id,
            include_private=include_private,
            note_type=note_type,
        )

    async def add_note(
        self,
        user_id: int,
        data: EmployeeNoteCreate,
        *,
        created_by: int | None = None,
    ) -> int:
        """Add a note to an employee's record. Returns note ID."""
        return await self.note_repo.insert({
            "user_id": user_id,
            "note_type": data.note_type,
            "title": data.title,
            "body": data.body,
            "is_private": 1 if data.is_private else 0,
            "created_by": created_by,
        })

    async def update_note(self, note_id: int, data: EmployeeNoteUpdate) -> bool:
        """Update a note."""
        update_dict: dict[str, Any] = {}
        for field in ("note_type", "title", "body"):
            value = getattr(data, field, None)
            if value is not None:
                update_dict[field] = value
        if data.is_private is not None:
            update_dict["is_private"] = 1 if data.is_private else 0
        if not update_dict:
            return False
        return await self.note_repo.update(note_id, update_dict)

    async def delete_note(self, note_id: int) -> bool:
        """Delete a note."""
        return await self.note_repo.delete(note_id)

    # ── Skills ─────────────────────────────────────────────────────

    async def get_skills(self, user_id: int) -> list[dict]:
        """Get all skills for an employee."""
        return await self.skill_repo.get_for_user(user_id)

    async def add_skill(self, user_id: int, data: UserSkillCreate) -> int:
        """Add a skill to an employee. Returns skill ID."""
        return await self.skill_repo.insert({
            "user_id": user_id,
            "skill_name": data.skill_name,
            "proficiency": data.proficiency,
            "years_experience": data.years_experience,
        })

    async def update_skill(self, skill_id: int, data: UserSkillUpdate) -> bool:
        """Update a skill."""
        update_dict = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
        if not update_dict:
            return False
        return await self.skill_repo.update(skill_id, update_dict)

    async def delete_skill(self, skill_id: int) -> bool:
        """Delete a skill."""
        return await self.skill_repo.delete(skill_id)

    # ── Hats (Roles) ──────────────────────────────────────────────

    async def list_hats(self) -> list[dict]:
        """Get all hats with permissions and user counts."""
        return await self.hat_repo.get_all_with_user_counts()

    async def create_hat(self, data: HatCreate) -> int:
        """Create a new hat. Returns the new hat ID."""
        return await self.hat_repo.insert({
            "name": data.name,
            "description": data.description,
            "level": data.level,
            "is_builtin": 0,
        })

    async def update_hat(self, hat_id: int, data: HatUpdate) -> bool:
        """Update a hat (name, description, level)."""
        update_dict = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
        if not update_dict:
            return False
        return await self.hat_repo.update(hat_id, update_dict)

    async def delete_hat(self, hat_id: int) -> tuple[bool, str | None]:
        """Delete a hat. Returns (success, error_message).

        Built-in hats cannot be deleted.
        """
        hat = await self.hat_repo.get_by_id(hat_id)
        if not hat:
            return False, "Hat not found."
        if hat.get("is_builtin"):
            return False, "Cannot delete built-in hats."

        # Remove all permission assignments first
        await self.db.execute(
            "DELETE FROM hat_permissions WHERE hat_id = ?", (hat_id,)
        )
        # Remove all user assignments
        await self.db.execute(
            "DELETE FROM user_hats WHERE hat_id = ?", (hat_id,)
        )
        await self.db.commit()

        deleted = await self.hat_repo.delete(hat_id)
        return deleted, None

    async def set_hat_permissions(self, hat_id: int, permission_keys: list[str]) -> None:
        """Replace all permissions for a hat."""
        await self.hat_repo.replace_permissions(hat_id, permission_keys)

    # ── Permission Matrix ─────────────────────────────────────────

    async def get_permission_matrix(self) -> dict[str, Any]:
        """Build the full permission matrix: all hats × all permissions.

        Returns:
            {
                "hats": [{id, name, level}, ...],
                "domains": {
                    "warehouse": [
                        {"permission_key": "view_warehouse", "hat_values": {1: true, 2: false, ...}},
                        ...
                    ],
                    ...
                }
            }
        """
        hats = await self.hat_repo.get_all_with_user_counts()

        # Build hat_id → set of permission keys
        hat_perm_map: dict[int, set[str]] = {}
        for hat in hats:
            hat_perm_map[hat["id"]] = set(hat.get("permissions", []))

        # Build matrix rows grouped by domain
        domains: dict[str, list[dict]] = {}
        for domain, keys in PERMISSION_DOMAINS.items():
            rows = []
            for key in keys:
                hat_values = {
                    hat["id"]: key in hat_perm_map.get(hat["id"], set())
                    for hat in hats
                }
                rows.append({
                    "permission_key": key,
                    "domain": domain,
                    "hat_values": hat_values,
                })
            domains[domain] = rows

        return {
            "hats": [
                {"id": h["id"], "name": h["name"], "level": h["level"]}
                for h in hats
            ],
            "domains": domains,
        }

    async def get_all_permission_keys(self) -> list[str]:
        """Get all known permission keys (from domains + any extras in DB)."""
        # Start with known domain keys
        known = set()
        for keys in PERMISSION_DOMAINS.values():
            known.update(keys)

        # Add any extras from the database
        db_keys = await self.hat_repo.get_all_permission_keys()
        known.update(db_keys)

        return sorted(known)

    # ── Job Lead Elevations ────────────────────────────────────────

    async def get_user_elevations(self, user_id: int) -> list[dict]:
        """Get all active elevations for a user."""
        return await self.user_repo.get_job_lead_elevations(user_id)

    async def get_job_elevations(self, job_id: int) -> list[dict]:
        """Get all active elevations for a job."""
        return await self.user_repo.get_elevations_for_job(job_id)

    async def grant_elevation(
        self,
        user_id: int,
        job_id: int,
        permission_key: str,
        *,
        granted_by: int,
    ) -> int:
        """Grant a job-level permission elevation. Returns the new row ID."""
        return await self.user_repo.grant_elevation(
            user_id, job_id, permission_key, granted_by,
        )

    async def revoke_elevation(self, elevation_id: int) -> bool:
        """Revoke a single elevation."""
        return await self.user_repo.revoke_elevation(elevation_id)

    async def revoke_all_elevations_for_job(
        self, user_id: int, job_id: int,
    ) -> int:
        """Revoke all elevations for a user on a job. Returns count revoked."""
        return await self.user_repo.revoke_all_for_job(user_id, job_id)

    # ── Cert Expiry Alerts ─────────────────────────────────────────

    async def get_cert_alerts(self, days: int = 60) -> list[dict]:
        """Get certifications expiring within N days for dashboard alerts.

        Returns items with severity 'red' (<30 days) or 'amber' (<60 days).
        Computes days_until_expiry from the expiry_date string.
        """
        from datetime import date as dt_date

        today = dt_date.today()
        rows = await self.cert_repo.get_expiring_soon(days)
        alerts = []
        for r in rows:
            try:
                exp_date = dt_date.fromisoformat(r["expiry_date"])
                d_until = (exp_date - today).days
            except (ValueError, TypeError, KeyError):
                d_until = 0
            severity = "red" if d_until < 30 else "amber"
            alerts.append({
                "cert_id": r["id"],
                "user_id": r["user_id"],
                "user_name": r.get("user_name", ""),
                "cert_name": r["cert_name"],
                "cert_type": r["cert_type"],
                "expiry_date": r["expiry_date"],
                "days_until_expiry": d_until,
                "severity": severity,
            })
        return alerts
