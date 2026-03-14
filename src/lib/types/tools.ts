/**
 * Tools & Kits types — tool registry, kit templates, movements, verification,
 * maintenance, dashboard, transfer, depreciation, todo-tool linking.
 */

// ═══════════════════════════════════════════════════════════════════
// TOOLS & KITS (Phase 9)
// ═══════════════════════════════════════════════════════════════════

export type ToolCategory =
  | 'power_tool' | 'hand_tool' | 'meter' | 'safety'
  | 'conduit' | 'cable' | 'lighting' | 'general';

export type ToolStatus =
  | 'available' | 'checked_out' | 'in_maintenance'
  | 'lost' | 'retired' | 'damaged';

export type ToolLocationType = 'warehouse' | 'truck' | 'job';

export type KitComponentType =
  | 'charger' | 'battery' | 'blade' | 'bit_set'
  | 'case' | 'accessory' | 'cable' | 'adapter' | 'other';

export type ToolMovementType =
  | 'register' | 'checkout' | 'return' | 'transfer'
  | 'maintenance_in' | 'maintenance_out' | 'retire' | 'lost';

export type KitVerificationTrigger = 'checkout' | 'return' | 'audit' | 'manual';

export type DepreciationMethod = 'straight_line' | 'declining_balance' | 'sum_of_years';

export type CalibrationResult = 'pass' | 'fail' | 'adjusted' | 'out_of_tolerance';


// ── Tool ─────────────────────────────────────────────────────────

export interface Tool {
  id: number;
  tool_number: string;
  name: string;
  category: ToolCategory;
  brand?: string | null;
  model_number?: string | null;
  serial_number?: string | null;
  purchase_date?: string | null;
  purchase_cost?: number | null;
  warranty_expiry?: string | null;
  location_type: ToolLocationType;
  location_id?: number | null;
  assigned_to?: number | null;
  status: ToolStatus;
  condition_rating: number;
  has_kit: boolean;
  notes?: string | null;
  photo_path?: string | null;
  barcode?: string | null;
  is_active: boolean;
  created_at?: string | null;
  updated_at?: string | null;
  // Depreciation fields
  depreciation_method?: DepreciationMethod | null;
  salvage_value?: number;
  useful_life_years?: number | null;
  calibration_due_date?: string | null;
  // Joined / computed
  assigned_to_name?: string | null;
  location_name?: string | null;
  kit_component_count: number;
  next_maintenance_due?: string | null;
  overdue_maintenance_count: number;
  current_book_value?: number | null;
}

export interface ToolListItem {
  id: number;
  tool_number: string;
  name: string;
  category: ToolCategory;
  brand?: string | null;
  status: ToolStatus;
  location_type: ToolLocationType;
  location_id?: number | null;
  location_name?: string | null;
  assigned_to?: number | null;
  assigned_to_name?: string | null;
  condition_rating: number;
  has_kit: boolean;
  kit_component_count: number;
  next_maintenance_due?: string | null;
  overdue_maintenance_count: number;
}

export interface ToolCreate {
  tool_number: string;
  name: string;
  category?: ToolCategory;
  brand?: string | null;
  model_number?: string | null;
  serial_number?: string | null;
  purchase_date?: string | null;
  purchase_cost?: number | null;
  warranty_expiry?: string | null;
  location_type?: ToolLocationType;
  location_id?: number | null;
  assigned_to?: number | null;
  condition_rating?: number;
  notes?: string | null;
  photo_path?: string | null;
  depreciation_method?: DepreciationMethod | null;
  salvage_value?: number;
  useful_life_years?: number | null;
}

export interface ToolUpdate {
  name?: string | null;
  category?: ToolCategory | null;
  brand?: string | null;
  model_number?: string | null;
  serial_number?: string | null;
  purchase_date?: string | null;
  purchase_cost?: number | null;
  warranty_expiry?: string | null;
  condition_rating?: number | null;
  notes?: string | null;
  photo_path?: string | null;
  is_active?: boolean | null;
  depreciation_method?: DepreciationMethod | null;
  salvage_value?: number | null;
  useful_life_years?: number | null;
}


// ── Kit Templates ────────────────────────────────────────────────

export interface KitTemplateItem {
  id: number;
  tool_id: number;
  component_name: string;
  component_type: KitComponentType;
  qty_required: number;
  brand?: string | null;
  model_number?: string | null;
  is_critical: boolean;
  sort_order: number;
  notes?: string | null;
}

export interface KitTemplateItemCreate {
  component_name: string;
  component_type?: KitComponentType;
  qty_required?: number;
  brand?: string | null;
  model_number?: string | null;
  is_critical?: boolean;
  sort_order?: number;
  notes?: string | null;
}

export interface KitTemplateItemUpdate {
  component_name?: string | null;
  component_type?: KitComponentType | null;
  qty_required?: number | null;
  brand?: string | null;
  model_number?: string | null;
  is_critical?: boolean | null;
  sort_order?: number | null;
  notes?: string | null;
}


// ── Tool Movements ───────────────────────────────────────────────

export interface ToolMovement {
  id: number;
  tool_id: number;
  from_location_type?: string | null;
  from_location_id?: number | null;
  to_location_type?: string | null;
  to_location_id?: number | null;
  movement_type: ToolMovementType;
  reason?: string | null;
  job_id?: number | null;
  performed_by: number;
  verified_by?: number | null;
  condition_at_move?: number | null;
  created_at?: string | null;
  // Joined
  performed_by_name?: string | null;
  verified_by_name?: string | null;
  from_location_name?: string | null;
  to_location_name?: string | null;
  tool_name?: string | null;
  tool_number?: string | null;
}

export interface ToolCheckoutRequest {
  to_location_type: ToolLocationType;
  to_location_id: number;
  job_id?: number | null;
  condition_at_move?: number | null;
  reason?: string | null;
}

export interface ToolReturnRequest {
  to_location_type?: ToolLocationType;
  to_location_id?: number | null;
  condition_at_move?: number | null;
  reason?: string | null;
}


// ── Kit Verification ─────────────────────────────────────────────

export interface KitVerificationSession {
  id: number;
  tool_id: number;
  movement_id?: number | null;
  verified_by: number;
  trigger_type: KitVerificationTrigger;
  is_complete: boolean;
  missing_count: number;
  notes?: string | null;
  created_at?: string | null;
  // Joined
  verified_by_name?: string | null;
  tool_name?: string | null;
  tool_number?: string | null;
  items: KitVerificationItem[];
}

export interface KitVerificationItem {
  id: number;
  session_id: number;
  template_item_id: number;
  is_present: boolean;
  condition_rating?: number | null;
  notes?: string | null;
  // Joined from kit_templates
  component_name?: string | null;
  component_type?: KitComponentType | null;
  qty_required: number;
  is_critical: boolean;
}

export interface KitVerificationStartRequest {
  trigger_type: KitVerificationTrigger;
}

export interface KitVerificationItemUpdate {
  item_id: number;
  is_present: boolean;
  condition_rating?: number | null;
  notes?: string | null;
}

export interface KitVerificationCompleteRequest {
  items: KitVerificationItemUpdate[];
  notes?: string | null;
}


// ── Tool Maintenance ─────────────────────────────────────────────

export interface ToolMaintenanceType {
  id: number;
  name: string;
  description?: string | null;
  default_interval_days?: number | null;
  sort_order: number;
  is_active: boolean;
  created_at?: string | null;
}

export interface ToolMaintenanceTypeCreate {
  name: string;
  description?: string | null;
  default_interval_days?: number | null;
  sort_order?: number;
}

export interface ToolMaintenanceTypeUpdate {
  name?: string | null;
  description?: string | null;
  default_interval_days?: number | null;
  sort_order?: number | null;
  is_active?: boolean | null;
}

export interface ToolMaintenanceSchedule {
  id: number;
  tool_id: number;
  maintenance_type_id: number;
  interval_days?: number | null;
  last_performed_at?: string | null;
  next_due_date?: string | null;
  is_enabled: boolean;
  notes?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  // Joined
  maintenance_type_name?: string | null;
}

export interface ToolMaintenanceScheduleCreate {
  maintenance_type_id: number;
  interval_days?: number | null;
  is_enabled?: boolean;
  notes?: string | null;
}

export interface ToolMaintenanceRecord {
  id: number;
  tool_id: number;
  maintenance_type_id: number;
  service_date: string;
  cost: number;
  vendor?: string | null;
  description?: string | null;
  performed_by?: number | null;
  notes?: string | null;
  created_at?: string | null;
  // Calibration fields
  calibration_certificate?: string | null;
  calibration_provider?: string | null;
  calibration_standard?: string | null;
  calibration_result?: CalibrationResult | null;
  // Joined
  maintenance_type_name?: string | null;
  performed_by_name?: string | null;
}

export interface ToolMaintenanceRecordCreate {
  maintenance_type_id: number;
  service_date?: string | null;
  cost?: number;
  vendor?: string | null;
  description?: string | null;
  notes?: string | null;
  // Calibration-specific
  calibration_certificate?: string | null;
  calibration_provider?: string | null;
  calibration_standard?: string | null;
  calibration_result?: CalibrationResult | null;
}

export interface ToolMaintenanceAlert {
  tool_id: number;
  tool_number: string;
  tool_name: string;
  maintenance_type_id: number;
  maintenance_type_name: string;
  next_due_date?: string | null;
  days_until_due?: number | null;
  is_overdue: boolean;
}


// ── Tools Dashboard ──────────────────────────────────────────────

export interface ToolsDashboardStats {
  total_tools: number;
  available: number;
  checked_out: number;
  in_maintenance: number;
  lost_or_damaged: number;
  at_warehouse: number;
  on_trucks: number;
  at_jobs: number;
  overdue_maintenance: number;
  kits_with_missing_items: number;
}


// ── Tool Transfer ────────────────────────────────────────────────

export interface ToolTransferRequest {
  to_location_type: ToolLocationType;
  to_location_id: number;
  job_id?: number | null;
  condition_at_move?: number | null;
  reason?: string | null;
}


// ── Tool Depreciation ────────────────────────────────────────────

export interface DepreciationConfig {
  depreciation_method: DepreciationMethod;
  salvage_value: number;
  useful_life_years: number;
}

export interface DepreciationEntry {
  id: number;
  tool_id: number;
  year_number: number;
  fiscal_year: string;
  beginning_value: number;
  depreciation_amount: number;
  accumulated: number;
  ending_value: number;
  created_at?: string | null;
}

export interface DepreciationSummary {
  tool_id: number;
  tool_name: string;
  purchase_cost?: number | null;
  depreciation_method?: DepreciationMethod | null;
  salvage_value: number;
  useful_life_years?: number | null;
  current_book_value?: number | null;
  total_depreciated: number;
  years_remaining?: number | null;
  schedule: DepreciationEntry[];
}

export interface DepreciationReportItem {
  id: number;
  tool_number: string;
  name: string;
  category: string;
  purchase_cost?: number | null;
  depreciation_method?: DepreciationMethod | null;
  salvage_value?: number;
  useful_life_years?: number | null;
  current_book_value?: number | null;
  total_depreciated?: number | null;
}


// ── Todo-Tool Linking ────────────────────────────────────────────

export interface EntryToolLink {
  id: number;
  entry_id: number;
  tool_id: number;
  notes?: string | null;
  created_by: number;
  created_at?: string | null;
  // Joined
  tool_number?: string | null;
  tool_name?: string | null;
  tool_status?: string | null;
  tool_location_type?: string | null;
  tool_location_name?: string | null;
}

export interface EntryToolLinkCreate {
  tool_id: number;
  notes?: string | null;
}
