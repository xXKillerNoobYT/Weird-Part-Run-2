/**
 * Theme store — manages light/dark mode, accent color, and font family.
 *
 * Supports three modes:
 * - "light": Always light mode
 * - "dark": Always dark mode
 * - "system": Follows the OS preference via prefers-color-scheme
 *
 * The theme is applied by:
 *  1. Toggling the "dark" class on <html> for dark mode
 *  2. Setting --color-primary-* CSS custom properties on <html> for accent color
 *     (Tailwind v4 resolves primary-* classes against these variables at runtime)
 *  3. Setting --font-sans on <html> for font family
 */

import { create } from 'zustand';
import type { ThemeSettings } from '../lib/types';

// ── Color shade generator ────────────────────────────────────────────────────

function hexToHsl(hex: string): [number, number, number] {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
      case g: h = ((b - r) / d + 2) / 6; break;
      case b: h = ((r - g) / d + 4) / 6; break;
    }
  }
  return [Math.round(h * 360), Math.round(s * 100), Math.round(l * 100)];
}

function buildHsl(h: number, s: number, l: number) {
  return `hsl(${h} ${s}% ${Math.max(5, Math.min(97, l))}%)`;
}

/**
 * Generate a 50–900 primary palette from a single hex color.
 * The input is treated as shade 500; other shades are lightness-offset derivations.
 */
function generatePrimaryShades(hex: string): Record<string, string> {
  if (!hex || !hex.startsWith('#') || hex.length < 7) return {};
  try {
    const [h, s, base] = hexToHsl(hex);
    const offsets: Record<number, number> = {
      50:  base + 44,
      100: base + 36,
      200: base + 26,
      300: base + 16,
      400: base + 8,
      500: base,
      600: base - 8,
      700: base - 18,
      800: base - 28,
      900: base - 38,
    };
    return Object.fromEntries(
      Object.entries(offsets).map(([shade, l]) => [shade, buildHsl(h, s, l)])
    );
  } catch {
    return {};
  }
}

const DEFAULT_COLOR = '#3B82F6';
const DEFAULT_FONT  = 'Inter';

// ── Store ────────────────────────────────────────────────────────────────────

type ThemeMode = 'light' | 'dark' | 'system';

interface ThemeState {
  mode: ThemeMode;
  isDark: boolean;
  primaryColor: string;
  fontFamily: string;

  initialize: (settings?: ThemeSettings) => void;
  setMode: (mode: ThemeMode) => void;
  setPrimaryColor: (color: string) => void;
  setFontFamily: (font: string) => void;
  applyTheme: () => void;
}

function resolveIsDark(mode: ThemeMode): boolean {
  if (mode === 'dark') return true;
  if (mode === 'light') return false;
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
  primaryColor: DEFAULT_COLOR,
  fontFamily: DEFAULT_FONT,

  initialize: (settings?: ThemeSettings) => {
    const mode = (settings?.theme_mode ?? localStorage.getItem('wiredpart_theme') ?? 'system') as ThemeMode;
    const primaryColor = settings?.primary_color ?? DEFAULT_COLOR;
    const fontFamily = settings?.font_family ?? DEFAULT_FONT;
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

  setPrimaryColor: (color: string) => {
    set({ primaryColor: color });
    get().applyTheme();
  },

  setFontFamily: (font: string) => {
    set({ fontFamily: font });
    get().applyTheme();
  },

  applyTheme: () => {
    const { isDark, primaryColor, fontFamily } = get();
    const html = document.documentElement;

    // 1. Dark mode class
    if (isDark) {
      html.classList.add('dark');
    } else {
      html.classList.remove('dark');
    }

    // 2. Accent color — override Tailwind's --color-primary-* CSS variables
    const shades = generatePrimaryShades(primaryColor);
    Object.entries(shades).forEach(([shade, value]) => {
      html.style.setProperty(`--color-primary-${shade}`, value);
    });

    // 3. Font family
    if (fontFamily && fontFamily !== DEFAULT_FONT) {
      html.style.setProperty('--font-sans', `'${fontFamily}', ui-sans-serif, system-ui, sans-serif`);
    } else {
      html.style.removeProperty('--font-sans');
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
