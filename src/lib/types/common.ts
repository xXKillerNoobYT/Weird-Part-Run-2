/**
 * Common types — API response wrapper, auth, settings, navigation, pagination, status messages.
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

export interface PDFSettings {
  accent_color: string;         // Hex color for header accent bar
  show_unit_prices: boolean;    // Show unit price column in line items
  show_extended: boolean;       // Show extended/total column in line items
  footer_text: string;          // Custom footer text
  payment_terms: string;        // Default payment terms
  delivery_notes: string;       // Default delivery instructions
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
