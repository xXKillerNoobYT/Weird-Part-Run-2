"""
APScheduler integration — Midnight daily tasks.

Scheduled jobs:
  - 00:05 — Generate daily reports for all jobs with labor activity
  - 00:15 — Delete PO PDF files older than 3 days
  - 00:20 — Purge notifications older than 30 days

Also catches up on any missed reports on startup.
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


async def midnight_pdf_cleanup_job():
    """Delete PO PDF files older than 3 days.

    PO data is permanent in the DB — PDFs are ephemeral and can be
    re-generated on demand. Keeps the tmp/pdfs/ directory clean.
    """
    from app.services.pdf_service import PDFService

    logger.info("PDF cleanup job starting...")
    db = await get_connection()
    try:
        svc = PDFService(db)
        count = await svc.cleanup_old_pdfs(max_age_days=3)
        logger.info("PDF cleanup job complete: removed %d old PDFs", count)
    except Exception:
        logger.exception("PDF cleanup job failed")
    finally:
        await db.close()


async def midnight_notification_cleanup_job():
    """Purge notifications older than 30 days.

    Old notifications add no value and slow down queries.
    Users can see the order status history for audit purposes.
    """
    from app.services.notification_service import NotificationService

    logger.info("Notification cleanup job starting...")
    db = await get_connection()
    try:
        svc = NotificationService(db)
        count = await svc.cleanup_old_notifications(days=30)
        logger.info("Notification cleanup job complete: purged %d old notifications", count)
    except Exception:
        logger.exception("Notification cleanup job failed")
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
    scheduler.add_job(
        midnight_pdf_cleanup_job,
        CronTrigger(hour=0, minute=15),
        id="pdf_cleanup",
        replace_existing=True,
    )
    scheduler.add_job(
        midnight_notification_cleanup_job,
        CronTrigger(hour=0, minute=20),
        id="notification_cleanup",
        replace_existing=True,
    )
    scheduler.start()
    logger.info(
        "Scheduler started — daily reports at 00:05, "
        "PDF cleanup at 00:15, notification cleanup at 00:20"
    )


def stop_scheduler():
    """Gracefully shut down the scheduler."""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler stopped")
