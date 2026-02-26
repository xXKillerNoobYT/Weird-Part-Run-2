"""
APScheduler integration — Midnight daily report generation.

Runs at 12:05 AM every day to generate daily reports for all jobs
that had labor activity the previous day. Also catches up on any
missed reports on startup (e.g., if server was down at midnight).
"""

from __future__ import annotations

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.database import get_connection

logger = logging.getLogger(__name__)

# Module-level scheduler instance
scheduler = AsyncIOScheduler()


async def midnight_report_job():
    """Generate daily reports for all jobs that had activity yesterday.

    Called at 12:05 AM to ensure all clock-outs are captured.
    Runs in its own database connection to avoid contention.
    """
    # Import here to avoid circular imports
    from app.services.report_service import ReportService

    logger.info("Midnight report job starting...")
    db = await get_connection()
    try:
        svc = ReportService(db)
        reports = await svc.generate_all_pending_reports()
        logger.info("Midnight report job complete: generated %d reports", len(reports))
    except Exception:
        logger.exception("Midnight report job failed")
    finally:
        await db.close()


async def catch_up_missed_reports():
    """Generate any missed reports from days the server was down.

    Called once on startup. Looks for labor entries with no corresponding
    daily report and generates them retroactively.
    """
    from app.services.report_service import ReportService

    db = await get_connection()
    try:
        svc = ReportService(db)
        count = await svc.catch_up_missed_reports()
        if count > 0:
            logger.info("Caught up %d missed daily reports on startup", count)
    except Exception:
        logger.exception("Failed to catch up missed reports")
    finally:
        await db.close()


def start_scheduler():
    """Configure and start the APScheduler.

    Schedules:
    - midnight_report_job: runs at 12:05 AM daily
    """
    scheduler.add_job(
        midnight_report_job,
        CronTrigger(hour=0, minute=5),
        id="daily_reports",
        replace_existing=True,
    )
    scheduler.start()
    logger.info("Scheduler started — daily reports at 00:05")


def stop_scheduler():
    """Gracefully shut down the scheduler."""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler stopped")
