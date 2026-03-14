/**
 * Warehouse types — movements, rules, dashboard, inventory, receive stock, staging,
 * pending pulls, audit, supplier preferences, locations, wizard search,
 * companion rules, alternatives.
 */

// ═══════════════════════════════════════════════════════════════════
// WAREHOUSE MODULE (Phase 3)
// ═══════════════════════════════════════════════════════════════════

// ── Movement Wizard ───────────────────────────────────────────────

export type LocationType = 'warehouse' | 'pulled' | 'truck' | 'trailer' | 'job';

export interface MovementLineItem {
  part_id: number;
  qty: number;
  supplier_id?: number | null;
}

export interface MovementRequest {
  from_location_type: LocationType;
  from_location_id: number;
  to_location_type: LocationType;
  to_location_id: number;
  items: MovementLineItem[];
  reason?: string | null;
  reason_detail?: string | null;
  notes?: string | null;
  reference_number?: string | null;
  job_id?: number | null;
  photo_path?: string | null;
  scan_confirmed?: boolean;
  gps_lat?: number | null;
  gps_lng?: number | null;
  destination_type?: string | null;
  destination_id?: number | null;
  destination_label?: string | null;
}

export interface ValidationError {
  field?: string | null;
  message: string;
  part_id?: number | null;
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
  warnings: string[];
}

export interface MovementPreviewLine {
  part_id: number;
  part_name: string;
  part_code?: string | null;
  qty: number;
  supplier_id?: number | null;
  supplier_name?: string | null;
  supplier_source?: string | null;
  source_before: number;
  source_after: number;
  dest_before: number;
  dest_after: number;
  unit_cost?: number | null;
  line_value?: number | null;
}

export interface MovementPreview {
  lines: MovementPreviewLine[];
  total_qty: number;
  total_value?: number | null;
  movement_type: string;
  photo_required: boolean;
  warnings: string[];
}

export interface MovementResult {
  movement_id: number;
  part_id: number;
  part_name: string;
  qty: number;
  movement_type: string;
  from_location_type?: string | null;
  to_location_type?: string | null;
}

export interface MovementExecuteResponse {
  success: boolean;
  movements: MovementResult[];
  total_items: number;
  total_qty: number;
}

export interface MovementLogEntry {
  id: number;
  part_id: number;
  part_name: string;
  part_code?: string | null;
  qty: number;
  movement_type: string;
  from_location_type?: string | null;
  from_location_id?: number | null;
  to_location_type?: string | null;
  to_location_id?: number | null;
  performed_by?: number | null;
  performer_name?: string | null;
  reason?: string | null;
  notes?: string | null;
  reference_number?: string | null;
  photo_path?: string | null;
  unit_cost?: number | null;
  unit_sell?: number | null;
  gps_lat?: number | null;
  gps_lng?: number | null;
  created_at: string;
}

// ── Movement Rules ────────────────────────────────────────────────

export interface MovementRule {
  from: string;
  to: string;
  type: string;
  photo_required: boolean;
}

export type ReasonCategories = Record<string, string[]>;

// ── Dashboard ─────────────────────────────────────────────────────

export interface DashboardKPIs {
  stock_health_pct: number;
  total_units: number;
  warehouse_value?: number | null;
  shortfall_count: number;
  pending_task_count: number;
}

export interface ActivitySummary {
  id: number;
  summary: string;
  movement_type: string;
  performer_name?: string | null;
  created_at?: string | null;
}

export interface PendingTask {
  task_type: string;
  title: string;
  subtitle?: string | null;
  severity: string;
  audit_id?: number | null;
  part_id?: number | null;
  stock_id?: number | null;
  destination_type?: string | null;
  destination_id?: number | null;
}

export interface DashboardData {
  kpis: DashboardKPIs;
  recent_activity: ActivitySummary[];
  pending_tasks: PendingTask[];
}

// ── Inventory Grid ────────────────────────────────────────────────

export type StockStatus = 'low_stock' | 'overstock' | 'in_range' | 'winding_down' | 'zero' | 'all';

export interface WarehouseInventoryItem {
  part_id: number;
  part_code?: string | null;
  part_name: string;
  category_id?: number | null;
  category_name?: string | null;
  brand_id?: number | null;
  brand_name?: string | null;
  unit_of_measure: string;
  shelf_location?: string | null;
  bin_location?: string | null;
  warehouse_qty: number;
  pulled_qty: number;
  truck_qty: number;
  total_qty: number;
  min_stock_level: number;
  target_stock_level: number;
  max_stock_level: number;
  stock_status: StockStatus;
  health_pct: number;
  unit_cost?: number | null;
  total_value?: number | null;
  forecast_days_until_low?: number | null;
  primary_supplier_name?: string | null;
  is_qr_tagged?: boolean;
}

export interface WarehouseInventoryParams {
  search?: string;
  category_id?: number;
  brand_id?: number;
  part_id?: number;
  stock_status?: StockStatus;
  sort_by?: string;
  sort_dir?: 'asc' | 'desc';
  page?: number;
  page_size?: number;
}

// ── Receive Stock ─────────────────────────────────────────────────

export interface ReceiveStockItem {
  part_id: number;
  qty: number;
  shelf_location?: string | null;
  bin_location?: string | null;
  supplier_id?: number | null;
  notes?: string | null;
}

export interface ReceiveStockRequest {
  items: ReceiveStockItem[];
  warehouse_location_id?: number;
  reason?: string | null;
  notes?: string | null;
  reference_number?: string | null;
}

export interface ReceiveStockResult {
  success: boolean;
  items_received: number;
  total_qty: number;
  movement_ids: number[];
}

// ── Staging ───────────────────────────────────────────────────────

export type AgingStatus = 'normal' | 'warning' | 'critical';

export interface StagingItem {
  stock_id: number;
  part_id: number;
  part_name: string;
  part_code?: string | null;
  qty: number;
  supplier_name?: string | null;
  destination_type?: string | null;
  destination_id?: number | null;
  destination_label?: string | null;
  tagged_by_name?: string | null;
  staged_at?: string | null;
  hours_staged: number;
  aging_status: AgingStatus;
}

export interface StagingGroup {
  destination_type?: string | null;
  destination_id?: number | null;
  destination_label: string;
  items: StagingItem[];
  total_qty: number;
  oldest_hours: number;
  aging_status: AgingStatus;
}

// ── Pending Pulls (JPO lines received but not yet staged) ─────────

export interface PendingPullItem {
  jpo_line_id: number;
  jpo_id: number;
  jpo_number: string;
  job_id: number | null;
  job_name: string | null;
  job_number: string | null;
  part_id: number;
  part_name: string;
  part_code: string | null;
  qty_received: number;
  qty_already_pulled: number;
  qty_pending: number;
  warehouse_qty: number;
  priority: string;
  supplier_name: string | null;
  requested_by_name: string | null;
}

export interface PendingPullGroup {
  job_id: number | null;
  job_name: string | null;
  job_number: string | null;
  items: PendingPullItem[];
  total_pending: number;
  total_already_pulled: number;
}

// ── Audit ─────────────────────────────────────────────────────────

export type AuditType = 'spot_check' | 'category' | 'rolling';
export type AuditStatus = 'in_progress' | 'paused' | 'completed' | 'cancelled';
export type AuditItemResult = 'pending' | 'match' | 'discrepancy' | 'skipped';

export interface AuditStartRequest {
  audit_type: AuditType;
  location_type?: LocationType;
  location_id?: number;
  category_id?: number | null;
  part_ids?: number[] | null;
}

export interface AuditCountRequest {
  actual_qty: number;
  result: AuditItemResult;
  discrepancy_note?: string | null;
  photo_path?: string | null;
}

export interface AuditItemResponse {
  id: number;
  audit_id: number;
  part_id: number;
  part_name: string;
  part_code?: string | null;
  shelf_location?: string | null;
  image_url?: string | null;
  expected_qty: number;
  actual_qty?: number | null;
  result: AuditItemResult;
  discrepancy_note?: string | null;
  photo_path?: string | null;
  counted_at?: string | null;
}

export interface AuditProgress {
  total_items: number;
  counted: number;
  matched: number;
  discrepancies: number;
  skipped: number;
  pending: number;
  pct_complete: number;
}

export interface AuditResponse {
  id: number;
  audit_type: AuditType;
  location_type: LocationType;
  location_id: number;
  category_id?: number | null;
  category_name?: string | null;
  status: AuditStatus;
  started_by: number;
  started_by_name?: string | null;
  completed_at?: string | null;
  progress: AuditProgress;
  notes?: string | null;
  created_at?: string | null;
}

export interface AuditSummary {
  audit_id: number;
  audit_type: AuditType;
  status: AuditStatus;
  progress: AuditProgress;
  adjustments_needed: number;
  has_unapplied_adjustments: boolean;
}

export interface SuggestedRollingPart {
  id: number;
  name: string;
  code?: string | null;
  shelf_location?: string | null;
  category_name?: string | null;
  last_counted_at: string;
  warehouse_qty: number;
}

// ── Supplier Preferences ──────────────────────────────────────────

export type SupplierPrefScope = 'category' | 'style' | 'type' | 'part';

export interface SupplierPreferenceResponse {
  scope_type?: string | null;
  scope_id?: number | null;
  supplier_id?: number | null;
  supplier_name?: string | null;
  resolved_from?: string | null;
}

export interface SupplierPreferenceSet {
  scope_type: SupplierPrefScope;
  scope_id: number;
  supplier_id: number;
}

// ── Locations Helper ──────────────────────────────────────────────

export interface LocationOption {
  location_type: LocationType;
  location_id: number;
  label: string;
  sub_label?: string | null;
}

// ── Wizard Part Search ────────────────────────────────────────────

export interface WizardPartSearchResult {
  part_id: number;
  part_name: string;
  part_code?: string | null;
  image_url?: string | null;
  category_name?: string | null;
  shelf_location?: string | null;
  available_qty: number;
  supplier_name?: string | null;
  supplier_id?: number | null;
}


// =================================================================
// COMPANION RULES — category-level linking
// =================================================================

export interface CompanionRuleSource {
  id: number;
  category_id: number;
  category_name?: string | null;
  style_id?: number | null;
  style_name?: string | null;
}

export interface CompanionRuleTarget {
  id: number;
  category_id: number;
  category_name?: string | null;
  style_id?: number | null;
  style_name?: string | null;
}

export interface CompanionRule {
  id: number;
  name: string;
  description?: string | null;
  style_match: 'auto' | 'any' | 'explicit';
  qty_mode: 'sum' | 'max' | 'ratio';
  qty_ratio: number;
  is_active: boolean;
  sources: CompanionRuleSource[];
  targets: CompanionRuleTarget[];
  created_by?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface CompanionRuleSourceCreate {
  category_id: number;
  style_id?: number | null;
}

export interface CompanionRuleTargetCreate {
  category_id: number;
  style_id?: number | null;
}

export interface CompanionRuleCreate {
  name: string;
  description?: string | null;
  style_match?: 'auto' | 'any' | 'explicit';
  qty_mode?: 'sum' | 'max' | 'ratio';
  qty_ratio?: number;
  is_active?: boolean;
  sources: CompanionRuleSourceCreate[];
  targets: CompanionRuleTargetCreate[];
}

export interface CompanionRuleUpdate {
  name?: string | null;
  description?: string | null;
  style_match?: 'auto' | 'any' | 'explicit' | null;
  qty_mode?: 'sum' | 'max' | 'ratio' | null;
  qty_ratio?: number | null;
  is_active?: boolean | null;
  sources?: CompanionRuleSourceCreate[] | null;
  targets?: CompanionRuleTargetCreate[] | null;
}


// =================================================================
// COMPANION SUGGESTIONS
// =================================================================

export interface SuggestionSource {
  id: number;
  category_id: number;
  category_name?: string | null;
  style_id?: number | null;
  style_name?: string | null;
  qty: number;
}

export interface CompanionSuggestion {
  id: number;
  rule_id?: number | null;
  target_category_id: number;
  target_style_id?: number | null;
  target_description: string;
  suggested_qty: number;
  approved_qty?: number | null;
  reason_type: 'rule' | 'learned' | 'mixed';
  reason_text: string;
  status: 'pending' | 'approved' | 'discarded';
  sources: SuggestionSource[];
  triggered_by?: number | null;
  decided_by?: number | null;
  decided_at?: string | null;
  order_id?: number | null;
  notes?: string | null;
  created_at?: string | null;
}

export interface SuggestionDecision {
  action: 'approved' | 'discarded';
  approved_qty?: number | null;
  notes?: string | null;
}


// =================================================================
// MANUAL TRIGGER — "What should I also order?"
// =================================================================

export interface ManualTriggerItem {
  category_id: number;
  style_id?: number | null;
  qty: number;
}

export interface ManualTriggerRequest {
  items: ManualTriggerItem[];
}


// =================================================================
// CO-OCCURRENCE
// =================================================================

export interface CoOccurrencePair {
  id: number;
  category_a_id: number;
  category_a_name?: string | null;
  category_b_id: number;
  category_b_name?: string | null;
  co_occurrence_count: number;
  total_jobs_a: number;
  total_jobs_b: number;
  avg_ratio_a_to_b: number;
  confidence: number;
  last_computed?: string | null;
}


// =================================================================
// COMPANION STATS
// =================================================================

export interface CompanionStats {
  total_rules: number;
  active_rules: number;
  pending_suggestions: number;
  approved_count: number;
  discarded_count: number;
  co_occurrence_pairs: number;
}


// =================================================================
// PART ALTERNATIVES — individual part cross-linking
// =================================================================

export type AlternativeRelationship = 'substitute' | 'upgrade' | 'compatible';

export interface PartAlternative {
  id: number;
  part_id: number;
  part_name?: string | null;
  part_code?: string | null;
  alternative_part_id: number;
  alternative_name?: string | null;
  alternative_code?: string | null;
  alternative_brand_name?: string | null;
  relationship: AlternativeRelationship;
  preference: number;
  notes?: string | null;
  created_by?: number | null;
  created_at?: string | null;
}

export interface PartAlternativeCreate {
  alternative_part_id: number;
  relationship?: AlternativeRelationship;
  preference?: number;
  notes?: string | null;
}

export interface PartAlternativeUpdate {
  relationship?: AlternativeRelationship | null;
  preference?: number | null;
  notes?: string | null;
}
