# Quire Makefile - ATS2 to WASM build

PATSOPT  = patsopt
CC       = clang
CFLAGS   = --target=wasm32 -nostdlib -O2
CFLAGS  += -D_ATS_CCOMP_HEADER_NONE_
CFLAGS  += -D_ATS_CCOMP_PRELUDE_NONE_
CFLAGS  += -D_ATS_CCOMP_EXCEPTION_NONE_
LDFLAGS  = -Wl,--no-entry -Wl,--allow-undefined

# Required WASM exports for bridge protocol
EXPORTS  = -Wl,--export=init \
           -Wl,--export=process_event \
           -Wl,--export=on_fetch_complete \
           -Wl,--export=on_timer_complete \
           -Wl,--export=on_file_open_complete \
           -Wl,--export=on_decompress_complete \
           -Wl,--export=on_kv_complete \
           -Wl,--export=on_kv_get_complete \
           -Wl,--export=on_kv_get_blob_complete \
           -Wl,--export=on_kv_open_complete \
           -Wl,--export=on_clipboard_copy_complete \
           -Wl,--export=get_event_buffer_ptr \
           -Wl,--export=get_diff_buffer_ptr \
           -Wl,--export=get_fetch_buffer_ptr \
           -Wl,--export=get_string_buffer_ptr \
           -Wl,--export=memory

# Source files (order matters: dependencies first)
ATS_SRC  = src/dom.dats src/zip.dats src/xml.dats src/epub.dats src/quire.dats
C_GEN    = $(patsubst src/%.dats,build/%_dats.c,$(ATS_SRC))

# Default target
all: build/quire.wasm

# Link all C files into final WASM
# Use -include to ensure runtime.h macros are available to ATS-generated code
# Link runtime.c separately to avoid duplicate symbols
build/quire.wasm: $(C_GEN) src/runtime.c src/runtime.h | build
	$(CC) $(CFLAGS) $(LDFLAGS) $(EXPORTS) -include src/runtime.h -o $@ src/runtime.c $(C_GEN)

# Compile ATS to C
build/%_dats.c: src/%.dats src/%.sats | build
	$(PATSOPT) -IATS src --output $@ --dynamic $<

# Create build directory
build:
	mkdir -p build

# Clean generated files
clean:
	rm -rf build/*

# Copy WASM to root for serving (convenience target)
install: build/quire.wasm
	cp build/quire.wasm quire.wasm

.PHONY: all clean install
