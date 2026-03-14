/**
 * Office workflow types — job preferences, special items, PO conversations,
 * PO groups, approvals, receiving sessions, return sorting, cost tracking analytics,
 * bulk actions.
 */

// ═══════════════════════════════════════════════════════════════════
// JOB PREFERENCES & SPECIAL ITEMS (Phase 7A)
// ═══════════════════════════════════════════════════════════════════

// ── Job Preferences ─────────────────────────────────────────────

export type PreferenceType = 'brand' | 'color' | 'supplier' | 'part';

export interface JobPreferenceResponse {
  id: number;
  job_id: number;
  preference_type: PreferenceType;
  entity_id: number | null;
  text_value: string | null;
  category: string | null;
  is_active: boolean;
  auto_learned: boolean;
  confidence_score: number;
  last_used_at: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  entity_name: string | null;
  category_name: string | null;
}

export interface JobPreferenceToggle {
  is_active: boolean;
}

export interface JobPreferencesSummary {
  brands: JobPreferenceResponse[];
  colors: JobPreferenceResponse[];
  suppliers: JobPreferenceResponse[];
  parts: JobPreferenceResponse[];
}

// ── Explicit Preferred Suppliers ────────────────────────────────

export interface PreferredSupplierEntry {
  supplier_id: number;
  category?: string | null;
}

export interface JobPreferredSuppliersUpdate {
  suppliers: PreferredSupplierEntry[];
}

export interface ExplicitSupplierResponse {
  id: number;
  supplier_id: number;
  supplier_name: string;
  category: string | null;
  confidence_score: number;
  is_active: boolean;
  created_at: string;
}

// ── Cross-Job Order Summary (Phase 17 Gap 4) ───────────────────

export interface OrderSummaryLine {
  part_id: number;
  part_name: string;
  category_name: string | null;
  total_qty_needed: number;
  job_count: number;
  job_names: string[];
  suggested_supplier_id: number | null;
  supplier_name: string | null;
}

export interface OrderSummary {
  total_parts: number;
  total_qty: number;
  total_jobs: number;
  total_suppliers: number;
  lines: OrderSummaryLine[];
  summary_text: string;
}

// ── Special Items ───────────────────────────────────────────────

// ── PO Conversations (Phase 7B) ────────────────────────────────

/** Entry types control visual treatment in the conversation thread UI */
export type POConversationEntryType = 'note' | 'call' | 'email_summary' | 'action' | 'system' | 'supplier_note';

/** Create a manual conversation entry (system entries use a separate path) */
export interface POConversationCreate {
  entry_type: Exclude<POConversationEntryType, 'system'>;
  message: string;
  follow_up_needed?: boolean;
}

/** A single conversation entry in API responses */
export interface POConversationEntry {
  id: number;
  po_id: number | null;
  supplier_id: number | null;
  entry_type: POConversationEntryType;
  message: string;
  follow_up_needed: boolean;
  follow_up_resolved_at: string | null;
  created_by: number | null;
  created_at: string | null;
  // Joined fields
  creator_name: string | null;
  po_number: string | null;   // included when viewing supplier-level thread
}

/** Toggle follow-up status on a conversation entry */
export interface POConversationFollowUp {
  resolved: boolean;
}


// ── PO Groups (Phase 7B) ───────────────────────────────────────

/** Create a PO group for bundled sending to a supplier */
export interface POGroupCreate {
  group_name?: string | null;
  supplier_id: number;
  po_ids: number[];
}

/** A PO that is part of a group — includes compact PO info */
export interface POGroupMemberResponse {
  id: number;
  group_id: number;
  po_id: number;
  po_number: string | null;
  status: string | null;
  total_cost: number;
  line_count: number;
}

/** Full PO group in API responses */
export interface POGroupResponse {
  id: number;
  group_name: string | null;
  supplier_id: number;
  supplier_name: string | null;
  pdf_path: string | null;
  individual_pdfs: string[] | null;
  created_by: number | null;
  creator_name: string | null;
  created_at: string | null;
  members: POGroupMemberResponse[];
  total_value: number;
}

/** Compact PO group for list views */
export interface POGroupListItem {
  id: number;
  group_name: string | null;
  supplier_id: number;
  supplier_name: string | null;
  po_count: number;
  total_value: number;
  has_pdf: boolean;
  created_at: string | null;
}


// ── Office Approval Queue (Phase 7B) ───────────────────────────

/** A unified approval queue item — covers both JPOs and Returns */
export interface PendingApprovalItem {
  entity_type: 'jpo' | 'return';
  entity_id: number;
  reference_number: string;
  status: string;
  priority: string;
  order_type: 'job' | 'warehouse' | null;  // JPO only
  return_type: string | null;               // Return only
  reason: string | null;                    // Return reason
  has_special_items: boolean;               // JPO only
  requester_id: number;
  requester_name: string | null;
  job_id: number | null;
  job_name: string | null;
  supplier_name: string | null;             // Return only
  line_count: number;
  created_at: string | null;
}

/** A single target in a bulk approval action */
export interface BulkApprovalTarget {
  entity_type: 'jpo' | 'return';
  entity_id: number;
}

/** Approve or reject multiple items at once */
export interface BulkApprovalAction {
  items: BulkApprovalTarget[];
  action: 'approve' | 'reject';
  notes?: string | null;
}

/** Result of a bulk approval action (per-item results) */
export interface BulkApprovalResult {
  entity_type: string;
  entity_id: number;
  success: boolean;
  error?: string;
}

/** Counts for the pending-approvals badge */
export interface PendingApprovalCounts {
  jpo_count: number;
  return_count: number;
  total: number;
}


// ── PO Confirmation Checklist (Phase 7B) ────────────────────────

/** A single line in the PO confirmation checklist */
export interface ConfirmationChecklistItem {
  po_line_id: number;
  part_id: number;
  confirmed: boolean;
  confirmed_by: number | null;
  confirmed_at: string | null;
  // Joined (only populated in response, not stored in JSON)
  part_description?: string | null;
  confirmer_name?: string | null;
  // Hierarchy fields
  part_number?: string | null;
  part_name?: string | null;
  category_name?: string | null;
  type_name?: string | null;
  color_name?: string | null;
  color_hex?: string | null;
  brand_name?: string | null;
}

/** Update the full confirmation checklist for a PO */
export interface ConfirmationChecklistUpdate {
  checklist: ConfirmationChecklistItem[];
}


// ── Receiving Sessions (Phase 7C) ──────────────────────────────

export type ReceivingMode = 'packing_slip' | 'scan';
export type ReceivingSessionStatus = 'in_progress' | 'completed' | 'cancelled';

/** Start a new receiving session for a PO */
export interface ReceivingSessionCreate {
  po_id: number;
  mode?: ReceivingMode;
  notes?: string | null;
}

/** Update a single line item in a receiving session */
export interface ReceivingSessionItemUpdate {
  po_line_id: number;
  received_qty: number;
  actual_cost?: number | null;
  staging_zone_id?: number | null;
  notes?: string | null;
}

/** Commit a receiving session — applies quantities to the PO */
export interface ReceivingSessionCommit {
  items?: ReceivingSessionItemUpdate[];
  notes?: string | null;
}

/** A single line in a receiving session (API response) */
export interface ReceivingSessionItemResponse {
  id: number;
  session_id: number;
  po_line_id: number;
  expected_qty: number;
  received_qty: number;
  actual_cost: number | null;
  staging_zone_id: number | null;
  scanned_at: string | null;
  notes: string | null;
  created_at: string | null;
  // Joined fields
  part_id: number | null;
  part_number: string | null;
  part_description: string | null;
  unit_cost: number | null;
  zone_label: string | null;
  // Hierarchy fields
  part_name: string | null;
  category_name: string | null;
  type_name: string | null;
  color_name: string | null;
  color_hex: string | null;
  brand_name: string | null;
}

/** Full receiving session (API response) */
export interface ReceivingSessionResponse {
  id: number;
  po_id: number;
  po_number: string | null;
  supplier_name: string | null;
  started_by: number;
  starter_name: string | null;
  mode: ReceivingMode;
  status: ReceivingSessionStatus;
  completed_at: string | null;
  notes: string | null;
  created_at: string | null;
  items: ReceivingSessionItemResponse[];
  // Progress summary
  total_expected: number;
  total_received: number;
  line_count: number;
}

/** Compact session for list views */
export interface ReceivingSessionListItem {
  id: number;
  po_id: number;
  po_number: string | null;
  supplier_name: string | null;
  mode: ReceivingMode;
  status: ReceivingSessionStatus;
  total_expected: number;
  total_received: number;
  started_by: number;
  starter_name: string | null;
  created_at: string | null;
  completed_at: string | null;
}


// ── Return Sorting (Phase 7C) ──────────────────────────────────

export type ReturnDisposition = 'return_to_supplier' | 'restock' | 'write_off';
export type ReturnCondition = 'new' | 'like_new' | 'used' | 'damaged' | 'defective';

/** Sorting guidance for a single return line item */
export interface ReturnSortingGuidance {
  return_line_id: number;
  part_id: number;
  part_number: string | null;
  part_description: string | null;
  qty: number;
  condition: ReturnCondition;
  current_stock: number;
  target_qty: number;
  below_target: boolean;
  returnable_to_supplier: boolean;
  non_return_reason: string | null;
  recommended_disposition: ReturnDisposition;
  recommendation_reason: string;
}

/** Apply a sorting disposition to a return line item */
export interface ReturnSortingDisposition {
  return_line_id: number;
  disposition: ReturnDisposition;
  dest_type?: string | null;  // warehouse | truck
  dest_id?: number | null;    // staging_zone_id or location_id
  notes?: string | null;
}

/** Process sorting dispositions for all lines in a return */
export interface ReturnSortingRequest {
  dispositions: ReturnSortingDisposition[];
}

/** Response for checking a part's return eligibility to supplier */
export interface ReturnEligibilityCheck {
  part_id: number;
  returnable: boolean;
  reasons: string[];
  supplier_return_window_days: number | null;
  days_since_receipt: number | null;
}

/** Below-target check result */
export interface BelowTargetCheck {
  part_id: number;
  current_stock: number;
  target_qty: number;
  below_target: boolean;
}

// ═══════════════════════════════════════════════════════════════════
// Phase 7D: Cost Tracking & Analytics
// ═══════════════════════════════════════════════════════════════════

/** A single inventory cost layer (FIFO audit view) */
export interface CostLayer {
  id: number;
  part_id: number;
  purchase_date: string;
  po_line_id: number | null;
  original_qty: number;
  remaining_qty: number;
  unit_cost: number;
  created_at: string | null;
  po_number: string | null;
}

/** A single data point for cost sparkline charts */
export interface CostHistoryPoint {
  date: string;
  weighted_avg_cost: number;
  total_qty: number;
}

/** Company-wide cost setting */
export interface CompanySetting {
  setting_key: string;
  setting_value: string;
  updated_by: number | null;
  updated_at: string | null;
  updated_by_name: string | null;
}

/** Consolidated cost info for a single part */
export interface PartCostSummary {
  part_id: number;
  weighted_avg_cost: number;
  custom_margin_percent: number | null;
  effective_margin_percent: number;
  calculated_sell_price: number;
  cost_last_updated: string | null;
  active_layers: number;
}

/** Top-level spending KPIs for a date range */
export interface SpendingSummary {
  total_spend: number;
  order_count: number;
  avg_order_size: number;
  active_suppliers: number;
  period_label?: string;
}

/** Spending breakdown for a single supplier */
export interface SupplierSpend {
  supplier_id: number;
  supplier_name: string;
  total_spend: number;
  order_count: number;
  pct_of_total: number;
}

/** Spending breakdown for a part category */
export interface CategorySpend {
  category_id: number | null;
  category_name: string;
  total_spend: number;
  item_count: number;
}

/** Spending breakdown for a single job */
export interface JobSpend {
  job_id: number;
  job_name: string;
  total_spend: number;
  budget_limit: number | null;
  budget_pct: number | null;
}

/** A single point on the spending trend line chart */
export interface SpendingTrendPoint {
  period_label: string;
  total_spend: number;
  order_count: number;
}

/** Full cost rollup for a single job */
export interface JobCostRollup {
  job_id: number;
  job_name: string;
  total_parts_cost: number;
  total_labor_cost: number;
  total_labor_hours?: number;
  billing_rate?: number;
  combined_total: number;
  budget_limit: number | null;
  budget_remaining: number | null;
  budget_pct: number | null;
  budget_alert_percent: number;
}

/** A job approaching or exceeding its budget */
export interface BudgetAlert {
  job_id: number;
  job_name: string;
  budget_limit: number;
  current_spend: number;
  pct_used: number;
  alert_level: 'warning' | 'danger';
}

/** A part with price variance between quoted and actual */
export interface PriceVarianceItem {
  part_id: number;
  part_name: string;
  supplier_name: string;
  po_number: string;
  quoted_price: number;
  actual_price: number;
  variance_amount: number;
  variance_pct: number;
  variance_level: 'ok' | 'warning' | 'danger';
}

/** Pending actions counts for daily report */
export interface DailyReportPendingActions {
  jpos_awaiting_approval: number;
  pos_to_submit: number;
  returns_to_sort: number;
  overdue_deliveries: number;
}

/** A PO expected this week (daily report) */
export interface DailyReportDelivery {
  po_id: number;
  po_number: string;
  supplier_name: string;
  expected_delivery: string;
  line_count: number;
  is_overdue: boolean;
}

/** Today's activity summary */
export interface DailyReportActivity {
  orders_created: number;
  items_received: number;
  returns_processed: number;
}

/** Full daily report response */
export interface DailyReportData {
  pending_actions: DailyReportPendingActions;
  expected_deliveries: DailyReportDelivery[];
  overdue_items: DailyReportDelivery[];
  todays_activity: DailyReportActivity;
  budget_alerts: BudgetAlert[];
}


// ═══════════════════════════════════════════════════════════════════
// Phase 7E: Bulk Actions
// ═══════════════════════════════════════════════════════════════════

/** Submit multiple draft POs at once */
export interface BulkPOSubmit {
  po_ids: number[];
}

/** Update status on multiple POs at once */
export interface BulkPOStatusUpdate {
  po_ids: number[];
  new_status: string;
  notes?: string | null;
}

/** Approve multiple pending returns at once */
export interface BulkReturnApprove {
  return_ids: number[];
  notes?: string | null;
}

/** Per-item result from a bulk action */
export interface BulkActionResult {
  id: number;
  success: boolean;
  error?: string;
}
