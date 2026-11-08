#!/usr/bin/env python3
"""Build the diag tapes: assemble with MADS, wrap as .cas, optionally deploy.

  python tools/build.py                 normal tapes into build/
  python tools/build.py --fault 2,5     also tapes with an injected fault
                                        (0 = low RAM, 4 = under the XL OS,
                                        5-8 = 130XE, 9 = loader area)
  python tools/build.py --fault 2,5,3   ... only every 3rd burn-in pass
  python tools/build.py --fast          skip the slow test patterns
  python tools/build.py --deploy        copy the .cas files to the MiSTer share
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MADS = ROOT / 'tools' / 'bin' / 'mads.exe'
BUILD = ROOT / 'build'          # everything the assembler makes (not in git)
CASSETTES = ROOT / 'cassettes'  # the release tapes (in git): what users load
SHARE = Path('//TRUENAS/Media/games/ATARI800/_diag')   # the tapes, in the MiSTer Atari800 core's folder

# Each tape: source dir, name, stages (first = boot), defines. A later stage
# is told where the boot stage keeps its BSS and where its own test area ends.
# The system tapes are one main.asm with the tests picked by WANT_* defines.
# The 400 and 16k sets share tape 1: its stage 2 (16K and up) relocates the
# RAM test to the RAM stage 1 sat in, and tests the XL/XE extras where it
# finds them. The 48k+ set is one boot file (build_oneload): tape 1's stage 1
# at $4000 (ONELOAD), with a payload built for $0800 appended: stage 2
# (ONELOAD+CHAIN3), its BSS page, then the system tests (CHAIN, SYSLOAD).
ALL7 = dict(WANT_ROM=1, WANT_KB=1, WANT_CON=1, WANT_JOY=1, WANT_PAD=1,
            WANT_POK=1, WANT_GTIA=1)
S400 = {'SETNO': 0}
TAPES = [('tape1', 'diag-400-01-ram', ['main.asm', 'stage2.asm'], {}),
         ('system', 'diag-400-02-rom', ['main.asm'], dict(S400, TAPENO=2, WANT_ROM=1)),
         ('system', 'diag-400-03-input', ['main.asm'],
          dict(S400, TAPENO=3, WANT_KB=1, WANT_CON=1)),
         ('system', 'diag-400-04-ports', ['main.asm'],
          dict(S400, TAPENO=4, WANT_JOY=1, WANT_PAD=1)),
         ('system', 'diag-400-05-av', ['main.asm'],
          dict(S400, TAPENO=5, WANT_POK=1, WANT_GTIA=1)),
         ('one16', 'diag-16k-01-ram', [], {}),
         ('system', 'diag-16k-02-system', ['main.asm'],
          dict(ALL7, SETNO=1, TAPENO=2, MENU=1, BIGSTAGE=1)),
         ('one32', 'diag-32k-xl-xe', [], {}),
         ('system', 'diag-controls', ['main.asm'],
          dict(SETNO=3, WANT_KB=1, WANT_JOY=1, WANT_PAD=1, BIGSTAGE=1)),
         ('tape2', 'diag-400-memtest', ['main.asm'], {'OWNTEST': 1, 'NOXL': 1, 'NORAMK': 1}),
         ('bounce', 'diag-memtest', [], {'BOUNCE': 1, 'BIGSTAGE': 1, 'OWNTEST': 1})]


def mads(src, asm, out, defines):
    args = [str(MADS), asm, f'-o:{out}.bin', f'-l:{out}.lst', f'-t:{out}.lab']
    args += [f'-d:{k}={v}' for k, v in defines.items()]
    r = subprocess.run(args, cwd=ROOT / 'src' / src, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f'{src}/{asm}:\n' + r.stdout + r.stderr)


def labels(path):
    lab = {}
    for line in open(path, encoding='latin-1'):
        p = line.split()
        if len(p) == 3 and len(p[1]) == 4:
            lab[p[2].upper()] = int(p[1], 16)
    return lab


def build(src, name, stages, defines, label):
    out = BUILD / name
    mads(src, stages[0], out, defines)
    s1 = labels(f'{out}.lab')
    prev, nexts = s1, []
    for k, asm in enumerate(stages[1:], 2):
        # 'dir/file.asm' takes a stage from another source dir (the 48k tape's
        # stage 3 is the system tests). PREVBSS: the stage before, whose
        # results it takes over.
        sdir, sasm = asm.split('/') if '/' in asm else (src, asm)
        d = dict(defines, S1BSS=f"${s1['BSS']:04X}", S1TSTART=f"${s1['TSTART']:02X}",
                 PREVBSS=f"${prev['BSS']:04X}")
        mads(sdir, sasm, Path(f'{out}.s{k}'), d)
        prev = labels(f'{out}.s{k}.lab')
        nexts += ['--next', f'{out}.s{k}.bin']
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'mkcas.py'), f'{out}.cas',
                    '--boot', f'{out}.bin', f'{out}.lab', *nexts, '--name', label],
                   check=True)
    return [Path(f'{out}.cas')] + [Path(f'{out}-part{k}.cas')
                                   for k in range(2, len(stages) + 1)]


def build_oneload(name, defines, label):
    """The 48k+ tape: one boot file. The payload's addresses depend on stage
    1's BSS (stage 2 takes its results over) and stage 1's size on the
    payload's, but no size depends on an address, so two rounds settle it."""
    out = BUILD / name
    s2, sy, pay = Path(f'{out}.s2'), Path(f'{out}.sys'), BUILD / 'payload48.bin'
    s1d = dict(defines, ONELOAD=1)
    s1 = {'BSS': 0x9000, 'TSTART': 0x91}         # a guess, for the first round
    for _ in range(3):
        d2 = dict(defines, ONELOAD=1, CHAIN3=1, S1BSS=f"${s1['BSS']:04X}",
                  S1TSTART=f"${s1['TSTART']:02X}")
        mads('tape1', 'stage2.asm', s2, d2)
        bss2 = labels(f'{s2}.lab')['BSS']
        dsy = dict(defines, CHAIN=1, SYSLOAD=f'${bss2 + 0x100:04X}', PREVBSS=f'${bss2:04X}')
        mads('system', 'main.asm', sy, dsy)
        img2 = Path(f'{s2}.bin').read_bytes()
        assert 0x0800 + len(img2) == bss2
        pay.write_bytes(img2 + bytes(0x100) + Path(f'{sy}.bin').read_bytes())
        mads('tape1', 'main.asm', out, s1d)
        new = labels(f'{out}.lab')
        if new['BSS'] == s1['BSS']:
            break
        s1 = new
    else:
        sys.exit('build_oneload: stage 1 BSS did not settle')
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'mkcas.py'), f'{out}.cas',
                    '--boot', f'{out}.bin', f'{out}.lab', '--name', label], check=True)
    return [Path(f'{out}.cas')]


def build_bounce(name, defines, label):
    """The 16K+ burn-in: tape 2 with BOUNCE. Its relocation bitmap marks the
    bytes that hold its own page numbers: assembled at $0800 and at $0C00,
    those bytes differ by exactly 4 (4 pages, not 1: the screen block is
    found on a 1K boundary, so values made from it only move in steps of 4,
    which is why BOFF is a multiple of 4 too). BOFF, the distance to copy B, is a
    whole number of 1K blocks just past copy A's screen block. Checked: copy
    A patched by the bitmap must equal the stage assembled at B's address."""
    out = BUILD / name
    bmap = BUILD / 'bounce.bmap'
    tmp = Path(f'{out}.reloc')
    def asm(load, boff, path):
        mads('tape2', 'main.asm', path, dict(defines, BLOAD=f'${load:04X}', BOFF=f'${boff:02X}'))
        return Path(f'{path}.bin').read_bytes(), labels(f'{path}.lab')
    bmap.write_bytes(bytes(1))
    _, lab = asm(0x0800, 0x1C, out)
    nrel = lab['BMAP'] - 0x0800                  # bytes the bitmap covers
    bmap.write_bytes(bytes((nrel + 7) // 8))
    _, lab = asm(0x0800, 0x1C, out)
    boff = (lab['SCR1'] + 4 - 0x08 + 3) & ~3
    a0, lab = asm(0x0800, boff, out)
    a1, _ = asm(0x0C00, boff, tmp)
    assert lab['BMAP'] - 0x0800 == nrel and len(a0) == len(a1)
    bits = bytearray((nrel + 7) // 8)
    for i in range(nrel):
        d = (a1[i] - a0[i]) & 0xFF
        if d not in (0, 4):
            sys.exit(f'build_bounce: byte ${0x0800 + i:04X} moves by {d}, not 0 or 4')
        if d:
            bits[i >> 3] |= 1 << (i & 7)
    assert a0[nrel:] == a1[nrel:-2] + a0[-2:] or a0[nrel:-2] == a1[nrel:-2]
    bmap.write_bytes(bytes(bits))
    a0, lab = asm(0x0800, boff, out)             # the real one, with the bitmap
    for off in (boff, lab['BOFFXL']):            # both places copy B can go
        b0, _ = asm(0x0800 + off * 256, boff, tmp)   # as the assembler sees it
        patched = bytes((v + off) & 0xFF if bits[i >> 3] >> (i & 7) & 1 else v
                        for i, v in enumerate(a0[:nrel])) + a0[nrel:]
        if patched[:-2] != b0[:-2]:
            bad = next(i for i in range(len(b0) - 2) if patched[i] != b0[i])
            sys.exit(f'build_bounce: copy B ({off:#04x} pages up) differs at ${bad:04X}')
    print(f'{name}: copy A $0800-${lab["BSS"] - 1:04X}, copy B {boff:#04x} pages up, '
          f'{sum(bin(x).count("1") for x in bits)} relocated bytes')
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'mkcas.py'), f'{out}.cas',
                    '--boot', f'{out}.bin', f'{out}.lab', '--name', label], check=True)
    return [Path(f'{out}.cas')]


def build_one16(name, defines, label):
    """The one-load 16k RAM tape: tape 1's stage 1 (ONE16) with stage 2
    inserted at PAYAT, built to run there. Stage 1's BSS and TSTART depend
    on stage 2's size, and stage 2 on those, but no size depends on an
    address: two rounds settle it."""
    out = BUILD / name
    s2, pay = Path(f'{out}.s2'), BUILD / 'payload16.bin'
    pay.write_bytes(bytes(0x1000))
    d1 = dict(defines, ONE16=1)
    mads('tape1', 'main.asm', out, d1)
    s1 = labels(f'{out}.lab')
    for _ in range(4):
        d2 = dict(defines, ONE16=1, S2AT=f"${s1['PAYAT']:04X}", S1AGAIN=f"${s1['AGAIN']:04X}",
                  S1BSS=f"${s1['BSS']:04X}", S1TSTART=f"${s1['TSTART']:02X}")
        mads('tape1', 'stage2.asm', s2, d2)
        pay.write_bytes(Path(f'{s2}.bin').read_bytes())
        mads('tape1', 'main.asm', out, d1)
        new = labels(f'{out}.lab')
        if (new['BSS'], new['PAYAT']) == (s1['BSS'], s1['PAYAT']):
            break
        s1 = new
    else:
        sys.exit('build_one16: did not settle')
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'mkcas.py'), f'{out}.cas',
                    '--boot', f'{out}.bin', f'{out}.lab', '--name', label], check=True)
    return [Path(f'{out}.cas')]


def build_one32(name, defines, label):
    """The one-load 32k+ tape: tape 1's stage 1 (ONE16, ONE32) with, at
    PAYAT, stage 2 and then the system tests (SYSAT), all three sharing
    stage 1's BSS page. No size depends on an address: a few rounds settle
    the addresses."""
    out = BUILD / name
    s2, sy, pay = Path(f'{out}.s2'), Path(f'{out}.sys'), BUILD / 'payload16.bin'
    pay.write_bytes(bytes(0x4000))
    d1 = dict(defines, ONE16=1, ONE32=1)
    mads('tape1', 'main.asm', out, d1)
    s1 = labels(f'{out}.lab')
    sysat = s1['PAYAT'] + 0x1200
    for _ in range(5):
        common = dict(S1BSS=f"${s1['BSS']:04X}", S1TSTART=f"${s1['TSTART']:02X}",
                      S1AGAIN=f"${s1['AGAIN']:04X}")
        d2 = dict(d1, S2AT=f"${s1['PAYAT']:04X}", SYS32=f'${sysat:04X}', **common)
        mads('tape1', 'stage2.asm', s2, d2)
        b2 = Path(f'{s2}.bin').read_bytes()
        sysat = s1['PAYAT'] + len(b2)
        d2['SYS32'] = f'${sysat:04X}'
        mads('tape1', 'stage2.asm', s2, d2)
        b2 = Path(f'{s2}.bin').read_bytes()
        dsy = dict(ALL7, SETNO=4, MENU=1, CHAIN=1, SYSAT=f'${sysat:04X}',
                   SHAREBSS=f"${s1['BSS']:04X}", PREVBSS=f"${s1['BSS']:04X}",
                   RAMAGAIN=f"${s1['AGAIN']:04X}")
        mads('system', 'main.asm', sy, dsy)
        pay.write_bytes(b2 + Path(f'{sy}.bin').read_bytes())
        mads('tape1', 'main.asm', out, d1)
        new = labels(f'{out}.lab')
        if (new['BSS'], new['PAYAT']) == (s1['BSS'], s1['PAYAT']):
            break
        s1 = new
    else:
        sys.exit('build_one32: did not settle')
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'mkcas.py'), f'{out}.cas',
                    '--boot', f'{out}.bin', f'{out}.lab', '--name', label], check=True)
    return [Path(f'{out}.cas')]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fault', help='BANK,BIT[,EVERY]  (bank 0 = low RAM; EVERY: burn-in '
                    'only, inject every n-th pass)')
    ap.add_argument('--fast', action='store_true')
    ap.add_argument('--deploy', action='store_true')
    a = ap.parse_args()

    BUILD.mkdir(exist_ok=True)
    cas = []
    for src, name, stages, defs in TAPES:
        d = dict(defs, FAST=1) if a.fast else dict(defs)
        if src == 'oneload':
            cas += build_oneload(name, d, f'A8 {name.upper()}')
            continue
        if src == 'one32':
            cas += build_one32(name, d, f'A8 {name.upper()}')
            continue
        if src == 'one16':
            cas += build_one16(name, d, f'A8 {name.upper()}')
            continue
        if src == 'bounce':
            cas += build_bounce(name, d, f'A8 {name.upper()}')
            continue
        cas += build(src, name, stages, d, f'A8 {name.upper()}')
        if a.fault:
            bank, bit, *every = a.fault.split(',')
            fd = dict(d, FAULT_BANK=bank, FAULT_BIT=bit)
            tag = f'b{bank}-d{bit}'
            if every:
                if src != 'tape2':
                    continue        # only the burn-in has passes
                fd['FAULT_EVERY'] = every[0]
                tag += f'-e{every[0]}'
            cas += build(src, f'{name}-FAULT-{tag}', stages, fd,
                         f'A8 {name.upper()} FAULT {tag}')
    CASSETTES.mkdir(exist_ok=True)
    for c in cas:
        if 'FAULT' not in c.name:       # fault-injection builds stay in build/
            shutil.copy2(c, CASSETTES / c.name)
    if a.deploy:
        for c in cas:
            shutil.copy2(c, SHARE / c.name)
            print('deployed', SHARE / c.name)


if __name__ == '__main__':
    main()
