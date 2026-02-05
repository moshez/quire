# Quire

PWA e-reader with all application logic in ATS2 compiled to WASM.

**Live demo:** https://moshez.github.io/quire/

## Prerequisites

### ATS2 (ATS/Postiats)

Download and build the integer-only version (no GMP dependency):

```bash
# Download from GitHub Pages mirror
curl -sL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-int-0.4.2.tgz" -o /tmp/ats2.tgz

# Extract
tar -xzf /tmp/ats2.tgz -C ~

# Build
cd ~/ATS2-Postiats-int-0.4.2
./configure
make -j$(nproc)

# Set environment variables (add to ~/.bashrc or ~/.zshrc)
export PATSHOME=~/ATS2-Postiats-int-0.4.2
export PATH=$PATSHOME/bin:$PATH
```

### WASM Toolchain

Install clang with WASM support:

```bash
# Ubuntu/Debian
sudo apt-get install -y clang lld
```

## Build

```bash
make                    # Build quire.wasm
make clean              # Remove build artifacts
make install            # Copy quire.wasm to project root
```

## Development

```bash
npm install             # Install dev dependencies
npm test                # Run bridge tests
npx serve .             # Start dev server
```

Open http://localhost:3000 in your browser.

## Project Structure

```
quire/
├── src/
│   ├── runtime.c       # Minimal C runtime for WASM
│   ├── quire.sats      # ATS2 type declarations
│   └── quire.dats      # ATS2 implementation
├── build/              # Generated files (gitignored)
├── bridge.js           # Generic WASM-to-DOM bridge
├── index.html          # App shell
└── test/               # Bridge protocol tests
```

## Architecture

See [CLAUDE.md](CLAUDE.md) for project guidelines and [quire-design.md](quire-design.md) for detailed design documentation.
