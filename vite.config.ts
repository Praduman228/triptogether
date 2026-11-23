// @lovable.dev/vite-tanstack-config already includes the following — do NOT add them manually
// or the app will break with duplicate plugins:
//   - TanStack devtools (dev-only, first), tanstackStart, viteReact, tailwindcss, tsConfigPaths,
//     nitro (build-only using cloudflare as a default target), VITE_* env injection, @ path alias,
//     React/TanStack dedupe, error logger plugins, and sandbox detection (port/host/strictPort).
// Never set ssr.external or resolve.external: the Worker has no runtime module resolution, so
// the build fails. Never add compression (compressPublicAssets, vite-plugin-compression):
// hosting already compresses at the edge.
// You can pass additional config via defineConfig({ vite: { ... }, etc... }) if needed.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  vite: {
    plugins: [VitePWA({ strategies:'generateSW', filename:'sw.js', injectRegister:null, registerType:'autoUpdate', devOptions:{enabled:false}, manifest:{name:'TripTogether',short_name:'TripTogether',description:'Shared trips. Clear balances. Developed by Praduman Kathade.',theme_color:'#147d68',background_color:'#f7f9fa',display:'standalone',start_url:'/',icons:[{src:'/icon-192.png',sizes:'192x192',type:'image/png',purpose:'any'},{src:'/icon-512.png',sizes:'512x512',type:'image/png',purpose:'any'},{src:'/icon-512.png',sizes:'512x512',type:'image/png',purpose:'maskable'},{src:'/favicon.svg',sizes:'any',type:'image/svg+xml'}]}, workbox:{globPatterns:['**/*.{js,css,png,jpg,ico,svg,woff2}'],navigateFallback:null,runtimeCaching:[{urlPattern:({request,url})=>request.mode==='navigate'&&!url.pathname.startsWith('/~oauth'),handler:'NetworkFirst',options:{cacheName:'triptogether-navigation',networkTimeoutSeconds:5,cacheableResponse:{statuses:[200]}}},{urlPattern:({url,sameOrigin})=>sameOrigin&&/\/assets\/.*-[a-zA-Z0-9_-]+\.(js|css|png|jpg|woff2)$/.test(url.pathname),handler:'CacheFirst',options:{cacheName:'triptogether-assets',expiration:{maxEntries:120}}}]}})],
  },
  tanstackStart: {
    // Redirect TanStack Start's bundled server entry to src/server.ts (our SSR error wrapper).
    // nitro/vite builds from this
    server: { entry: "server" },
  },
});
