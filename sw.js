const CACHE='dk-v1';
const ASSETS=['./','./index.html','./manifest.json'];
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS).catch(()=>{})))});
self.addEventListener('activate',e=>{e.waitUntil((async()=>{const ks=await caches.keys();await Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)));self.clients.claim()}))});
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET'||e.request.url.includes('file://'))return;
  e.respondWith(
    (async()=>{
      const cached=await caches.match(e.request,{ignoreSearch:true});
      const network=fetch(e.request,{cache:'no-store'}).then(r=>{
        if(r&&r.status===200&&e.request.url.startsWith('http')){
          const clone=r.clone();caches.open(CACHE).then(c=>c.put(e.request,clone)).catch(()=>{});
        }
        return r;
      }).catch(()=>null);
      return cached||network||caches.match('./index.html').then(r=>r||new Response('Offline',{status:503}));
    })()
  );
});
