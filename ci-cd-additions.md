# CI/CD Additions to Quire Design Document

These are additions to the design document. Three things change: §6 gets the new files in the tree, §7 gets a CI note in CLAUDE.md, and a new §9 is added after Milestones.

---

## §6 Project Structure — updated tree

```
quire/
├── .github/
│   └── workflows/
│       ├── pr.yaml               # PR checks: bridge tests + WASM build
│       └── upload.yaml           # Main merge: package PWA artifact
├── CLAUDE.md
├── Makefile
├── package.json
├── index.html
├── manifest.json
├── service-worker.js
├── bridge.js
├── reader.css
├── src/
│   ├── runtime.c
│   ├── quire.sats
│   ├── quire.dats
│   ├── dom.sats
│   ├── dom.dats
│   ├── epub.sats
│   ├── epub.dats
│   ├── reader.sats
│   └── reader.dats
├── build/                        # Generated files (gitignored)
│   ├── *_dats.c
│   └── quire.wasm
└── test/
    ├── bridge.test.js            # Bridge protocol tests
    └── mock-wasm.js              # Mock WASM module for bridge tests
```

---

## §7 CLAUDE.md — add after the Testing section

```markdown
## CI

Two GitHub Actions workflows enforce quality:

- `pr.yaml` — runs on every PR. Runs bridge unit tests (`npm test`) and
  builds `quire.wasm` from ATS2 source. Both must pass to merge.
- `upload.yaml` — runs on merge to main. Builds the WASM, collects all PWA
  assets, and uploads a `quire-pwa` artifact. Download the artifact to get
  a deployable directory.

The ATS2 toolchain is built from source and cached. Cache key includes the
ATS-Postiats commit hash pinned in the workflow.
```

---

## §9 CI/CD Workflows (new section, after §8 Milestones)

### 9.1 PR Checks (`.github/workflows/pr.yaml`)

Triggered on every pull request. Two jobs run in parallel: bridge unit tests and WASM build. Both must pass.

**Bridge tests** run under Node with jsdom. The test suite (`test/bridge.test.js`) imports bridge internals and exercises them against a mock WASM module (`test/mock-wasm.js`) that provides the required exports — buffer pointers into a shared `ArrayBuffer`, a no-op `init`, and a `process_event` that writes known diff sequences into the diff buffer. This validates:

- Node registration and lookup (`registerNode`, `getNode`)
- Event encoding (`writeEvent` writes correct bytes at correct offsets)
- Diff application for every op code: `SET_TEXT`, `SET_ATTR`, `SET_TRANSFORM`, `CREATE_ELEMENT`, `REMOVE_CHILD`, `SET_INNER_HTML`
- The 16-byte stride alignment (no off-by-one on multi-entry diff buffers)
- The `wrapExports` proxy (every call flushes diffs, pointer getters are not wrapped)
- String buffer read helpers (`getStringFromBuffer`, `getStringFromFetchBuffer`)
- File and blob handle lifecycle (open/read/close with mock data)
- Error paths (missing nodes, unknown ops, zero-length strings)

The mock WASM module is a plain JS object that mimics the WASM export surface. It allocates a single `ArrayBuffer` and returns offsets into it for the four buffer pointers. Tests write crafted byte sequences into the diff buffer, then call `applyDiffs` (or trigger it through the proxy) and assert DOM state via jsdom.

**WASM build** installs ATS2 from source (cached) and system clang with `lld` for `wasm-ld`. Runs `make` and verifies `build/quire.wasm` exists. The ATS-Postiats commit is pinned in the workflow to ensure reproducible builds; updating it is a deliberate choice, not something that drifts.

```yaml
name: PR Checks

on:
  pull_request:
    branches: [main]

concurrency:
  group: pr-${{ github.head_ref }}
  cancel-in-progress: true

env:
  ATS_COMMIT: "66b10a29"  # Pin ATS-Postiats version; update deliberately

jobs:
  bridge-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci
      - run: npm test

  build-wasm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache ATS2 toolchain
        id: cache-ats
        uses: actions/cache@v4
        with:
          path: ~/ats2
          key: ats2-${{ env.ATS_COMMIT }}-${{ runner.os }}

      - name: Build ATS2
        if: steps.cache-ats.outputs.cache-hit != 'true'
        run: |
          sudo apt-get update && sudo apt-get install -y libgmp-dev
          git clone https://github.com/githwxi/ATS-Postiats.git ~/ats2
          cd ~/ats2
          git checkout ${{ env.ATS_COMMIT }}
          ./configure
          make -j$(nproc)

      - name: Install WASM toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y clang lld

      - name: Build quire.wasm
        env:
          PATSHOME: ~/ats2
          PATH: ~/ats2/bin:$PATH
        run: |
          make
          test -f build/quire.wasm
```

### 9.2 PWA Packaging (`.github/workflows/upload.yaml`)

Triggered on push to `main` (i.e., merged PRs). Builds the WASM binary, assembles all files needed to serve the PWA into a staging directory, and uploads it as a GitHub Actions artifact named `quire-pwa`. Downloading and extracting this artifact gives a directory that can be served from any static host.

The artifact contains:

```
quire-pwa/
├── index.html
├── bridge.js
├── quire.wasm
├── reader.css
├── manifest.json
├── service-worker.js
├── icon-192.png
└── icon-512.png
```

No build step touches `bridge.js`, `index.html`, or `reader.css` — they are static assets copied as-is. Only `quire.wasm` is built.

```yaml
name: Package PWA

on:
  push:
    branches: [main]

env:
  ATS_COMMIT: "66b10a29"

jobs:
  package:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache ATS2 toolchain
        id: cache-ats
        uses: actions/cache@v4
        with:
          path: ~/ats2
          key: ats2-${{ env.ATS_COMMIT }}-${{ runner.os }}

      - name: Build ATS2
        if: steps.cache-ats.outputs.cache-hit != 'true'
        run: |
          sudo apt-get update && sudo apt-get install -y libgmp-dev
          git clone https://github.com/githwxi/ATS-Postiats.git ~/ats2
          cd ~/ats2
          git checkout ${{ env.ATS_COMMIT }}
          ./configure
          make -j$(nproc)

      - name: Install WASM toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y clang lld

      - name: Build quire.wasm
        env:
          PATSHOME: ~/ats2
          PATH: ~/ats2/bin:$PATH
        run: make

      - name: Assemble PWA
        run: |
          mkdir -p dist
          cp index.html dist/
          cp bridge.js dist/
          cp reader.css dist/
          cp manifest.json dist/
          cp service-worker.js dist/
          cp build/quire.wasm dist/
          # Icons may not exist yet (M16); copy if present
          cp icon-192.png dist/ 2>/dev/null || true
          cp icon-512.png dist/ 2>/dev/null || true

      - name: Upload PWA artifact
        uses: actions/upload-artifact@v4
        with:
          name: quire-pwa
          path: dist/
          retention-days: 90
```

### 9.3 Design Notes

**Why not wasi-sdk?** The build is freestanding (`-nostdlib`, `--target=wasm32`, `--allow-undefined`). System clang plus `lld` (which provides `wasm-ld`) is sufficient and avoids downloading a 200MB+ SDK tarball on every uncached run. If the build ever needs WASI imports, switch to wasi-sdk and cache it the same way as ATS2.

**Why pin the ATS-Postiats commit?** ATS2 development is active and occasionally introduces breaking changes in codegen. Pinning to a known-good commit prevents mysterious CI failures unrelated to Quire changes. Bumping the pin is a one-line change in both workflow files (via the shared `ATS_COMMIT` env var).

**Why not deploy to Pages?** The `upload.yaml` workflow deliberately stops at artifact upload rather than deploying to GitHub Pages. Deployment target is a separate decision — could be Pages, Cloudflare, Netlify, or a custom server. The artifact is the universal intermediate: download it and put it wherever you want. A deployment step can be added later as a third workflow or appended to this one.

**Artifact retention** is set to 90 days. Older builds can always be regenerated from the corresponding commit.

---

## §8 Milestones — additions

Add to M1 (Project scaffold):

- [ ] `.github/workflows/pr.yaml` and `.github/workflows/upload.yaml` per §9
- [ ] `test/mock-wasm.js`: mock WASM module with buffer exports
- [ ] `test/bridge.test.js`: initial test scaffolding (node registry, event encoding)
- [ ] `package.json` includes `vitest` and `jsdom` as dev dependencies, `"test": "vitest run"`

Bridge test coverage expands incrementally: M2–M4 each add tests for the bridge changes made in that milestone.
