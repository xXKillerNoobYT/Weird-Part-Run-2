/**
 * Local Fleet Service — read-only vehicle info for offline use.
 *
 * Field workers can view their assigned vehicle, check assignments,
 * and see what's on the truck. Vehicle management (CRUD, maintenance
 * scheduling, mileage tracking) stays shop-only.
 */

import { getDb } from '../db';

// ── Types ──────────────────────────────────────────────────────────

export interface Vehicle {
  id: number;
  name: string;
  vehicle_number: string;
  vin: string | null;
  make: string | null;
  model: string | null;
  year: number | null;
  color: string | null;
  license_plate: string | null;
  status: string;
  vehicle_type: string;
  current_mileage: number | null;
  insurance_expiry: string | null;
  registration_expiry: string | null;
  notes: string | null;
  is_active: number;
  created_at: string;
  updated_at: string;
}

export interface VehicleAssignment {
  id: number;
  vehicle_id: number;
  user_id: number;
  assignment_type: string;
  start_date: string;
  end_date: string | null;
  is_active: number;
  // Joined
  vehicle_name?: string;
  vehicle_number?: string;
  user_name?: string;
}

// ── Service Functions ──────────────────────────────────────────────

/** Get the user's assigned vehicle */
export async function getMyVehicle(userId: number): Promise<Vehicle | null> {
  const db = await getDb();

  // Check default_truck_id first
  const userResult = await db.query(
    'SELECT default_truck_id FROM users WHERE id = ?',
    [userId],
  );
  const truckId = userResult.values[0]?.default_truck_id;
  if (truckId) {
    const result = await db.query('SELECT * FROM vehicles WHERE id = ?', [truckId]);
    return (result.values[0] as Vehicle) ?? null;
  }

  // Fallback: check active assignments
  const assignResult = await db.query(
    `SELECT v.* FROM vehicles v
     JOIN vehicle_assignments va ON va.vehicle_id = v.id
     WHERE va.user_id = ? AND va.is_active = 1
     ORDER BY va.start_date DESC
     LIMIT 1`,
    [userId],
  );
  return (assignResult.values[0] as Vehicle) ?? null;
}

/** Get a vehicle by ID */
export async function getVehicle(vehicleId: number): Promise<Vehicle | null> {
  const db = await getDb();
  const result = await db.query('SELECT * FROM vehicles WHERE id = ?', [vehicleId]);
  return (result.values[0] as Vehicle) ?? null;
}

/** List all active vehicles */
export async function listVehicles(): Promise<Vehicle[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT * FROM vehicles WHERE is_active = 1 ORDER BY vehicle_number ASC',
  );
  return result.values as Vehicle[];
}

/** Get active assignments for a vehicle */
export async function getVehicleAssignments(vehicleId: number): Promise<VehicleAssignment[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT va.*, v.name as vehicle_name, v.vehicle_number,
       u.display_name as user_name
     FROM vehicle_assignments va
     JOIN vehicles v ON v.id = va.vehicle_id
     JOIN users u ON u.id = va.user_id
     WHERE va.vehicle_id = ? AND va.is_active = 1
     ORDER BY va.start_date DESC`,
    [vehicleId],
  );
  return result.values as VehicleAssignment[];
}

/** Get what stock is on a truck (delegates to warehouse-service pattern) */
export async function getTruckInventory(
  vehicleId: number,
): Promise<{ part_id: number; part_number: string; description: string; qty: number }[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT s.part_id, p.part_number, p.description, SUM(s.qty) as qty
     FROM stock s
     JOIN parts p ON p.id = s.part_id
     WHERE s.location_type = 'truck' AND s.location_id = ? AND s.qty > 0
     GROUP BY s.part_id
     ORDER BY p.part_number ASC`,
    [vehicleId],
  );
  return result.values as any[];
}
