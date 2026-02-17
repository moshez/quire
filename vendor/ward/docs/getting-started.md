# Getting Started

## Prerequisites

- **ATS2** -- the ATS2-Postiats compiler (no root required)
- **clang + lld** -- WASM toolchain (clang with wasm32 target and wasm-ld)
- **Node.js 20+** -- for running the bridge tests and Node.js exerciser

### Install ATS2

```bash
curl -sL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-int-0.4.2.tgz" -o /tmp/ats2.tgz
mkdir -p ~/.ats2
tar -xzf /tmp/ats2.tgz -C ~/.ats2
cd ~/.ats2/ATS2-Postiats-int-0.4.2
make -j$(nproc) -C src/CBOOT patsopt
mkdir -p bin && cp src/CBOOT/patsopt bin/patsopt
```

### Install WASM toolchain

```bash
# Ubuntu/Debian
sudo apt-get install -y clang lld
```

### Install Node.js dependencies

```bash
npm install
```

## Building

```bash
make              # Build WASM + native exerciser
make check        # Build everything + run anti-exerciser
make test         # Run bridge tests (requires Node.js + npm install)
make check-all    # make check + make test
make wasm         # WASM only (build/ward.wasm)
make exerciser    # Native exerciser (builds and runs)
make anti-exerciser  # Verify unsafe code is rejected
make node-exerciser  # Node.js DOM exerciser (requires Node.js + npm)
make clean        # Remove build/
```

## Ward library layout

```
lib/                    # Core library
  memory.sats/dats      # Typed arrays, safe text, borrow protocol
  dom.sats/dats         # DOM diffing
  promise.sats/dats     # Linear promises
  event.sats/dats       # Timers, exit
  idb.sats/dats         # IndexedDB
  window.sats/dats      # Window/logging
  nav.sats/dats         # Navigation/URL
  dom_read.sats/dats    # DOM measurement/query
  listener.sats/dats    # Event listeners
  fetch.sats/dats       # Network fetch
  clipboard.sats/dats   # Clipboard
  file.sats/dats        # File I/O
  decompress.sats/dats  # Decompression
  notify.sats/dats      # Notifications/push
  runtime.h             # Freestanding WASM runtime macros
  runtime.c             # Free-list allocator + stash/resolver/listener tables
  ward_prelude.h        # Native build macros
  ward_bridge.mjs       # JS bridge (DOM protocol, data stash, event listeners)

exerciser/              # Test programs
  exerciser.dats        # Native exerciser
  wasm_exerciser.dats   # WASM exerciser
  dom_exerciser.dats    # DOM exerciser (pure safe ATS2)
  node_exerciser.mjs    # Node.js wrapper (jsdom)
  anti/                 # 17 files that must FAIL to compile

tests/                  # Bridge tests (node:test)
docs/                   # Documentation
```

---

## Building an Application with Ward

A ward application is a WASM module served as a static site. The browser-side scaffolding consists of a small set of fixed files. Most of these are ward infrastructure, not application-specific.

For coding rules and safety requirements, see `vendor/ward/docs/platform-usage.md`.

### Application project structure

```
myapp/
  index.html              # Loader page (see template below)
  loader.css              # Loading screen styles (see template below)
  manifest.json           # PWA manifest
  service-worker.js       # Offline caching
  icon-192.png            # App icon (192x192)
  icon-512.png            # App icon (512x512)
  vendor/ward/            # Ward vendored dependency
  src/                    # ATS2 application source
  e2e/                    # Playwright e2e tests
  playwright.config.js    # Playwright configuration
  Makefile                # Build system
  package.json            # Node.js dependencies (Playwright, serve)
```

### index.html

The loader page is mostly fixed infrastructure. **Only three things are application-specific**: the title, the version indicator text, and the icon. Everything else must remain exactly as shown.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MyApp</title>                              <!-- CUSTOMIZE: app title -->
  <meta name="theme-color" content="#fafaf8">
  <link rel="manifest" href="manifest.json">
  <link rel="stylesheet" href="loader.css">
  <link rel="icon" href="icon-192.png" type="image/png">
  <link rel="apple-touch-icon" href="icon-192.png">
</head>
<body>
  <div id="app">
    <div class="ward-loading">
      <div class="spinner"></div>
      <div class="app-name">MyApp</div>             <!-- CUSTOMIZE: app name -->
    </div>
  </div>
  <script type="module">
    import { loadWard } from './vendor/ward/lib/ward_bridge.mjs';
    const root = document.getElementById('app');
    const resp = await fetch('myapp.wasm');           // CUSTOMIZE: wasm filename
    const bytes = await resp.arrayBuffer();
    await loadWard(bytes, root, {
      extraImports: {
        // Application-specific bridge imports go here (if any)
      }
    });
  </script>
  <script>
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('service-worker.js');
    }
  </script>
  <div id="build-version" style="position:fixed;bottom:2px;right:4px;font-size:10px;color:#ccc;pointer-events:none">dev</div>  <!-- version stamp -->
</body>
</html>
```

**Do not modify anything else in index.html.** The `<div id="app">` with the loading spinner, the bridge import, the service worker registration, and the version stamp are all ward infrastructure. If you need to change how the app loads, that is a bug in ward.

### loader.css

The loading screen CSS is scoped to `.ward-loading` so it does NOT affect the app once WASM replaces the loading div. All app styles are injected from WASM via DOM operations -- there is no application CSS file.

```css
html, body {
  margin: 0;
  padding: 0;
  background: #fafaf8;
}
.ward-loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100vh;
  font-family: Georgia, serif;
  color: #999;
}
.ward-loading .spinner {
  width: 36px;
  height: 36px;
  border: 3px solid #e8e8e8;
  border-top-color: #4a7c59;
  border-radius: 50%;
  animation: ward-spin 0.8s linear infinite;
}
.ward-loading .app-name {
  margin-top: 1.5rem;
  font-size: 1.1rem;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  animation: ward-fade 1.2s ease-in-out infinite alternate;
}
@keyframes ward-spin {
  to { transform: rotate(360deg); }
}
@keyframes ward-fade {
  from { opacity: 0.4; }
  to { opacity: 1; }
}
```

### ward_bridge.mjs and deployment

During development, `index.html` imports ward's bridge as `./vendor/ward/lib/ward_bridge.mjs`. For deployment, the bridge must be copied and renamed to `.js` (not `.mjs`) for correct MIME type detection on static hosting servers. Some static hosts serve `.mjs` files without the `application/javascript` MIME type, which causes module loading to fail.

The `dist` target in your Makefile handles this rename and patches the import path in the copied `index.html`:

```makefile
dist: build/myapp.wasm
	@mkdir -p dist
	cp index.html dist/
	cp vendor/ward/lib/ward_bridge.mjs dist/ward_bridge.js   # .mjs -> .js for MIME
	cp loader.css dist/
	cp manifest.json dist/
	cp service-worker.js dist/
	cp build/myapp.wasm dist/
	cp icon-192.png dist/ 2>/dev/null || true
	cp icon-512.png dist/ 2>/dev/null || true
	sed -i "s|./vendor/ward/lib/ward_bridge.mjs|./ward_bridge.js|" dist/index.html
```

### service-worker.js

The service worker caches the app shell for offline use. The cache list must reference `ward_bridge.js` (the deployed `.js` name), not the vendored `.mjs` source path:

```js
const CACHE = 'myapp-v1';
const SHELL = ['./', 'ward_bridge.js', 'myapp.wasm', 'loader.css', 'manifest.json'];

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
```

For deployment, the Makefile `dist` target should stamp the cache version with the commit SHA to ensure cache invalidation on each deploy:

```makefile
COMMIT_SHA ?= dev
# In dist target, add:
	sed -i "s|myapp-v1|myapp-$(COMMIT_SHA)|" dist/service-worker.js
```

### manifest.json

Standard PWA manifest. Customize the name and icons:

```json
{
  "name": "MyApp",
  "short_name": "MyApp",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#fafaf8",
  "theme_color": "#fafaf8",
  "icons": [
    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

### Makefile

The Makefile compiles ATS2 sources to C via `patsopt`, then compiles C to WASM objects via `clang --target=wasm32`, and links them with `wasm-ld`. Ward library sources are compiled alongside application sources. Key flags:

```makefile
PATSHOME ?= $(HOME)/.ats2/ATS2-Postiats-int-0.4.2
PATSOPT  := PATSHOME=$(PATSHOME) $(PATSHOME)/bin/patsopt
WARD_DIR := vendor/ward/lib

WASM_CFLAGS := --target=wasm32 -O2 -flto -nostdlib -ffreestanding \
  -I$(WARD_DIR)/../exerciser/wasm_stubs \
  -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime \
  -D_ATS_CCOMP_HEADER_NONE_ \
  -D_ATS_CCOMP_EXCEPTION_NONE_ \
  -D_ATS_CCOMP_PRELUDE_NONE_ \
  -DWARD_NO_DOM_STUB \
  -include $(WARD_DIR)/runtime.h

WASM_LDFLAGS := --no-entry --allow-undefined --lto-O2 \
  -z stack-size=262144 --initial-memory=16777216 --max-memory=268435456
```

The three `-D` flags suppress ATS2 runtime headers that require libc. `runtime.h` provides all needed macros for freestanding mode. See ward's CLAUDE.md for the full list of WASM exports required by the bridge protocol.

### package.json

```json
{
  "type": "module",
  "devDependencies": {
    "@playwright/test": "^1.56.0",
    "serve": "^14.2.0"
  }
}
```

### Playwright e2e tests

See `vendor/ward/docs/platform-usage.md` (E2E Testing section) for the required Playwright configuration and failure response protocol.
