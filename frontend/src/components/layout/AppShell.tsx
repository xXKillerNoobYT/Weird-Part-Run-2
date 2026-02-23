/**
 * AppShell — the main application layout.
 *
 * Composes:
 * - Sidebar (left, collapsible)
 * - TopBar (top, with user info and theme toggle)
 * - TabBar (below TopBar, sub-navigation for active module)
 * - Content area (scrollable, takes remaining space)
 *
 * This component wraps all authenticated pages.
 */

import { Outlet } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { TopBar } from './TopBar';
import { TabBar } from './TabBar';

export function AppShell() {
  return (
    <div className="flex h-screen overflow-hidden bg-surface-secondary">
      {/* Sidebar */}
      <Sidebar />

      {/* Main content area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <TopBar />
        <TabBar />

        {/* Page content — scrollable */}
        <main className="flex-1 overflow-y-auto p-4 lg:p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
