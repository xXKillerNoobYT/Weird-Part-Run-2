import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
  build: {
    rollupOptions: {
      // Capacitor plugins are only available at runtime on native devices.
      // Externalize them so the browser/PWA build succeeds without them installed.
      external: [
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
      ],
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
})
