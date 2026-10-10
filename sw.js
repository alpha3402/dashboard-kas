/* KILL-SWITCH service worker.
   Versi lama (dk-v1/dk-v2/dk-v3) memakai strategi cache-first dan "nyangkut"
   di HP, sehingga HTML lama terus disajikan walau kode sudah diperbaiki.
   SW ini: bersihkan semua cache → lepas registrasi dirinya → reload semua tab,
   supaya HP langsung mengambil HTML terbaru dari network.
   Setelah ini aplikasi TIDAK lagi meregistrasi service worker. */
self.addEventListener('install', () => { self.skipWaiting(); });

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    // 1) buang SEMUA cache
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(k => caches.delete(k)));
    } catch (err) {}

    // 2) ambil kendali semua tab yang sudah terbuka
    try { await self.clients.claim(); } catch (err) {}

    // 3) lepas registrasi service worker ini sendiri
    try { await self.registration.unregister(); } catch (err) {}

    // 4) paksa semua tab reload → ambil HTML terbaru dari network
    try {
      const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      list.forEach(c => { try { c.navigate(c.url); } catch (err) {} });
    } catch (err) {}
  })());
});
