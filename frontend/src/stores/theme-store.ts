/**
 * Theme store — manages light/dark mode and theme settings.
 *
 * Supports three modes:
 * - "light": Always light mode
 * - "dark": Always dark mode
 * - "system": Follows the OS preference via prefers-color-scheme
 *
 * The theme is applied by toggling the "dark" class on <html>.
 * This is the standard Tailwind CSS dark mode approach.
 */

import { create } from 'zustand';
import type { ThemeSettings } from '../lib/types';

type ThemeMode = 'light' | 'dark' | 'system';

interface ThemeState {
  /** Current theme mode setting */
  mode: ThemeMode;
  /** Whether dark mode is actually active (resolved from mode + system) */
  isDark: boolean;
  /** Primary accent color (hex) */
  primaryColor: string;
  /** Font family name */
  fontFamily: string;

  /** Initialize theme from backend settings or localStorage */
  initialize: (settings?: ThemeSettings) => void;
  /** Set the theme mode */
  setMode: (mode: ThemeMode) => void;
  /** Apply the resolved theme to the DOM */
  applyTheme: () => void;
}

function resolveIsDark(mode: ThemeMode): boolean {
  if (mode === 'dark') return true;
  if (mode === 'light') return false;
  // System mode — check OS preference
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

// Resolve saved mode on module load (before store creation)
const savedMode = (typeof window !== 'undefined'
  ? (localStorage.getItem('wiredpart_theme') as ThemeMode | null) ?? 'system'
  : 'system') as ThemeMode;
const initialIsDark = resolveIsDark(savedMode);

export const useThemeStore = create<ThemeState>((set, get) => ({
  mode: savedMode,
  isDark: initialIsDark,
  primaryColor: '#3B82F6',
  fontFamily: 'Inter',

  initialize: (settings?: ThemeSettings) => {
    // Try backend settings first, then localStorage, then defaults
    const mode = (settings?.theme_mode ?? localStorage.getItem('wiredpart_theme') ?? 'system') as ThemeMode;
    const primaryColor = settings?.primary_color ?? '#3B82F6';
    const fontFamily = settings?.font_family ?? 'Inter';
    const isDark = resolveIsDark(mode);

    set({ mode, isDark, primaryColor, fontFamily });
    get().applyTheme();
  },

  setMode: (mode: ThemeMode) => {
    const isDark = resolveIsDark(mode);
    localStorage.setItem('wiredpart_theme', mode);
    set({ mode, isDark });
    get().applyTheme();
  },

  applyTheme: () => {
    const { isDark } = get();
    const html = document.documentElement;

    if (isDark) {
      html.classList.add('dark');
    } else {
      html.classList.remove('dark');
    }
  },
}));

// Apply theme immediately on module load (before React renders)
if (typeof window !== 'undefined') {
  useThemeStore.getState().applyTheme();
}

// Listen for OS theme changes when in "system" mode
if (typeof window !== 'undefined') {
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    const { mode } = useThemeStore.getState();
    if (mode === 'system') {
      const isDark = resolveIsDark('system');
      useThemeStore.setState({ isDark });
      useThemeStore.getState().applyTheme();
    }
  });
}
