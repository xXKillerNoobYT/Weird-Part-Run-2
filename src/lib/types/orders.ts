/**
 * Orders & Procurement types — JPO, PO, receiving, returns, staging zones,
 * status history, supplier rankings, procurement dashboard, price history,
 * notifications, company profiles.
 */

// ═══════════════════════════════════════════════════════════════════
// ORDERS & PROCUREMENT MODULE (Phase 5)
// ═══════════════════════════════════════════════════════════════════

// ── Status Type Unions ───────────────────────────────────────────

export type JPOStatus =
  | 'draft' | 'pending_approval' | 'approved' | 'ordering'
  | 'partially_ordered' | 'ordered' | 'partially_received'
  | 'received' | 'closed';

export type POStatus =
  | 'draft' | 'submitted' | 'acknowledged' | 'confirmed'
  | 'partially_received' | 'received' | 'closed' | 'cancelled';

export type POLineStatus = 'pending' | 'partial' | 'received' | 'backordered' | 'cancelled';

export type ReturnStatus =
  | 'draft' | 'pending_approval' | 'approved' | 'shipped'
  | 'received_by_supplier' | 'credited' | 'closed';

export type ReturnType = 'job_to_warehouse' | 'warehouse_to_supplier';
export type ReturnReason = 'defective' | 'wrong_item' | 'surplus' | 'damaged' | 'unused';
export type ItemCondition = 'new' | 'used' | 'damaged' | 'defective';
export type DispositionType = 'return_to_supplier' | 'restock' | 'write_off';
export type JPOPriority = 'normal' | 'urgent';
export type LinePriority = 'normal' | 'urgent' | 'critical';
export type StagingZoneType = 'general' | 'job_assigned' | 'returns' | 'overflow';

/** Human-readable labels for JPO statuses */
export const JPO_STATUS_LABELS: Record<JPOStatus, string> = {
  draft: 'Draft',
  pending_approval: 'Pending Approval',
  approved: 'Approved',
  ordering: 'Ordering',
  partially_ordered: 'Partially Ordered',
  ordered: 'Ordered',
  partially_received: 'Partially Received',
  received: 'Received',
  closed: 'Closed',
};

/** Human-readable labels for PO statuses */
export const PO_STATUS_LABELS: Record<POStatus, string> = {
  draft: 'Draft',
  submitted: 'Sent',
  acknowledged: 'Acknowledged',
  confirmed: 'Confirmed',
  partially_received: 'Partially Received',
  received: 'Received',
  closed: 'Closed',
  cancelled: 'Cancelled',
};

/** Human-readable labels for return statuses */
export const RETURN_STATUS_LABELS: Record<ReturnStatus, string> = {
  draft: 'Draft',
  pending_approval: 'Pending Approval',
  approved: 'Approved',
  shipped: 'Shipped',
  received_by_supplier: 'Received by Supplier',
  credited: 'Credited',
  closed: 'Closed',
};


// ── JPO (Job Parts Order) Types ──────────────────────────────────

export interface JPOLineCreate {
  part_id: number;
  qty_requested: number;
  priority?: LinePriority;
  entry_id?: number | null;
  suggested_supplier_id?: number | null;
  notes?: string;
}

export interface SpecialItemCreate {
  description: string;
  part_number?: string;
  quantity?: number;
  unit?: string;
  estimated_cost?: number | null;
  notes?: string;
}

export interface JPOCreate {
  job_id?: number | null;          // NULL for warehouse restocks
  order_type?: 'job' | 'warehouse';
  priority?: JPOPriority;
  smart_suggestions_enabled?: boolean;
  notes?: string;
  lines: JPOLineCreate[];
  special_items?: SpecialItemCreate[];
}

export interface JPOUpdate {
  priority?: JPOPriority;
  notes?: string;
}

export interface JPOLineResponse {
  id: number;
  jpo_id: number;
  part_id: number;
  qty_requested: number;
  qty_ordered: number;
  qty_received: number;
  priority: LinePriority;
  entry_id: number | null;
  suggested_supplier_id: number | null;
  notes: string | null;
  created_at: string | null;
  // Joined fields
  part_number: string | null;
  part_description: string | null;
  supplier_name: string | null;
  // Hierarchy fields
  part_name: string | null;
  category_name: string | null;
  type_name: string | null;
  color_name: string | null;
  color_hex: string | null;
  brand_name: string | null;
}

export interface JPOResponse {
  id: number;
  job_id: number | null;
  order_number: string;
  status: JPOStatus;
  priority: JPOPriority;
  order_type: 'job' | 'warehouse';
  has_special_items: boolean;
  smart_suggestions_enabled: boolean;
  requested_by: number;
  approved_by: number | null;
  approved_at: string | null;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  job_name: string | null;
  job_number: string | null;
  requester_name: string | null;
  approver_name: string | null;
  line_count: number;
  special_item_count: number;
  lines: JPOLineResponse[] | null;
  special_items?: SpecialItemResponse[] | null;
}

export interface JPOListItem {
  id: number;
  job_id: number | null;
  order_number: string;
  status: JPOStatus;
  priority: JPOPriority;
  order_type: 'job' | 'warehouse';
  has_special_items: boolean;
  requested_by: number;
  requester_name: string | null;
  job_name: string | null;
  job_number: string | null;
  line_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface JPOApproval {
  action: 'approve' | 'reject';
  notes?: string;
}


// ── PO (Purchase Order) Types ────────────────────────────────────

export interface POLineCreate {
  part_id: number;
  jpo_line_id?: number | null;
  qty_ordered: number;
  unit_cost?: number | null;
  notes?: string;
}

export interface POCreate {
  supplier_id: number;
  expected_delivery?: string;
  shipping_method?: string;
  notes?: string;
  internal_notes?: string;
  lines: POLineCreate[];
}

export interface POUpdate {
  expected_delivery?: string;
  shipping_method?: string;
  tracking_number?: string;
  notes?: string;
  internal_notes?: string;
  tax_amount?: number;
  shipping_cost?: number;
}

export interface POLineResponse {
  id: number;
  po_id: number;
  jpo_line_id: number | null;
  part_id: number;
  qty_ordered: number;
  qty_received: number;
  unit_cost: number | null;
  received_unit_cost: number | null;
  status: POLineStatus;
  backorder_expected_date: string | null;
  received_at: string | null;
  received_by: number | null;
  notes: string | null;
  created_at: string | null;
  // Joined fields
  part_number: string | null;
  part_description: string | null;
  line_total: number | null;
  // Hierarchy fields
  part_name: string | null;
  category_name: string | null;
  type_name: string | null;
  color_name: string | null;
  color_hex: string | null;
  brand_name: string | null;
}

export interface POResponse {
  id: number;
  po_number: string;
  supplier_id: number;
  status: POStatus;
  order_date: string | null;
  expected_delivery: string | null;
  actual_delivery: string | null;
  shipping_method: string | null;
  tracking_number: string | null;
  subtotal: number;
  tax_amount: number;
  shipping_cost: number;
  total_cost: number;
  notes: string | null;
  internal_notes: string | null;
  pdf_path: string | null;
  submitted_by: number | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  supplier_name: string | null;
  submitter_name: string | null;
  line_count: number;
  lines: POLineResponse[] | null;
}

export interface POListItem {
  id: number;
  po_number: string;
  supplier_id: number;
  supplier_name: string | null;
  status: POStatus;
  order_date: string | null;
  expected_delivery: string | null;
  total_cost: number;
  line_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface POFromJPO {
  jpo_id: number;
  supplier_line_groups?: SupplierLineGroup[] | null;
}

export interface SupplierLineGroup {
  supplier_id: number;
  line_ids: number[];
  expected_delivery?: string;
  notes?: string;
}


// ── Receiving Types ──────────────────────────────────────────────

export interface ReceiveItem {
  po_line_id: number;
  qty_received: number;
  actual_cost?: number | null;
  staging_zone_id?: number | null;
  notes?: string;
}

export interface ReceiveByPO {
  po_id: number;
  items: ReceiveItem[];
}


// ── Return Types ─────────────────────────────────────────────────

export interface ReturnLineCreate {
  part_id: number;
  po_line_id?: number | null;
  qty: number;
  condition?: ItemCondition;
  disposition: DispositionType;
  unit_cost?: number | null;
  notes?: string;
}

export interface ReturnCreate {
  return_type: ReturnType;
  po_id?: number | null;
  supplier_id?: number | null;
  job_id?: number | null;
  reason: ReturnReason;
  notes?: string;
  lines: ReturnLineCreate[];
}

export interface ReturnUpdate {
  rma_number?: string;
  shipping_carrier?: string;
  tracking_number?: string;
  credit_amount?: number;
  notes?: string;
}

export interface ReturnLineResponse {
  id: number;
  return_id: number;
  part_id: number;
  po_line_id: number | null;
  qty: number;
  condition: ItemCondition;
  disposition: DispositionType;
  unit_cost: number | null;
  notes: string | null;
  created_at: string | null;
  // Joined fields
  part_number: string | null;
  part_description: string | null;
  // Hierarchy fields
  part_name: string | null;
  category_name: string | null;
  type_name: string | null;
  color_name: string | null;
  color_hex: string | null;
  brand_name: string | null;
}

export interface ReturnResponse {
  id: number;
  return_number: string;
  return_type: ReturnType;
  po_id: number | null;
  supplier_id: number | null;
  job_id: number | null;
  status: ReturnStatus;
  rma_number: string | null;
  reason: ReturnReason;
  shipping_carrier: string | null;
  tracking_number: string | null;
  credit_amount: number;
  notes: string | null;
  initiated_by: number;
  approved_by: number | null;
  approved_at: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  supplier_name: string | null;
  job_name: string | null;
  initiator_name: string | null;
  line_count: number;
  lines: ReturnLineResponse[] | null;
}

export interface ReturnListItem {
  id: number;
  return_number: string;
  return_type: ReturnType;
  status: ReturnStatus;
  reason: ReturnReason;
  supplier_name: string | null;
  job_name: string | null;
  initiator_name: string | null;
  line_count: number;
  credit_amount: number;
  created_at: string | null;
}


// ── Staging Zone Types ───────────────────────────────────────────

export interface StagingZoneResponse {
  id: number;
  label: string;
  qr_code: string | null;
  zone_type: StagingZoneType;
  current_job_id: number | null;
  is_active: boolean;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined fields
  job_name: string | null;
  item_count: number;
}

export interface DistributionItem {
  part_id: number;
  qty: number;
  dest_type: 'warehouse' | 'truck' | 'job';
  dest_id: number;
  notes?: string;
}

export interface DistributeFromStaging {
  zone_id: number;
  items: DistributionItem[];
}


// ── Status History (Audit Trail) ─────────────────────────────────

export interface StatusHistoryEntry {
  id: number;
  entity_type: string;
  entity_id: number;
  old_status: string | null;
  new_status: string;
  changed_by: number;
  changer_name: string | null;
  notes: string | null;
  created_at: string | null;
}


// ── Supplier Contact Ratings ─────────────────────────────────────

export type ContactType = 'business' | 'rep' | 'driver';
export type RatingCategory = 'responsiveness' | 'accuracy' | 'helpfulness' | 'professionalism';

export interface SupplierContactRatingCreate {
  supplier_id: number;
  contact_type: ContactType;
  score: number;  // 1-5
  category?: RatingCategory;
  notes?: string;
  interaction_date?: string;
}

export interface SupplierContactRatingResponse {
  id: number;
  supplier_id: number;
  contact_type: ContactType;
  rated_by: number;
  score: number;
  category: RatingCategory | null;
  notes: string | null;
  interaction_date: string;
  created_at: string | null;
  rater_name: string | null;
}


// ── Supplier Ranking ─────────────────────────────────────────────

export interface SupplierRanking {
  supplier_id: number;
  supplier_name: string;
  composite_score: number;
  price_score: number;
  on_time_score: number;
  communication_score: number;
  quality_score: number;
  lead_time_score: number;
  avg_unit_cost: number | null;
  avg_lead_days: number | null;
  is_preferred: boolean;
}


// ── Procurement Dashboard ────────────────────────────────────────

export interface ReorderSuggestion {
  part_id: number;
  part_number: string | null;
  part_description: string | null;
  current_stock: number;
  reorder_point: number;
  target_qty: number;
  pending_po_qty: number;
  expected_return_qty: number;
  suggested_order_qty: number;
  best_supplier_id: number | null;
  best_supplier_name: string | null;
  estimated_cost: number | null;
  days_until_stockout: number | null;
  // Hierarchy fields
  part_name: string | null;
  category_name: string | null;
  type_name: string | null;
  color_name: string | null;
  color_hex: string | null;
  brand_name: string | null;
}

export interface ProcurementDashboard {
  parts_needing_reorder: number;
  pending_po_count: number;
  pending_po_value: number;
  avg_lead_time_days: number;
  overdue_deliveries: number;
  parts_below_critical: number;
}


// ── Price History ────────────────────────────────────────────────

export interface PriceHistoryEntry {
  id: number;
  part_id: number;
  supplier_id: number;
  price: number;
  effective_date: string;
  source: string;
  reference_id: number | null;
  notes: string | null;
  created_at: string | null;
  supplier_name: string | null;
  part_number: string | null;
}


// ═══════════════════════════════════════════════════════════════════
// NOTIFICATIONS (Phase 5 — cross-module)
// ═══════════════════════════════════════════════════════════════════

export interface NotificationResponse {
  id: number;
  user_id: number;
  type: string;
  title: string;
  message: string | null;
  link: string | null;
  entity_type: string | null;
  entity_id: number | null;
  is_read: boolean;
  created_at: string | null;
}

export interface NotificationListResponse {
  items: NotificationResponse[];
  total: number;
  unread_count: number;
}

export interface NotificationMarkRead {
  notification_ids?: number[];
  mark_all?: boolean;
}

export interface NotificationBadge {
  unread_count: number;
  has_urgent: boolean;
}

export interface NotificationPreference {
  notification_type: string;
  is_enabled: boolean;
}

export interface NotificationPreferenceResponse {
  user_id: number;
  preferences: NotificationPreference[];
}

// Sound settings (Phase 7E)
export interface NotificationSoundSetting {
  notification_type: string;
  sound_enabled: boolean;
  sound_file: string;
}

export interface NotificationSoundSettingsResponse {
  user_id: number;
  settings: NotificationSoundSetting[];
}


// ═══════════════════════════════════════════════════════════════════
// COMPANY PROFILES (Phase 5 — Settings)
// ═══════════════════════════════════════════════════════════════════

export interface CompanyProfile {
  id: number;
  name: string;
  address_street: string | null;
  address_city: string | null;
  address_state: string | null;
  address_zip: string | null;
  phone: string | null;
  email: string | null;
  website: string | null;
  logo_path: string | null;
  contractor_license: string | null;
  insurance_info: string | null;
  tax_id: string | null;
  is_primary: boolean;
  branch_name: string | null;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface CompanyProfileCreate {
  name: string;
  address_street?: string;
  address_city?: string;
  address_state?: string;
  address_zip?: string;
  phone?: string;
  email?: string;
  website?: string;
  contractor_license?: string;
  insurance_info?: string;
  tax_id?: string;
  is_primary?: boolean;
  branch_name?: string;
  notes?: string;
}

export interface CompanyProfileUpdate {
  name?: string;
  address_street?: string;
  address_city?: string;
  address_state?: string;
  address_zip?: string;
  phone?: string;
  email?: string;
  website?: string;
  logo_path?: string;
  contractor_license?: string;
  insurance_info?: string;
  tax_id?: string;
  is_primary?: boolean;
  branch_name?: string;
  notes?: string;
}


// ── Special Items (referenced by JPOResponse) ────────────────────

export interface SpecialItemResponse {
  id: number;
  jpo_id: number;
  description: string;
  part_number: string | null;
  quantity: number;
  unit: string;
  estimated_cost: number | null;
  notes: string | null;
  is_flagged: boolean;
  flag_resolved_by: number | null;
  flag_resolved_at: string | null;
  linked_part_id: number | null;
  created_at: string | null;
  // Joined fields
  resolver_name: string | null;
  linked_part_description: string | null;
  // Joined when fetched via flagged-items endpoint
  order_number?: string | null;
  job_id?: number | null;
  job_name?: string | null;
  job_number?: string | null;
  requester_name?: string | null;
}

export interface SpecialItemResolve {
  linked_part_id?: number | null;
  notes?: string;
}
