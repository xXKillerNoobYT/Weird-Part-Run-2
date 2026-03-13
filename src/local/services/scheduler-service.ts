/**
 * Scheduler Service — lightweight cron-like scheduler for Tauri mode.
 *
 * Replaces Python APScheduler for local device tasks. Uses setInterval
 * with time-of-day checks rather than real cron expressions — simpler
 * and sufficient since the app is not a 24/7 server.
 *
 * Jobs:
 *   - Notification cleanup: purge >30 days (daily, ~00:20)
 *   - Change log retention: purge synced entries >90 days (daily, ~01:00)
 *   - DB backup: VACUUM INTO a timestamped copy (daily, configurable hour)
 *
 * Catch-up logic: On start, checks if any job was missed (app was closed
 * at scheduled time) and runs it immediately if the last run was >24h ago.
 *
 * State is persisted in the `_scheduler_state` table so we know when
 * each job last ran.
 */

import { getDb } from '../db';
import { isNativeApp } from '../../lib/environment';

// ── Types ──────────────────────────────────────────────────────────

interface ScheduledJob {
  id: string;
  /** Hour of day (0-23) to run. null = interval-based, not time-based. */
  hour: number;
  /** Minute of hour (0-59) to run. */
  minute: number;
  /** Whether the job is enabled. */
  enabled: boolean;
  /** The async function to execute. */
  fn: () => Promise<void>;
}

// ── State ──────────────────────────────────────────────────────────

let _running = false;
let _tickTimer: ReturnType<typeof setInterval> | null = null;
const _jobs: Map<string, ScheduledJob> = new Map();

// Track which jobs already fired this calendar minute to avoid double-runs
const _firedThisMinute: Set<string> = new Set();
let _lastCheckedMinute = -1;

// ── Schema bootstrap ───────────────────────────────────────────────

async function ensureTable(): Promise<void> {
  const db = await getDb();
  await db.run(`
    CREATE TABLE IF NOT EXISTS _scheduler_state (
      job_id   TEXT PRIMARY KEY,
      last_run TEXT,
      status   TEXT DEFAULT 'ok'
    )
  `);
}

async function getLastRun(jobId: string): Promise<Date | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT last_run FROM _scheduler_state WHERE job_id = ?`,
    [jobId],
  );
  const row = result.values[0] as { last_run: string } | undefined;
  return row?.last_run ? new Date(row.last_run) : null;
}

async function setLastRun(jobId: string, status = 'ok'): Promise<void> {
  const db = await getDb();
  await db.run(
    `INSERT OR REPLACE INTO _scheduler_state (job_id, last_run, status)
     VALUES (?, datetime('now'), ?)`,
    [jobId, status],
  );
}

// ── Job Implementations ────────────────────────────────────────────

/**
 * Purge notifications older than 30 days.
 * Matches Python: midnight_notification_cleanup_job
 */
async function notificationCleanup(): Promise<void> {
  const db = await getDb();
  const result = await db.run(
    `DELETE FROM notifications WHERE created_at < datetime('now', '-30 days')`,
  );
  const count = result?.changes?.changes ?? 0;
  if (count > 0) {
    console.log(`[scheduler] Purged ${count} old notifications`);
  }
}

/**
 * Purge synced change_log entries older than 90 days.
 * Keeps unsynced entries forever (they still need to sync).
 * Matches Python: log_retention_cleanup_job
 */
async function changeLogRetention(): Promise<void> {
  const db = await getDb();
  const result = await db.run(
    `DELETE FROM _change_log
     WHERE synced = 1 AND timestamp < datetime('now', '-90 days')`,
  );
  const count = result?.changes?.changes ?? 0;
  if (count > 0) {
    console.log(`[scheduler] Purged ${count} old change_log entries`);
  }
}

/**
 * Create a SQLite database backup using VACUUM INTO.
 *
 * Stores the backup in the Tauri app data directory under `backups/`.
 * Keeps the last N backups (default 5) and deletes older ones.
 *
 * In browser mode this is a no-op — backups are managed by the Python server.
 */
async function dbBackup(): Promise<void> {
  if (!isNativeApp()) return;

  try {
    const { appDataDir, join } = await import('@tauri-apps/api/path');
    const { mkdir, exists, readDir, remove } = await import(
      '@tauri-apps/plugin-fs'
    );

    const appData = await appDataDir();
    const backupDir = await join(appData, 'backups');

    // Ensure backup directory exists
    if (!(await exists(backupDir))) {
      await mkdir(backupDir, { recursive: true });
    }

    // Generate timestamped filename
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const backupPath = await join(backupDir, `wiredpart-backup-${ts}.db`);

    // VACUUM INTO creates an exact, defragmented copy
    const db = await getDb();
    await db.run(`VACUUM INTO '${backupPath}'`);
    console.log(`[scheduler] DB backup created: ${backupPath}`);

    // Retention: keep last 5 backups, delete older ones
    const MAX_BACKUPS = 5;
    const entries = await readDir(backupDir);
    const backups = entries
      .filter((e: any) => e.name?.startsWith('wiredpart-backup-') && e.name?.endsWith('.db'))
      .sort((a: any, b: any) => (b.name ?? '').localeCompare(a.name ?? ''));

    if (backups.length > MAX_BACKUPS) {
      for (const old of backups.slice(MAX_BACKUPS)) {
        const oldPath = await join(backupDir, old.name!);
        await remove(oldPath);
        console.log(`[scheduler] Removed old backup: ${old.name}`);
      }
    }
  } catch (err) {
    console.error('[scheduler] DB backup failed:', err);
    throw err;
  }
}

// ── Core Scheduler Logic ───────────────────────────────────────────

/**
 * Register the default set of scheduled jobs.
 */
function registerDefaultJobs(): void {
  _jobs.set('notification_cleanup', {
    id: 'notification_cleanup',
    hour: 0,
    minute: 20,
    enabled: true,
    fn: notificationCleanup,
  });

  _jobs.set('change_log_retention', {
    id: 'change_log_retention',
    hour: 1,
    minute: 0,
    enabled: true,
    fn: changeLogRetention,
  });

  _jobs.set('db_backup', {
    id: 'db_backup',
    hour: 2,
    minute: 0,
    enabled: true,
    fn: dbBackup,
  });
}

/**
 * Check if it's time to run any jobs. Called every 60 seconds.
 */
async function tick(): Promise<void> {
  const now = new Date();
  const currentHour = now.getHours();
  const currentMinute = now.getMinutes();
  const minuteKey = currentHour * 60 + currentMinute;

  // Reset the fired-this-minute set when the minute changes
  if (minuteKey !== _lastCheckedMinute) {
    _firedThisMinute.clear();
    _lastCheckedMinute = minuteKey;
  }

  for (const job of _jobs.values()) {
    if (!job.enabled) continue;
    if (_firedThisMinute.has(job.id)) continue;

    if (currentHour === job.hour && currentMinute === job.minute) {
      _firedThisMinute.add(job.id);
      await runJob(job);
    }
  }
}

/**
 * Execute a single job with error handling and state persistence.
 */
async function runJob(job: ScheduledJob): Promise<void> {
  console.log(`[scheduler] Running job: ${job.id}`);
  try {
    await job.fn();
    await setLastRun(job.id, 'ok');
  } catch (err) {
    console.error(`[scheduler] Job ${job.id} failed:`, err);
    await setLastRun(job.id, 'error');
  }
}

/**
 * On startup, check if any jobs missed their window and need catch-up.
 * A job needs catch-up if it hasn't run in the last 24 hours.
 */
async function catchUpMissedJobs(): Promise<void> {
  const now = Date.now();
  const ONE_DAY = 24 * 60 * 60 * 1000;

  for (const job of _jobs.values()) {
    if (!job.enabled) continue;

    const lastRun = await getLastRun(job.id);
    if (!lastRun || now - lastRun.getTime() > ONE_DAY) {
      console.log(`[scheduler] Catching up missed job: ${job.id}`);
      await runJob(job);
    }
  }
}

// ── Public API ─────────────────────────────────────────────────────

/**
 * Start the scheduler. Safe to call multiple times.
 * Registers default jobs, catches up missed runs, then ticks every 60s.
 */
export async function startScheduler(): Promise<void> {
  if (_running) return;
  if (!isNativeApp()) return;

  await ensureTable();
  registerDefaultJobs();
  _running = true;

  console.log('[scheduler] Starting scheduler with jobs:', [..._jobs.keys()].join(', '));

  // Catch up on any missed jobs (app was closed at scheduled time)
  await catchUpMissedJobs();

  // Tick every 60 seconds
  _tickTimer = setInterval(() => {
    tick().catch((err) => console.error('[scheduler] Tick error:', err));
  }, 60_000);
}

/**
 * Stop the scheduler.
 */
export function stopScheduler(): void {
  if (_tickTimer) {
    clearInterval(_tickTimer);
    _tickTimer = null;
  }
  _running = false;
  _jobs.clear();
  _firedThisMinute.clear();
  console.log('[scheduler] Stopped');
}

/**
 * Update the DB backup schedule (called from backup settings UI).
 */
export function rescheduleBackup(hour: number, minute: number, enabled: boolean): void {
  const job = _jobs.get('db_backup');
  if (job) {
    job.hour = hour;
    job.minute = minute;
    job.enabled = enabled;
    console.log(
      `[scheduler] DB backup rescheduled: ${enabled ? `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}` : 'disabled'}`,
    );
  }
}

/**
 * Manually trigger a specific job (e.g., from a "Run Now" button).
 */
export async function runJobManually(jobId: string): Promise<boolean> {
  const job = _jobs.get(jobId);
  if (!job) return false;
  await runJob(job);
  return true;
}

/** Check if the scheduler is running */
export function isSchedulerRunning(): boolean {
  return _running;
}

/** Get status of all registered jobs */
export async function getJobStatuses(): Promise<
  Array<{ id: string; enabled: boolean; hour: number; minute: number; lastRun: string | null; status: string | null }>
> {
  const db = await getDb();
  const result = await db.query(
    `SELECT job_id, last_run, status FROM _scheduler_state`,
  );
  const states = result.values as Array<{ job_id: string; last_run: string; status: string }>;
  const stateMap = new Map(states.map((s) => [s.job_id, s]));

  return [..._jobs.values()].map((job) => {
    const state = stateMap.get(job.id);
    return {
      id: job.id,
      enabled: job.enabled,
      hour: job.hour,
      minute: job.minute,
      lastRun: state?.last_run ?? null,
      status: state?.status ?? null,
    };
  });
}
