/**
 * Sidebar store — manages sidebar collapse state.
 *
 * The sidebar can be:
 * - Expanded (full width with labels) on desktop
 * - Collapsed (icon-only) on desktop
 * - Hidden / overlay on mobile (toggled by hamburger menu)
 */

import { create } from 'zustand';

interface SidebarState {
  /** Whether the sidebar is collapsed (icon-only) on desktop */
  isCollapsed: boolean;
  /** Whether the mobile menu overlay is open */
  isMobileOpen: boolean;

  /** Toggle desktop collapse */
  toggleCollapse: () => void;
  /** Set desktop collapse state */
  setCollapsed: (collapsed: boolean) => void;
  /** Toggle mobile menu */
  toggleMobile: () => void;
  /** Close mobile menu */
  closeMobile: () => void;
}

export const useSidebarStore = create<SidebarState>((set) => ({
  isCollapsed: false,
  isMobileOpen: false,

  toggleCollapse: () => set((s) => ({ isCollapsed: !s.isCollapsed })),
  setCollapsed: (collapsed) => set({ isCollapsed: collapsed }),
  toggleMobile: () => set((s) => ({ isMobileOpen: !s.isMobileOpen })),
  closeMobile: () => set({ isMobileOpen: false }),
}));
