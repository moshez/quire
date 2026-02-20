# Quire Makefile — ATS2 to WASM build via Ward
#
# All ward .dats files are compiled and linked alongside quire .dats files.
# Uses ward's runtime.h/runtime.c for freestanding WASM.

PATSHOME ?= $(HOME)/.ats2/ATS2-Postiats-int-0.4.2
PATSOPT  := PATSHOME=$(PATSHOME) $(PATSHOME)/bin/patsopt
CLANG    := clang
WASM_LD  := wasm-ld

WARD_DIR := vendor/ward/lib

# WASM compilation flags
WASM_CFLAGS := --target=wasm32 -O2 -flto -nostdlib -ffreestanding \
  -I$(WARD_DIR)/../exerciser/wasm_stubs \
  -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime \
  -D_ATS_CCOMP_HEADER_NONE_ \
  -D_ATS_CCOMP_EXCEPTION_NONE_ \
  -D_ATS_CCOMP_PRELUDE_NONE_ \
  -DWARD_NO_DOM_STUB \
  -include $(WARD_DIR)/runtime.h

WASM_LDFLAGS := --no-entry --allow-undefined --lto-O2 \
  -z stack-size=1048576 --initial-memory=16777216 --max-memory=268435456

# WASM exports for bridge protocol
WASM_EXPORTS := \
  --export=ward_node_init \
  --export=ward_timer_fire \
  --export=ward_idb_fire \
  --export=ward_idb_fire_get \
  --export=malloc \
  --export=ward_on_event \
  --export=ward_measure_set \
  --export=ward_on_fetch_complete \
  --export=ward_on_clipboard_complete \
  --export=ward_on_file_open \
  --export=ward_on_decompress_complete \
  --export=ward_on_permission_result \
  --export=ward_on_push_subscribe \
  --export=ward_parse_html_stash \
  --export=ward_bridge_stash_set_ptr \
  --export=ward_bridge_stash_set_int \
  --export=memory

# Ward library sources (order: dependencies first)
WARD_DATS := \
  $(WARD_DIR)/memory.dats \
  $(WARD_DIR)/callback.dats \
  $(WARD_DIR)/dom.dats \
  $(WARD_DIR)/promise.dats \
  $(WARD_DIR)/event.dats \
  $(WARD_DIR)/idb.dats \
  $(WARD_DIR)/window.dats \
  $(WARD_DIR)/nav.dats \
  $(WARD_DIR)/dom_read.dats \
  $(WARD_DIR)/listener.dats \
  $(WARD_DIR)/fetch.dats \
  $(WARD_DIR)/clipboard.dats \
  $(WARD_DIR)/file.dats \
  $(WARD_DIR)/decompress.dats \
  $(WARD_DIR)/notify.dats \
  $(WARD_DIR)/xml.dats

# Quire application sources (order: dependencies first)
QUIRE_DATS := \
  src/app_state.dats \
  src/dom.dats \
  src/quire_ext.dats \
  src/zip.dats \
  src/xml.dats \
  src/epub.dats \
  src/sha256.dats \
  src/settings.dats \
  src/library.dats \
  src/reader.dats \
  src/quire.dats

ALL_DATS := $(WARD_DATS) $(QUIRE_DATS)

# Generated C files
WARD_C_GEN  := $(patsubst $(WARD_DIR)/%.dats,build/ward_%_dats.c,$(WARD_DATS))
QUIRE_C_GEN := $(patsubst src/%.dats,build/%_dats.c,$(QUIRE_DATS))
ALL_C_GEN   := $(WARD_C_GEN) $(QUIRE_C_GEN)

# Object files
WARD_OBJS   := $(patsubst build/%.c,build/%.o,$(WARD_C_GEN))
QUIRE_OBJS  := $(patsubst build/%.c,build/%.o,$(QUIRE_C_GEN))
ALL_OBJS    := $(WARD_OBJS) $(QUIRE_OBJS) build/ward_runtime.o

# Default target
all: build/quire.wasm

# --- ATS2 -> C compilation ---

build:
	@mkdir -p build

# Ward library: ATS2 -> C
build/ward_%_dats.c: $(WARD_DIR)/%.dats | build
	$(PATSOPT) -IATS $(WARD_DIR) -o $@ -d $<

# Quire sources: ATS2 -> C
build/%_dats.c: src/%.dats | build
	$(PATSOPT) -IATS src -IATS $(WARD_DIR) -o $@ -d $<

# --- C -> WASM object compilation ---

build/ward_%_dats.o: build/ward_%_dats.c $(WARD_DIR)/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

build/%_dats.o: build/%_dats.c $(WARD_DIR)/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

build/ward_runtime.o: $(WARD_DIR)/runtime.c $(WARD_DIR)/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

# --- Link ---

build/quire.wasm: $(ALL_OBJS)
	$(WASM_LD) $(WASM_LDFLAGS) $(WASM_EXPORTS) -o $@ $^

# --- Utilities ---

# --- Static tests (compile-time only, C output discarded) ---

static-tests: | build
	$(PATSOPT) -IATS src -IATS $(WARD_DIR) -o /dev/null -d src/static_tests.dats

clean:
	rm -rf build/*

install: build/quire.wasm
	cp build/quire.wasm quire.wasm

# --- PWA packaging ---
# Assembles a deployable PWA in dist/.
# COMMIT_SHA controls version stamp (default: "dev" for local use).
# Used by both PR validation and deploy workflows.

COMMIT_SHA ?= dev

# Required PWA files — build fails if any are missing
PWA_REQUIRED := index.html reader.css manifest.json service-worker.js

dist: build/quire.wasm
	@mkdir -p dist
	@for f in $(PWA_REQUIRED); do \
	  test -f $$f || { echo "ERROR: required PWA file missing: $$f"; exit 1; }; \
	done
	cp index.html dist/
	cp $(WARD_DIR)/ward_bridge.mjs dist/ward_bridge.js
	cp reader.css dist/
	cp manifest.json dist/
	cp service-worker.js dist/
	cp build/quire.wasm dist/
	cp icon-192.png dist/ 2>/dev/null || true
	cp icon-512.png dist/ 2>/dev/null || true
	sed -i "s|./vendor/ward/lib/ward_bridge.mjs|./ward_bridge.js|" dist/index.html
	sed -i "s|>dev</div>|>$(COMMIT_SHA)</div>|" dist/index.html
	sed -i "s|quire-v3|quire-$(COMMIT_SHA)|" dist/service-worker.js

.PHONY: all clean install dist static-tests
