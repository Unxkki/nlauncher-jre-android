#!/usr/bin/env python3
"""Sanity checks for the ELF files of an Android runtime image.

Pure Python (no readelf needed), so it runs on any build host.

  elfcheck.py <image-dir> [--page-size 16384] [--arch aarch64|arm]

Checks every ELF file below <image-dir>:
  * machine matches --arch;
  * every PT_LOAD segment is aligned to at least --page-size (16 KB pages);
  * no DT_TEXTREL;
  * no DT_RPATH, and DT_RUNPATH only uses $ORIGIN-relative entries;
  * every DT_NEEDED is either an Android system library from the NDK's
    stable API set or a library shipped inside the image;
  * none of the known-unwanted dependencies (libc++_shared, Termux helper
    libraries, X11, ALSA, CUPS, fontconfig, freetype) is referenced.
Exit status 1 if anything fails.
"""
import argparse
import os
import struct
import sys

SYSTEM_LIBS = {"libc.so", "libm.so", "libdl.so", "liblog.so", "libz.so", "libandroid.so"}
FORBIDDEN_PREFIXES = ("libc++_shared", "libandroid-shmem", "libandroid-spawn", "libiconv",
                      "libasound", "libX", "libcups", "libfontconfig", "libfreetype")
EM = {"aarch64": 183, "arm": 40}
PT_LOAD, PT_DYNAMIC = 1, 2
DT_NULL, DT_NEEDED, DT_STRTAB, DT_RPATH, DT_TEXTREL, DT_FLAGS, DT_RUNPATH = 0, 1, 5, 15, 22, 30, 29
DF_TEXTREL = 0x4


def parse(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF":
        return None
    cls, enc = data[4], data[5]
    if enc != 1:
        raise ValueError("big-endian ELF")
    is64 = cls == 2
    e_type, e_machine = struct.unpack_from("<HH", data, 16)
    if is64:
        e_phoff, = struct.unpack_from("<Q", data, 32)
        e_phentsize, e_phnum = struct.unpack_from("<HH", data, 54)
    else:
        e_phoff, = struct.unpack_from("<I", data, 28)
        e_phentsize, e_phnum = struct.unpack_from("<HH", data, 42)
    phdrs = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if is64:
            p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = \
                struct.unpack_from("<IIQQQQQQ", data, off)
        else:
            p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
                struct.unpack_from("<IIIIIIII", data, off)
        phdrs.append((p_type, p_offset, p_vaddr, p_filesz, p_align))

    def vaddr_to_off(addr):
        for t, off, va, fsz, _ in phdrs:
            if t == PT_LOAD and va <= addr < va + fsz:
                return off + (addr - va)
        return None

    dyn = []
    for t, off, va, fsz, _ in phdrs:
        if t != PT_DYNAMIC:
            continue
        esz = 16 if is64 else 8
        for j in range(fsz // esz):
            tag, val = struct.unpack_from("<qQ" if is64 else "<iI", data, off + j * esz)
            if tag == DT_NULL:
                break
            dyn.append((tag, val))
    strtab = next((v for t, v in dyn if t == DT_STRTAB), None)
    stroff = vaddr_to_off(strtab) if strtab is not None else None

    def dstr(v):
        if stroff is None:
            return "?"
        end = data.index(b"\0", stroff + v)
        return data[stroff + v:end].decode()

    return {
        "type": e_type,
        "machine": e_machine,
        "loads": [(va, al) for t, _, va, _, al in phdrs if t == PT_LOAD],
        "needed": [dstr(v) for t, v in dyn if t == DT_NEEDED],
        "rpath": [dstr(v) for t, v in dyn if t == DT_RPATH],
        "runpath": [dstr(v) for t, v in dyn if t == DT_RUNPATH],
        "textrel": any(t == DT_TEXTREL for t, _ in dyn) or
                   any(t == DT_FLAGS and v & DF_TEXTREL for t, v in dyn),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--page-size", type=int, default=16384)
    ap.add_argument("--arch", choices=sorted(EM), default="aarch64")
    a = ap.parse_args()

    elves = {}
    for root, _, files in os.walk(a.image):
        for name in files:
            p = os.path.join(root, name)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            try:
                info = parse(p)
            except (ValueError, struct.error) as e:
                print(f"FAIL {p}: cannot parse ELF: {e}")
                return 1
            if info is not None:
                elves[p] = info
    shipped = {os.path.basename(p) for p in elves}
    errors = 0
    for p, e in sorted(elves.items()):
        rel = os.path.relpath(p, a.image)
        problems = []
        if e["machine"] != EM[a.arch]:
            problems.append(f"machine {e['machine']} != {a.arch}")
        for va, al in e["loads"]:
            if al < a.page_size:
                problems.append(f"PT_LOAD at {va:#x} aligned to {al:#x} < {a.page_size:#x}")
        if e["textrel"]:
            problems.append("has TEXTREL")
        if e["rpath"]:
            problems.append(f"DT_RPATH {e['rpath']} (use DT_RUNPATH)")
        for rp in e["runpath"]:
            for part in rp.split(":"):
                if part and not part.startswith("$ORIGIN"):
                    problems.append(f"absolute RUNPATH entry {part!r}")
        for n in e["needed"]:
            if n.startswith(FORBIDDEN_PREFIXES):
                problems.append(f"forbidden dependency {n}")
            elif n not in SYSTEM_LIBS and n not in shipped:
                problems.append(f"dependency {n} is neither a system library nor shipped")
        status = "FAIL" if problems else "ok  "
        print(f"{status} {rel}  needed={','.join(e['needed']) or '-'}"
              + (f"  runpath={':'.join(e['runpath'])}" if e["runpath"] else ""))
        for pr in problems:
            print(f"       - {pr}")
        errors += bool(problems)
    print(f"{len(elves)} ELF files checked, {errors} with problems")
    if not elves:
        print("FAIL: no ELF files found")
        return 1
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
