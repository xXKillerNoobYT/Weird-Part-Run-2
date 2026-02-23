/**
 * Application-wide constants.
 */

/** API base URL (proxied through Vite in dev, direct in production) */
export const API_BASE_URL = '/api';

/** All permission keys used in the app. Matches backend hat_permissions. */
export const PERMISSIONS = {
  // Parts
  VIEW_PARTS_CATALOG: 'view_parts_catalog',
  EDIT_PARTS_CATALOG: 'edit_parts_catalog',
  EDIT_PRICING: 'edit_pricing',
  SHOW_DOLLAR_VALUES: 'show_dollar_values',
  MANAGE_DEPRECATION: 'manage_deprecation',

  // Warehouse
  VIEW_WAREHOUSE: 'view_warehouse',
  MANAGE_WAREHOUSE: 'manage_warehouse',
  MOVE_STOCK_WAREHOUSE: 'move_stock_warehouse',

  // Trucks
  VIEW_TRUCKS: 'view_trucks',
  MANAGE_TRUCKS: 'manage_trucks',
  MOVE_STOCK_TRUCK: 'move_stock_truck',

  // Jobs
  VIEW_JOBS: 'view_jobs',
  MANAGE_JOBS: 'manage_jobs',
  CLOCK_IN_OUT: 'clock_in_out',
  CONSUME_PARTS_ANY_JOB: 'consume_parts_any_job',

  // Labor
  VIEW_LABOR: 'view_labor',
  MANAGE_LABOR: 'manage_labor',

  // Orders
  VIEW_ORDERS: 'view_orders',
  MANAGE_ORDERS: 'manage_orders',
  APPROVE_RETURNS: 'approve_returns',

  // People
  VIEW_PEOPLE: 'view_people',
  MANAGE_PEOPLE: 'manage_people',

  // Reports
  VIEW_REPORTS: 'view_reports',
  EXPORT_REPORTS: 'export_reports',

  // System
  MANAGE_SETTINGS: 'manage_settings',
  MANAGE_DEVICES: 'manage_devices',
  MANAGE_TEMPLATES: 'manage_templates',
  PERFORM_AUDIT: 'perform_audit',
  MANAGER_OVERRIDE: 'manager_override',
  VIEW_ACTIVITY_LOG: 'view_activity_log',
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

/** Severity levels for notifications and alerts. */
export const SEVERITY = {
  INFO: 'info',
  WARNING: 'warning',
  ERROR: 'error',
  CRITICAL: 'critical',
} as const;
