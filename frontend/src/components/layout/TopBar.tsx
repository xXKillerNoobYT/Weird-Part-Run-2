/**
 * TopBar — horizontal header bar above the content area.
 *
 * Shows:
 * - Hamburger menu (mobile only)
 * - Current module title
 * - Search (future)
 * - Theme toggle
 * - Notification bell (future)
 * - User avatar/name
 */

import { useLocation } from 'react-router-dom';
import { Menu, Moon, Sun, Monitor, Bell, LogOut } from 'lucide-react';
import { cn } from '../../lib/utils';
import { findModuleByPath } from '../../lib/navigation';
import { useAuthStore } from '../../stores/auth-store';
import { useSidebarStore } from '../../stores/sidebar-store';
import { useThemeStore } from '../../stores/theme-store';

export function TopBar() {
  const location = useLocation();
  const { user, logout } = useAuthStore();
  const { toggleMobile } = useSidebarStore();
  const { mode, setMode } = useThemeStore();

  const currentModule = findModuleByPath(location.pathname);
  const title = currentModule?.label ?? 'Dashboard';

  const cycleTheme = () => {
    const next = mode === 'light' ? 'dark' : mode === 'dark' ? 'system' : 'light';
    setMode(next);
  };

  const ThemeIcon = mode === 'dark' ? Moon : mode === 'light' ? Sun : Monitor;

  return (
    <header className="h-16 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between px-4 lg:px-6">
      {/* Left: Hamburger + Title */}
      <div className="flex items-center gap-3">
        <button
          onClick={toggleMobile}
          className="lg:hidden p-2 rounded-lg text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700"
        >
          <Menu className="h-5 w-5" />
        </button>
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          {title}
        </h1>
      </div>

      {/* Right: Actions */}
      <div className="flex items-center gap-2">
        {/* Theme toggle */}
        <button
          onClick={cycleTheme}
          title={`Theme: ${mode}`}
          className="p-2 rounded-lg text-gray-500 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700 transition-colors"
        >
          <ThemeIcon className="h-5 w-5" />
        </button>

        {/* Notification bell (stub) */}
        <button
          className="p-2 rounded-lg text-gray-500 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700 transition-colors relative"
          title="Notifications"
        >
          <Bell className="h-5 w-5" />
        </button>

        {/* User info */}
        {user && (
          <div className="flex items-center gap-2 ml-2 pl-2 border-l border-gray-200 dark:border-gray-700">
            <div className={cn(
              'w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium',
              'bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300',
            )}>
              {user.display_name.charAt(0).toUpperCase()}
            </div>
            <span className="hidden md:block text-sm font-medium text-gray-700 dark:text-gray-300">
              {user.display_name}
            </span>
            <button
              onClick={logout}
              title="Sign out"
              className="p-1.5 rounded-lg text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
            >
              <LogOut className="h-4 w-4" />
            </button>
          </div>
        )}
      </div>
    </header>
  );
}
