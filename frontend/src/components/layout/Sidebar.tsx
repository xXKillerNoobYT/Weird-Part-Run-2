/**
 * Sidebar — left navigation panel with module icons and labels.
 *
 * Features:
 * - 9 module items, each filtered by user permissions
 * - Collapsible (icon-only) on desktop
 * - Overlay drawer on mobile (toggled via hamburger)
 * - Active module highlighted
 * - Smooth collapse/expand animation
 */

import { useLocation, useNavigate } from 'react-router-dom';
import {
  LayoutDashboard, Package, Warehouse, Truck, Briefcase,
  ShoppingCart, Users, BarChart3, Settings, ChevronLeft, X, Zap,
} from 'lucide-react';
import { cn } from '../../lib/utils';
import { MODULES, getDefaultTabPath } from '../../lib/navigation';
import { useAuthStore } from '../../stores/auth-store';
import { useSidebarStore } from '../../stores/sidebar-store';

/** Map icon names to Lucide components */
const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  LayoutDashboard,
  Package,
  Warehouse,
  Truck,
  Briefcase,
  ShoppingCart,
  Users,
  BarChart3,
  Settings,
};

export function Sidebar() {
  const location = useLocation();
  const navigate = useNavigate();
  const { user } = useAuthStore();
  const { isCollapsed, isMobileOpen, toggleCollapse, closeMobile } = useSidebarStore();

  const permissions = user?.permissions ?? [];

  // Filter modules by user permissions
  const visibleModules = MODULES.filter(
    (m) => !m.permission || permissions.includes(m.permission),
  );

  const handleModuleClick = (module: typeof MODULES[0]) => {
    const targetPath = getDefaultTabPath(module, permissions);
    navigate(targetPath);
    closeMobile();
  };

  const isActive = (modulePath: string) =>
    location.pathname === modulePath ||
    location.pathname.startsWith(modulePath + '/');

  const sidebarContent = (
    <>
      {/* Logo / Brand */}
      <div className={cn(
        'flex items-center gap-3 px-4 h-16 border-b border-gray-200 dark:border-gray-700',
        isCollapsed && 'justify-center px-2',
      )}>
        <div className="flex items-center justify-center w-8 h-8 rounded-lg bg-primary-500 text-white">
          <Zap className="h-5 w-5" />
        </div>
        {!isCollapsed && (
          <span className="font-semibold text-gray-900 dark:text-gray-100 whitespace-nowrap">
            Wired-Part
          </span>
        )}
      </div>

      {/* Module List */}
      <nav className="flex-1 py-3 px-2 space-y-1 overflow-y-auto scrollbar-thin">
        {visibleModules.map((module) => {
          const Icon = iconMap[module.icon] ?? LayoutDashboard;
          const active = isActive(module.path);

          return (
            <button
              key={module.id}
              onClick={() => handleModuleClick(module)}
              title={isCollapsed ? module.label : undefined}
              className={cn(
                'flex items-center gap-3 w-full rounded-lg px-3 py-2.5 text-sm font-medium',
                'transition-colors duration-150',
                active
                  ? 'bg-primary-50 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300'
                  : 'text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800',
                isCollapsed && 'justify-center px-2',
              )}
            >
              <Icon className={cn('h-5 w-5 shrink-0', active && 'text-primary-500')} />
              {!isCollapsed && <span className="truncate">{module.label}</span>}
            </button>
          );
        })}
      </nav>

      {/* Collapse Toggle (desktop only) */}
      <div className="hidden lg:flex items-center justify-center py-3 border-t border-gray-200 dark:border-gray-700">
        <button
          onClick={toggleCollapse}
          className="p-2 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:text-gray-300 dark:hover:bg-gray-800 transition-colors"
          title={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          <ChevronLeft className={cn(
            'h-5 w-5 transition-transform duration-200',
            isCollapsed && 'rotate-180',
          )} />
        </button>
      </div>
    </>
  );

  return (
    <>
      {/* Desktop Sidebar */}
      <aside
        className={cn(
          'hidden lg:flex flex-col h-screen bg-sidebar border-r border-gray-200 dark:border-gray-700',
          'transition-[width] duration-200 ease-in-out',
          isCollapsed ? 'w-16' : 'w-60',
        )}
      >
        {sidebarContent}
      </aside>

      {/* Mobile Overlay */}
      {isMobileOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          {/* Backdrop */}
          <div
            className="absolute inset-0 bg-black/50"
            onClick={closeMobile}
          />
          {/* Drawer */}
          <aside className="absolute inset-y-0 left-0 w-72 bg-sidebar border-r border-gray-200 dark:border-gray-700 flex flex-col shadow-xl">
            {/* Close button */}
            <button
              onClick={closeMobile}
              className="absolute top-4 right-4 p-1 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:text-gray-300 dark:hover:bg-gray-700 z-10"
            >
              <X className="h-5 w-5" />
            </button>
            {sidebarContent}
          </aside>
        </div>
      )}
    </>
  );
}
