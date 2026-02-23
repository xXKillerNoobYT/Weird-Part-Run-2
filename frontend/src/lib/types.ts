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
  // Delivery logistics
  delivery_method: DeliveryMethod;
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
  delivery_method?: DeliveryMethod;
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
  delivery_method?: DeliveryMethod;
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
  // Inventory targets
  min_stock_level: number;
  max_stock_level: number;
  target_stock_level: number;
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
