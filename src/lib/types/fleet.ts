/**
 * Fleet & Vehicle Management types — vehicles, assignments, deliveries, maintenance,
 * mileage, reimbursements, fleet dashboard, trailers, fuel, telematics, inspections,
 * transfers, alerts, home dashboard.
 */

// ═══════════════════════════════════════════════════════════════════
// FLEET & VEHICLE MANAGEMENT (Phase 6)
// ═══════════════════════════════════════════════════════════════════

// ── Vehicle Types ──────────────────────────────────────────────────

export type VehicleType = 'company_truck' | 'company_van' | 'company_car' | 'private_vehicle';
export type VehicleStatus = 'active' | 'inactive' | 'maintenance' | 'retired';

export interface VehicleCreate {
  vehicle_number: string;
  vehicle_name?: string;
  vehicle_type?: VehicleType;
  make?: string;
  model?: string;
  year?: number;
  color?: string;
  vin?: string;
  license_plate?: string;
  insurance_policy?: string;
  insurance_expiry?: string;
  registration_expiry?: string;
  current_odometer?: number;
  owner_user_id?: number;
  notes?: string;
}

export interface VehicleUpdate {
  vehicle_name?: string;
  vehicle_type?: VehicleType;
  status?: VehicleStatus;
  make?: string;
  model?: string;
  year?: number;
  color?: string;
  vin?: string;
  license_plate?: string;
  insurance_policy?: string;
  insurance_expiry?: string;
  registration_expiry?: string;
  current_odometer?: number;
  notes?: string;
  photo_path?: string;
}

export interface Vehicle {
  id: number;
  vehicle_number: string;
  vehicle_name: string;
  vehicle_type: VehicleType;
  status: VehicleStatus;
  make: string | null;
  model: string | null;
  year: number | null;
  color: string | null;
  vin: string | null;
  license_plate: string | null;
  insurance_policy: string | null;
  insurance_expiry: string | null;
  registration_expiry: string | null;
  current_odometer: number;
  owner_user_id: number | null;
  notes: string | null;
  photo_path: string | null;
  is_active: boolean;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  owner_name: string | null;
  primary_driver_name: string | null;
  primary_driver_id: number | null;
  assignment_count: number;
  next_maintenance_due: string | null;
  next_maintenance_type: string | null;
}

export interface VehicleListItem {
  id: number;
  vehicle_number: string;
  vehicle_name: string;
  vehicle_type: VehicleType;
  status: VehicleStatus;
  make: string | null;
  model: string | null;
  year: number | null;
  license_plate: string | null;
  current_odometer: number;
  is_active: boolean;
  is_take_home: boolean;
  created_at: string | null;
  // Joined fields
  primary_driver_name: string | null;
  primary_driver_id: number | null;
  next_maintenance_due: string | null;
  overdue_maintenance_count: number;
  upcoming_maintenance_count: number;
}

// ── Vehicle Assignments ────────────────────────────────────────────

export type AssignmentType = 'primary' | 'authorized' | 'temporary';

export interface VehicleAssignmentCreate {
  user_id: number;
  assignment_type?: AssignmentType;
  is_take_home?: boolean;
  home_to_shop_miles?: number;
  home_address_street?: string;
  home_address_city?: string;
  home_address_state?: string;
  home_address_zip?: string;
  notes?: string;
}

export interface VehicleAssignment {
  id: number;
  vehicle_id: number;
  user_id: number;
  assignment_type: AssignmentType;
  is_take_home: boolean;
  home_to_shop_miles: number | null;
  home_address_street: string | null;
  home_address_city: string | null;
  home_address_state: string | null;
  home_address_zip: string | null;
  start_date: string | null;
  end_date: string | null;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  user_name: string | null;
  vehicle_name: string | null;
  vehicle_number: string | null;
}

// ── Warehouse Locations ────────────────────────────────────────────

export interface WarehouseLocationCreate {
  name: string;
  address_street?: string;
  address_city?: string;
  address_state?: string;
  address_zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  is_primary?: boolean;
  company_profile_id?: number;
  phone?: string;
  notes?: string;
}

export interface WarehouseLocationUpdate {
  name?: string;
  address_street?: string;
  address_city?: string;
  address_state?: string;
  address_zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  is_primary?: boolean;
  company_profile_id?: number;
  phone?: string;
  is_active?: boolean;
  notes?: string;
}

export interface WarehouseLocation {
  id: number;
  name: string;
  address_street: string | null;
  address_city: string | null;
  address_state: string | null;
  address_zip: string | null;
  gps_lat: number | null;
  gps_lng: number | null;
  is_primary: boolean;
  is_active: boolean;
  company_profile_id: number | null;
  phone: string | null;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
}

// ── Vehicle Delivery Items ─────────────────────────────────────────

export type DeliveryStatus = 'assigned' | 'loaded' | 'in_transit' | 'delivered' | 'returned';

export interface DeliveryItemCreate {
  job_id: number;
  part_id: number;
  qty_assigned?: number;
  notes?: string;
}

export interface DeliveryItemBulkCreate {
  job_id: number;
  items: DeliveryItemCreate[];
}

export interface VehicleDeliveryItem {
  id: number;
  vehicle_id: number;
  job_id: number;
  part_id: number;
  qty_assigned: number;
  qty_delivered: number;
  assigned_by: number | null;
  delivered_by: number | null;
  delivered_at: string | null;
  status: DeliveryStatus;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  job_name: string | null;
  part_number: string | null;
  part_description: string | null;
  assigner_name: string | null;
}

// ── Maintenance Types ──────────────────────────────────────────────

export interface MaintenanceTypeCreate {
  name: string;
  description?: string;
  default_interval_miles?: number;
  default_interval_months?: number;
  sort_order?: number;
}

export interface MaintenanceTypeUpdate {
  name?: string;
  description?: string;
  default_interval_miles?: number;
  default_interval_months?: number;
  sort_order?: number;
  is_active?: boolean;
}

export interface MaintenanceType {
  id: number;
  name: string;
  description: string | null;
  default_interval_miles: number | null;
  default_interval_months: number | null;
  sort_order: number;
  is_active: boolean;
  created_at: string | null;
}

// ── Maintenance Schedules ──────────────────────────────────────────

export interface MaintenanceScheduleCreate {
  maintenance_type_id: number;
  interval_miles?: number;
  interval_months?: number;
  last_performed_at?: string;
  last_performed_miles?: number;
  is_enabled?: boolean;
  notes?: string;
}

export interface MaintenanceScheduleUpdate {
  interval_miles?: number;
  interval_months?: number;
  last_performed_at?: string;
  last_performed_miles?: number;
  next_due_date?: string;
  next_due_miles?: number;
  is_enabled?: boolean;
  notes?: string;
}

export interface MaintenanceSchedule {
  id: number;
  vehicle_id: number;
  maintenance_type_id: number;
  interval_miles: number | null;
  interval_months: number | null;
  last_performed_at: string | null;
  last_performed_miles: number | null;
  next_due_date: string | null;
  next_due_miles: number | null;
  is_enabled: boolean;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  maintenance_type_name: string | null;
  vehicle_name: string | null;
  vehicle_number: string | null;
  current_odometer: number | null;
  // Computed (enriched by service)
  urgency?: 'normal' | 'soon' | 'overdue';
}

// ── Maintenance Records ────────────────────────────────────────────

export interface MaintenanceRecordCreate {
  maintenance_type_id: number;
  service_date?: string;
  odometer_reading?: number;
  cost?: number;
  vendor?: string;
  invoice_number?: string;
  description?: string;
  photo_path?: string;
  notes?: string;
}

export interface MaintenanceRecord {
  id: number;
  vehicle_id: number;
  maintenance_type_id: number;
  service_date: string;
  odometer_reading: number | null;
  cost: number;
  vendor: string | null;
  invoice_number: string | null;
  description: string | null;
  performed_by: number | null;
  photo_path: string | null;
  notes: string | null;
  created_at: string | null;
  // Joined fields
  maintenance_type_name: string | null;
  performer_name: string | null;
  vehicle_name: string | null;
}

// ── Mileage Logs ───────────────────────────────────────────────────

export type TripLegType =
  | 'home_to_shop'
  | 'shop_to_job'
  | 'job_to_job'
  | 'job_to_shop'
  | 'shop_to_home'
  | 'home_to_job'
  | 'job_to_home'
  | 'other';

export interface MileageLogCreate {
  log_date?: string;
  odometer_start?: number;
  odometer_end?: number;
  is_take_home_day?: boolean;
  notes?: string;
}

export interface MileageLogUpdate {
  odometer_start?: number;
  odometer_end?: number;
  is_take_home_day?: boolean;
  notes?: string;
}

export interface TripLeg {
  id: number;
  mileage_log_id: number;
  leg_order: number;
  leg_type: TripLegType;
  from_label: string | null;
  to_label: string | null;
  estimated_miles: number | null;
  actual_miles: number | null;
  estimated_drive_minutes: number | null;
  actual_drive_minutes: number | null;
  is_billable: boolean;
  from_job_id: number | null;
  to_job_id: number | null;
  notes: string | null;
  created_at: string | null;
  // Joined fields
  from_job_name: string | null;
  to_job_name: string | null;
}

export interface TripLegCreate {
  leg_order?: number;
  leg_type: TripLegType;
  from_label?: string;
  to_label?: string;
  estimated_miles?: number;
  actual_miles?: number;
  estimated_drive_minutes?: number;
  actual_drive_minutes?: number;
  is_billable?: boolean;
  from_job_id?: number;
  to_job_id?: number;
  notes?: string;
}

export interface MileageLog {
  id: number;
  vehicle_id: number;
  driver_id: number;
  log_date: string;
  odometer_start: number | null;
  odometer_end: number | null;
  total_miles: number | null;
  is_take_home_day: boolean;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  driver_name: string | null;
  vehicle_name: string | null;
  vehicle_number: string | null;
  trip_legs: TripLeg[] | null;
}

// ── Mileage Reimbursements ─────────────────────────────────────────

export type ReimbursementStatus = 'pending' | 'approved' | 'paid' | 'rejected';

export interface ReimbursementCreate {
  vehicle_id: number;
  period_start: string;
  period_end: string;
  total_miles: number;
  rate_per_mile?: number;
  notes?: string;
}

export interface MileageReimbursement {
  id: number;
  user_id: number;
  vehicle_id: number;
  period_start: string;
  period_end: string;
  total_miles: number;
  rate_per_mile: number;
  total_amount: number | null;
  status: ReimbursementStatus;
  approved_by: number | null;
  approved_at: string | null;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  user_name: string | null;
  vehicle_name: string | null;
  approver_name: string | null;
}

export interface ReimbursementApproval {
  action: 'approve' | 'reject';
  notes?: string;
}

// ── Fleet Dashboard & Aggregation ──────────────────────────────────

export interface FleetDashboardStats {
  total_vehicles: number;
  active_vehicles: number;
  in_maintenance: number;
  retired_vehicles: number;
  company_vehicles: number;
  private_vehicles: number;
  total_fleet_miles_month: number;
  total_maintenance_cost_month: number;
  overdue_maintenance_count: number;
  upcoming_maintenance_count: number;
  pending_reimbursements: number;
  vehicles_needing_inspection: number;
}

export interface MyVehicleDashboard {
  vehicle: Vehicle | null;
  assignment: VehicleAssignment | null;
  todays_mileage: MileageLog | null;
  pending_deliveries: VehicleDeliveryItem[];
  maintenance_alerts: MaintenanceAlert[];
  recent_mileage: MileageLog[];
}

export interface MaintenanceAlert {
  vehicle_id: number;
  vehicle_name: string;
  vehicle_number: string;
  maintenance_type_id: number;
  maintenance_type_name: string;
  next_due_date: string | null;
  next_due_miles: number | null;
  current_odometer: number;
  miles_until_due: number | null;
  days_until_due: number | null;
  is_overdue: boolean;
  urgency: 'normal' | 'soon' | 'overdue';
}

export interface MileageEstimate {
  home_to_shop_miles: number | null;
  shop_to_job_miles: number | null;
  total_round_trip_miles: number | null;
  total_billable_miles: number | null;
  estimated_drive_minutes_one_way: number | null;
  estimated_billable_drive_minutes: number | null;
  is_take_home: boolean;
  legs: MileageEstimateLeg[];
}

export interface MileageEstimateLeg {
  leg_type: TripLegType;
  from_label: string;
  to_label: string;
  estimated_miles: number;
  estimated_drive_minutes: number | null;
  is_billable: boolean;
}

export interface MileageSummary {
  vehicle_id: number | null;
  driver_id: number | null;
  period_start: string;
  period_end: string;
  total_miles: number;
  total_days_logged: number;
  total_billable_drive_minutes: number;
  avg_miles_per_day: number;
  total_take_home_days: number;
}

// ── Vehicle Inventory (Stock on Truck) ─────────────────────────────

export interface VehicleInventoryItem {
  id: number;
  part_id: number;
  qty: number;
  supplier_id: number | null;
  part_number: string | null;
  part_description: string | null;
  category: string | null;
  brand: string | null;
  supplier_name: string | null;
}

export interface VehicleInventoryTransfer {
  part_id: number;
  qty: number;
  from_location_type?: string;
  from_location_id?: number;
  notes?: string;
}

// ── Job Trailers ───────────────────────────────────────────────────

export type TrailerStatus = 'active' | 'in_transit' | 'maintenance' | 'inactive';

export interface JobTrailerCreate {
  trailer_code: string;
  name: string;
  status?: TrailerStatus;
  home_warehouse_id?: number | null;
  current_job_id?: number | null;
  assigned_driver_user_id?: number | null;
  notes?: string | null;
}

export interface JobTrailerUpdate {
  name?: string;
  status?: TrailerStatus;
  home_warehouse_id?: number | null;
  current_job_id?: number | null;
  assigned_driver_user_id?: number | null;
  notes?: string | null;
  is_active?: boolean;
}

export interface JobTrailer {
  id: number;
  trailer_code: string;
  name: string;
  status: TrailerStatus;
  home_warehouse_id: number | null;
  current_job_id: number | null;
  assigned_driver_user_id: number | null;
  notes: string | null;
  is_active: boolean;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  home_warehouse_name: string | null;
  current_job_name: string | null;
  assigned_driver_name: string | null;
}

export type TrailerLocationEventType = 'check_in' | 'departed' | 'arrived_job' | 'arrived_warehouse' | 'manual_update';
export type TrailerLocationKind = 'warehouse' | 'job' | 'road' | 'other';

export interface TrailerLocationEventCreate {
  event_type?: TrailerLocationEventType;
  location_kind?: TrailerLocationKind;
  warehouse_id?: number | null;
  job_id?: number | null;
  lat?: number | null;
  lng?: number | null;
  notes?: string | null;
}

export interface TrailerLocationEvent {
  id: number;
  trailer_id: number;
  event_type: TrailerLocationEventType;
  location_kind: TrailerLocationKind;
  warehouse_id: number | null;
  job_id: number | null;
  lat: number | null;
  lng: number | null;
  recorded_by: number;
  recorded_at: string | null;
  notes: string | null;
  // Joined fields
  recorded_by_name: string | null;
  warehouse_name: string | null;
  job_name: string | null;
}

export interface TrailerStockTemplate {
  id: number;
  trailer_id: number | null;
  name: string;
  is_default: boolean;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  lines?: TrailerStockTemplateLine[];
}

export interface TrailerStockTemplateLine {
  id: number;
  template_id: number;
  part_id: number;
  target_qty: number;
  min_qty: number;
  // Joined
  part_number?: string | null;
  part_description?: string | null;
}

export interface TrailerStockTemplateCreate {
  name: string;
  trailer_id?: number | null;
  is_default?: boolean;
  notes?: string | null;
  lines: { part_id: number; target_qty: number; min_qty?: number }[];
}

export interface TrailerInventoryItem {
  id: number;
  part_id: number;
  qty: number;
  supplier_id: number | null;
  part_number: string | null;
  part_description: string | null;
  category: string | null;
  brand: string | null;
  supplier_name: string | null;
}

export interface TrailerRestockGuidance {
  trailer_id: number;
  template_id: number | null;
  template_name: string | null;
  lines: {
    part_id: number;
    part_number: string | null;
    part_description: string | null;
    target_qty: number;
    min_qty: number;
    current_qty: number;
    needed: number;
    status: 'ok' | 'low' | 'out';
  }[];
}

// ── Fuel Tracking ──────────────────────────────────────────────────

export interface FuelLogCreate {
  fill_date?: string;
  odometer_reading: number;
  gallons: number;
  price_per_gallon: number;
  fuel_type?: 'regular' | 'premium' | 'diesel' | 'e85';
  station_name?: string | null;
  receipt_photo?: string | null;
  notes?: string | null;
}

export interface FuelLogUpdate {
  fill_date?: string;
  odometer_reading?: number;
  gallons?: number;
  price_per_gallon?: number;
  fuel_type?: string;
  station_name?: string | null;
  receipt_photo?: string | null;
  notes?: string | null;
}

export interface FuelLog {
  id: number;
  vehicle_id: number;
  driver_id: number;
  fill_date: string;
  odometer_reading: number;
  gallons: number;
  price_per_gallon: number;
  total_cost: number;
  fuel_type: string;
  station_name: string | null;
  receipt_photo: string | null;
  notes: string | null;
  mpg: number | null;
  driver_name?: string | null;
  created_at: string;
}

export interface FuelSummary {
  fill_count: number;
  total_gallons: number | null;
  total_cost: number | null;
  avg_price: number | null;
  avg_mpg: number | null;
  total_miles_driven: number | null;
}

// ── Telematics ─────────────────────────────────────────────────────

export interface TelematicsDeviceCreate {
  vehicle_id: number;
  device_type?: string;
  device_serial: string;
  device_name?: string | null;
}

export interface TelematicsDevice {
  id: number;
  vehicle_id: number;
  device_type: string;
  device_serial: string;
  device_name: string | null;
  auth_token: string;
  is_active: boolean;
  last_seen_at: string | null;
  vehicle_number?: string | null;
  vehicle_make?: string | null;
  vehicle_model?: string | null;
  created_at: string;
}

export interface TelematicsPositionIngest {
  auth_token: string;
  lat: number;
  lng: number;
  speed_mph?: number | null;
  heading?: number | null;
  altitude_ft?: number | null;
  odometer_reading?: number | null;
  engine_on?: boolean;
  recorded_at: string;
}

export interface TelematicsPosition {
  id: number;
  device_id: number;
  vehicle_id: number;
  lat: number;
  lng: number;
  speed_mph: number | null;
  heading: number | null;
  altitude_ft: number | null;
  odometer_reading: number | null;
  engine_on: boolean;
  recorded_at: string;
  created_at: string;
}

export interface TelematicsEventIngest {
  auth_token: string;
  event_type: string;
  event_data?: string | null;
  lat?: number | null;
  lng?: number | null;
  recorded_at: string;
}

export interface TelematicsEvent {
  id: number;
  device_id: number;
  vehicle_id: number;
  event_type: string;
  event_data: string | null;
  lat: number | null;
  lng: number | null;
  recorded_at: string;
  created_at: string;
}

export interface VehicleLocationSummary {
  vehicle_id: number;
  vehicle_number: string;
  vehicle_make: string | null;
  vehicle_model: string | null;
  lat: number;
  lng: number;
  speed_mph: number | null;
  engine_on: boolean;
  recorded_at: string;
}

// ── Vehicle Inspections ────────────────────────────────────────────

export type InspectionItemSeverity = 'critical' | 'warning' | 'info';
export type InspectionItemStatus = 'pending' | 'pass' | 'fail' | 'na';
export type InspectionOverallResult = 'pass' | 'fail' | 'needs_attention';

export interface InspectionTemplateItemCreate {
  sort_order?: number;
  category?: string;
  item_name: string;
  description?: string | null;
  severity?: InspectionItemSeverity;
  requires_photo?: boolean;
}

export interface InspectionTemplateCreate {
  name: string;
  description?: string | null;
  vehicle_type?: string | null;
  inspection_type?: string;
  items: InspectionTemplateItemCreate[];
}

export interface InspectionTemplateUpdate {
  name?: string;
  description?: string | null;
  vehicle_type?: string | null;
  inspection_type?: string;
  is_active?: boolean;
  items?: InspectionTemplateItemCreate[];
}

export interface InspectionTemplateItem {
  id: number;
  template_id: number;
  sort_order: number;
  category: string;
  item_name: string;
  description: string | null;
  severity: InspectionItemSeverity;
  requires_photo: boolean;
}

export interface InspectionTemplate {
  id: number;
  name: string;
  description: string | null;
  vehicle_type: string | null;
  inspection_type: string;
  is_active: boolean;
  items?: InspectionTemplateItem[];
  created_at: string;
  updated_at: string;
}

export interface InspectionRecordCreate {
  template_id: number;
  inspection_type?: string;
  odometer_reading?: number | null;
  notes?: string | null;
}

export interface InspectionRecordItem {
  id: number;
  record_id: number;
  template_item_id: number | null;
  item_name: string;
  category: string;
  status: InspectionItemStatus;
  severity: InspectionItemSeverity;
  photo: string | null;
  notes: string | null;
}

export interface InspectionRecord {
  id: number;
  vehicle_id: number;
  template_id: number;
  inspector_id: number;
  inspection_type: string;
  inspection_date: string;
  odometer_reading: number | null;
  overall_result: InspectionOverallResult | null;
  notes: string | null;
  completed_at: string | null;
  inspector_name?: string | null;
  vehicle_number?: string | null;
  template_name?: string | null;
  items?: InspectionRecordItem[];
  created_at: string;
}

export interface InspectionItemSubmit {
  status: InspectionItemStatus;
  photo?: string | null;
  notes?: string | null;
}

// ── Vehicle Transfers ──────────────────────────────────────────────

export type TransferStatus = 'requested' | 'approved' | 'in_transit' | 'completed' | 'cancelled';

export interface VehicleTransferCreate {
  vehicle_id: number;
  from_warehouse_id?: number | null;
  to_warehouse_id: number;
  reason?: string | null;
  notes?: string | null;
}

export interface VehicleTransfer {
  id: number;
  vehicle_id: number;
  from_warehouse_id: number | null;
  to_warehouse_id: number;
  requested_by: number;
  approved_by: number | null;
  status: TransferStatus;
  reason: string | null;
  notes: string | null;
  approved_at: string | null;
  completed_at: string | null;
  vehicle_number?: string | null;
  from_warehouse_name?: string | null;
  to_warehouse_name?: string | null;
  requested_by_name?: string | null;
  approved_by_name?: string | null;
  created_at: string;
  updated_at: string;
}

// ── Document Alerts & Utilization ──────────────────────────────────

export interface VehicleDocumentAlert {
  vehicle_id: number;
  vehicle_number: string;
  vehicle_label: string;
  alert_type: 'insurance' | 'registration';
  expiry_date: string;
  days_remaining: number | null;
  is_expired: boolean;
}

export interface VehicleUtilizationEntry {
  vehicle_id: number;
  vehicle_number: string;
  year: number | null;
  make: string | null;
  model: string | null;
  status: string;
  total_miles: number;
  mileage_entries: number;
  maintenance_cost: number;
  fuel_cost: number;
  total_gallons: number;
  total_cost: number;
  avg_mpg: number | null;
  cost_per_mile: number | null;
}

export interface FleetUtilizationSummary {
  total_vehicles: number;
  fleet_total_miles: number;
  fleet_maintenance_cost: number;
  fleet_fuel_cost: number;
  fleet_total_cost: number;
  fleet_avg_cost_per_mile: number | null;
}

export interface VehicleUtilizationReport {
  period_start: string;
  period_end: string;
  vehicles: VehicleUtilizationEntry[];
  summary: FleetUtilizationSummary;
}

// ── Maintenance Cost Summary ───────────────────────────────────────

export interface MaintenanceCostSummary {
  total_cost: number;
  total_records: number;
  per_type?: { maintenance_type_name: string; total_cost: number; record_count: number }[];
  per_vehicle?: { vehicle_name: string; vehicle_number: string; total_cost: number; record_count: number }[];
}

// ── Home Dashboard (landing page) ──────────────────────────────────

export interface HomeDashboardData {
  kpis: {
    total_parts: number;
    active_jobs: number;
    pending_orders: number;
    low_stock_alerts: number;
  };
  quick_actions: { label: string; icon: string; route: string }[];
  user_name: string;
}

export interface FastDriveDestination {
  type: 'home' | 'shop' | 'job';
  label: string;
  address?: string | null;
  gps_lat?: number | null;
  gps_lng?: number | null;
  miles_estimate?: number | null;
  job_id?: number | null;
  trip_count_30d: number;
}

export interface FastDriveContext {
  has_vehicle: boolean;
  vehicle_id?: number;
  vehicle_name?: string;
  vehicle_number?: string;
  suggested: FastDriveDestination[];
  all_destinations: FastDriveDestination[];
}

export interface FastDriveStartRequest {
  leg_type: string;
  from_label: string;
  to_label: string;
  estimated_miles?: number | null;
  to_job_id?: number | null;
  from_job_id?: number | null;
}

export interface FastDriveResult {
  mileage_log_id: number;
  trip_leg_id: number;
}
