/* Dashboard Kas & Kegiatan — service worker
   Strategi:
   - HTML/JSON   → NETWORK-FIRST (selalu ambil versi terbaru, fallback cache saat offline)
   - aset statis → CACHE-FIRST (cepat, jarang berubah)
   Bump CACHE version tiap deploy penting supaya cache lama dibuang. */
const CACHE = 'dk-v3';
const ASSETS = ['./', './index.html', './manifest.json', './icon-180.png', './icon-512.png'];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(ASSETS).catch(() => {}))
  );
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Jangan ganggu request ke API backend (tunnel) — biarkan langsung ke network
  if (url.hostname.endsWith('trycloudflare.com') ||
      url.hostname.endsWith('loca.lt') ||
      url.port === '8000') return;

  const isHTML = req.mode === 'navigate' ||
                 (req.headers.get('accept') || '').includes('text/html');
  const isJSON = url.pathname.endsWith('.json');

  // NETWORK-FIRST: HTML & JSON (update langsung kelihatan)
  if (isHTML || isJSON) {
    e.respondWith((async () => {
      try {
        const fresh = await fetch(req, { cache: 'no-store' });
        if (fresh && fresh.status === 200) {
          const clone = fresh.clone();
          caches.open(CACHE).then(c => c.put(req, clone)).catch(() => {});
        }
        return fresh;
      } catch (err) {
        const cached = await caches.match(req, { ignoreSearch: true });
        if (cached) return cached;
        const shell = await caches.match('./index.html');
        return shell || new Response('Offline', { status: 503, headers: { 'Content-Type': 'text/plain' } });
      }
    })());
    return;
  }

  // CACHE-FIRST: aset statis
  e.respondWith((async () => {
    const cached = await caches.match(req, { ignoreSearch: true });
    if (cached) return cached;
    try {
      const fresh = await fetch(req);
      if (fresh && fresh.status === 200 && url.origin === self.location.origin) {
        const clone = fresh.clone();
        caches.open(CACHE).then(c => c.put(req, clone)).catch(() => {});
      }
      return fresh;
    } catch (err) {
      return new Response('Offline', { status: 503 });
    }
  })());
});
