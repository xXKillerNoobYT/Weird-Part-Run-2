/**
 * Fleet & Vehicle Management API functions.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 * Mirrors the ~35 endpoints in backend/app/routers/trucks.py.
 */

import apiClient from './client';
import type {
  ApiResponse,
  StatusMessage,
  // Vehicle
  VehicleCreate,
  VehicleUpdate,
  Vehicle,
  VehicleListItem,
  // Assignments
  VehicleAssignmentCreate,
  VehicleAssignment,
  // Warehouse Locations
  WarehouseLocationCreate,
  WarehouseLocationUpdate,
  WarehouseLocation,
  // Delivery Items
  DeliveryItemBulkCreate,
  VehicleDeliveryItem,
  // Maintenance
  MaintenanceTypeCreate,
  MaintenanceTypeUpdate,
  MaintenanceType,
  MaintenanceScheduleCreate,
  MaintenanceSchedule,
  MaintenanceRecordCreate,
  MaintenanceRecord,
  MaintenanceAlert,
  MaintenanceCostSummary,
  // Mileage
  MileageLogCreate,
  MileageLogUpdate,
  MileageLog,
  TripLegCreate,
  TripLeg,
  MileageEstimate,
  MileageSummary,
  // Reimbursement
  ReimbursementCreate,
  MileageReimbursement,
  ReimbursementApproval,
  // Dashboard
  FleetDashboardStats,
  MyVehicleDashboard,
  // Inventory
  VehicleInventoryItem,
  VehicleInventoryTransfer,
} from '../lib/types';


// =================================================================
// VEHICLE CRUD
// =================================================================

/** List vehicles with optional filters. */
export async function listVehicles(params?: {
  vehicle_type?: string;
  status?: string;
  driver_id?: number;
  search?: string;
  include_inactive?: boolean;
}): Promise<VehicleListItem[]> {
  // Backend returns PaginatedData: { items, total, page, page_size, total_pages }
  const { data } = await apiClient.get<
    ApiResponse<{ items: VehicleListItem[]; total: number }>
  >('/trucks', { params });
  return data.data?.items ?? [];
}

/** Create a new vehicle. */
export async function createVehicle(
  vehicle: VehicleCreate,
): Promise<Vehicle> {
  const { data } = await apiClient.post<ApiResponse<Vehicle>>(
    '/trucks',
    vehicle,
  );
  return data.data!;
}

/** Get current user's assigned vehicle dashboard. */
export async function getMyVehicle(): Promise<MyVehicleDashboard> {
  const { data } = await apiClient.get<ApiResponse<MyVehicleDashboard>>(
    '/trucks/my-vehicle',
  );
  return data.data!;
}

/** Get full vehicle detail. */
export async function getVehicle(vehicleId: number): Promise<Vehicle> {
  const { data } = await apiClient.get<ApiResponse<Vehicle>>(
    `/trucks/${vehicleId}`,
  );
  return data.data!;
}

/** Update a vehicle. */
export async function updateVehicle(
  vehicleId: number,
  update: VehicleUpdate,
): Promise<Vehicle> {
  const { data } = await apiClient.put<ApiResponse<Vehicle>>(
    `/trucks/${vehicleId}`,
    update,
  );
  return data.data!;
}

/** Deactivate (soft delete) a vehicle. */
export async function deactivateVehicle(
  vehicleId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/${vehicleId}`,
  );
  return data.data!;
}


// =================================================================
// VEHICLE ASSIGNMENTS
// =================================================================

/** List active assignments for a vehicle. */
export async function listAssignments(
  vehicleId: number,
): Promise<VehicleAssignment[]> {
  const { data } = await apiClient.get<ApiResponse<VehicleAssignment[]>>(
    `/trucks/${vehicleId}/assignments`,
  );
  return data.data ?? [];
}

/** Assign a driver to a vehicle. */
export async function assignDriver(
  vehicleId: number,
  assignment: VehicleAssignmentCreate,
): Promise<VehicleAssignment> {
  const { data } = await apiClient.post<ApiResponse<VehicleAssignment>>(
    `/trucks/${vehicleId}/assign`,
    assignment,
  );
  return data.data!;
}

/** Unassign a driver from a vehicle. */
export async function unassignDriver(
  vehicleId: number,
  userId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/${vehicleId}/assign/${userId}`,
  );
  return data.data!;
}

/** Toggle take-home status for a driver's assignment. */
export async function toggleTakeHome(
  vehicleId: number,
  payload: { user_id: number; is_take_home: boolean },
): Promise<StatusMessage> {
  const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
    `/trucks/${vehicleId}/take-home`,
    payload,
  );
  return data.data!;
}


// =================================================================
// VEHICLE INVENTORY (Stock on Truck)
// =================================================================

/** Get parts inventory on a vehicle. */
export async function getVehicleInventory(
  vehicleId: number,
  params?: { search?: string },
): Promise<VehicleInventoryItem[]> {
  const { data } = await apiClient.get<ApiResponse<VehicleInventoryItem[]>>(
    `/trucks/${vehicleId}/inventory`,
    { params },
  );
  return data.data ?? [];
}

/** Add parts to a vehicle (stock transfer). */
export async function addToVehicleInventory(
  vehicleId: number,
  transfer: VehicleInventoryTransfer,
): Promise<{ part_id: number; qty_added: number; vehicle_id: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ part_id: number; qty_added: number; vehicle_id: number }>
  >(`/trucks/${vehicleId}/inventory/add`, transfer);
  return data.data!;
}

/** Remove parts from a vehicle (stock transfer). */
export async function removeFromVehicleInventory(
  vehicleId: number,
  transfer: VehicleInventoryTransfer & {
    to_location_type?: string;
    to_location_id?: number;
  },
): Promise<{ part_id: number; qty_removed: number; vehicle_id: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ part_id: number; qty_removed: number; vehicle_id: number }>
  >(`/trucks/${vehicleId}/inventory/remove`, transfer);
  return data.data!;
}


// =================================================================
// DELIVERY ITEMS
// =================================================================

/** Get delivery items for a vehicle. */
export async function listDeliveries(
  vehicleId: number,
  params?: { status?: string; job_id?: number },
): Promise<VehicleDeliveryItem[]> {
  const { data } = await apiClient.get<ApiResponse<VehicleDeliveryItem[]>>(
    `/trucks/${vehicleId}/deliveries`,
    { params },
  );
  return data.data ?? [];
}

/** Assign parts for delivery on a vehicle. */
export async function assignDeliveryItems(
  vehicleId: number,
  payload: DeliveryItemBulkCreate,
): Promise<VehicleDeliveryItem[]> {
  const { data } = await apiClient.post<ApiResponse<VehicleDeliveryItem[]>>(
    `/trucks/${vehicleId}/deliveries`,
    payload,
  );
  return data.data ?? [];
}

/** Update delivery item status (loaded, in_transit, etc.). */
export async function updateDeliveryStatus(
  vehicleId: number,
  itemId: number,
  payload: { status: string },
): Promise<VehicleDeliveryItem> {
  const { data } = await apiClient.put<ApiResponse<VehicleDeliveryItem>>(
    `/trucks/${vehicleId}/deliveries/${itemId}/status`,
    payload,
  );
  return data.data!;
}

/** Mark a delivery item as delivered (triggers stock movement). */
export async function markDelivered(
  vehicleId: number,
  itemId: number,
  payload?: { qty_delivered?: number },
): Promise<VehicleDeliveryItem> {
  const { data } = await apiClient.put<ApiResponse<VehicleDeliveryItem>>(
    `/trucks/${vehicleId}/deliveries/${itemId}/deliver`,
    payload ?? {},
  );
  return data.data!;
}

/** Return an undelivered item. */
export async function returnDelivery(
  vehicleId: number,
  itemId: number,
  payload?: { return_to?: 'truck' | 'warehouse'; notes?: string },
): Promise<VehicleDeliveryItem> {
  const { data } = await apiClient.put<ApiResponse<VehicleDeliveryItem>>(
    `/trucks/${vehicleId}/deliveries/${itemId}/return`,
    payload ?? {},
  );
  return data.data!;
}


// =================================================================
// MAINTENANCE TYPES (Admin)
// =================================================================

/** List all maintenance types. */
export async function listMaintenanceTypes(params?: {
  active_only?: boolean;
}): Promise<MaintenanceType[]> {
  const { data } = await apiClient.get<ApiResponse<MaintenanceType[]>>(
    '/trucks/maintenance-types',
    { params },
  );
  return data.data ?? [];
}

/** Create a new maintenance type. */
export async function createMaintenanceType(
  mtype: MaintenanceTypeCreate,
): Promise<MaintenanceType> {
  const { data } = await apiClient.post<ApiResponse<MaintenanceType>>(
    '/trucks/maintenance-types',
    mtype,
  );
  return data.data!;
}

/** Update a maintenance type. */
export async function updateMaintenanceType(
  typeId: number,
  update: MaintenanceTypeUpdate,
): Promise<MaintenanceType> {
  const { data } = await apiClient.put<ApiResponse<MaintenanceType>>(
    `/trucks/maintenance-types/${typeId}`,
    update,
  );
  return data.data!;
}


// =================================================================
// MAINTENANCE SCHEDULES
// =================================================================

/** Get per-vehicle maintenance schedule. */
export async function getMaintenanceSchedule(
  vehicleId: number,
): Promise<MaintenanceSchedule[]> {
  const { data } = await apiClient.get<ApiResponse<MaintenanceSchedule[]>>(
    `/trucks/${vehicleId}/maintenance/schedule`,
  );
  return data.data ?? [];
}

/** Set or update a schedule entry for a vehicle. */
export async function setMaintenanceSchedule(
  vehicleId: number,
  schedule: MaintenanceScheduleCreate,
): Promise<MaintenanceSchedule> {
  const { data } = await apiClient.post<ApiResponse<MaintenanceSchedule>>(
    `/trucks/${vehicleId}/maintenance/schedule`,
    schedule,
  );
  return data.data!;
}

/** Get fleet-wide upcoming maintenance (within N days). */
export async function getUpcomingMaintenance(params?: {
  days_ahead?: number;
  vehicle_id?: number;
}): Promise<MaintenanceAlert[]> {
  const { data } = await apiClient.get<ApiResponse<MaintenanceAlert[]>>(
    '/trucks/maintenance/upcoming',
    { params },
  );
  return data.data ?? [];
}

/** Get fleet-wide overdue maintenance. */
export async function getOverdueMaintenance(params?: {
  vehicle_id?: number;
}): Promise<MaintenanceAlert[]> {
  const { data } = await apiClient.get<ApiResponse<MaintenanceAlert[]>>(
    '/trucks/maintenance/overdue',
    { params },
  );
  return data.data ?? [];
}


// =================================================================
// MAINTENANCE RECORDS (Service History)
// =================================================================

/** Get service history for a vehicle. */
export async function getServiceHistory(
  vehicleId: number,
  params?: {
    maintenance_type_id?: number;
    limit?: number;
    offset?: number;
  },
): Promise<MaintenanceRecord[]> {
  const { data } = await apiClient.get<ApiResponse<MaintenanceRecord[]>>(
    `/trucks/${vehicleId}/maintenance/history`,
    { params },
  );
  return data.data ?? [];
}

/** Log a maintenance service for a vehicle. */
export async function logService(
  vehicleId: number,
  record: MaintenanceRecordCreate,
): Promise<MaintenanceRecord> {
  const { data } = await apiClient.post<ApiResponse<MaintenanceRecord>>(
    `/trucks/${vehicleId}/maintenance/log`,
    record,
  );
  return data.data!;
}

/** Get maintenance cost summary for a vehicle. */
export async function getMaintenanceCosts(
  vehicleId: number,
  params?: { period_start?: string; period_end?: string },
): Promise<MaintenanceCostSummary> {
  const { data } = await apiClient.get<ApiResponse<MaintenanceCostSummary>>(
    `/trucks/${vehicleId}/maintenance/costs`,
    { params },
  );
  return data.data!;
}


// =================================================================
// MILEAGE LOGS
// =================================================================

/** Get mileage logs for a vehicle. */
export async function getMileageLogs(
  vehicleId: number,
  params?: { limit?: number; offset?: number },
): Promise<MileageLog[]> {
  const { data } = await apiClient.get<ApiResponse<MileageLog[]>>(
    `/trucks/${vehicleId}/mileage`,
    { params },
  );
  return data.data ?? [];
}

/** Log daily mileage for a vehicle. */
export async function logMileage(
  vehicleId: number,
  log: MileageLogCreate,
): Promise<MileageLog> {
  const { data } = await apiClient.post<ApiResponse<MileageLog>>(
    `/trucks/${vehicleId}/mileage`,
    log,
  );
  return data.data!;
}

/** Update a mileage log entry. */
export async function updateMileageLog(
  vehicleId: number,
  logId: number,
  update: MileageLogUpdate,
): Promise<MileageLog> {
  const { data } = await apiClient.put<ApiResponse<MileageLog>>(
    `/trucks/${vehicleId}/mileage/${logId}`,
    update,
  );
  return data.data!;
}

/** Get trip legs for a mileage log. */
export async function getTripLegs(
  vehicleId: number,
  logId: number,
): Promise<TripLeg[]> {
  const { data } = await apiClient.get<ApiResponse<TripLeg[]>>(
    `/trucks/${vehicleId}/mileage/${logId}/trips`,
  );
  return data.data ?? [];
}

/** Add trip legs to a mileage log (bulk). */
export async function addTripLegs(
  vehicleId: number,
  logId: number,
  legs: TripLegCreate[],
): Promise<TripLeg[]> {
  const { data } = await apiClient.post<ApiResponse<TripLeg[]>>(
    `/trucks/${vehicleId}/mileage/${logId}/trips`,
    { legs },
  );
  return data.data ?? [];
}

/** Estimate trip mileage based on manual distances. */
export async function estimateMileage(params: {
  vehicle_id?: number;
  job_id?: number;
  user_id?: number;
}): Promise<MileageEstimate> {
  const { data } = await apiClient.get<ApiResponse<MileageEstimate>>(
    '/trucks/mileage/estimate',
    { params },
  );
  return data.data!;
}

/** Get mileage summary for a period. */
export async function getMileageSummary(params: {
  vehicle_id?: number;
  driver_id?: number;
  period_start?: string;
  period_end?: string;
}): Promise<MileageSummary> {
  const { data } = await apiClient.get<ApiResponse<MileageSummary>>(
    '/trucks/mileage/summary',
    { params },
  );
  return data.data!;
}


// =================================================================
// MILEAGE REIMBURSEMENTS
// =================================================================

/** List reimbursements (optionally by user or status). */
export async function listReimbursements(params?: {
  user_id?: number;
  status?: string;
}): Promise<MileageReimbursement[]> {
  const { data } = await apiClient.get<ApiResponse<MileageReimbursement[]>>(
    '/trucks/reimbursements',
    { params },
  );
  return data.data ?? [];
}

/** Get pending reimbursements count. */
export async function getPendingReimbursements(): Promise<
  MileageReimbursement[]
> {
  const { data } = await apiClient.get<ApiResponse<MileageReimbursement[]>>(
    '/trucks/reimbursements/pending',
  );
  return data.data ?? [];
}

/** Create a reimbursement request. */
export async function createReimbursement(
  reimbursement: ReimbursementCreate,
): Promise<MileageReimbursement> {
  const { data } = await apiClient.post<ApiResponse<MileageReimbursement>>(
    '/trucks/reimbursements',
    reimbursement,
  );
  return data.data!;
}

/** Approve or reject a reimbursement. */
export async function approveReimbursement(
  reimbursementId: number,
  approval: ReimbursementApproval,
): Promise<MileageReimbursement> {
  const { data } = await apiClient.put<ApiResponse<MileageReimbursement>>(
    `/trucks/reimbursements/${reimbursementId}/approve`,
    approval,
  );
  return data.data!;
}


// =================================================================
// WAREHOUSE LOCATIONS
// =================================================================

/** List warehouse/shop locations. */
export async function listWarehouseLocations(params?: {
  include_inactive?: boolean;
}): Promise<WarehouseLocation[]> {
  const { data } = await apiClient.get<ApiResponse<WarehouseLocation[]>>(
    '/trucks/warehouse-locations',
    { params },
  );
  return data.data ?? [];
}

/** Create a new warehouse/shop location. */
export async function createWarehouseLocation(
  location: WarehouseLocationCreate,
): Promise<WarehouseLocation> {
  const { data } = await apiClient.post<ApiResponse<WarehouseLocation>>(
    '/trucks/warehouse-locations',
    location,
  );
  return data.data!;
}

/** Update a warehouse/shop location. */
export async function updateWarehouseLocation(
  locationId: number,
  update: WarehouseLocationUpdate,
): Promise<WarehouseLocation> {
  const { data } = await apiClient.put<ApiResponse<WarehouseLocation>>(
    `/trucks/warehouse-locations/${locationId}`,
    update,
  );
  return data.data!;
}

/** Deactivate a warehouse/shop location. */
export async function deactivateWarehouseLocation(
  locationId: number,
): Promise<StatusMessage> {
  const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/warehouse-locations/${locationId}`,
  );
  return data.data!;
}


// =================================================================
// FLEET DASHBOARD
// =================================================================

/** Get fleet-wide dashboard stats. */
export async function getFleetDashboard(): Promise<FleetDashboardStats> {
  const { data } = await apiClient.get<ApiResponse<FleetDashboardStats>>(
    '/trucks/fleet/dashboard',
  );
  return data.data!;
}
