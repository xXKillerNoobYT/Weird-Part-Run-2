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
  template: TemplateResponse;
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
  task_status: TaskStatus;
  task_parts_note?: string;
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
