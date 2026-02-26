#!/usr/bin/env python3
"""Generate ATS2 _w4() calls from CSS text files.

Usage: python3 tools/gen_css_bytes.py <css_file> [--chunk-size N]

Reads plain CSS text, outputs chunked fill_css_chunkN functions + fill_css wrapper.
"""

import struct
import sys
import argparse


def main():
    parser = argparse.ArgumentParser(description='Generate ATS2 _w4 calls from CSS')
    parser.add_argument('css_file', help='CSS text file to convert')
    parser.add_argument('--chunk-size', type=int, default=400,
                        help='Max bytes per function chunk (default 400)')
    args = parser.parse_args()

    with open(args.css_file) as f:
        css = f.read().strip()

    css_bytes = css.encode('ascii')

    # Split into chunks
    chunks = []
    i = 0
    while i < len(css_bytes):
        end = min(i + args.chunk_size, len(css_bytes))
        chunks.append((i, css_bytes[i:end]))
        i = end

    print(f"(* App CSS — generated from {args.css_file} by tools/gen_css_bytes.py *)")
    print(f"(* {len(css_bytes)} bytes in {len(chunks)} chunks of ~{args.chunk_size} *)")
    print(f"(* DO NOT EDIT — regenerate from {args.css_file} *)")
    print()

    for ci, (start, chunk) in enumerate(chunks):
        print(f"fn fill_css_chunk{ci} {{l:agz}}{{n:int | n >= APP_CSS_LEN}}")
        print(f"  (arr: !ward_arr(byte, l, n), alen: int n): void = let")
        j = 0
        while j < len(chunk):
            remaining = len(chunk) - j
            off = start + j
            if remaining >= 4:
                val = struct.unpack('<I', chunk[j:j+4])[0]
                print(f"  val () = _w4(arr, alen, {off}, {val})")
                j += 4
            else:
                for k in range(remaining):
                    print(f"  val () = ward_arr_set_byte(arr, {off+k}, alen, {css_bytes[start+j+k]})")
                j += remaining
        print(f"in end")
        print()

    # Main fill_css wrapper
    print(f"fn fill_css {{l:agz}}{{n:int | n >= APP_CSS_LEN}}")
    print(f"  (arr: !ward_arr(byte, l, n), alen: int n)")
    print(f"  : (CSS_READER_WRITTEN | void) = let")
    for ci in range(len(chunks)):
        print(f"  val () = fill_css_chunk{ci}(arr, alen)")
    print(f"  prval pf_reader = __stamp() where {{")
    print(f"    extern praxi __stamp(): CSS_READER_WRITTEN")
    print(f"  }}")
    print(f"in (pf_reader | ()) end")

    print(f"\n(* APP_CSS_LEN = {len(css_bytes)} *)", file=sys.stderr)


if __name__ == '__main__':
    main()
