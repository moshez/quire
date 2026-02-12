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

## Project layout

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
  anti/                 # 13 files that must FAIL to compile

tests/                  # Bridge tests (node:test)
docs/                   # Documentation
```
