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
BUILD = ROOT / 'build'
SHARE = Path('//TRUENAS/Media/games/ATARI800')   # MiSTer Atari800 core's folder

# Each tape: source dir, name, stages (first = boot), defines. A later stage
# is told where the boot stage keeps its BSS and where its own test area ends.
# The system tapes are one main.asm with the tests picked by WANT_* defines.
# Every set shares tape 1: its stage 2 (16K and up) relocates the RAM test
# to the RAM stage 1 sat in, and tests the XL/XE extras where it finds them.
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
         ('tape1', 'diag-16k-01-ram', ['main.asm', 'stage2.asm'], {}),
         ('system', 'diag-16k-02-system', ['main.asm'],
          dict(ALL7, SETNO=1, TAPENO=2, MENU=1, BIGSTAGE=1)),
         ('tape1', 'diag-48k-01-ram', ['main.asm', 'stage2.asm'], {}),
         ('system', 'diag-48k-02-system', ['main.asm'],
          dict(ALL7, SETNO=2, TAPENO=2, MENU=1, BIGSTAGE=1)),
         ('tape2', 'diag-burnin', ['main.asm'], {})]


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
    nexts = []
    for k, asm in enumerate(stages[1:], 2):
        d = dict(defines, S1BSS=f"${s1['BSS']:04X}", S1TSTART=f"${s1['TSTART']:02X}")
        mads(src, asm, Path(f'{out}.s{k}'), d)
        nexts += ['--next', f'{out}.s{k}.bin']
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'mkcas.py'), f'{out}.cas',
                    '--boot', f'{out}.bin', f'{out}.lab', *nexts, '--name', label],
                   check=True)
    return [Path(f'{out}.cas')] + [Path(f'{out}-part{k}.cas')
                                   for k in range(2, len(stages) + 1)]


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
    if a.deploy:
        for c in cas:
            shutil.copy2(c, SHARE / c.name)
            print('deployed', SHARE / c.name)


if __name__ == '__main__':
    main()
