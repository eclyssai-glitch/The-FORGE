#!/usr/bin/env python3
"""Lists the files inside a Godot 4 PCK, standalone or embedded in an exported executable
(e.g. build/windows/KoriumUniverse.exe). Used to prove what the export ships (docs/BUILD.md:
the dev inspector in tools/ must not be there). Python standard library only.

  tools/pck_list.py build/windows/KoriumUniverse.exe            one path per line (sorted)
  tools/pck_list.py build/windows/KoriumUniverse.exe --grep=tools/   only paths containing tools/
  tools/pck_list.py build/windows/KoriumUniverse.exe --sizes    path, size, md5

Exit 0 = listed; with --grep, exit 1 when nothing matched (handy for "must be absent" checks:
`! tools/pck_list.py exe --grep=tools/inspector`). Pack formats 2-4 (Godot 4.x) without
encrypted directory.
"""
import argparse
import os
import struct
import sys

MAGIC = b"GDPC"
PACK_DIR_ENCRYPTED = 1
PACK_REL_FILEBASE = 2


def pck_start(f, size: int) -> int:
    f.seek(0)
    if f.read(4) == MAGIC:
        return 0
    # Embedded: ... <pck> <u64 pck size> "GDPC" at the very end.
    f.seek(size - 12)
    tail = f.read(12)
    if tail[8:] != MAGIC:
        raise SystemExit("pck_list: no PCK found (neither a .pck nor an executable with an embedded pack)")
    pck_size = struct.unpack("<Q", tail[:8])[0]
    return size - 12 - pck_size


def entries(path: str):
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        start = pck_start(f, size)
        f.seek(start)
        if f.read(4) != MAGIC:
            raise SystemExit("pck_list: bad PCK header")
        version, major, minor, patch = struct.unpack("<IIII", f.read(16))
        flags = 0
        dir_offset = None
        if version >= 2:
            flags, _file_base = struct.unpack("<IQ", f.read(12))
        if version >= 3:
            dir_offset = struct.unpack("<Q", f.read(8))[0]
        if flags & PACK_DIR_ENCRYPTED:
            raise SystemExit("pck_list: encrypted directory")
        if dir_offset is not None:
            f.seek(start + dir_offset)
        else:
            f.read(16 * 4)  # reserved
        count = struct.unpack("<I", f.read(4))[0]
        out = []
        for _ in range(count):
            n = struct.unpack("<I", f.read(4))[0]
            name = f.read(n).rstrip(b"\0").decode("utf-8")
            offset, fsize = struct.unpack("<QQ", f.read(16))
            md5 = f.read(16).hex()
            if version >= 2:
                f.read(4)  # per-file flags
            out.append((name, fsize, md5))
        return (version, major, minor, patch), out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pack")
    ap.add_argument("--grep", default="")
    ap.add_argument("--sizes", action="store_true")
    a = ap.parse_args()
    ver, files = entries(a.pack)
    shown = 0
    for name, fsize, md5 in sorted(files):
        if a.grep and a.grep not in name:
            continue
        shown += 1
        print(f"{name}\t{fsize}\t{md5}" if a.sizes else name)
    print(f"pck_list: format {ver[0]}, Godot {ver[1]}.{ver[2]}.{ver[3]}, {len(files)} files, {shown} listed",
          file=sys.stderr)
    return 1 if a.grep and shown == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
