# Ward

Linear memory safety for ATS2, compiled to freestanding WASM.

## Overview

Ward provides Rust-like guarantees through dependent and linear types:

- **No buffer overflow** -- array indices are bounds-checked at compile time
- **No use-after-free** -- linear types enforce single ownership
- **No double-free** -- consuming a value twice is a type error
- **No mutable aliasing** -- freeze/thaw protocol prevents shared mutation

All proofs are erased at runtime. Zero overhead.

## Documentation

- [Getting Started](docs/getting-started.md) -- prerequisites, building, project layout
- [Concepts](docs/concepts.md) -- linear types, dependent types, borrow protocol, safe text, promises
- [API Reference](docs/api-reference.md) -- complete reference for all types and functions
- [JS Bridge](docs/bridge.md) -- `loadWard()` API, binary protocol, WASM imports/exports
- [Examples](docs/examples.md) -- arrays, borrows, DOM, promises, IDB
- [Architecture](docs/architecture.md) -- build pipeline, safety guarantees, runtime, anti-exerciser

## Quick start

```bash
# Install ATS2 (no root required)
curl -sL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-int-0.4.2.tgz" -o /tmp/ats2.tgz
mkdir -p ~/.ats2 && tar -xzf /tmp/ats2.tgz -C ~/.ats2
cd ~/.ats2/ATS2-Postiats-int-0.4.2 && make -j$(nproc) -C src/CBOOT patsopt
mkdir -p bin && cp src/CBOOT/patsopt bin/patsopt

# Install WASM toolchain
sudo apt-get install -y clang lld

# Build and verify
cd /path/to/ward
make check
```

## Vendoring

Ward is designed to be vendored into your project. There is no package registry -- you copy the source.

```bash
# Clone and vendor
git clone https://github.com/moshez/ward.git /tmp/ward
cd /tmp/ward && echo "$(git rev-parse HEAD)" > WARD_VERSION
rm -rf .git
cp -r /tmp/ward vendor/ward/

# Check in to your repo
git add vendor/ward/
git commit -m "Vendor ward $(cat vendor/ward/WARD_VERSION)"
```

To update, repeat the process and diff `WARD_VERSION`.

### Claude Code rules

Symlink the platform usage guidelines into your project's Claude Code rules so they are always active:

```bash
mkdir -p .claude/rules
ln -s ../../vendor/ward/docs/platform-usage.md .claude/rules/platform-usage.md
```

Adjust the relative path if your vendor directory is located elsewhere.

## Using Ward

### 1. Write ATS2 code

```ats
#include "share/atspre_staload.hats"
staload "vendor/ward/lib/memory.sats"
staload "vendor/ward/lib/dom.sats"
staload "vendor/ward/lib/promise.sats"
staload "vendor/ward/lib/event.sats"
staload _ = "vendor/ward/lib/memory.dats"
staload _ = "vendor/ward/lib/dom.dats"
staload _ = "vendor/ward/lib/promise.dats"
staload _ = "vendor/ward/lib/event.dats"

extern fun ward_node_init (root_id: int): void = "ext#ward_node_init"

implement ward_node_init (root_id) = let
  val dom = ward_dom_init()
  (* ... build your UI ... *)
  val () = ward_dom_fini(dom)
in end
```

### 2. Compile to WASM

```bash
# ATS2 → C
patsopt -o build/app_dats.c -d src/app.dats

# C → WASM objects (for each module)
clang --target=wasm32 -O2 -nostdlib -ffreestanding \
  -Ivendor/ward/exerciser/wasm_stubs -I$PATSHOME -I$PATSHOME/ccomp/runtime \
  -D_ATS_CCOMP_HEADER_NONE_ -D_ATS_CCOMP_EXCEPTION_NONE_ -D_ATS_CCOMP_PRELUDE_NONE_ \
  -include vendor/ward/lib/runtime.h \
  -c -o build/app_dats.o build/app_dats.c

# Link
wasm-ld --no-entry --allow-undefined \
  --export=ward_node_init --export=ward_timer_fire --export=malloc \
  -z stack-size=65536 --initial-memory=1048576 \
  -o build/app.wasm build/app_dats.o build/memory_dats.o build/dom_dats.o ...
```

### 3. Wire the JS bridge

```html
<div id="root">
  <!-- Visible while WASM loads. Your ward_node_init should start
       with ward_dom_remove_children to clear this placeholder. -->
  <p>Loading...</p>
</div>
<script type="module">
  import { loadWard } from './vendor/ward/lib/ward_bridge.mjs';

  const root = document.getElementById('root');
  const wasm = await (await fetch('app.wasm')).arrayBuffer();
  const { done } = await loadWard(wasm, root);
  await done;
</script>
```

Put a loading indicator (spinner, skeleton screen, etc.) inside `ward-root`. Since `loadWard` calls `ward_node_init` after instantiation, your init function should begin with `ward_dom_remove_children` on the root node to clear the placeholder before rendering.

See [bridge.md](docs/bridge.md) for the complete API and all WASM imports/exports.
