import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

/**
 * Vite configuration for WiredPart.
 *
 * Two modes:
 * - `vite dev` (browser): proxies /api to FastAPI backend
 * - `npm run tauri dev` (Tauri): no proxy, all data is local SQLite
 *
 * Tauri sets TAURI_ENV_PLATFORM so we can detect which mode we're in.
 */
const isTauriDev = !!process.env.TAURI_ENV_PLATFORM;

export default defineConfig(() => ({
  plugins: [
    react(),
    tailwindcss(),
  ],

  build: {
    chunkSizeWarningLimit: 600,
    rollupOptions: {
      // Tauri plugins + bcryptjs are only available at runtime inside
      // the native shell. Externalize so the browser build succeeds.
      // The adapter pattern ensures these code paths are never reached
      // in browser mode (HTTP API is used instead).
      external: [
        '@tauri-apps/api',
        '@tauri-apps/plugin-sql',
        '@tauri-apps/plugin-fs',
        'bcryptjs',
      ],
      output: {
        manualChunks(id) {
          // ── node_modules ──
          if (id.includes('node_modules')) {
            if (id.includes('lucide-react')) return 'icons';
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
    proxy: isTauriDev
      ? undefined  // Tauri mode: no proxy needed (all data is local)
      : {
          // Browser mode: proxy API requests to the FastAPI backend
          '/api': {
            target: 'http://localhost:8000',
            changeOrigin: true,
          },
        },
  },

  // Tauri dev mode settings
  ...(isTauriDev ? {
    clearScreen: false,
    envPrefix: ['VITE_', 'TAURI_ENV_*'],
  } : {}),
}))
