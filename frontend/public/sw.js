/**
 * Service Worker — Weird Parts PWA
 *
 * Strategy:
 * - Static assets (JS, CSS, HTML, fonts, icons): Cache-first with a versioned
 *   cache name. On new deployments the old cache is cleaned up.
 * - API calls (/api/*): Network-first with 5 s timeout fallback to cache.
 *   Capped at 200 entries, max 1 hour stale.
 * - Images: Cache-first, max 100 entries, 7-day expiry.
 *
 * The SW auto-updates via skipWaiting + clients.claim so users always
 * get the latest assets without a manual refresh.
 */

const CACHE_VERSION = 'v1';
const STATIC_CACHE  = `static-${CACHE_VERSION}`;
const API_CACHE     = `api-${CACHE_VERSION}`;
const IMAGE_CACHE   = `images-${CACHE_VERSION}`;

const VALID_CACHES = new Set([STATIC_CACHE, API_CACHE, IMAGE_CACHE]);

// ── Install: activate immediately ──────────────────────────
self.addEventListener('install', () => {
  self.skipWaiting();
});

// ── Activate: clean old caches + take control ──────────────
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => !VALID_CACHES.has(k))
          .map((k) => caches.delete(k)),
      ),
    ).then(() => self.clients.claim()),
  );
});

// ── Fetch strategies ───────────────────────────────────────
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Only handle same-origin GET requests
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;

  // API requests → network-first
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(networkFirst(request, API_CACHE, 5000, 200, 60 * 60));
    return;
  }

  // Images → cache-first
  if (/\.(png|jpg|jpeg|svg|gif|webp|ico)$/i.test(url.pathname)) {
    event.respondWith(cacheFirst(request, IMAGE_CACHE, 100, 7 * 24 * 60 * 60));
    return;
  }

  // Static assets (JS, CSS, HTML, fonts) → cache-first
  if (/\.(js|css|html|woff2?|ttf|eot)$/i.test(url.pathname) || url.pathname === '/') {
    event.respondWith(cacheFirst(request, STATIC_CACHE));
    return;
  }

  // SPA fallback — serve / for navigation requests
  if (request.mode === 'navigate') {
    event.respondWith(
      caches.match('/').then((cached) => cached || fetch(request)),
    );
  }
});

// ── Cache-first ────────────────────────────────────────────
async function cacheFirst(request, cacheName, maxEntries, maxAgeSec) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  if (cached && !isExpired(cached, maxAgeSec)) return cached;

  try {
    const response = await fetch(request);
    if (response.ok) {
      const clone = response.clone();
      cache.put(request, clone);
      if (maxEntries) trimCache(cacheName, maxEntries);
    }
    return response;
  } catch {
    // Offline — return cached even if stale
    return cached || new Response('Offline', { status: 503 });
  }
}

// ── Network-first with timeout ─────────────────────────────
async function networkFirst(request, cacheName, timeoutMs, maxEntries, maxAgeSec) {
  const cache = await caches.open(cacheName);

  try {
    const response = await fetchWithTimeout(request, timeoutMs);
    if (response.ok) {
      const clone = response.clone();
      cache.put(request, clone);
      if (maxEntries) trimCache(cacheName, maxEntries);
    }
    return response;
  } catch {
    const cached = await cache.match(request);
    if (cached) return cached;
    return new Response(JSON.stringify({ error: 'Offline' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

// ── Helpers ────────────────────────────────────────────────
function fetchWithTimeout(request, ms) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), ms);
    fetch(request).then(
      (res)  => { clearTimeout(timer); resolve(res); },
      (err)  => { clearTimeout(timer); reject(err); },
    );
  });
}

function isExpired(response, maxAgeSec) {
  if (!maxAgeSec) return false;
  const dateHeader = response.headers.get('date');
  if (!dateHeader) return false;
  const age = (Date.now() - new Date(dateHeader).getTime()) / 1000;
  return age > maxAgeSec;
}

async function trimCache(cacheName, max) {
  const cache = await caches.open(cacheName);
  const keys  = await cache.keys();
  if (keys.length <= max) return;
  // Delete oldest entries (first in list)
  for (let i = 0; i < keys.length - max; i++) {
    await cache.delete(keys[i]);
  }
}
