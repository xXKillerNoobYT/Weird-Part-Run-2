/**
 * Navigation configuration — THE single source of truth for all modules,
 * tabs, routes, icons, and permission requirements.
 *
 * Every sidebar item and tab bar item is defined here. The Sidebar and
 * TabBar components read this config and filter by the user's permissions.
 *
 * If you need to add a new page or tab, add it HERE first.
 *
 * Phase 16 restructure:
 *  - Office is now the Admin Hub — contains employee management, all reports,
 *    and scheduling admin (dispatch, templates, default schedules, subcontractors).
 *  - People = external contacts only (Customers, Contractors, Directory).
 *  - Scheduling = personal/field view only (Calendar 3-wk default, Time Off).
 *  - Reports module removed from sidebar (all tabs now live in Office).
 */

import type { NavModule } from './types';

export const MODULES: NavModule[] = [
  // ── Dashboard ────────────────────────────────────────────────────────────
  {
    id: 'dashboard',
    label: 'Dashboard',
    icon: 'LayoutDashboard',
    path: '/dashboard',
    tabs: [],
  },

  // ── Parts & Inventory ────────────────────────────────────────────────────
  {
    id: 'parts',
    label: 'Parts',
    icon: 'Package',
    path: '/parts',
    permission: 'view_parts_catalog',
    tabs: [
      { id: 'categories', label: 'Categories', path: '/parts/categories' },
      { id: 'catalog', label: 'Catalog', path: '/parts/catalog' },
      { id: 'brands', label: 'Brands', path: '/parts/brands' },
      { id: 'suppliers', label: 'Suppliers', path: '/parts/suppliers' },
      { id: 'pricing', label: 'Pricing', path: '/parts/pricing', permission: 'show_dollar_values' },
      { id: 'forecasting', label: 'Forecasting', path: '/parts/forecasting' },
      { id: 'companions', label: 'Companions', path: '/parts/companions' },
      { id: 'import-export', label: 'Import/Export', path: '/parts/import-export' },
    ],
  },

  // ── Office (Admin Hub) ───────────────────────────────────────────────────
  // The central management destination for admin and manager roles.
  // Contains: warehouse exec, job management, employee admin, all reports,
  // scheduling management (dispatch/templates/schedules/subs), and spending.
  {
    id: 'office',
    label: 'Office',
    icon: 'Building2',
    path: '/office',
    permission: 'view_people',
    tabs: [
      // ── Warehouse / Operations ──────────────────────────────────────────
      { id: 'warehouse-exec', label: 'Warehouse Executive', path: '/office/warehouse-exec', permission: 'manage_warehouse', group: 'Operations' },
      { id: 'manage-jobs', label: 'Manage Jobs', path: '/office/manage-jobs', permission: 'manage_jobs', group: 'Operations' },
      { id: 'spending', label: 'Spending', path: '/office/spending', permission: 'show_dollar_values', group: 'Operations' },
      { id: 'notebook-templates', label: 'Notebook Templates', path: '/office/notebook-templates', permission: 'manage_notebooks', group: 'Operations' },
      { id: 'clock-out-questions', label: 'Clock-Out Questions', path: '/office/clock-out-questions', permission: 'manage_settings', group: 'Operations' },
      { id: 'warehouse-locations', label: 'Warehouse Locations', path: '/office/warehouse-locations', permission: 'manage_fleet', group: 'Operations' },

      // ── People / HR ─────────────────────────────────────────────────────
      { id: 'employees', label: 'Employee List', path: '/people/employees', permission: 'view_people', group: 'People' },
      { id: 'teams', label: 'Teams', path: '/people/teams', permission: 'view_people', group: 'People' },
      { id: 'hats', label: 'Roles & Hats', path: '/people/hats', permission: 'manage_people', group: 'People' },
      { id: 'permissions', label: 'Permissions', path: '/people/permissions', permission: 'manage_people', group: 'People' },

      // ── Scheduling Admin ─────────────────────────────────────────────────
      { id: 'dispatch', label: 'Daily Dispatch', path: '/scheduling/dispatch', permission: 'dispatch_employees', group: 'Scheduling' },
      { id: 'availability', label: 'Team Availability', path: '/scheduling/availability', permission: 'view_schedule', group: 'Scheduling' },
      { id: 'templates', label: 'Dispatch Templates', path: '/scheduling/templates', permission: 'dispatch_employees', group: 'Scheduling' },
      { id: 'schedules', label: 'Default Schedules', path: '/scheduling/schedules', permission: 'manage_schedule', group: 'Scheduling' },
      { id: 'subcontractors', label: 'Subcontractors', path: '/scheduling/subcontractors', permission: 'manage_schedule', group: 'Scheduling' },

      // ── Reports ──────────────────────────────────────────────────────────
      { id: 'daily-reports', label: 'Daily Reports', path: '/reports/daily-reports', permission: 'view_reports', group: 'Reports' },
      { id: 'pre-billing', label: 'Pre-Billing', path: '/reports/pre-billing', permission: 'view_reports', group: 'Reports' },
      { id: 'timesheets', label: 'Timesheets', path: '/reports/timesheets', permission: 'view_reports', group: 'Reports' },
      { id: 'labor-overview', label: 'Labor Overview', path: '/reports/labor-overview', permission: 'view_reports', group: 'Reports' },
      { id: 'profitability', label: 'Profitability', path: '/reports/profitability', permission: 'view_reports', group: 'Reports' },
      { id: 'exports', label: 'Exports', path: '/reports/exports', permission: 'export_reports', group: 'Reports' },
    ],
  },

  // ── Warehouse ────────────────────────────────────────────────────────────
  {
    id: 'warehouse',
    label: 'Warehouse',
    icon: 'Warehouse',
    path: '/warehouse',
    permission: 'view_warehouse',
    tabs: [
      { id: 'dashboard', label: 'Dashboard', path: '/warehouse/dashboard' },
      { id: 'inventory', label: 'Inventory Grid', path: '/warehouse/inventory' },
      { id: 'receiving', label: 'Receiving', path: '/warehouse/receiving', permission: 'manage_orders' },
      { id: 'return-sorting', label: 'Return Sorting', path: '/warehouse/return-sorting', permission: 'manage_orders' },
      { id: 'staging', label: 'Pulled/Staging', path: '/warehouse/staging' },
      { id: 'audit', label: 'Audit', path: '/warehouse/audit', permission: 'perform_audit' },
      { id: 'movements', label: 'Movements Log', path: '/warehouse/movements' },
      { id: 'tools', label: 'Tools', path: '/warehouse/tools', permission: 'view_tools' },
      { id: 'network', label: 'Network', path: '/warehouse/network', permission: 'manage_warehouse' },
      { id: 'wh-settings', label: 'Settings', path: '/warehouse/settings', permission: 'manage_warehouse' },
    ],
  },

  // ── Trucks / Fleet ───────────────────────────────────────────────────────
  {
    id: 'trucks',
    label: 'Trucks',
    icon: 'Truck',
    path: '/trucks',
    permission: 'view_trucks',
    tabs: [
      { id: 'my-truck', label: 'My Vehicle', path: '/trucks/my-truck' },
      { id: 'all', label: 'All Vehicles', path: '/trucks/all' },
      { id: 'tools', label: 'Tools', path: '/trucks/tools', permission: 'view_tools' },
      { id: 'maintenance', label: 'Maintenance', path: '/trucks/maintenance' },
      { id: 'mileage', label: 'Mileage', path: '/trucks/mileage' },
      { id: 'fleet', label: 'Fleet', path: '/trucks/fleet', permission: 'manage_fleet' },
      { id: 'fuel', label: 'Fuel', path: '/trucks/fuel', permission: 'manage_fleet' },
      { id: 'inspections', label: 'Inspections', path: '/trucks/inspections' },
      { id: 'telematics', label: 'GPS', path: '/trucks/telematics', permission: 'manage_fleet' },
      { id: 'trailers', label: 'Trailers', path: '/trucks/trailers', permission: 'manage_fleet' },
      { id: 'trailer-locations', label: 'Locations', path: '/trucks/trailer-locations', permission: 'manage_fleet' },
    ],
  },

  // ── Jobs ─────────────────────────────────────────────────────────────────
  {
    id: 'jobs',
    label: 'Jobs',
    icon: 'Briefcase',
    path: '/jobs',
    permission: 'view_jobs',
    tabs: [
      { id: 'active', label: 'Active Jobs', path: '/jobs/active' },
      { id: 'my-clock', label: 'My Clock', path: '/jobs/my-clock' },
    ],
  },

  // ── Scheduling (personal / field view) ──────────────────────────────────
  // Admin scheduling (dispatch, templates, schedules, subs) has moved to Office.
  // This module is for personal use: view your schedule, request time off.
  {
    id: 'scheduling',
    label: 'Scheduling',
    icon: 'CalendarDays',
    path: '/scheduling',
    permission: 'view_schedule',
    tabs: [
      { id: 'calendar', label: 'My Schedule', path: '/scheduling/calendar' },
      { id: 'time-off', label: 'Time Off', path: '/scheduling/time-off' },
    ],
  },

  // ── Notebooks ────────────────────────────────────────────────────────────
  {
    id: 'notebooks',
    label: 'Notebooks',
    icon: 'BookOpen',
    path: '/notebooks',
    tabs: [
      { id: 'all', label: 'All', path: '/notebooks/all' },
      { id: 'job-notebooks', label: 'Job Notebooks', path: '/notebooks/job-notebooks' },
      { id: 'general', label: 'General', path: '/notebooks/general' },
    ],
  },

  // ── Chat & Q&A ──────────────────────────────────────────────────────
  {
    id: 'chat',
    label: 'Chat',
    icon: 'MessageSquare',
    path: '/chat',
    permission: 'use_chat',
    tabs: [
      { id: 'inbox', label: 'Inbox', path: '/chat/inbox' },
      { id: 'qa-board', label: 'Q&A Board', path: '/chat/qa-board', permission: 'ask_qa' },
      { id: 'rfis', label: 'RFIs', path: '/chat/rfis', permission: 'send_rfi' },
    ],
  },

  // ── Orders ───────────────────────────────────────────────────────────────
  {
    id: 'orders',
    label: 'Orders',
    icon: 'ShoppingCart',
    path: '/orders',
    permission: 'view_orders',
    tabs: [
      // Field worker tabs
      { id: 'my-orders', label: 'My Orders', path: '/orders/my-orders', group: 'My Orders' },
      { id: 'new-order', label: 'New Order', path: '/orders/new-order', group: 'My Orders' },
      { id: 'returns', label: 'Returns', path: '/orders/returns', group: 'My Orders' },
      // Office / management tabs
      { id: 'approvals', label: 'Approvals', path: '/orders/approvals', permission: 'manage_orders', group: 'Office' },
      { id: 'all-requests', label: 'All Requests', path: '/orders/all-requests', permission: 'manage_orders', group: 'Office' },
      { id: 'review-and-send', label: 'Review & Send', path: '/orders/review-and-send', permission: 'manage_orders', group: 'Office' },
      { id: 'purchase-orders', label: 'Purchase Orders', path: '/orders/purchase-orders', permission: 'manage_orders', group: 'Office' },
      { id: 'procurement', label: 'Procurement', path: '/orders/procurement', permission: 'manage_orders', group: 'Office' },
      { id: 'return-analytics', label: 'Return Analytics', path: '/orders/return-analytics', permission: 'view_orders', group: 'Office' },
    ],
  },

  // ── People (external contacts) ───────────────────────────────────────────
  // Employee management, hats, and permissions have moved to Office.
  // This module is for managing external relationships: customers, GCs, contacts.
  {
    id: 'people',
    label: 'People',
    icon: 'Users',
    path: '/people',
    permission: 'view_customers',
    tabs: [
      { id: 'customers', label: 'Customers', path: '/people/customers', permission: 'view_customers' },
      { id: 'contractors', label: 'Contractors', path: '/people/contractors', permission: 'view_contractors' },
      { id: 'directory', label: 'All Contacts', path: '/people/directory' },
    ],
  },

  // ── Settings ─────────────────────────────────────────────────────────────
  {
    id: 'settings',
    label: 'Settings',
    icon: 'Settings',
    path: '/settings',
    tabs: [
      { id: 'app-config', label: 'App Config', path: '/settings/app-config', permission: 'manage_settings' },
      { id: 'company-profile', label: 'Company', path: '/settings/company-profile', permission: 'manage_settings' },
      { id: 'pdf', label: 'PDF & Docs', path: '/settings/pdf', permission: 'manage_settings' },
      { id: 'billing-pay', label: 'Billing & Pay', path: '/settings/billing-pay', permission: 'manage_settings' },
      { id: 'themes', label: 'Themes', path: '/settings/themes' },
      { id: 'notifications', label: 'Notifications', path: '/settings/notifications' },
      { id: 'sync', label: 'Sync', path: '/settings/sync', permission: 'manage_settings' },
      { id: 'bootstrap', label: 'Bootstrap', path: '/settings/bootstrap', permission: 'manage_people' },
      { id: 'supplier-bridge', label: 'Supplier Bridge', path: '/settings/supplier-bridge', permission: 'manage_people' },
      { id: 'updates', label: 'Update Protocol', path: '/settings/updates', permission: 'manage_people' },
      { id: 'backups', label: 'Backups', path: '/settings/backups', permission: 'manage_settings' },
      { id: 'ai-config', label: 'AI Config', path: '/settings/ai-config', permission: 'manage_settings' },
      { id: 'devices', label: 'Device Management', path: '/settings/devices', permission: 'manage_devices' },
      { id: 'keys', label: 'Key Management', path: '/settings/keys', permission: 'manage_people' },
      { id: 'bluetooth', label: 'Bluetooth', path: '/settings/bluetooth', permission: 'manage_devices' },
      { id: 'security', label: 'Security', path: '/settings/security', permission: 'manage_people' },
      { id: 'remote-sync', label: 'Remote Sync', path: '/settings/remote-sync', permission: 'manage_remote_sync' },
      { id: 'shared-channels', label: 'Shared Channels', path: '/settings/shared-channels', permission: 'manage_remote_sync' },
      { id: 'about', label: 'About', path: '/settings/about' },
    ],
  },
];

/**
 * Get the default tab path for a module (first tab the user has permission for).
 */
export function getDefaultTabPath(module: NavModule, permissions: string[]): string {
  if (module.tabs.length === 0) return module.path;

  const firstAllowed = module.tabs.find(
    (tab) => !tab.permission || permissions.includes(tab.permission)
  );

  return firstAllowed?.path ?? module.path;
}

/**
 * Find which module a given path belongs to.
 *
 * Uses a two-pass strategy:
 *  1. First, check if the path matches any tab in any module (exact or prefix).
 *     This handles cross-module tabs — e.g. the Office module referencing
 *     /people/employees or /scheduling/dispatch. Tab matches are precise and
 *     take priority.
 *  2. Fallback: match by module base-path prefix (e.g. /people → People module).
 *
 * This ensures that navigating to /scheduling/dispatch from the Office tab bar
 * keeps the user in the Office context, while /scheduling/calendar (a tab
 * belonging to the Scheduling module) stays in Scheduling.
 */
export function findModuleByPath(path: string): NavModule | undefined {
  // Pass 1: exact tab-path match across all modules (first match wins)
  for (const m of MODULES) {
    for (const tab of m.tabs) {
      if (path === tab.path || path.startsWith(tab.path + '/')) {
        return m;
      }
    }
  }

  // Pass 2: module base-path prefix match
  return MODULES.find(
    (m) => path === m.path || path.startsWith(m.path + '/')
  );
}
