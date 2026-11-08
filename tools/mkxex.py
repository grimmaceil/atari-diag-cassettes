#!/usr/bin/env python3
"""Wrap an assembled boot image (the same kind mkcas.py wraps as a tape) as
an Atari binary file (.xex), for DOS or an XEX loader.

The image runs at $0800, where DOS lives while the file loads, so it loads
at BASE and the mover copies it down (src/disk/xexwrap.asm). Segments:
  1. the guard at BASE, then INITAD: halts with a message on a machine
     with too little RAM, or DOS in the way, before anything else loads;
  2. the image at BASE (overwriting the guard);
  3. the mover just past the image, then RUNAD.
"""
import argparse
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mkcas import patch_boot   # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MADS = ROOT / 'tools' / 'bin' / 'mads.exe'
BASE = 0x2000


def seg(start, data):
    return struct.pack('<HH', start, start + len(data) - 1) + bytes(data)


def part(n, org, out, defs):
    path = Path(f'{out}.wrap{n}')
    args = [str(MADS), 'xexwrap.asm', f'-o:{path}.bin', f'-l:{path}.lst',
            f'-d:PART={n}', f'-d:ORG=${org:04X}'] + [f'-d:{k}={v}' for k, v in defs.items()]
    r = subprocess.run(args, cwd=ROOT / 'src' / 'disk', capture_output=True, text=True)
    if r.returncode:
        sys.exit('xexwrap.asm:\n' + r.stdout + r.stderr)
    return Path(f'{path}.bin').read_bytes()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('xex')
    ap.add_argument('--boot', nargs=2, metavar=('BIN', 'LAB'), required=True)
    ap.add_argument('--needpg', type=lambda x: int(x, 0), required=True,
                    help='RAM the program needs, in pages (RAMTOP)')
    a = ap.parse_args()

    img, nrec, load, s = patch_boot(*a.boot)
    if load != 0x0800:
        sys.exit('the image must run at $0800')
    out = a.boot[0][:-4]
    defs = dict(BASE=f'${BASE:04X}', NEEDPG=f'${a.needpg:02X}', NEEDK=a.needpg // 4,
                NPAGES=(len(img) + 255) // 256)
    top = BASE + len(img)
    guard = part(1, BASE, out, defs)
    mover = part(2, top, out, defs)
    data = (b'\xff\xff' + seg(BASE, guard) + seg(0x02E2, struct.pack('<H', BASE))
            + seg(BASE, img) + seg(top, mover) + seg(0x02E0, struct.pack('<H', top)))
    open(a.xex, 'wb').write(data)
    print(f'{a.xex}: image ${len(img):04X} bytes at ${BASE:04X}-${top - 1:04X}, '
          f'mover to ${top + len(mover) - 1:04X}, runs at $0800, needs {a.needpg // 4}K, '
          f'sum ${s:04X}')
    if top + len(mover) > a.needpg << 8:
        sys.exit('the file does not fit in the RAM it asks for')


if __name__ == '__main__':
    main()
