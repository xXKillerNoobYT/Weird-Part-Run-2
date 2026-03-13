/**
 * Local Dashboard Service — KPI aggregation, Fast Drive, and alert queries.
 *
 * Mirrors backend dashboard router for offline use on native devices.
 * All queries run against local SQLite — no network calls.
 *
 * Source tables: jobs, labor_entries, stock, parts, purchase_orders,
 *   notebook_entries, notifications, vehicles, vehicle_assignments,
 *   vehicle_mileage_logs, vehicle_trip_legs, certifications, users
 */

import { getDb } from '../db';
import { generateId } from '../../lib/ids';
import type {
  HomeDashboardData,
  FastDriveContext,
  FastDriveStartRequest,
  FastDriveResult,
  CertAlertItem,
  VehicleExpiryAlert,
} from '../../lib/types';

// ── Helpers ─────────────────────────────────────────────────────

/** Run a COUNT query, returning 0 if the table doesn't exist yet. */
async function safeCount(sql: string, params: any[] = []): Promise<number> {
  const db = getDb();
  try {
    const result = await db.query(sql, params);
    const row = result.values[0];
    if (!row) return 0;
    // The first column value, regardless of alias
    const val = Object.values(row)[0];
    return typeof val === 'number' ? val : 0;
  } catch {
    return 0;
  }
}

/** Run a SELECT query, returning [] if the table doesn't exist yet. */
async function safeSelect<T = Record<string, any>>(
  sql: string,
  params: any[] = [],
): Promise<T[]> {
  const db = getDb();
  try {
    const result = await db.query(sql, params);
    return result.values as T[];
  } catch {
    return [];
  }
}

// ── Dashboard KPIs ──────────────────────────────────────────────

/** Fetch live KPI counts for the home dashboard. */
export async function getDashboard(): Promise<HomeDashboardData> {
  const [
    total_parts,
    active_jobs,
    pending_orders,
    low_stock_alerts,
  ] = await Promise.all([
    safeCount(`SELECT COUNT(*) AS c FROM parts WHERE is_active = 1`),
    safeCount(`SELECT COUNT(*) AS c FROM jobs WHERE status IN ('active', 'in_progress')`),
    safeCount(`SELECT COUNT(*) AS c FROM purchase_orders WHERE status = 'pending'`),
    safeCount(`
      SELECT COUNT(*) AS c FROM (
        SELECT p.id
        FROM parts p
        JOIN stock s ON s.part_id = p.id AND s.location_type = 'warehouse'
        WHERE p.is_active = 1
          AND p.min_stock_level > 0
        GROUP BY p.id
        HAVING SUM(s.qty) < p.min_stock_level
      )
    `),
  ]);

  return {
    kpis: {
      total_parts,
      active_jobs,
      pending_orders,
      low_stock_alerts,
    },
    quick_actions: [
      { label: 'New Job', icon: 'briefcase', route: '/jobs/active' },
      { label: 'Create PO', icon: 'shopping-cart', route: '/orders/purchase-orders/new' },
      { label: 'Stock Check', icon: 'search', route: '/warehouse/inventory' },
      { label: 'Pull Parts', icon: 'arrow-right-left', route: '/warehouse/staging' },
    ],
    user_name: '', // Filled by caller from auth context
  };
}

// ── Fast Drive ──────────────────────────────────────────────────

/** Get the current user's vehicle and ranked destination list. */
export async function getFastDriveContext(userId: number): Promise<FastDriveContext> {
  const db = getDb();

  // 1. Active vehicle assignment
  const assignmentRows = await safeSelect<Record<string, any>>(
    `SELECT va.vehicle_id, va.is_take_home,
            va.home_to_shop_miles,
            v.vehicle_name, v.vehicle_number
     FROM vehicle_assignments va
     JOIN vehicles v ON v.id = va.vehicle_id
     WHERE va.user_id = ?
       AND va.is_active = 1
       AND (va.end_date IS NULL OR va.end_date >= date('now', 'localtime'))
     LIMIT 1`,
    [userId],
  );

  if (assignmentRows.length === 0) {
    return { has_vehicle: false, suggested: [], all_destinations: [] };
  }

  const assignment = assignmentRows[0];
  const vehicleId = assignment.vehicle_id;

  // 2. Build destinations: active jobs (home/shop require address fields not in local schema)
  const destinations: any[] = [];

  // 2a. Active jobs
  const jobs = await safeSelect<Record<string, any>>(
    `SELECT id, job_name, gps_lat, gps_lng, distance_from_shop_miles
     FROM jobs
     WHERE status IN ('active', 'in_progress')
     ORDER BY job_name ASC`,
  );

  for (const job of jobs) {
    destinations.push({
      type: 'job',
      label: job.job_name,
      address: null,
      gps_lat: job.gps_lat ?? null,
      gps_lng: job.gps_lng ?? null,
      miles_estimate: job.distance_from_shop_miles ?? null,
      job_id: job.id,
      trip_count_30d: 0,
    });
  }

  // 3. Rank by 30-day trip frequency (vehicle_trip_legs may not exist locally yet)
  const freqRows = await safeSelect<{ to_label: string; trip_count: number }>(
    `SELECT vtl.to_label, COUNT(*) AS trip_count
     FROM vehicle_trip_legs vtl
     JOIN vehicle_mileage_logs vml ON vml.id = vtl.mileage_log_id
     WHERE vml.driver_id = ?
       AND vml.log_date >= date('now', '-30 days', 'localtime')
     GROUP BY vtl.to_label
     ORDER BY trip_count DESC`,
    [userId],
  );

  const freqMap = new Map(freqRows.map((r) => [r.to_label, r.trip_count]));
  for (const dest of destinations) {
    dest.trip_count_30d = freqMap.get(dest.label) ?? 0;
  }

  // Sort by frequency, take top 3 as suggestions
  const ranked = [...destinations].sort(
    (a, b) => (b.trip_count_30d ?? 0) - (a.trip_count_30d ?? 0),
  );

  return {
    has_vehicle: true,
    vehicle_id: vehicleId,
    vehicle_name: assignment.vehicle_name,
    vehicle_number: assignment.vehicle_number,
    suggested: ranked.slice(0, 3),
    all_destinations: destinations,
  };
}

/** Log a trip leg for the current user's vehicle. */
export async function startDrive(
  userId: number,
  req: FastDriveStartRequest,
): Promise<FastDriveResult> {
  const db = getDb();
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

  // 1. Get active vehicle assignment
  const vaRows = await safeSelect<{ vehicle_id: number }>(
    `SELECT vehicle_id FROM vehicle_assignments
     WHERE user_id = ? AND is_active = 1
       AND (end_date IS NULL OR end_date >= date('now', 'localtime'))
     LIMIT 1`,
    [userId],
  );
  if (vaRows.length === 0) {
    throw new Error('No active vehicle assignment found');
  }
  const vehicleId = vaRows[0].vehicle_id;

  // 2. Find or create today's mileage log
  const existingLog = await safeSelect<{ id: number }>(
    `SELECT id FROM vehicle_mileage_logs
     WHERE vehicle_id = ? AND driver_id = ? AND log_date = ?
     LIMIT 1`,
    [vehicleId, userId, today],
  );

  let logId: number;
  if (existingLog.length > 0) {
    logId = existingLog[0].id;
  } else {
    const logResult = await db.run(
      `INSERT INTO vehicle_mileage_logs (vehicle_id, driver_id, log_date, created_at, updated_at)
       VALUES (?, ?, ?, datetime('now'), datetime('now'))`,
      [vehicleId, userId, today],
    );
    logId = logResult.changes.lastId;
  }

  // 3. Add trip leg
  const legResult = await db.run(
    `INSERT INTO vehicle_trip_legs
       (mileage_log_id, leg_order, leg_type, from_label, to_label,
        estimated_miles, to_job_id, from_job_id, created_at, updated_at)
     VALUES (?, 1, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))`,
    [
      logId,
      req.leg_type,
      req.from_label,
      req.to_label,
      req.estimated_miles ?? null,
      req.to_job_id ?? null,
      req.from_job_id ?? null,
    ],
  );

  return {
    mileage_log_id: logId,
    trip_leg_id: legResult.changes.lastId,
  };
}

// ── Certification Alerts ────────────────────────────────────────

/** Get certifications expiring within the look-ahead window. */
export async function getCertAlerts(days = 60): Promise<CertAlertItem[]> {
  return safeSelect<CertAlertItem>(
    `SELECT c.user_id,
            u.first_name || ' ' || u.last_name AS user_name,
            c.cert_name,
            c.expiry_date,
            CAST(julianday(c.expiry_date) - julianday(date('now', 'localtime')) AS INTEGER) AS days_until_expiry
     FROM certifications c
     JOIN users u ON u.id = c.user_id
     WHERE c.expiry_date IS NOT NULL
       AND c.is_active = 1
       AND c.deleted_at IS NULL
       AND c.expiry_date <= date('now', '+' || ? || ' days', 'localtime')
       AND c.expiry_date >= date('now', '-30 days', 'localtime')
     ORDER BY c.expiry_date ASC`,
    [days],
  );
}

// ── Vehicle Expiry Alerts ───────────────────────────────────────

/** Get vehicles with insurance or registration expiring within N days. */
export async function getVehicleExpiryAlerts(days = 60): Promise<VehicleExpiryAlert[]> {
  const rows = await safeSelect<Record<string, any>>(
    `SELECT id, vehicle_name, vehicle_number,
            insurance_expiry, registration_expiry
     FROM vehicles
     WHERE is_active = 1
       AND (
         (insurance_expiry IS NOT NULL
          AND insurance_expiry <= date('now', '+' || ? || ' days', 'localtime')
          AND insurance_expiry >= date('now', '-30 days', 'localtime'))
         OR
         (registration_expiry IS NOT NULL
          AND registration_expiry <= date('now', '+' || ? || ' days', 'localtime')
          AND registration_expiry >= date('now', '-30 days', 'localtime'))
       )
     ORDER BY COALESCE(insurance_expiry, registration_expiry) ASC`,
    [days, days],
  );

  const today = new Date().toISOString().slice(0, 10);
  const todayMs = new Date(today).getTime();
  const alerts: VehicleExpiryAlert[] = [];

  for (const v of rows) {
    for (const [alertType, field] of [
      ['insurance', 'insurance_expiry'],
      ['registration', 'registration_expiry'],
    ] as const) {
      const expiry: string | null = v[field];
      if (!expiry) continue;

      const daysUntil = Math.round(
        (new Date(expiry).getTime() - todayMs) / (1000 * 60 * 60 * 24),
      );
      if (daysUntil > days || daysUntil < -30) continue;

      alerts.push({
        vehicle_id: v.id,
        vehicle_name: v.vehicle_name,
        vehicle_number: v.vehicle_number,
        alert_type: alertType,
        expiry_date: expiry,
        days_until_expiry: daysUntil,
      });
    }
  }

  alerts.sort((a, b) => a.days_until_expiry - b.days_until_expiry);
  return alerts;
}
