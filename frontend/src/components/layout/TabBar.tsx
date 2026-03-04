/**
 * TabBar — horizontal tab strip below the TopBar for sub-navigation.
 *
 * Shows the tabs for the current active module, filtered by permissions.
 * On mobile, scrolls horizontally if too many tabs.
 * Only renders if the current module has tabs.
 *
 * Supports optional `group` labels on tabs — when present, tabs are
 * visually clustered with a small group header + subtle divider so the
 * user can distinguish e.g. "Job Orders" from "Purchasing" at a glance.
 */

import { Fragment } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { cn } from '../../lib/utils';
import { findModuleByPath } from '../../lib/navigation';
import { useAuthStore } from '../../stores/auth-store';
import type { NavTab } from '../../lib/types';

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

  // Check if any tabs use groups — if so, render grouped layout
  const hasGroups = visibleTabs.some((t) => t.group);

  return (
    <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-4 lg:px-6">
      <nav className="flex gap-0.5 overflow-x-auto scrollbar-thin -mb-px items-end">
        {hasGroups
          ? renderGroupedTabs(visibleTabs, location.pathname, navigate)
          : renderFlatTabs(visibleTabs, location.pathname, navigate)}
      </nav>
    </div>
  );
}


/* ── Flat layout (default — no groups) ────────────────────────── */

function renderFlatTabs(
  tabs: NavTab[],
  pathname: string,
  navigate: (path: string) => void,
) {
  return tabs.map((tab) => (
    <TabButton key={tab.id} tab={tab} pathname={pathname} navigate={navigate} />
  ));
}


/* ── Grouped layout ───────────────────────────────────────────── */

function renderGroupedTabs(
  tabs: NavTab[],
  pathname: string,
  navigate: (path: string) => void,
) {
  // Build ordered list of unique groups (preserving order of first appearance)
  const groups: string[] = [];
  for (const tab of tabs) {
    const g = tab.group ?? '';
    if (!groups.includes(g)) groups.push(g);
  }

  return groups.map((group, gi) => {
    const groupTabs = tabs.filter((t) => (t.group ?? '') === group);

    return (
      <Fragment key={group || `ungrouped-${gi}`}>
        {/* Divider between groups — hidden on mobile where groups labels are also hidden */}
        {gi > 0 && (
          <div className="hidden sm:flex self-stretch items-center px-1">
            <div className="w-px h-6 bg-gray-200 dark:bg-gray-600" />
          </div>
        )}

        {/* Group cluster: label + tabs */}
        <div className="flex flex-col items-start">
          {/* Group label — hidden on small screens to save horizontal space */}
          {group && (
            <span className="hidden sm:block text-[10px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500 px-3 pt-1 whitespace-nowrap">
              {group}
            </span>
          )}
          {/* Tab buttons in this group */}
          <div className="flex gap-0.5">
            {groupTabs.map((tab) => (
              <TabButton key={tab.id} tab={tab} pathname={pathname} navigate={navigate} />
            ))}
          </div>
        </div>
      </Fragment>
    );
  });
}


/* ── Shared tab button ────────────────────────────────────────── */

function TabButton({
  tab,
  pathname,
  navigate,
}: {
  tab: NavTab;
  pathname: string;
  navigate: (path: string) => void;
}) {
  const isActive =
    pathname === tab.path || pathname.startsWith(tab.path + '/');

  return (
    <button
      onClick={() => navigate(tab.path)}
      className={cn(
        'px-3 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 transition-colors min-h-[44px]',
        isActive
          ? 'border-primary-500 text-primary-600 dark:text-primary-400'
          : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300',
      )}
    >
      {tab.label}
    </button>
  );
}
