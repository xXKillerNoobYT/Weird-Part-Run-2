/**
 * Local Trailer Service — trailer management and location tracking.
 *
 * Manages job trailers (master records) and their location history.
 * Supports: CRUD, status transitions, location event logging.
 *
 * Source tables: migration 012_warehouse_attachments
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface TrailerCreate {
  trailer_code: string;
  name: string;
  status?: string;
  current_job_id?: number;
  assigned_driver_user_id?: number;
  notes?: string;
}

export interface TrailerUpdate {
  name?: string;
  status?: string;
  current_job_id?: number;
  assigned_driver_user_id?: number;
  notes?: string;
  is_active?: number;
}

export interface Trailer {
  id: number;
  trailer_code: string;
  name: string;
  status: string;
  current_job_id: number | null;
  assigned_driver_user_id: number | null;
  notes: string | null;
  is_active: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  // Joined fields
  current_job_name?: string;
  driver_name?: string;
  last_location?: string;
}

export interface LocationEventCreate {
  trailer_id: number;
  event_type?: string;
  location_kind?: string;
  job_id?: number;
  lat?: number;
  lng?: number;
  recorded_by: number;
  notes?: string;
}

export interface TrailerLocationEvent {
  id: number;
  trailer_id: number;
  event_type: string;
  location_kind: string;
  job_id: number | null;
  lat: number | null;
  lng: number | null;
  recorded_by: number;
  recorded_at: string;
  notes: string | null;
  // Joined fields
  recorded_by_name?: string;
  job_name?: string;
}

// ── Repos ──────────────────────────────────────────────────────────

const trailerRepo = new BaseRepo('job_trailers');
const eventRepo = new BaseRepo('trailer_location_events');

// ═══════════════════════════════════════════════════════════════════
// TRAILERS
// ═══════════════════════════════════════════════════════════════════

/** Create a trailer */
export async function createTrailer(data: TrailerCreate): Promise<Trailer> {
  const now = new Date().toISOString();
  const id = await trailerRepo.insert({
    trailer_code: data.trailer_code,
    name: data.name,
    status: data.status ?? 'active',
    current_job_id: data.current_job_id ?? null,
    assigned_driver_user_id: data.assigned_driver_user_id ?? null,
    notes: data.notes ?? null,
    is_active: 1,
    created_at: now,
    updated_at: now,
  });
  return (await getTrailer(id))!;
}

/** Get a trailer by ID with joined info */
export async function getTrailer(id: number): Promise<Trailer | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*,
       j.job_name as current_job_name,
       u.display_name as driver_name,
       (SELECT tle.location_kind FROM trailer_location_events tle
        WHERE tle.trailer_id = t.id ORDER BY tle.recorded_at DESC LIMIT 1) as last_location
     FROM job_trailers t
     LEFT JOIN jobs j ON j.id = t.current_job_id
     LEFT JOIN users u ON u.id = t.assigned_driver_user_id
     WHERE t.id = ?`,
    [id],
  );
  return (result.values[0] as Trailer) ?? null;
}

/** List all trailers */
export async function listTrailers(opts?: {
  status?: string;
  is_active?: number;
  search?: string;
}): Promise<Trailer[]> {
  const db = await getDb();
  const conditions: string[] = ['t.deleted_at IS NULL'];
  const params: any[] = [];

  if (opts?.status) {
    conditions.push('t.status = ?');
    params.push(opts.status);
  }
  if (opts?.is_active !== undefined) {
    conditions.push('t.is_active = ?');
    params.push(opts.is_active);
  } else {
    conditions.push('t.is_active = 1');
  }
  if (opts?.search) {
    conditions.push('(t.trailer_code LIKE ? OR t.name LIKE ?)');
    const term = `%${opts.search}%`;
    params.push(term, term);
  }

  const result = await db.query(
    `SELECT t.*,
       j.job_name as current_job_name,
       u.display_name as driver_name
     FROM job_trailers t
     LEFT JOIN jobs j ON j.id = t.current_job_id
     LEFT JOIN users u ON u.id = t.assigned_driver_user_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY t.trailer_code ASC`,
    params,
  );
  return result.values as Trailer[];
}

/** Update a trailer */
export async function updateTrailer(id: number, data: TrailerUpdate): Promise<Trailer | null> {
  const updated = await trailerRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getTrailer(id);
}

/** Soft-delete a trailer */
export async function deleteTrailer(id: number): Promise<boolean> {
  return trailerRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// LOCATION EVENTS (append-only — no update/delete)
// ═══════════════════════════════════════════════════════════════════

/** Record a location event for a trailer */
export async function recordLocationEvent(data: LocationEventCreate): Promise<TrailerLocationEvent> {
  const id = await eventRepo.insert({
    trailer_id: data.trailer_id,
    event_type: data.event_type ?? 'manual_update',
    location_kind: data.location_kind ?? 'other',
    job_id: data.job_id ?? null,
    lat: data.lat ?? null,
    lng: data.lng ?? null,
    recorded_by: data.recorded_by,
    recorded_at: new Date().toISOString(),
    notes: data.notes ?? null,
  });
  return (await eventRepo.getById(id)) as TrailerLocationEvent;
}

/** Get location history for a trailer */
export async function getTrailerLocationHistory(
  trailerId: number,
  opts?: { limit?: number },
): Promise<TrailerLocationEvent[]> {
  const db = await getDb();
  const limit = opts?.limit ?? 50;
  const result = await db.query(
    `SELECT tle.*, u.display_name as recorded_by_name, j.job_name
     FROM trailer_location_events tle
     LEFT JOIN users u ON u.id = tle.recorded_by
     LEFT JOIN jobs j ON j.id = tle.job_id
     WHERE tle.trailer_id = ?
     ORDER BY tle.recorded_at DESC
     LIMIT ?`,
    [trailerId, limit],
  );
  return result.values as TrailerLocationEvent[];
}

/** Get the latest location event for each active trailer */
export async function getTrailerCurrentLocations(): Promise<(Trailer & { last_event: TrailerLocationEvent | null })[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*,
       tle.event_type as last_event_type,
       tle.location_kind as last_location_kind,
       tle.recorded_at as last_event_at,
       j.job_name as current_job_name,
       u.display_name as driver_name
     FROM job_trailers t
     LEFT JOIN jobs j ON j.id = t.current_job_id
     LEFT JOIN users u ON u.id = t.assigned_driver_user_id
     LEFT JOIN trailer_location_events tle ON tle.id = (
       SELECT tle2.id FROM trailer_location_events tle2
       WHERE tle2.trailer_id = t.id
       ORDER BY tle2.recorded_at DESC LIMIT 1
     )
     WHERE t.is_active = 1 AND t.deleted_at IS NULL
     ORDER BY t.trailer_code ASC`,
  );
  return result.values as any[];
}
