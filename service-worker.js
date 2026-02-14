const CACHE = 'quire-v2';
const SHELL = ['/', '/ward_bridge.js', '/quire.wasm', '/reader.css', '/manifest.json'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
});

self.addEventListener('fetch', e => {
  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));
});
