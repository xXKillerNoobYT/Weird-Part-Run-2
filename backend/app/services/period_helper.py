"""
Period Helper — computes billing cycle and pay period boundaries.

Reads settings from the DB (seeded by migration 045):
  - billing_cycle_type: weekly | biweekly | semi_monthly | monthly | quarterly | yearly
  - billing_cycle_start: day-of-week (1=Mon) or day-of-month (1-28)
  - pay_period_type: weekly | biweekly | semi_monthly | monthly
  - pay_period_start_day: day-of-week (1=Mon) or day-of-month (1-28)

Each helper returns named list of period dicts: {label, start, end}.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


# ── Settings Keys ─────────────────────────────────────────────────

_BILLING_KEYS = {
    "type": "billing_cycle_type",
    "start": "billing_cycle_start",
}
_PAY_KEYS = {
    "type": "pay_period_type",
    "start": "pay_period_start_day",
}


# ── Public API ────────────────────────────────────────────────────

class PeriodHelper:
    """Computes billing cycle and pay period boundaries from settings."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Read settings ─────────────────────────────────────────

    async def _get_setting(self, key: str, default: str = "") -> str:
        """Read a single setting value from the settings table."""
        cursor = await self.db.execute(
            "SELECT value FROM settings WHERE key = ?", (key,)
        )
        row = await cursor.fetchone()
        if row and row["value"]:
            # Strip surrounding quotes from JSON-encoded strings
            val = row["value"].strip()
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            return val
        return default

    async def get_billing_config(self) -> dict[str, Any]:
        """Return current billing cycle configuration."""
        cycle_type = await self._get_setting(_BILLING_KEYS["type"], "monthly")
        start_day = int(await self._get_setting(_BILLING_KEYS["start"], "1"))
        return {"cycle_type": cycle_type, "start_day": start_day}

    async def get_pay_config(self) -> dict[str, Any]:
        """Return current pay period configuration."""
        period_type = await self._get_setting(_PAY_KEYS["type"], "weekly")
        start_day = int(await self._get_setting(_PAY_KEYS["start"], "1"))
        return {"period_type": period_type, "start_day": start_day}

    async def update_billing_config(
        self, cycle_type: str, start_day: int
    ) -> None:
        """Save billing cycle configuration to settings."""
        await self._upsert_setting(
            _BILLING_KEYS["type"], f'"{cycle_type}"', "billing"
        )
        await self._upsert_setting(
            _BILLING_KEYS["start"], str(start_day), "billing"
        )
        await self.db.commit()

    async def update_pay_config(
        self, period_type: str, start_day: int
    ) -> None:
        """Save pay period configuration to settings."""
        await self._upsert_setting(
            _PAY_KEYS["type"], f'"{period_type}"', "payroll"
        )
        await self._upsert_setting(
            _PAY_KEYS["start"], str(start_day), "payroll"
        )
        await self.db.commit()

    async def _upsert_setting(
        self, key: str, value: str, category: str
    ) -> None:
        """Insert or update a setting."""
        await self.db.execute(
            """INSERT INTO settings (key, value, category)
               VALUES (?, ?, ?)
               ON CONFLICT(key) DO UPDATE SET value = excluded.value,
                                              category = excluded.category,
                                              updated_at = datetime('now')""",
            (key, value, category),
        )

    # ── Period computation ────────────────────────────────────

    async def get_billing_periods(
        self, start: str, end: str
    ) -> list[dict[str, str]]:
        """Return named billing periods that overlap with [start, end].

        Each period: {"label": "...", "start": "YYYY-MM-DD", "end": "YYYY-MM-DD"}
        """
        config = await self.get_billing_config()
        return _compute_periods(
            _parse_date(start),
            _parse_date(end),
            config["cycle_type"],
            config["start_day"],
            "Billing",
        )

    async def get_pay_periods(
        self, start: str, end: str
    ) -> list[dict[str, str]]:
        """Return named pay periods that overlap with [start, end]."""
        config = await self.get_pay_config()
        return _compute_periods(
            _parse_date(start),
            _parse_date(end),
            config["period_type"],
            config["start_day"],
            "Pay",
        )

    async def get_current_billing_period(self) -> dict[str, str]:
        """Return the billing period that contains today."""
        config = await self.get_billing_config()
        today = date.today()
        periods = _compute_periods(
            today - timedelta(days=366),
            today + timedelta(days=366),
            config["cycle_type"],
            config["start_day"],
            "Billing",
        )
        for p in periods:
            if _parse_date(p["start"]) <= today <= _parse_date(p["end"]):
                return p
        # Fallback: current calendar month
        first = today.replace(day=1)
        next_month = (first + timedelta(days=32)).replace(day=1)
        last = next_month - timedelta(days=1)
        return {"label": "Current Month", "start": _fmt(first), "end": _fmt(last)}

    async def get_current_pay_period(self) -> dict[str, str]:
        """Return the pay period that contains today."""
        config = await self.get_pay_config()
        today = date.today()
        periods = _compute_periods(
            today - timedelta(days=60),
            today + timedelta(days=60),
            config["period_type"],
            config["start_day"],
            "Pay",
        )
        for p in periods:
            if _parse_date(p["start"]) <= today <= _parse_date(p["end"]):
                return p
        # Fallback: current week
        monday = today - timedelta(days=today.weekday())
        sunday = monday + timedelta(days=6)
        return {"label": "Current Week", "start": _fmt(monday), "end": _fmt(sunday)}


# ── Period Computation (Pure Functions) ───────────────────────────

def _parse_date(s: str) -> date:
    """Parse YYYY-MM-DD string to date object."""
    return datetime.strptime(s, "%Y-%m-%d").date()


def _fmt(d: date) -> str:
    """Format date to YYYY-MM-DD."""
    return d.isoformat()


def _compute_periods(
    range_start: date,
    range_end: date,
    cycle_type: str,
    start_day: int,
    label_prefix: str,
) -> list[dict[str, str]]:
    """Generate named periods of given cycle type overlapping [range_start, range_end].

    cycle_type: weekly | biweekly | semi_monthly | monthly | quarterly | yearly
    start_day:
      - For weekly/biweekly: 1=Monday .. 7=Sunday (ISO weekday)
      - For monthly/quarterly/yearly: day-of-month (1-28)
      - For semi_monthly: first half start day (second half starts on 16th always)
    """
    periods: list[dict[str, str]] = []

    if cycle_type == "weekly":
        periods = _weekly_periods(range_start, range_end, start_day, 1, label_prefix)
    elif cycle_type == "biweekly":
        periods = _weekly_periods(range_start, range_end, start_day, 2, label_prefix)
    elif cycle_type == "semi_monthly":
        periods = _semi_monthly_periods(range_start, range_end, start_day, label_prefix)
    elif cycle_type == "monthly":
        periods = _monthly_periods(range_start, range_end, start_day, 1, label_prefix)
    elif cycle_type == "quarterly":
        periods = _monthly_periods(range_start, range_end, start_day, 3, label_prefix)
    elif cycle_type == "yearly":
        periods = _monthly_periods(range_start, range_end, start_day, 12, label_prefix)
    else:
        logger.warning("Unknown cycle_type '%s', falling back to monthly", cycle_type)
        periods = _monthly_periods(range_start, range_end, start_day, 1, label_prefix)

    return periods


def _weekly_periods(
    range_start: date,
    range_end: date,
    start_weekday: int,  # 1=Mon..7=Sun
    weeks: int,
    prefix: str,
) -> list[dict[str, str]]:
    """Generate weekly or biweekly periods."""
    # Normalize start_weekday to Python's 0=Mon..6=Sun
    py_weekday = (start_weekday - 1) % 7
    # Find the start of the first period at or before range_start
    cursor = range_start
    while cursor.weekday() != py_weekday:
        cursor -= timedelta(days=1)
    # Walk back one extra period to be safe
    cursor -= timedelta(weeks=weeks)

    periods = []
    seq = 1
    while cursor <= range_end:
        p_start = cursor
        p_end = cursor + timedelta(weeks=weeks) - timedelta(days=1)
        # Only include if it overlaps our range
        if p_end >= range_start and p_start <= range_end:
            label = f"{prefix} Week {seq}" if weeks == 1 else f"{prefix} Period {seq}"
            periods.append({
                "label": label,
                "start": _fmt(p_start),
                "end": _fmt(p_end),
            })
            seq += 1
        cursor += timedelta(weeks=weeks)

    return periods


def _semi_monthly_periods(
    range_start: date,
    range_end: date,
    first_half_start: int,
    prefix: str,
) -> list[dict[str, str]]:
    """Generate semi-monthly periods (1st-15th and 16th-end of month)."""
    # Start from the month of range_start, minus one month for safety
    y, m = range_start.year, range_start.month
    if m == 1:
        y -= 1
        m = 12
    else:
        m -= 1

    periods = []
    seq = 1
    while True:
        # First half: start_day to 15th
        first_start = _safe_date(y, m, first_half_start)
        first_end = _safe_date(y, m, 15)
        if first_start <= first_end:
            if first_end >= range_start and first_start <= range_end:
                periods.append({
                    "label": f"{prefix} {seq} (1st half)",
                    "start": _fmt(first_start),
                    "end": _fmt(first_end),
                })
                seq += 1

        # Second half: 16th to end of month
        second_start = _safe_date(y, m, 16)
        # End of month
        if m == 12:
            second_end = _safe_date(y + 1, 1, 1) - timedelta(days=1)
        else:
            second_end = _safe_date(y, m + 1, 1) - timedelta(days=1)

        if second_end >= range_start and second_start <= range_end:
            periods.append({
                "label": f"{prefix} {seq} (2nd half)",
                "start": _fmt(second_start),
                "end": _fmt(second_end),
            })
            seq += 1

        # Move to next month
        if m == 12:
            y += 1
            m = 1
        else:
            m += 1

        if _safe_date(y, m, 1) > range_end:
            break

    return periods


def _monthly_periods(
    range_start: date,
    range_end: date,
    start_day: int,  # day-of-month where period starts (1-28)
    months: int,      # 1=monthly, 3=quarterly, 12=yearly
    prefix: str,
) -> list[dict[str, str]]:
    """Generate monthly, quarterly, or yearly periods."""
    start_day = max(1, min(28, start_day))  # Clamp to 1-28

    # Start from a month before range_start
    y, m = range_start.year, range_start.month
    if m == 1:
        y -= 1
        m = 12
    else:
        m -= 1

    periods = []
    seq = 1
    while True:
        p_start = _safe_date(y, m, start_day)
        # Move forward by `months` months for end
        end_y, end_m = y, m
        for _ in range(months):
            if end_m == 12:
                end_y += 1
                end_m = 1
            else:
                end_m += 1
        p_end = _safe_date(end_y, end_m, start_day) - timedelta(days=1)

        if p_end >= range_start and p_start <= range_end:
            if months == 1:
                label = f"{prefix} {p_start.strftime('%b %Y')}"
            elif months == 3:
                q = ((m - 1) // 3) + 1
                label = f"{prefix} Q{q} {y}"
            elif months == 12:
                label = f"{prefix} {y}"
            else:
                label = f"{prefix} Period {seq}"
            periods.append({
                "label": label,
                "start": _fmt(p_start),
                "end": _fmt(p_end),
            })
            seq += 1

        # Advance
        for _ in range(months):
            if m == 12:
                y += 1
                m = 1
            else:
                m += 1

        if _safe_date(y, m, 1) > range_end + timedelta(days=31):
            break

    return periods


def _safe_date(year: int, month: int, day: int) -> date:
    """Create a date, clamping day to the month's max days."""
    import calendar
    max_day = calendar.monthrange(year, month)[1]
    return date(year, month, min(day, max_day))
