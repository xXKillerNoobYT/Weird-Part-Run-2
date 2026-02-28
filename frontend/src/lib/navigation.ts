/**
 * Navigation configuration — THE single source of truth for all modules,
 * tabs, routes, icons, and permission requirements.
 *
 * Every sidebar item and tab bar item is defined here. The Sidebar and
 * TabBar components read this config and filter by the user's permissions.
 *
 * If you need to add a new page or tab, add it HERE first.
 */

import type { NavModule } from './types';

export const MODULES: NavModule[] = [
  {
    id: 'dashboard',
    label: 'Dashboard',
    icon: 'LayoutDashboard',
    path: '/dashboard',
    tabs: [],  // Dashboard has no sub-tabs
  },
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
  {
    id: 'office',
    label: 'Office',
    icon: 'Building2',
    path: '/office',
    permission: 'view_warehouse',
    tabs: [
      { id: 'warehouse-exec', label: 'Warehouse Executive', path: '/office/warehouse-exec', permission: 'manage_warehouse' },
      { id: 'manage-jobs', label: 'Manage Jobs', path: '/office/manage-jobs', permission: 'manage_jobs' },
      { id: 'clock-out-questions', label: 'Clock-Out Questions', path: '/office/clock-out-questions', permission: 'manage_settings' },
    ],
  },
  {
    id: 'warehouse',
    label: 'Warehouse',
    icon: 'Warehouse',
    path: '/warehouse',
    permission: 'view_warehouse',
    tabs: [
      { id: 'dashboard', label: 'Dashboard', path: '/warehouse/dashboard' },
      { id: 'inventory', label: 'Inventory Grid', path: '/warehouse/inventory' },
      { id: 'staging', label: 'Pulled/Staging', path: '/warehouse/staging' },
      { id: 'audit', label: 'Audit', path: '/warehouse/audit', permission: 'perform_audit' },
      { id: 'movements', label: 'Movements Log', path: '/warehouse/movements' },
      { id: 'tools', label: 'Tools', path: '/warehouse/tools' },
    ],
  },
  {
    id: 'trucks',
    label: 'Trucks',
    icon: 'Truck',
    path: '/trucks',
    permission: 'view_trucks',
    tabs: [
      { id: 'my-truck', label: 'My Truck', path: '/trucks/my-truck' },
      { id: 'all', label: 'All Trucks', path: '/trucks/all' },
      { id: 'tools', label: 'Tools', path: '/trucks/tools' },
      { id: 'maintenance', label: 'Maintenance', path: '/trucks/maintenance' },
      { id: 'mileage', label: 'Mileage', path: '/trucks/mileage' },
    ],
  },
  {
    id: 'jobs',
    label: 'Jobs',
    icon: 'Briefcase',
    path: '/jobs',
    permission: 'view_jobs',
    tabs: [
      { id: 'active', label: 'Active Jobs', path: '/jobs/active' },
      { id: 'my-clock', label: 'My Clock', path: '/jobs/my-clock' },
      { id: 'templates', label: 'Templates', path: '/jobs/templates', permission: 'manage_templates' },
    ],
  },
  {
    id: 'orders',
    label: 'Orders',
    icon: 'ShoppingCart',
    path: '/orders',
    permission: 'view_orders',
    tabs: [
      { id: 'drafts', label: 'Draft POs', path: '/orders/drafts' },
      { id: 'pending', label: 'Pending', path: '/orders/pending' },
      { id: 'incoming', label: 'Incoming', path: '/orders/incoming' },
      { id: 'returns', label: 'Returns', path: '/orders/returns', permission: 'approve_returns' },
      { id: 'procurement', label: 'Procurement Planner', path: '/orders/procurement', permission: 'manage_orders' },
    ],
  },
  {
    id: 'people',
    label: 'People',
    icon: 'Users',
    path: '/people',
    permission: 'view_people',
    tabs: [
      { id: 'employees', label: 'Employee List', path: '/people/employees' },
      { id: 'hats', label: 'Roles/Hats', path: '/people/hats', permission: 'manage_people' },
      { id: 'permissions', label: 'Permissions', path: '/people/permissions', permission: 'manage_people' },
    ],
  },
  {
    id: 'reports',
    label: 'Reports',
    icon: 'BarChart3',
    path: '/reports',
    permission: 'view_reports',
    tabs: [
      { id: 'daily-reports', label: 'Daily Reports', path: '/reports/daily-reports' },
      { id: 'pre-billing', label: 'Pre-Billing', path: '/reports/pre-billing' },
      { id: 'timesheets', label: 'Timesheets', path: '/reports/timesheets' },
      { id: 'labor-overview', label: 'Labor Overview', path: '/reports/labor-overview' },
      { id: 'exports', label: 'Exports', path: '/reports/exports', permission: 'export_reports' },
    ],
  },
  {
    id: 'settings',
    label: 'Settings',
    icon: 'Settings',
    path: '/settings',
    tabs: [
      { id: 'app-config', label: 'App Config', path: '/settings/app-config', permission: 'manage_settings' },
      { id: 'themes', label: 'Themes', path: '/settings/themes' },
      { id: 'sync', label: 'Sync', path: '/settings/sync', permission: 'manage_settings' },
      { id: 'ai-config', label: 'AI Config', path: '/settings/ai-config', permission: 'manage_settings' },
      { id: 'devices', label: 'Device Management', path: '/settings/devices', permission: 'manage_devices' },
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
 */
export function findModuleByPath(path: string): NavModule | undefined {
  return MODULES.find(
    (m) => path === m.path || path.startsWith(m.path + '/')
  );
}
