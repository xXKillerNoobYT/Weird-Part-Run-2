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
      { id: 'notebook-templates', label: 'Notebook Templates', path: '/office/notebook-templates', permission: 'manage_notebooks' },
      { id: 'clock-out-questions', label: 'Clock-Out Questions', path: '/office/clock-out-questions', permission: 'manage_settings' },
      { id: 'warehouse-locations', label: 'Warehouse Locations', path: '/office/warehouse-locations', permission: 'manage_fleet' },
      { id: 'spending', label: 'Spending', path: '/office/spending', permission: 'show_dollar_values' },
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
      { id: 'receiving', label: 'Receiving', path: '/warehouse/receiving', permission: 'manage_orders' },
      { id: 'return-sorting', label: 'Return Sorting', path: '/warehouse/return-sorting', permission: 'manage_orders' },
      { id: 'staging', label: 'Pulled/Staging', path: '/warehouse/staging' },
      { id: 'audit', label: 'Audit', path: '/warehouse/audit', permission: 'perform_audit' },
      { id: 'movements', label: 'Movements Log', path: '/warehouse/movements' },
      { id: 'tools', label: 'Tools', path: '/warehouse/tools', permission: 'view_tools' },
    ],
  },
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
    ],
  },
  {
    id: 'scheduling',
    label: 'Scheduling',
    icon: 'CalendarDays',
    path: '/scheduling',
    permission: 'view_schedule',
    tabs: [
      { id: 'calendar', label: 'Calendar', path: '/scheduling/calendar' },
      { id: 'dispatch', label: 'Daily Dispatch', path: '/scheduling/dispatch', permission: 'dispatch_employees' },
      { id: 'time-off', label: 'Time Off', path: '/scheduling/time-off' },
      { id: 'schedules', label: 'Default Schedules', path: '/scheduling/schedules', permission: 'manage_schedule' },
      { id: 'subcontractors', label: 'Subcontractors', path: '/scheduling/subcontractors', permission: 'dispatch_employees' },
    ],
  },
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
  {
    id: 'orders',
    label: 'Orders',
    icon: 'ShoppingCart',
    path: '/orders',
    permission: 'view_orders',
    tabs: [
      // ── Field worker tabs (visible to everyone with view_orders) ──
      { id: 'my-orders', label: 'My Orders', path: '/orders/my-orders', group: 'My Orders' },
      { id: 'new-order', label: 'New Order', path: '/orders/new-order', group: 'My Orders' },
      { id: 'returns', label: 'Returns', path: '/orders/returns', group: 'My Orders' },
      // ── Office / management tabs (requires manage_orders) ──
      { id: 'approvals', label: 'Approvals', path: '/orders/approvals', permission: 'manage_orders', group: 'Office' },
      { id: 'all-requests', label: 'All Requests', path: '/orders/all-requests', permission: 'manage_orders', group: 'Office' },
      { id: 'review-and-send', label: 'Review & Send', path: '/orders/review-and-send', permission: 'manage_orders', group: 'Office' },
      { id: 'purchase-orders', label: 'Purchase Orders', path: '/orders/purchase-orders', permission: 'manage_orders', group: 'Office' },
      { id: 'procurement', label: 'Procurement', path: '/orders/procurement', permission: 'manage_orders', group: 'Office' },
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
      { id: 'customers', label: 'Customers', path: '/people/customers', permission: 'view_customers' },
      { id: 'contractors', label: 'Contractors', path: '/people/contractors', permission: 'view_contractors' },
      { id: 'directory', label: 'All Contacts', path: '/people/directory' },
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
      { id: 'company-profile', label: 'Company', path: '/settings/company-profile', permission: 'manage_settings' },
      { id: 'themes', label: 'Themes', path: '/settings/themes' },
      { id: 'notifications', label: 'Notifications', path: '/settings/notifications' },
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
