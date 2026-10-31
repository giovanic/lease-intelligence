import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The SPA talks to the Rails API same-origin (docs/adr/0013): in
// development Vite forwards /api to Rails, so the httpOnly session cookie
// is first-party and no CORS is needed. The Host header is preserved
// (changeOrigin: false), which is what the API's Origin check compares to.
const apiTarget = process.env.VITE_API_PROXY_TARGET ?? 'http://127.0.0.1:3000'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': { target: apiTarget, changeOrigin: false },
    },
  },
})
