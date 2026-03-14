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
import { OfflineBanner } from '../ui/OfflineBanner';
import { CommandPalette } from '../ui/CommandPalette';
import { InstallPrompt } from '../ui/InstallPrompt';
import { useKeyboardShortcuts } from '../../lib/useKeyboardShortcuts';

export function AppShell() {
  const { isPaletteOpen, setIsPaletteOpen } = useKeyboardShortcuts();

  return (
    <div
      className="flex overflow-hidden bg-surface-secondary"
      style={{
        height: 'calc(100vh - var(--dev-overlay-h, 0px))',
        paddingTop: 'var(--safe-top)',
        paddingRight: 'var(--safe-right)',
        paddingLeft: 'var(--safe-left)',
      }}
    >
      {/* Sidebar — hidden when printing, h-full so sidebar inherits shell height */}
      <div className="no-print h-full">
        <Sidebar />
      </div>

      {/* Main content area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <div className="no-print">
          <TopBar />
          <TabBar />
        </div>

        {/* Offline indicator — above content, below nav */}
        <OfflineBanner />

        {/* Page content — scrollable, bottom safe area for home indicator */}
        <main
          className="flex-1 overflow-y-auto p-4 lg:p-6"
          style={{ paddingBottom: 'calc(1rem + var(--safe-bottom))' }}
        >
          <Outlet />
        </main>
      </div>

      {/* Command palette (Ctrl+K) */}
      <CommandPalette open={isPaletteOpen} onOpenChange={setIsPaletteOpen} />

      {/* PWA install prompt */}
      <InstallPrompt />
    </div>
  );
}
