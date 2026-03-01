const CACHE = 'quire-v4';
const SHELL = [
  './', 'ward_bridge.js', 'quire.wasm', 'reader.css', 'manifest.json',
  'privacy.txt',
  'assets/fonts/literata-latin.woff2',
  'assets/fonts/literata-italic-latin.woff2',
  'assets/fonts/inter-latin.woff2',
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));
});
