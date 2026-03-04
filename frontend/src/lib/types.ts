/**
 * Shared TypeScript types used across the frontend.
 *
 * These mirror the backend Pydantic models for type-safe API communication.
 */

// ── API Response Wrapper ───────────────────────────────────────────

export interface ApiResponse<T = unknown> {
  success: boolean;
  data: T | null;
  message: string | null;
  error: string | null;
}

// ── Auth Types ─────────────────────────────────────────────────────

export interface TokenResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
}

export interface PinTokenResponse {
  pin_token: string;
  token_type: string;
  expires_in: number;
}

export interface DeviceLoginResponse {
  auto_login: boolean;
  token: TokenResponse | null;
  requires_user_selection: boolean;
  is_public_device: boolean;
  device_id: number | null;
}

export interface HatSummary {
  id: number;
  name: string;
  level: number;
}

export interface UserProfile {
  id: number;
  display_name: string;
  email: string | null;
  phone: string | null;
  avatar_url: string | null;
  certification: string | null;
  hire_date: string | null;
  is_active: boolean;
  hats: HatSummary[];
  permissions: string[];
  created_at: string | null;
}

export interface UserPickerItem {
  id: number;
  display_name: string;
  avatar_url: string | null;
  hats: string[];
}

// ── Settings Types ─────────────────────────────────────────────────

export interface ThemeSettings {
  theme_mode: 'light' | 'dark' | 'system';
  primary_color: string;
  font_family: string;
}

// ── Navigation Types ───────────────────────────────────────────────

export interface NavModule {
  id: string;
  label: string;
  icon: string;
  path: string;
  permission?: string;
  tabs: NavTab[];
}

export interface NavTab {
  id: string;
  label: string;
  path: string;
  permission?: string;
  /** Optional group label — tabs with the same group are visually clustered with a divider. */
  group?: string;
}

// ── Pagination ────────────────────────────────────────────────────

export interface PaginatedData<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

// ── Common Types ───────────────────────────────────────────────────

export interface StatusMessage {
  status: string;
  module: string;
  message?: string;
}

// ═══════════════════════════════════════════════════════════════════
// PARTS MODULE (Phase 2)
// ═══════════════════════════════════════════════════════════════════

// ── Part Hierarchy (Category → Style → Type → Color) ─────────────

export interface PartCategory {
  id: number;
  name: string;
  description: string | null;
  sort_order: number;
  is_active: boolean;
  image_url: string | null;
  style_count: number;
  part_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface PartCategoryCreate {
  name: string;
  description?: string;
  sort_order?: number;
  image_url?: string;
}

export interface PartCategoryUpdate {
  name?: string;
  description?: string;
  sort_order?: number;
  is_active?: boolean;
  image_url?: string;
}

export interface PartStyle {
  id: number;
  category_id: number;
  category_name: string | null;
  name: string;
  description: string | null;
  sort_order: number;
  is_active: boolean;
  image_url: string | null;
  type_count: number;
  part_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface PartStyleCreate {
  category_id: number;
  name: string;
  description?: string;
  sort_order?: number;
  image_url?: string;
}

export interface PartStyleUpdate {
  name?: string;
  description?: string;
  sort_order?: number;
  is_active?: boolean;
  image_url?: string;
}

export interface PartType {
  id: number;
  style_id: number;
  style_name: string | null;
  category_name: string | null;
  name: string;
  description: string | null;
  sort_order: number;
  is_active: boolean;
  image_url: string | null;
  color_count: number;
  part_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface PartTypeCreate {
  style_id: number;
  name: string;
  description?: string;
  sort_order?: number;
  image_url?: string;
}

export interface PartTypeUpdate {
  name?: string;
  description?: string;
  sort_order?: number;
  is_active?: boolean;
  image_url?: string;
}

export interface PartColor {
  id: number;
  name: string;
  hex_code: string | null;
  sort_order: number;
  is_active: boolean;
  part_count: number;
  created_at: string | null;
}

export interface PartColorCreate {
  name: string;
  hex_code?: string;
  sort_order?: number;
}

export interface PartColorUpdate {
  name?: string;
  hex_code?: string;
  sort_order?: number;
  is_active?: boolean;
}

// ── Type ↔ Color Links ───────────────────────────────────────────

export interface TypeColorLink {
  id: number;
  type_id: number;
  color_id: number;
  color_name: string | null;
  hex_code: string | null;
  image_url: string | null;
  sort_order: number;
  created_at: string | null;
}

export interface TypeColorLinkCreate {
  type_id: number;
  color_id: number;
  image_url?: string;
  sort_order?: number;
}

// ── Type ↔ Brand Links ──────────────────────────────────────────

export interface TypeBrandLink {
  id: number;
  type_id: number;
  brand_id: number | null;     // null = General (unbranded)
  brand_name: string | null;   // "General" when brand_id is null
  part_count: number;
  created_at: string | null;
}

export interface TypeBrandLinkCreate {
  type_id: number;
  brand_id: number | null;     // null = General
}

// ── Categories Tree Selection ───────────────────────────────────

export type CategoryNodeType = 'category' | 'style' | 'type' | 'brand' | 'part' | 'color';

export interface SelectedCategoryNode {
  type: CategoryNodeType;
  id: number;
  // Context for deep nodes — carry parent info down the tree
  categoryId?: number;
  styleId?: number;
  typeId?: number;
  brandId?: number | null;   // null = General
  colorId?: number;
  partId?: number;
}

// ── Quick-create Part (minimal request from tree) ───────────────

export interface QuickCreatePartRequest {
  color_id: number;
}

// ── Hierarchy Tree (nested for UI cascading dropdowns) ───────────

export interface HierarchyTypeColor {
  id: number;            // type_color_link.id
  color_id: number;
  name: string;
  hex_code: string | null;
  image_url: string | null;
  sort_order: number;
}

export interface HierarchyType {
  id: number;
  name: string;
  image_url: string | null;
  sort_order: number;
  colors: HierarchyTypeColor[];
}

export interface HierarchyStyle {
  id: number;
  name: string;
  image_url: string | null;
  sort_order: number;
  types: HierarchyType[];
}

export interface HierarchyCategory {
  id: number;
  name: string;
  image_url: string | null;
  sort_order: number;
  styles: HierarchyStyle[];
}

export interface HierarchyColor {
  id: number;
  name: string;
  hex_code: string | null;
  image_url: string | null;
  sort_order: number;
}

export interface HierarchyTree {
  categories: HierarchyCategory[];
  colors: HierarchyColor[];
}

// ── Catalog Groups (grouped product card view) ───────────────────

export interface CatalogGroupVariant {
  id: number;
  style_name: string | null;
  type_name: string | null;
  color_name: string | null;
  code: string | null;
  name: string;
  manufacturer_part_number: string | null;
  has_pending_part_number: boolean;
  unit_of_measure: string;
  company_cost_price: number | null;
  company_sell_price: number | null;
  total_stock: number;
  image_url: string | null;
  is_deprecated: boolean;
}

export interface CatalogGroup {
  category_id: number;
  category_name: string;
  brand_id: number | null;
  brand_name: string | null;
  image_url: string | null;
  variant_count: number;
  total_stock: number;
  price_range_low: number | null;
  price_range_high: number | null;
  variants: CatalogGroupVariant[];
}

// ── Brands ────────────────────────────────────────────────────────

export interface Brand {
  id: number;
  name: string;
  website: string | null;
  notes: string | null;
  is_active: boolean;
  part_count: number;
  supplier_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface BrandCreate {
  name: string;
  website?: string;
  notes?: string;
}

export interface BrandUpdate {
  name?: string;
  website?: string;
  notes?: string;
  is_active?: boolean;
}

// ── Brand ↔ Supplier Links ──────────────────────────────────────

export interface BrandSupplierLink {
  id: number;
  brand_id: number;
  brand_name: string | null;
  supplier_id: number;
  supplier_name: string | null;
  account_number: string | null;
  notes: string | null;
  is_active: boolean;
  created_at: string | null;
}

export interface BrandSupplierLinkCreate {
  brand_id: number;
  supplier_id: number;
  account_number?: string;
  notes?: string;
}

// ── Suppliers ─────────────────────────────────────────────────────

export type DeliveryMethod = 'standard_shipping' | 'scheduled_delivery' | 'in_store_pickup';

export interface Supplier {
  id: number;
  name: string;
  // Business contact (main office / general inquiries / returns)
  contact_name: string | null;
  email: string | null;
  phone: string | null;
  address: string | null;
  website: string | null;
  // Sales rep contact (the person you call for orders and quotes)
  rep_name: string | null;
  rep_email: string | null;
  rep_phone: string | null;
  notes: string | null;
  // Delivery logistics — multi-select with a primary
  delivery_methods: DeliveryMethod[];        // All methods this supplier offers
  primary_delivery_method: DeliveryMethod;   // The default/preferred method
  delivery_days: string | null;              // JSON: '["monday","wednesday","friday"]'
  special_order_lead_days: number | null;    // Extra days for items not in local warehouse
  delivery_notes: string | null;
  // Delivery driver contact (the person physically bringing parts)
  driver_name: string | null;
  driver_phone: string | null;
  driver_email: string | null;
  // Reliability metrics
  on_time_rate: number;
  quality_score: number;
  avg_lead_days: number;
  reliability_score: number;
  is_active: boolean;
  // Computed
  brand_count: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface SupplierCreate {
  name: string;
  // Business contact
  contact_name?: string;
  email?: string;
  phone?: string;
  address?: string;
  website?: string;
  // Sales rep contact
  rep_name?: string;
  rep_email?: string;
  rep_phone?: string;
  notes?: string;
  delivery_methods?: DeliveryMethod[];
  primary_delivery_method?: DeliveryMethod;
  delivery_days?: string;
  special_order_lead_days?: number;
  delivery_notes?: string;
  // Delivery driver contact
  driver_name?: string;
  driver_phone?: string;
  driver_email?: string;
}

export interface SupplierUpdate {
  name?: string;
  // Business contact
  contact_name?: string;
  email?: string;
  phone?: string;
  address?: string;
  website?: string;
  // Sales rep contact
  rep_name?: string;
  rep_email?: string;
  rep_phone?: string;
  notes?: string;
  delivery_methods?: DeliveryMethod[];
  primary_delivery_method?: DeliveryMethod;
  delivery_days?: string;
  special_order_lead_days?: number;
  delivery_notes?: string;
  // Delivery driver contact
  driver_name?: string;
  driver_phone?: string;
  driver_email?: string;
  on_time_rate?: number;
  quality_score?: number;
  avg_lead_days?: number;
  is_active?: boolean;
}

// ── Part-Supplier Links ───────────────────────────────────────────

export interface PartSupplierLink {
  id: number;
  supplier_id: number;
  supplier_name: string | null;
  supplier_part_number: string | null;
  supplier_cost_price: number | null;
  moq: number;
  discount_brackets: string | null;
  is_preferred: boolean;
  last_price_date: string | null;
}

export interface PartSupplierLinkCreate {
  supplier_id: number;
  supplier_part_number?: string;
  supplier_cost_price?: number;
  moq?: number;
  is_preferred?: boolean;
}

// ── Parts (Orderable Variants) ──────────────────────────────────

export interface PartListItem {
  id: number;
  // Hierarchy names
  category_name: string | null;
  style_name: string | null;
  type_name: string | null;
  color_name: string | null;
  color_id: number | null;
  color_hex: string | null;
  // Identity
  part_type: 'general' | 'specific';
  code: string | null;
  name: string;
  brand_id: number | null;
  brand_name: string | null;
  manufacturer_part_number: string | null;
  has_pending_part_number: boolean;
  // Physical
  unit_of_measure: string;
  // Pricing
  company_cost_price: number | null;
  company_markup_percent: number | null;
  company_sell_price: number | null;
  // Stock
  total_stock: number;
  // Inventory targets
  min_stock_level: number;
  max_stock_level: number;
  target_stock_level: number;
  // Forecast
  forecast_adu_30: number | null;
  forecast_days_until_low: number | null;
  forecast_suggested_order: number | null;
  // Status
  is_deprecated: boolean;
  is_qr_tagged: boolean;
}

export interface Part extends PartListItem {
  // Hierarchy IDs
  category_id: number;
  style_id: number | null;
  type_id: number | null;
  color_id: number | null;
  // Identity extras
  description: string | null;
  brand_id: number | null;
  // Physical
  weight_lbs: number | null;
  // Stock breakdown
  warehouse_stock: number;
  truck_stock: number;
  job_stock: number;
  pulled_stock: number;
  // Forecast extras
  forecast_last_run: string | null;
  // Status extras
  deprecation_reason: string | null;
  notes: string | null;
  image_url: string | null;
  pdf_url: string | null;
  // Related
  suppliers: PartSupplierLink[];
  // Timestamps
  created_at: string | null;
  updated_at: string | null;
}

export interface PartCreate {
  // Hierarchy (category required, rest optional)
  category_id: number;
  style_id?: number;
  type_id?: number;
  color_id?: number;
  // Identity
  part_type?: 'general' | 'specific';
  code?: string;    // Optional for general parts
  name: string;
  description?: string;
  // Brand (for specific parts)
  brand_id?: number;
  manufacturer_part_number?: string;
  // Physical
  unit_of_measure?: string;
  weight_lbs?: number;
  // Pricing
  company_cost_price?: number;
  company_markup_percent?: number;
  // Inventory targets
  min_stock_level?: number;
  max_stock_level?: number;
  target_stock_level?: number;
  // Metadata
  notes?: string;
  image_url?: string;
  pdf_url?: string;
}

export interface PartUpdate {
  // Hierarchy
  category_id?: number;
  style_id?: number;
  type_id?: number;
  color_id?: number;
  // Identity
  part_type?: 'general' | 'specific';
  code?: string;
  name?: string;
  description?: string;
  // Brand
  brand_id?: number;
  manufacturer_part_number?: string;
  // Physical
  unit_of_measure?: string;
  weight_lbs?: number;
  // Pricing
  company_cost_price?: number;
  company_markup_percent?: number;
  // Inventory targets
  min_stock_level?: number;
  max_stock_level?: number;
  target_stock_level?: number;
  // Status
  is_deprecated?: boolean;
  deprecation_reason?: string;
  is_qr_tagged?: boolean;
  notes?: string;
  image_url?: string;
  pdf_url?: string;
}

export interface PartPricingUpdate {
  company_cost_price: number;
  company_markup_percent: number;
}

export interface PartSearchParams {
  search?: string;
  // Hierarchy filters
  category_id?: number;
  style_id?: number;
  type_id?: number;
  color_id?: number;
  // Classification filters
  part_type?: string;
  brand_id?: number;
  has_pending_pn?: boolean;
  // Status filters
  is_deprecated?: boolean;
  is_qr_tagged?: boolean;
  low_stock?: boolean;
  // Sorting & pagination
  sort_by?: string;
  sort_dir?: 'asc' | 'desc';
  page?: number;
  page_size?: number;
}

// ── Pending Part Numbers ─────────────────────────────────────────

export interface PendingPartNumberItem {
  id: number;
  name: string;
  category_name: string | null;
  style_name: string | null;
  type_name: string | null;
  color_name: string | null;
  brand_id: number | null;
  brand_name: string | null;
  created_at: string | null;
}

// ── Stock ─────────────────────────────────────────────────────────

export interface StockEntry {
  id: number;
  part_id: number;
  part_code?: string;
  part_name?: string;
  location_type: string;
  location_id: number;
  qty: number;
  supplier_id: number | null;
  supplier_name: string | null;
  last_counted: string | null;
  updated_at: string | null;
}

export interface StockSummary {
  part_id: number;
  total: number;
  warehouse: number;
  pulled: number;
  truck: number;
  job: number;
}

// ── Forecasting ───────────────────────────────────────────────────

export interface ForecastItem {
  id: number;
  code: string | null;
  name: string;
  category_name: string | null;
  brand_name: string | null;
  total_stock: number;
  min_stock_level: number;
  forecast_adu_30: number;
  forecast_adu_90: number;
  forecast_reorder_point: number;
  forecast_target_qty: number;
  forecast_suggested_order: number;
  forecast_days_until_low: number;
  forecast_last_run: string | null;
}

// ── Catalog Stats ─────────────────────────────────────────────────

export interface CatalogStats {
  total_parts: number;
  deprecated_parts: number;
  general_parts: number;
  specific_parts: number;
  unique_brands: number;
  unique_categories: number;
  pending_part_numbers: number;
}

// ── Import/Export ──────────────────────────────────────────────────

export interface ImportResult {
  created: number;
  updated: number;
  errors: string[];
  total_errors: number;
}

// ═══════════════════════════════════════════════════════════════════
// WAREHOUSE MODULE (Phase 3)
// ═══════════════════════════════════════════════════════════════════

// ── Movement Wizard ───────────────────────────────────────────────

export type LocationType = 'warehouse' | 'pulled' | 'truck' | 'job';

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


// ═══════════════════════════════════════════════════════════════════
// JOBS MODULE (Phase 4)
// ═══════════════════════════════════════════════════════════════════

// ── Job Types ────────────────────────────────────────────────────

export type JobStatus =
  | 'pending' | 'active' | 'on_hold'
  | 'completed' | 'cancelled'
  | 'continuous_maintenance' | 'on_call';
export type JobPriority = 'low' | 'normal' | 'high' | 'urgent';
export type JobType = 'service' | 'new_construction' | 'remodel' | 'maintenance' | 'emergency';
export type OnCallType = 'on_call' | 'warranty';

/** Display labels for on_call sub-types */
export const ON_CALL_TYPE_LABELS: Record<OnCallType, string> = {
  on_call: 'On Call',
  warranty: 'Warranty',
};

/** Human-readable display labels for job statuses */
export const JOB_STATUS_LABELS: Record<JobStatus, string> = {
  pending: 'Pending',
  active: 'Active',
  on_hold: 'On Hold',
  completed: 'Completed',
  cancelled: 'Cancelled',
  continuous_maintenance: 'Cont. Maint.',
  on_call: 'On Call / Warranty',
};

// ── Bill Rate Types ──────────────────────────────────────────────

export interface BillRateType {
  id: number;
  name: string;
  description?: string | null;
  sort_order: number;
  is_active: boolean;
  created_at?: string | null;
}

export interface BillRateTypeCreate {
  name: string;
  description?: string | null;
}

export interface BillRateTypeUpdate {
  name?: string;
  description?: string | null;
  is_active?: boolean;
}
export type LaborStatus = 'clocked_in' | 'clocked_out' | 'edited' | 'approved';
export type ReportStatus = 'generated' | 'reviewed' | 'locked';

export interface JobCreate {
  job_number: string;
  job_name: string;
  customer_name: string;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  state?: string;
  zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  status?: JobStatus;
  priority?: JobPriority;
  job_type?: JobType;
  bill_rate_type_id?: number;
  lead_user_id?: number;
  start_date?: string;
  due_date?: string;
  notes?: string;
  on_call_type?: OnCallType;
  warranty_start_date?: string;
  warranty_end_date?: string;
}

export interface JobUpdate {
  job_name?: string;
  customer_name?: string;
  status?: JobStatus;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  state?: string;
  zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  priority?: JobPriority;
  job_type?: JobType;
  bill_rate_type_id?: number;
  lead_user_id?: number;
  start_date?: string;
  due_date?: string;
  notes?: string;
  on_call_type?: OnCallType | null;
  warranty_start_date?: string | null;
  warranty_end_date?: string | null;
}

export interface JobResponse {
  id: number;
  job_number: string;
  job_name: string;
  customer_name: string;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  gps_lat?: number | null;
  gps_lng?: number | null;
  status: JobStatus;
  priority: JobPriority;
  job_type: JobType;
  bill_rate_type_id?: number | null;
  bill_rate_type_name?: string | null;
  lead_user_id?: number | null;
  lead_user_name?: string | null;
  start_date?: string | null;
  due_date?: string | null;
  completed_date?: string | null;
  notes?: string | null;
  on_call_type?: OnCallType | null;
  warranty_start_date?: string | null;
  warranty_end_date?: string | null;
  warranty_days_remaining?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
  // Aggregated stats
  total_labor_hours?: number | null;
  total_parts_cost?: number | null;
  active_workers?: number | null;
  // Notebook task aggregation
  open_task_count: number;
  task_summary?: Record<string, number> | null;
}

export interface JobListItem {
  id: number;
  job_number: string;
  job_name: string;
  customer_name: string;
  address_line1?: string | null;
  city?: string | null;
  state?: string | null;
  zip?: string | null;
  gps_lat?: number | null;
  gps_lng?: number | null;
  status: JobStatus;
  priority: JobPriority;
  job_type: JobType;
  bill_rate_type_name?: string | null;
  lead_user_name?: string | null;
  on_call_type?: OnCallType | null;
  warranty_end_date?: string | null;
  active_workers: number;
  total_labor_hours: number;
  total_parts_cost: number;
  open_task_count: number;
  created_at?: string | null;
}

// ── Labor Entry Types ────────────────────────────────────────────

export interface ClockInRequest {
  gps_lat?: number;
  gps_lng?: number;
}

export interface ClockOutResponseInput {
  question_id: number;
  answer_text?: string | null;
  answer_bool?: boolean | null;
}

export interface OneTimeAnswerInput {
  question_id: number;
  answer_text?: string | null;
}

export interface ClockOutRequest {
  labor_entry_id: number;
  gps_lat?: number;
  gps_lng?: number;
  drive_time_minutes?: number;
  notes?: string;
  responses: ClockOutResponseInput[];
  one_time_answers: OneTimeAnswerInput[];
}

export interface LaborEntryResponse {
  id: number;
  user_id: number;
  user_name?: string | null;
  job_id: number;
  job_name?: string | null;
  job_number?: string | null;
  clock_in: string;
  clock_out?: string | null;
  regular_hours?: number | null;
  overtime_hours?: number | null;
  drive_time_minutes: number;
  clock_in_gps_lat?: number | null;
  clock_in_gps_lng?: number | null;
  clock_out_gps_lat?: number | null;
  clock_out_gps_lng?: number | null;
  clock_in_photo_path?: string | null;
  clock_out_photo_path?: string | null;
  status: LaborStatus;
  notes?: string | null;
  created_at?: string | null;
}

export interface ActiveClockResponse {
  is_clocked_in: boolean;
  entry?: LaborEntryResponse | null;
}

// ── Clock-Out Questions ──────────────────────────────────────────

export type QuestionAnswerType = 'text' | 'yes_no' | 'photo';

export interface ClockOutQuestionResponse {
  id: number;
  question_text: string;
  answer_type: QuestionAnswerType;
  is_required: boolean;
  sort_order: number;
  is_active: boolean;
  created_at?: string | null;
}

export interface ClockOutQuestionCreate {
  question_text: string;
  answer_type?: QuestionAnswerType;
  is_required?: boolean;
  sort_order?: number;
}

// ── One-Time Questions ───────────────────────────────────────────

export type OneTimeQuestionStatus = 'pending' | 'answered' | 'expired' | 'cancelled';

export interface OneTimeQuestionResponse {
  id: number;
  job_id: number;
  target_user_id?: number | null;
  target_user_name?: string | null;
  question_text: string;
  answer_type: QuestionAnswerType;
  status: OneTimeQuestionStatus;
  created_by: number;
  created_by_name?: string | null;
  answered_by?: number | null;
  answer_text?: string | null;
  answer_photo_path?: string | null;
  created_at?: string | null;
  answered_at?: string | null;
}

export interface OneTimeQuestionCreate {
  question_text: string;
  answer_type?: QuestionAnswerType;
  target_user_id?: number | null;
}

// ── Clock-Out Bundle ─────────────────────────────────────────────

export interface ClockOutBundle {
  global_questions: ClockOutQuestionResponse[];
  one_time_questions: OneTimeQuestionResponse[];
}

// ── Job Parts ────────────────────────────────────────────────────

export interface JobPartConsumeRequest {
  part_id: number;
  qty_consumed: number;
  notes?: string;
}

export interface JobPartResponse {
  id: number;
  job_id: number;
  part_id: number;
  part_name?: string | null;
  part_code?: string | null;
  qty_consumed: number;
  qty_returned: number;
  unit_cost_at_consume?: number | null;
  unit_sell_at_consume?: number | null;
  consumed_by?: number | null;
  consumed_by_name?: string | null;
  consumed_at?: string | null;
  notes?: string | null;
}

// ── Daily Reports ────────────────────────────────────────────────

export interface DailyReportResponse {
  id: number;
  job_id: number;
  job_name?: string | null;
  job_number?: string | null;
  report_date: string;
  status: ReportStatus;
  generated_at?: string | null;
  reviewed_by?: number | null;
  reviewed_at?: string | null;
  // Summary fields extracted from report JSON
  worker_count: number;
  total_labor_hours: number;
  total_parts_cost: number;
}

export interface DailyReportFull {
  id: number;
  job_id: number;
  job_name?: string | null;
  job_number?: string | null;
  report_date: string;
  status: ReportStatus;
  generated_at?: string | null;
  report_data: ReportData;
}

// ── Report Data (the JSON blob structure) ────────────────────────

export interface ReportData {
  job_id: number;
  job_name: string;
  job_number: string;
  report_date: string;
  workers: ReportWorker[];
  parts_consumed: ReportPartConsumed[];
  deliveries?: ReportDelivery[];
  trip_legs?: ReportTripLeg[];
  vehicles_involved?: ReportVehicleInvolved[];
  summary: ReportSummary;
}

export interface ReportWorker {
  user_id: number;
  display_name: string;
  clock_in: string;
  clock_out?: string | null;
  regular_hours: number;
  overtime_hours: number;
  drive_time_minutes: number;
  clock_in_gps?: { lat: number; lng: number } | null;
  clock_out_gps?: { lat: number; lng: number } | null;
  clock_in_photo?: string | null;
  clock_out_photo?: string | null;
  responses: ReportQuestionAnswer[];
  one_time_responses: ReportOneTimeAnswer[];
}

export interface ReportQuestionAnswer {
  question: string;
  type: QuestionAnswerType;
  answer: string | boolean;
  photo?: string | null;
}

export interface ReportOneTimeAnswer {
  question: string;
  answer: string;
  photo?: string | null;
}

export interface ReportPartConsumed {
  part_name: string;
  part_code?: string | null;
  qty: number;
  unit_cost: number;
  total: number;
}

export interface ReportSummary {
  total_labor_hours: number;
  total_parts_cost: number;
  worker_count: number;
  total_delivery_items?: number;
  total_miles_driven?: number;
  total_billable_drive_minutes?: number;
  vehicles_involved_count?: number;
}

export interface ReportDelivery {
  vehicle_name: string;
  vehicle_number: string;
  part_name: string;
  part_code?: string | null;
  qty_delivered: number;
  delivered_by_name?: string | null;
  delivered_at?: string | null;
}

export interface ReportTripLeg {
  leg_type: string;
  from_label?: string | null;
  to_label?: string | null;
  miles?: number | null;
  drive_minutes?: number | null;
  is_billable: boolean;
  vehicle_name: string;
  vehicle_number: string;
  driver_name: string;
}

export interface ReportVehicleInvolved {
  vehicle_name: string;
  vehicle_number: string;
  drivers: string[];
  total_miles: number;
  delivered_items: number;
}


// ═══════════════════════════════════════════════════════════════════
// NOTEBOOKS MODULE (Phase 4.5)
// ═══════════════════════════════════════════════════════════════════

// ── Entry/Section/Task Type Unions ───────────────────────────────

export type EntryType = 'note' | 'task' | 'field';
export type FieldType = 'text' | 'checkbox' | 'textarea';
export type TaskStatus = 'planned' | 'parts_ordered' | 'parts_delivered' | 'in_progress' | 'done';
export type SectionType = 'info' | 'notes' | 'tasks';

export const TASK_STATUS_LABELS: Record<TaskStatus, string> = {
  planned: 'Planned',
  parts_ordered: 'Parts Ordered',
  parts_delivered: 'Parts Delivered',
  in_progress: 'In Progress',
  done: 'Done',
};

export const TASK_STATUS_COLORS: Record<TaskStatus, string> = {
  planned: 'gray',
  parts_ordered: 'amber',
  parts_delivered: 'blue',
  in_progress: 'sky',
  done: 'green',
};

export const TASK_STATUS_ORDER: TaskStatus[] = [
  'planned', 'parts_ordered', 'parts_delivered', 'in_progress', 'done',
];

// ── Template Types ──────────────────────────────────────────────

export interface TemplateCreate {
  name: string;
  description?: string;
  job_type?: string;
  is_default?: boolean;
}

export interface TemplateUpdate {
  name?: string;
  description?: string;
  job_type?: string;
  is_default?: boolean;
}

export interface TemplateResponse {
  id: number;
  name: string;
  description?: string | null;
  job_type?: string | null;
  is_default: boolean;
  created_by?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface TemplateEntryCreate {
  title: string;
  default_content?: string;
  entry_type?: EntryType;
  field_type?: FieldType;
  field_required?: boolean;
  sort_order?: number;
}

export interface TemplateEntryResponse {
  id: number;
  section_id: number;
  title: string;
  default_content?: string | null;
  entry_type: EntryType;
  field_type?: FieldType | null;
  field_required: boolean;
  sort_order: number;
}

export interface TemplateSectionCreate {
  name: string;
  section_type?: SectionType;
  sort_order?: number;
  is_locked?: boolean;
}

export interface TemplateSectionUpdate {
  name?: string;
  sort_order?: number;
  is_locked?: boolean;
}

export interface TemplateSectionResponse {
  id: number;
  template_id: number;
  name: string;
  section_type: SectionType;
  sort_order: number;
  is_locked: boolean;
}

export interface TemplateSectionWithEntries extends TemplateSectionResponse {
  entries: TemplateEntryResponse[];
}

export interface TemplateFull {
  id: number;
  name: string;
  description?: string | null;
  job_type?: string | null;
  is_default: boolean;
  created_by?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
  sections: TemplateSectionWithEntries[];
}

// ── Notebook Types ──────────────────────────────────────────────

export interface NotebookCreate {
  title: string;
  description?: string;
}

export interface NotebookUpdate {
  title?: string;
  description?: string;
}

export interface NotebookResponse {
  id: number;
  title: string;
  description?: string | null;
  job_id?: number | null;
  template_id?: number | null;
  created_by: number;
  creator_name?: string | null;
  is_archived: boolean;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface NotebookListItem {
  id: number;
  title: string;
  description?: string | null;
  job_id?: number | null;
  job_name?: string | null;
  job_number?: string | null;
  created_by: number;
  creator_name?: string | null;
  is_archived: boolean;
  open_task_count: number;
  total_task_count: number;
  created_at?: string | null;
  updated_at?: string | null;
}

// ── Section Types ───────────────────────────────────────────────

export interface SectionCreate {
  name: string;
  section_type?: SectionType;
}

export interface SectionUpdate {
  name?: string;
  sort_order?: number;
}

export interface SectionResponse {
  id: number;
  notebook_id: number;
  name: string;
  section_type: SectionType;
  sort_order: number;
  is_locked: boolean;
  created_at?: string | null;
}

export interface SectionReorderRequest {
  ordered_ids: number[];
}

// ── Entry Types ─────────────────────────────────────────────────

export interface EntryCreate {
  title: string;
  content?: string;
  entry_type?: EntryType;
  field_type?: FieldType;
  field_required?: boolean;
  task_status?: TaskStatus;
  task_due_date?: string;
  task_assigned_to?: number;
  task_parts_note?: string;
}

export interface EntryUpdate {
  title?: string;
  content?: string;
  task_status?: TaskStatus;
  task_due_date?: string;
  task_assigned_to?: number;
  task_parts_note?: string;
}

export interface EntryResponse {
  id: number;
  section_id: number;
  title: string;
  content?: string | null;
  entry_type: EntryType;
  field_type?: FieldType | null;
  field_required: boolean;
  field_filled_by?: number | null;
  task_status?: TaskStatus | null;
  task_due_date?: string | null;
  task_assigned_to?: number | null;
  task_assigned_to_name?: string | null;
  task_parts_note?: string | null;
  created_by: number;
  creator_name?: string | null;
  can_edit: boolean;
  sort_order: number;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface TaskStatusUpdate {
  status: TaskStatus;
  parts_note?: string;
}

export interface FieldValueUpdate {
  value: string;
}

export interface TaskAssignRequest {
  user_id: number;
}

// ── Nested Response Types ───────────────────────────────────────

export interface SectionWithEntries extends SectionResponse {
  entries: EntryResponse[];
}

export interface NotebookFull {
  notebook: NotebookResponse;
  sections: SectionWithEntries[];
}

export interface TaskSummary {
  planned: number;
  parts_ordered: number;
  parts_delivered: number;
  in_progress: number;
  done: number;
  total: number;
  open: number;
}


// ═══════════════════════════════════════════════════════════════════
// ORDERS & PROCUREMENT MODULE (Phase 5)
// ═══════════════════════════════════════════════════════════════════

// ── Status Type Unions ───────────────────────────────────────────

export type JPOStatus =
  | 'draft' | 'pending_approval' | 'approved' | 'ordering'
  | 'partially_ordered' | 'ordered' | 'partially_received'
  | 'received' | 'closed';

export type POStatus =
  | 'draft' | 'submitted' | 'acknowledged'
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
  submitted: 'Submitted',
  acknowledged: 'Acknowledged',
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

export interface JPOCreate {
  job_id: number;
  priority?: JPOPriority;
  notes?: string;
  lines: JPOLineCreate[];
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
}

export interface JPOResponse {
  id: number;
  job_id: number;
  order_number: string;
  status: JPOStatus;
  priority: JPOPriority;
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
  lines: JPOLineResponse[] | null;
}

export interface JPOListItem {
  id: number;
  job_id: number;
  order_number: string;
  status: JPOStatus;
  priority: JPOPriority;
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

// ── Maintenance Cost Summary ───────────────────────────────────────

export interface MaintenanceCostSummary {
  total_cost: number;
  total_records: number;
  per_type?: { maintenance_type_name: string; total_cost: number; record_count: number }[];
  per_vehicle?: { vehicle_name: string; vehicle_number: string; total_cost: number; record_count: number }[];
}

// ── Dashboard ──────────────────────────────────────────────────────

export interface DashboardData {
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
