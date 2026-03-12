import path from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

/**
 * Capacitor packages only exist inside the native shell (iOS/Android).
 * During `vite dev` they aren't installed, so Vite's import-analysis plugin
 * fails on dynamic `await import("@capacitor/...")` calls — even when wrapped
 * in try/catch or gated behind `isCapacitor()`.
 *
 * We use `resolve.alias` (dev only) to redirect all Capacitor imports to a
 * stub module that throws on access — matching real Capacitor behavior outside
 * native context. The app's try/catch blocks handle the graceful degradation.
 *
 * The production build uses `rollupOptions.external` instead (below).
 */
const CAPACITOR_PACKAGES = [
  '@capacitor/core',
  '@capacitor/app',
  '@capacitor/camera',
  '@capacitor/filesystem',
  '@capacitor/geolocation',
  '@capacitor/haptics',
  '@capacitor/network',
  '@capacitor/preferences',
  '@capacitor/splash-screen',
  '@capacitor/status-bar',
  '@capacitor-community/sqlite',
  '@capacitor-community/bluetooth-le',
];

const stubFile = path.resolve(__dirname, 'src/lib/capacitor-stubs.ts');

export default defineConfig(({ command }) => ({
  plugins: [
    react(),
    tailwindcss(),
  ],
  resolve: command === 'serve'
    ? {
      alias: Object.fromEntries(
        CAPACITOR_PACKAGES.map((pkg) => [pkg, stubFile]),
      ),
    }
    : {},
  build: {
    chunkSizeWarningLimit: 600,
    rollupOptions: {
      // Capacitor plugins are only available at runtime on native devices.
      // Externalize them so the browser/PWA build succeeds without them installed.
      // bcryptjs is used only by local (Capacitor) auth service.
      external: [...CAPACITOR_PACKAGES, 'bcryptjs'],
      output: {
        manualChunks(id) {
          // ── node_modules ──
          if (id.includes('node_modules')) {
            if (id.includes('lucide-react')) return 'icons';
            // React ecosystem (react, react-dom, react-router, scheduler)
            if (
              id.includes('/react/') ||
              id.includes('/react-dom/') ||
              id.includes('/react-router') ||
              id.includes('/scheduler/')
            ) return 'react-core';
            if (id.includes('@tanstack')) return 'tanstack';
            if (id.includes('recharts') || id.includes('d3-')) return 'charts';
            return 'vendor';
          }
          // ── Feature chunks ──
          // Jobs, orders, office & reports share heavy cross-imports → single chunk
          if (
            id.includes('/features/jobs/') ||
            id.includes('/features/orders/') ||
            id.includes('/features/office/') ||
            id.includes('/features/reports/')
          ) return 'feat-workflow';
          if (id.includes('/features/parts/') || id.includes('/local/')) return 'feat-parts';
          if (id.includes('/features/trucks/')) return 'feat-trucks';
          if (id.includes('/features/scheduling/')) return 'feat-scheduling';
          if (id.includes('/features/chat/')) return 'feat-chat';
          if (id.includes('/features/settings/')) return 'feat-settings';
          if (id.includes('/features/warehouse/')) return 'feat-warehouse';
          if (id.includes('/features/people/')) return 'feat-people';
          if (id.includes('/features/tools/')) return 'feat-tools';
        },
      },
    },
  },
  server: {
    port: 5173,
    proxy: {
      // Proxy API requests to the FastAPI backend during development
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
}))
