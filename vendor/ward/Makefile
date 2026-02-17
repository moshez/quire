# Ward -- Linear memory safety library for ATS2
# Builds WASM output, native exerciser, and anti-exerciser checks

PATSHOME ?= $(HOME)/.ats2/ATS2-Postiats-int-0.4.2
PATSOPT  := PATSHOME=$(PATSHOME) $(PATSHOME)/bin/patsopt

CC       := gcc
CLANG    := clang
WASM_LD  := wasm-ld

CFLAGS_ATS := -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime
WARD_DIR   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# WASM flags
WASM_CFLAGS := --target=wasm32 -O2 -nostdlib -ffreestanding \
  -I$(WARD_DIR)exerciser/wasm_stubs -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime \
  -D_ATS_CCOMP_HEADER_NONE_ \
  -D_ATS_CCOMP_EXCEPTION_NONE_ \
  -D_ATS_CCOMP_PRELUDE_NONE_ \
  -include $(WARD_DIR)lib/runtime.h
WASM_LDFLAGS := --no-entry --export-dynamic \
  -z stack-size=65536 --initial-memory=16777216 --max-memory=268435456

# Node WASM flags (ward_dom_flush = WASM import, not stub)
WASM_NODE_CFLAGS := $(WASM_CFLAGS) -DWARD_NO_DOM_STUB

# Anti-exerciser files (must all FAIL to compile)
ANTI_SRCS := $(wildcard exerciser/anti/*.dats)

# --- Default target ---
.PHONY: all clean exerciser wasm anti-exerciser check node-exerciser test check-all

all: wasm exerciser

check: wasm exerciser anti-exerciser

# --- ATS2 → C compilation ---
build:
	@mkdir -p build

build/memory_dats.c: lib/memory.dats lib/memory.sats | build
	$(PATSOPT) -o $@ -d $<

build/dom_dats.c: lib/dom.dats lib/dom.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

build/promise_dats.c: lib/promise.dats lib/promise.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

build/exerciser_dats.c: exerciser/exerciser.dats lib/memory.sats lib/memory.dats lib/dom.sats lib/dom.dats lib/promise.sats lib/promise.dats | build
	$(PATSOPT) -o $@ -d $<

build/wasm_exerciser_dats.c: exerciser/wasm_exerciser.dats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

# --- Native exerciser (links with libc) ---
build/exerciser: build/memory_dats.c build/dom_dats.c build/promise_dats.c build/exerciser_dats.c lib/ward_prelude.h | build
	$(CC) $(CFLAGS_ATS) -include $(WARD_DIR)lib/ward_prelude.h \
	  -o $@ build/memory_dats.c build/dom_dats.c build/promise_dats.c build/exerciser_dats.c

exerciser: build/exerciser
	@echo "==> Running exerciser"
	@build/exerciser

# --- WASM build ---
build/memory_dats.o: build/memory_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

build/dom_dats.o: build/dom_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

build/promise_dats.o: build/promise_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

build/wasm_exerciser_dats.o: build/wasm_exerciser_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

build/runtime.o: lib/runtime.c lib/runtime.h | build
	$(CLANG) $(WASM_CFLAGS) -c -o $@ $<

WASM_TEST_EXPORTS := --export=ward_test_raw --export=ward_test_borrow \
  --export=ward_test_typed --export=ward_test_safe_text --export=ward_test_large_alloc

build/ward.wasm: build/memory_dats.o build/dom_dats.o build/promise_dats.o build/wasm_exerciser_dats.o build/runtime.o
	$(WASM_LD) $(WASM_LDFLAGS) $(WASM_TEST_EXPORTS) -o $@ $^

wasm: build/ward.wasm
	@echo "==> build/ward.wasm built"

# --- Anti-exerciser (verify unsafe code is rejected) ---
anti-exerciser:
	@echo "==> Anti-exerciser: verifying unsafe code is rejected"
	@pass=0; fail=0; \
	for f in $(ANTI_SRCS); do \
	  if $(PATSOPT) -o /dev/null -d $$f >/dev/null 2>&1; then \
	    echo "FAIL: $$f compiled (should have been rejected)"; \
	    fail=$$((fail + 1)); \
	  else \
	    echo "  ok: $$f rejected"; \
	    pass=$$((pass + 1)); \
	  fi; \
	done; \
	echo "==> $$pass rejected, $$fail unexpectedly compiled"; \
	test $$fail -eq 0

# --- Node DOM exerciser ---

# Bridge module common deps
BRIDGE_SATS := lib/memory.sats lib/memory.dats lib/promise.sats lib/promise.dats

# ATS2 -> C for event module
build/event_dats.c: lib/event.dats lib/event.sats $(BRIDGE_SATS) | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for IDB module
build/idb_dats.c: lib/idb.dats lib/idb.sats $(BRIDGE_SATS) | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for window module
build/window_dats.c: lib/window.dats lib/window.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for nav module
build/nav_dats.c: lib/nav.dats lib/nav.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for dom_read module
build/dom_read_dats.c: lib/dom_read.dats lib/dom_read.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for listener module
build/listener_dats.c: lib/listener.dats lib/listener.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for callback module
build/callback_dats.c: lib/callback.dats lib/callback.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for xml module
build/xml_dats.c: lib/xml.dats lib/xml.sats lib/memory.sats lib/memory.dats | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for fetch module
build/fetch_dats.c: lib/fetch.dats lib/fetch.sats $(BRIDGE_SATS) | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for clipboard module
build/clipboard_dats.c: lib/clipboard.dats lib/clipboard.sats $(BRIDGE_SATS) | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for file module
build/file_dats.c: lib/file.dats lib/file.sats $(BRIDGE_SATS) | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for decompress module
build/decompress_dats.c: lib/decompress.dats lib/decompress.sats $(BRIDGE_SATS) | build
	$(PATSOPT) -o $@ -d $<

# ATS2 -> C for notify module
build/notify_dats.c: lib/notify.dats lib/notify.sats $(BRIDGE_SATS) | build
	$(PATSOPT) -o $@ -d $<

# All bridge .sats/.dats for dom_exerciser deps
BRIDGE_ALL_SATS := lib/memory.sats lib/memory.dats lib/dom.sats lib/dom.dats \
  lib/promise.sats lib/promise.dats lib/event.sats lib/event.dats \
  lib/idb.sats lib/idb.dats lib/window.sats lib/window.dats \
  lib/nav.sats lib/nav.dats lib/dom_read.sats lib/dom_read.dats \
  lib/listener.sats lib/listener.dats lib/callback.sats lib/callback.dats \
  lib/fetch.sats lib/fetch.dats \
  lib/clipboard.sats lib/clipboard.dats lib/file.sats lib/file.dats \
  lib/decompress.sats lib/decompress.dats lib/notify.sats lib/notify.dats \
  lib/xml.sats lib/xml.dats

# ATS2 -> C for dom_exerciser
build/dom_exerciser_dats.c: exerciser/dom_exerciser.dats $(BRIDGE_ALL_SATS) | build
	$(PATSOPT) -o $@ -d $<

# Recompile dom for node (ward_dom_flush = WASM import, not stub)
build/dom_node_dats.o: build/dom_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/event_dats.o: build/event_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/idb_dats.o: build/idb_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/window_dats.o: build/window_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/nav_dats.o: build/nav_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/dom_read_dats.o: build/dom_read_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/listener_dats.o: build/listener_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/callback_dats.o: build/callback_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/xml_dats.o: build/xml_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/fetch_dats.o: build/fetch_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/clipboard_dats.o: build/clipboard_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/file_dats.o: build/file_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/decompress_dats.o: build/decompress_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/notify_dats.o: build/notify_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/dom_exerciser_dats.o: build/dom_exerciser_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

# Recompile memory + promise + runtime for node build
build/memory_node_dats.o: build/memory_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/promise_node_dats.o: build/promise_dats.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

build/runtime_node.o: lib/runtime.c lib/runtime.h | build
	$(CLANG) $(WASM_NODE_CFLAGS) -c -o $@ $<

# All node WASM objects
NODE_WASM_OBJS := build/memory_node_dats.o build/dom_node_dats.o build/promise_node_dats.o \
  build/event_dats.o build/idb_dats.o \
  build/window_dats.o build/nav_dats.o build/dom_read_dats.o build/listener_dats.o build/callback_dats.o \
  build/fetch_dats.o build/clipboard_dats.o build/file_dats.o build/decompress_dats.o build/xml_dats.o \
  build/notify_dats.o \
  build/dom_exerciser_dats.o build/runtime_node.o

# WASM exports for bridge callbacks
NODE_WASM_EXPORTS := --export=ward_node_init --export=ward_timer_fire \
  --export=ward_idb_fire --export=ward_idb_fire_get \
  --export=ward_on_event --export=ward_measure_set \
  --export=ward_on_fetch_complete --export=ward_on_clipboard_complete \
  --export=ward_on_file_open --export=ward_on_decompress_complete \
  --export=ward_on_permission_result --export=ward_on_push_subscribe \
  --export=ward_on_callback \
  --export=ward_bridge_stash_set_int

build/node_ward.wasm: $(NODE_WASM_OBJS)
	$(WASM_LD) $(WASM_LDFLAGS) --allow-undefined \
	  $(NODE_WASM_EXPORTS) \
	  -o $@ $^

node_modules: package.json
	npm install

node-exerciser: build/node_ward.wasm node_modules
	@echo "==> Running Node DOM exerciser"
	@node exerciser/node_exerciser.mjs

test: build/node_ward.wasm node_modules
	@echo "==> Running bridge tests"
	@node --test tests/

check-all: check test

clean:
	rm -rf build
