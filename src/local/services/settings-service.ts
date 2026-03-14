/**
 * Local Settings Service — theme, app configuration, company profiles, billing/pay cycles.
 *
 * Mirrors the HTTP API in api/settings.ts for offline Tauri use.
 * Settings are stored as key-value rows; compound settings (theme, pdf, billing)
 * use a shared category with one row per field.
 *
 * Source tables: migration 001_foundation (settings, company_profiles)
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';
import type {
  ThemeSettings,
  PDFSettings,
  CompanyProfile,
  CompanyProfileCreate,
  CompanyProfileUpdate,
} from '../../lib/types';
import type {
  BillingCycleSettings,
  PayPeriodSettings,
  PayrollColumnConfig,
} from '../../api/settings';

// ── Repos ──────────────────────────────────────────────────────────

const profileRepo = new BaseRepo('company_profiles');

// ── Helpers ────────────────────────────────────────────────────────

/** Read a single setting value by key. Returns null when not found. */
async function getSettingValue(key: string): Promise<string | null> {
  const db = await getDb();
  const result = await db.query('SELECT value FROM settings WHERE key = ?', [key]);
  return result.values[0]?.value ?? null;
}

/** Insert-or-update a setting row, tracked for sync. */
async function upsertSetting(key: string, value: string, category: string = 'general'): Promise<void> {
  const db = await getDb();
  await db.run(
    `INSERT INTO settings (key, value, category, updated_at)
     VALUES (?, ?, ?, datetime('now'))
     ON CONFLICT(key) DO UPDATE SET value = ?, category = ?, updated_at = datetime('now')`,
    [key, value, category, value, category],
  );
}

/** Read all setting rows for a category and return as a key→value map. */
async function getSettingsByCategory(category: string): Promise<Record<string, string>> {
  const db = await getDb();
  const result = await db.query(
    'SELECT key, value FROM settings WHERE category = ?',
    [category],
  );
  const map: Record<string, string> = {};
  for (const row of result.values) {
    map[row.key] = row.value;
  }
  return map;
}

/** Bulk upsert an object of key→value pairs under one category. */
async function upsertSettingsMap(data: Record<string, unknown>, category: string): Promise<void> {
  for (const [key, val] of Object.entries(data)) {
    if (val !== undefined) {
      await upsertSetting(key, String(val), category);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// THEME
// ═══════════════════════════════════════════════════════════════════

const THEME_DEFAULTS: ThemeSettings = {
  theme_mode: 'system',
  primary_color: '#2563eb',
  font_family: 'Inter',
};

/** Get current theme settings, filling in defaults for any missing keys. */
export async function getTheme(): Promise<ThemeSettings> {
  const map = await getSettingsByCategory('theme');
  return {
    theme_mode: (map.theme_mode as ThemeSettings['theme_mode']) ?? THEME_DEFAULTS.theme_mode,
    primary_color: map.primary_color ?? THEME_DEFAULTS.primary_color,
    font_family: map.font_family ?? THEME_DEFAULTS.font_family,
  };
}

/** Update theme settings (partial or full). */
export async function updateTheme(theme: ThemeSettings): Promise<ThemeSettings> {
  await upsertSettingsMap(theme as unknown as Record<string, unknown>, 'theme');
  return getTheme();
}

// ═══════════════════════════════════════════════════════════════════
// GENERIC SETTINGS
// ═══════════════════════════════════════════════════════════════════

/** Get all settings grouped by category. */
export async function getAllSettings(): Promise<Record<string, unknown>> {
  const db = await getDb();
  const result = await db.query('SELECT key, value, category FROM settings ORDER BY category, key');
  const grouped: Record<string, Record<string, string>> = {};
  for (const row of result.values) {
    const cat = row.category ?? 'general';
    if (!grouped[cat]) grouped[cat] = {};
    grouped[cat][row.key] = row.value;
  }
  return grouped;
}

/** Get a single setting value by key. Returns null if not found. */
export async function getSetting(key: string): Promise<string | null> {
  return getSettingValue(key);
}

/** Upsert a single setting by key. */
export async function updateSetting(key: string, value: string, category: string = 'general'): Promise<void> {
  await upsertSetting(key, value, category);
}

// ═══════════════════════════════════════════════════════════════════
// WARRANTY
// ═══════════════════════════════════════════════════════════════════

/** Get default warranty length in days. Falls back to 365. */
export async function getWarrantyLengthDays(): Promise<number> {
  const val = await getSettingValue('warranty_length_days');
  return val ? parseInt(val, 10) : 365;
}

/** Update default warranty length in days. */
export async function updateWarrantyLengthDays(days: number): Promise<void> {
  await upsertSetting('warranty_length_days', String(days), 'general');
}

// ═══════════════════════════════════════════════════════════════════
// COMPANY PROFILES
// ═══════════════════════════════════════════════════════════════════

/** List all company profiles (excludes soft-deleted). */
export async function listCompanyProfiles(): Promise<CompanyProfile[]> {
  return profileRepo.findAll('deleted_at IS NULL', [], 'name ASC') as Promise<CompanyProfile[]>;
}

/** Get a single company profile by ID. */
export async function getCompanyProfile(id: number): Promise<CompanyProfile> {
  const row = await profileRepo.getById(id);
  if (!row) throw new Error(`Company profile ${id} not found`);
  return row as unknown as CompanyProfile;
}

/** Create a new company profile. Returns `{ id }`. */
export async function createCompanyProfile(profile: CompanyProfileCreate): Promise<{ id: number }> {
  const now = new Date().toISOString();
  const id = await profileRepo.insert({
    name: profile.name,
    address_street: profile.address_street ?? null,
    address_city: profile.address_city ?? null,
    address_state: profile.address_state ?? null,
    address_zip: profile.address_zip ?? null,
    phone: profile.phone ?? null,
    email: profile.email ?? null,
    website: profile.website ?? null,
    contractor_license: profile.contractor_license ?? null,
    insurance_info: profile.insurance_info ?? null,
    tax_id: profile.tax_id ?? null,
    is_primary: profile.is_primary ? 1 : 0,
    branch_name: profile.branch_name ?? null,
    notes: profile.notes ?? null,
    created_at: now,
    updated_at: now,
  });
  return { id };
}

/** Update an existing company profile. */
export async function updateCompanyProfile(
  id: number,
  updates: CompanyProfileUpdate,
): Promise<{ status: string }> {
  const data: Record<string, unknown> = { updated_at: new Date().toISOString() };
  for (const [key, val] of Object.entries(updates)) {
    if (val !== undefined) {
      data[key] = key === 'is_primary' ? (val ? 1 : 0) : val;
    }
  }
  await profileRepo.update(id, data);
  return { status: 'ok' };
}

/** Soft-delete a company profile. */
export async function deleteCompanyProfile(id: number): Promise<{ status: string }> {
  await profileRepo.update(id, { deleted_at: new Date().toISOString() });
  return { status: 'ok' };
}

// ═══════════════════════════════════════════════════════════════════
// PDF SETTINGS
// ═══════════════════════════════════════════════════════════════════

const PDF_DEFAULTS: PDFSettings = {
  accent_color: '#2563eb',
  show_unit_prices: true,
  show_extended: true,
  footer_text: '',
  payment_terms: 'Net 30',
  delivery_notes: '',
};

/** Get PDF template/document settings. */
export async function getPDFSettings(): Promise<PDFSettings> {
  const map = await getSettingsByCategory('pdf');
  return {
    accent_color: map.accent_color ?? PDF_DEFAULTS.accent_color,
    show_unit_prices: map.show_unit_prices !== undefined ? map.show_unit_prices === 'true' : PDF_DEFAULTS.show_unit_prices,
    show_extended: map.show_extended !== undefined ? map.show_extended === 'true' : PDF_DEFAULTS.show_extended,
    footer_text: map.footer_text ?? PDF_DEFAULTS.footer_text,
    payment_terms: map.payment_terms ?? PDF_DEFAULTS.payment_terms,
    delivery_notes: map.delivery_notes ?? PDF_DEFAULTS.delivery_notes,
  };
}

/** Update PDF template/document settings. */
export async function updatePDFSettings(settings: PDFSettings): Promise<PDFSettings> {
  await upsertSettingsMap(settings as unknown as Record<string, unknown>, 'pdf');
  return getPDFSettings();
}

// ═══════════════════════════════════════════════════════════════════
// COMPANY LOGO
// ═══════════════════════════════════════════════════════════════════

/**
 * Store a company logo path. In local/native mode we just persist the
 * file path in a setting rather than uploading to a server.
 */
export async function uploadCompanyLogo(
  filePath: string,
): Promise<{ logo_path: string; filename: string }> {
  await upsertSetting('company_logo_path', filePath, 'general');
  const filename = filePath.split('/').pop() ?? filePath.split('\\').pop() ?? 'logo';
  return { logo_path: filePath, filename };
}

// ═══════════════════════════════════════════════════════════════════
// BILLING CYCLE & PAY PERIOD
// ═══════════════════════════════════════════════════════════════════

/** Get billing cycle configuration. */
export async function getBillingCycle(): Promise<BillingCycleSettings> {
  const map = await getSettingsByCategory('billing_cycle');
  return {
    cycle_type: map.cycle_type ?? 'monthly',
    start_day: map.start_day ? parseInt(map.start_day, 10) : 1,
  };
}

/** Update billing cycle configuration. */
export async function updateBillingCycle(settings: BillingCycleSettings): Promise<BillingCycleSettings> {
  await upsertSettingsMap(settings as unknown as Record<string, unknown>, 'billing_cycle');
  return getBillingCycle();
}

/** Get pay period configuration. */
export async function getPayPeriod(): Promise<PayPeriodSettings> {
  const map = await getSettingsByCategory('pay_period');
  return {
    period_type: map.period_type ?? 'biweekly',
    start_day: map.start_day ? parseInt(map.start_day, 10) : 1,
  };
}

/** Update pay period configuration. */
export async function updatePayPeriod(settings: PayPeriodSettings): Promise<PayPeriodSettings> {
  await upsertSettingsMap(settings as unknown as Record<string, unknown>, 'pay_period');
  return getPayPeriod();
}

// ═══════════════════════════════════════════════════════════════════
// PAYROLL COLUMNS
// ═══════════════════════════════════════════════════════════════════

/** Get customizable payroll export column configuration. */
export async function getPayrollColumns(): Promise<PayrollColumnConfig> {
  const val = await getSettingValue('payroll_columns');
  if (val) {
    try {
      return JSON.parse(val) as PayrollColumnConfig;
    } catch {
      // Corrupted JSON — return default
    }
  }
  return { columns: [] };
}

/** Update payroll export column configuration. */
export async function updatePayrollColumns(config: PayrollColumnConfig): Promise<PayrollColumnConfig> {
  await upsertSetting('payroll_columns', JSON.stringify(config), 'payroll');
  return config;
}
