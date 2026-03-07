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
  '@capacitor/geolocation',
  '@capacitor/haptics',
  '@capacitor/network',
  '@capacitor/preferences',
  '@capacitor/splash-screen',
  '@capacitor/status-bar',
  '@capacitor-community/sqlite',
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
    rollupOptions: {
      // Capacitor plugins are only available at runtime on native devices.
      // Externalize them so the browser/PWA build succeeds without them installed.
      external: CAPACITOR_PACKAGES,
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
