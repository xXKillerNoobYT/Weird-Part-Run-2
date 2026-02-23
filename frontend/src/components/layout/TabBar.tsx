/**
 * TabBar — horizontal tab strip below the TopBar for sub-navigation.
 *
 * Shows the tabs for the current active module, filtered by permissions.
 * On mobile, scrolls horizontally if too many tabs.
 * Only renders if the current module has tabs.
 */

import { useLocation, useNavigate } from 'react-router-dom';
import { cn } from '../../lib/utils';
import { findModuleByPath } from '../../lib/navigation';
import { useAuthStore } from '../../stores/auth-store';

export function TabBar() {
  const location = useLocation();
  const navigate = useNavigate();
  const { user } = useAuthStore();

  const permissions = user?.permissions ?? [];
  const currentModule = findModuleByPath(location.pathname);

  // Don't render if no module found or module has no tabs
  if (!currentModule || currentModule.tabs.length === 0) return null;

  // Filter tabs by permissions
  const visibleTabs = currentModule.tabs.filter(
    (tab) => !tab.permission || permissions.includes(tab.permission),
  );

  if (visibleTabs.length === 0) return null;

  return (
    <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-4 lg:px-6">
      <nav className="flex gap-1 overflow-x-auto scrollbar-thin -mb-px">
        {visibleTabs.map((tab) => {
          const isActive =
            location.pathname === tab.path ||
            location.pathname.startsWith(tab.path + '/');

          return (
            <button
              key={tab.id}
              onClick={() => navigate(tab.path)}
              className={cn(
                'px-4 py-3 text-sm font-medium whitespace-nowrap border-b-2 transition-colors',
                isActive
                  ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300',
              )}
            >
              {tab.label}
            </button>
          );
        })}
      </nav>
    </div>
  );
}
