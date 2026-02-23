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

// ── Brands ────────────────────────────────────────────────────────

export interface Brand {
  id: number;
  name: string;
  website: string | null;
  notes: string | null;
  is_active: boolean;
  part_count: number;
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

// ── Parts ─────────────────────────────────────────────────────────

export interface PartListItem {
  id: number;
  code: string;
  name: string;
  part_type: 'general' | 'specific';
  brand_name: string | null;
  unit_of_measure: string;
  company_cost_price: number | null;
  company_markup_percent: number | null;
  company_sell_price: number | null;
  total_stock: number;
  forecast_adu_30: number | null;
  forecast_days_until_low: number | null;
  forecast_suggested_order: number | null;
  is_deprecated: boolean;
  is_qr_tagged: boolean;
}

export interface Part extends PartListItem {
  description: string | null;
  brand_id: number | null;
  manufacturer_part_number: string | null;
  weight_lbs: number | null;
  color: string | null;
  variant: string | null;
  min_stock_level: number;
  max_stock_level: number;
  target_stock_level: number;
  warehouse_stock: number;
  truck_stock: number;
  job_stock: number;
  pulled_stock: number;
  forecast_last_run: string | null;
  deprecation_reason: string | null;
  notes: string | null;
  image_url: string | null;
  pdf_url: string | null;
  suppliers: PartSupplierLink[];
  created_at: string | null;
  updated_at: string | null;
}

export interface PartCreate {
  code: string;
  name: string;
  description?: string;
  part_type?: 'general' | 'specific';
  brand_id?: number;
  manufacturer_part_number?: string;
  unit_of_measure?: string;
  weight_lbs?: number;
  color?: string;
  variant?: string;
  company_cost_price?: number;
  company_markup_percent?: number;
  min_stock_level?: number;
  max_stock_level?: number;
  target_stock_level?: number;
  notes?: string;
}

export interface PartUpdate {
  code?: string;
  name?: string;
  description?: string;
  part_type?: 'general' | 'specific';
  brand_id?: number;
  manufacturer_part_number?: string;
  unit_of_measure?: string;
  weight_lbs?: number;
  color?: string;
  variant?: string;
  company_cost_price?: number;
  company_markup_percent?: number;
  min_stock_level?: number;
  max_stock_level?: number;
  target_stock_level?: number;
  is_deprecated?: boolean;
  deprecation_reason?: string;
  is_qr_tagged?: boolean;
  notes?: string;
}

export interface PartPricingUpdate {
  company_cost_price: number;
  company_markup_percent: number;
}

export interface PartSearchParams {
  search?: string;
  part_type?: string;
  brand_id?: number;
  is_deprecated?: boolean;
  is_qr_tagged?: boolean;
  low_stock?: boolean;
  sort_by?: string;
  sort_dir?: 'asc' | 'desc';
  page?: number;
  page_size?: number;
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
  code: string;
  name: string;
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
}

// ── Import/Export ──────────────────────────────────────────────────

export interface ImportResult {
  created: number;
  updated: number;
  errors: string[];
  total_errors: number;
}
