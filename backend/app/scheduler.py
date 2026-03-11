"""
APScheduler integration — Scheduled background tasks.

Scheduled jobs:
  - 00:05 — Generate daily reports for all jobs with labor activity
  - 00:15 — Delete PO PDF files older than 3 days
  - 00:20 — Purge notifications older than 30 days
  - 01:00 — Log retention cleanup (3 months device, 1 year shop)
  - 02:00 — Auto database backup (configurable)
  - 03:00 — Auto application backup (configurable, disabled by default)

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


async def log_retention_cleanup_job():
    """Purge old log entries based on retention policy.

    Runs at 01:00 AM daily. Applies retention windows from _log_retention_config:
    - Device logs: ~90 days (default)
    - Shop-side logs: ~365 days (default)
    """
    from app.services.device_management_service import DeviceManagementService

    logger.info("Log retention cleanup starting...")
    db = await get_connection()
    try:
        svc = DeviceManagementService(db)
        results = await svc.run_log_retention()
        total = sum(results.values())
        logger.info("Log retention cleanup complete: purged %d total rows (%s)",
                     total, results)
    except Exception:
        logger.exception("Log retention cleanup failed")
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


async def backup_db_job():
    """Create an automated database backup and run retention cleanup.

    Scheduled daily at a configurable hour (default 02:00).
    """
    from app.services.backup_service import BackupService

    logger.info("Scheduled DB backup starting...")
    db = await get_connection()
    try:
        svc = BackupService(db)
        result = await svc.run_db_backup()
        cleanup = await svc.cleanup_old_backups("db")
        logger.info(
            "Scheduled DB backup complete: %s (%d bytes), cleaned up %d old backups",
            result["file_name"], result.get("size_bytes", 0), cleanup,
        )
    except Exception:
        logger.exception("Scheduled DB backup failed")
    finally:
        await db.close()


async def backup_app_job():
    """Create an automated application code backup and run retention cleanup.

    Scheduled daily at a configurable hour (default 03:00).
    Disabled by default — enabled via settings.
    """
    from app.services.backup_service import BackupService

    logger.info("Scheduled app backup starting...")
    db = await get_connection()
    try:
        svc = BackupService(db)
        result = await svc.run_app_backup()
        cleanup = await svc.cleanup_old_backups("app")
        logger.info(
            "Scheduled app backup complete: %s (%d bytes), cleaned up %d old backups",
            result["file_name"], result.get("size_bytes", 0), cleanup,
        )
    except Exception:
        logger.exception("Scheduled app backup failed")
    finally:
        await db.close()


async def ai_anomaly_detection_job():
    """Run AI anomaly detection on labor, parts, scheduling, and cost patterns.

    Scheduled daily at 04:00 AM. Results are cached in ai_cached_results table.
    Requires AI to be enabled in settings and LM Studio to be running.
    """
    from app.services.ai_service import AiService

    logger.info("AI anomaly detection starting...")
    db = await get_connection()
    try:
        svc = AiService(db)
        anomalies = await svc.detect_anomalies()
        logger.info("AI anomaly detection complete: found %d anomalies", len(anomalies))
    except Exception:
        logger.exception("AI anomaly detection failed")
    finally:
        await db.close()


async def ai_prediction_job():
    """Run AI predictive ordering based on 90-day usage patterns.

    Scheduled daily at 04:30 AM. Results are cached in ai_cached_results table.
    Requires AI to be enabled in settings and LM Studio to be running.
    """
    from app.services.ai_service import AiService

    logger.info("AI prediction generation starting...")
    db = await get_connection()
    try:
        svc = AiService(db)
        predictions = await svc.predict_ordering(days_ahead=30)
        logger.info("AI prediction generation complete: %d predictions", len(predictions))
    except Exception:
        logger.exception("AI prediction generation failed")
    finally:
        await db.close()


async def shared_channel_expire_job():
    """Auto-expire shared channels that have passed their expiry date.

    Scheduled daily at 05:00 AM. Channels with expires_at in the past
    are deactivated automatically.
    """
    from app.services.shared_channel_service import SharedChannelService

    logger.info("Shared channel expiry check starting...")
    db = await get_connection()
    try:
        svc = SharedChannelService(db)
        expired = await svc.expire_stale_channels()
        logger.info("Shared channel expiry check complete: %d channels expired", expired)
    except Exception:
        logger.exception("Shared channel expiry check failed")
    finally:
        await db.close()


async def remote_sync_health_job():
    """Check health of all active remote sync peers.

    Scheduled every hour. Logs unhealthy peers and updates status.
    """
    from app.services.remote_sync_service import RemoteSyncService

    logger.info("Remote sync health check starting...")
    db = await get_connection()
    try:
        svc = RemoteSyncService(db)
        results = await svc.check_peer_health()
        unhealthy = [r for r in results if r.get("health") in ("stale", "offline")]
        if unhealthy:
            logger.warning(
                "Remote sync health: %d/%d peers unhealthy: %s",
                len(unhealthy), len(results),
                [f"{p['peer_name']}={p['health']}" for p in unhealthy],
            )
        else:
            logger.info("Remote sync health check complete: all %d peers healthy", len(results))
    except Exception:
        logger.exception("Remote sync health check failed")
    finally:
        await db.close()


async def file_sync_cleanup_job():
    """Clean up expired file-based sync packages.

    Scheduled daily at 05:15 AM. Deletes expired package files from disk
    and marks DB records as expired.
    """
    from app.services.file_sync_service import FileSyncService

    logger.info("File sync package cleanup starting...")
    db = await get_connection()
    try:
        svc = FileSyncService(db)
        cleaned = await svc.cleanup_expired_packages()
        logger.info("File sync cleanup complete: %d packages expired", cleaned)
    except Exception:
        logger.exception("File sync package cleanup failed")
    finally:
        await db.close()


async def bt_sync_via_tunnel_job():
    """Sync data over the Bluetooth RFCOMM tunnel (if active).

    Runs every 2 minutes. The job is a complete no-op when no BT tunnel
    is connected — it just checks the tunnel state and returns immediately.
    When a tunnel IS active and this machine is the secondary, it pushes
    local changes to the primary and pulls the primary's changes back.
    """
    from app.services.bt_sync_job import bt_sync_job

    try:
        await bt_sync_job()
    except Exception:
        logger.exception("BT sync tunnel job failed")


def start_scheduler():
    """Configure and start the APScheduler.

    Schedules:
    - midnight_report_job: runs at 12:05 AM daily
    - midnight_pdf_cleanup_job: runs at 12:15 AM daily
    - midnight_notification_cleanup_job: runs at 12:20 AM daily
    - backup_db_job: runs at 02:00 AM daily (configurable)
    - backup_app_job: runs at 03:00 AM daily (configurable, paused by default)
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
    scheduler.add_job(
        log_retention_cleanup_job,
        CronTrigger(hour=1, minute=0),
        id="log_retention_cleanup",
        replace_existing=True,
    )

    # Backup jobs — added with defaults, then rescheduled from saved settings
    scheduler.add_job(
        backup_db_job,
        CronTrigger(hour=2, minute=0),
        id="backup_db",
        replace_existing=True,
    )
    scheduler.add_job(
        backup_app_job,
        CronTrigger(hour=3, minute=0),
        id="backup_app",
        replace_existing=True,
        next_run_time=None,  # Paused by default — enabled via settings
    )

    # AI anomaly detection + prediction — runs at 04:00 AM daily
    scheduler.add_job(
        ai_anomaly_detection_job,
        CronTrigger(hour=4, minute=0),
        id="ai_anomaly_detection",
        replace_existing=True,
    )
    scheduler.add_job(
        ai_prediction_job,
        CronTrigger(hour=4, minute=30),
        id="ai_predictions",
        replace_existing=True,
    )

    # Remote sync / shared channel maintenance
    scheduler.add_job(
        shared_channel_expire_job,
        CronTrigger(hour=5, minute=0),
        id="shared_channel_expire",
        replace_existing=True,
    )
    scheduler.add_job(
        remote_sync_health_job,
        CronTrigger(minute=0),  # Every hour on the hour
        id="remote_sync_health",
        replace_existing=True,
    )
    scheduler.add_job(
        file_sync_cleanup_job,
        CronTrigger(hour=5, minute=15),
        id="file_sync_cleanup",
        replace_existing=True,
    )

    # Bluetooth sync — runs every 2 minutes when a BT tunnel is connected.
    # The job is a no-op if no tunnel is active (checks state first).
    from apscheduler.triggers.interval import IntervalTrigger

    scheduler.add_job(
        bt_sync_via_tunnel_job,
        IntervalTrigger(seconds=120),
        id="bt_sync_tunnel",
        replace_existing=True,
    )

    scheduler.start()
    logger.info(
        "Scheduler started — reports 00:05, PDF cleanup 00:15, "
        "notif cleanup 00:20, log retention 01:00, DB backup 02:00, "
        "app backup (paused), AI anomaly 04:00, AI predictions 04:30, "
        "channel expire 05:00, remote health hourly, file sync cleanup 05:15, "
        "BT sync every 2min"
    )


async def schedule_backup_jobs_from_settings():
    """Read backup settings from DB and reschedule the backup jobs.

    Called once on startup after the scheduler is running.
    """
    from app.services.backup_service import BackupService

    db = await get_connection()
    try:
        svc = BackupService(db)
        cfg = await svc.get_settings()
        reschedule_backup_jobs(cfg)
    except Exception:
        logger.exception("Failed to load backup settings for scheduling")
    finally:
        await db.close()


def reschedule_backup_jobs(cfg: dict) -> None:
    """Reschedule backup jobs based on settings dict.

    Called from both startup and the settings update endpoint.
    """
    if not scheduler.running:
        return

    # Database backup
    db_enabled = cfg.get("backup_db_enabled", True)
    db_hour = int(cfg.get("backup_db_hour", 2))
    db_minute = int(cfg.get("backup_db_minute", 0))

    try:
        job = scheduler.get_job("backup_db")
        if job:
            if db_enabled:
                job.reschedule(CronTrigger(hour=db_hour, minute=db_minute))
                logger.info("DB backup rescheduled: %02d:%02d", db_hour, db_minute)
            else:
                job.pause()
                logger.info("DB backup paused")
    except Exception:
        logger.exception("Failed to reschedule backup_db job")

    # App backup
    app_enabled = cfg.get("backup_app_enabled", False)
    app_hour = int(cfg.get("backup_app_hour", 3))
    app_minute = int(cfg.get("backup_app_minute", 0))

    try:
        job = scheduler.get_job("backup_app")
        if job:
            if app_enabled:
                job.reschedule(CronTrigger(hour=app_hour, minute=app_minute))
                logger.info("App backup rescheduled: %02d:%02d", app_hour, app_minute)
            else:
                job.pause()
                logger.info("App backup paused")
    except Exception:
        logger.exception("Failed to reschedule backup_app job")


def stop_scheduler():
    """Gracefully shut down the scheduler."""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler stopped")
