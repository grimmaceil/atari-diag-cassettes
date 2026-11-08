#!/usr/bin/env python3
"""Make the user guide's pictures: run the simulator on the release tapes and
save screens as PNGs (docs/img), plus color swatches and their RGB values.

The pictures use the MiSTer Atari800 core's NTSC palette (ntsc.act) and the
font from a real OS ROM, so the colors are the ones the core shows. ROMs and
palette are not in the repo: point --sysroms and --palette at your own.

    python tools/docshots.py [--sysroms DIR] [--palette FILE] [--only NAME]
"""
import argparse
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IMG = ROOT / 'docs' / 'img'      # the guide's pictures, with callouts
RAW = IMG / 'raw'                # the screens as captured
CAS = ROOT / 'cassettes'
SHARE = Path('//TRUENAS/Media/games/ATARI800')

OS800 = 'Atari 400-800 OS rev B NTSC - CRC 0E86D61D.rom'
OSXL = 'Atari XL-XE OS rev 2 - 800XL 65XE 130XE - 1983-05-10 - CRC 1F9CD270.rom'
BASIC = 'BASIC - Revision A.rom'

# name: (tape, simulator arguments, [(screen text, delay s, picture)]). The
# one-load 16k and 32k+ tapes run from FAST builds (build_one16/build_one32
# with FAST=1, made by fastbuilds() into build/): the same screens, a fraction
# of the simulator's time (py65 is slow on a big march).
RUNS = {
    'ram-pass': ('diag-400-01-ram', ['--ram', '0x4000', '--key', '10', '--until', '300'], [
        ('CAN YOU READ', 2, 'ram-01-video-check'),
        ('TESTING BANK 1', 1, 'ram-02-testing'),
        ('ALL RAM PASSED', 2, 'ram-03-pass'),       # (past the jingle: steady
        ('ALL PASSED. NEXT', 2, 'ram-04-summary')]),  # green, not a flash gap)
    'ram-fail': ('diag-400-01-ram', ['--ram', '0x4000', '--stuck', '3000-30FF:5:1', '--until', '200'], [
        ('BITS D4', 1, 'ram-05-fail')]),
    'rom-400': ('diag-400-02-rom', ['--ram', '0xA000', '--auto', '--basic', '@BASIC',
                                    '--until', '60'], [
        ('TEST 1 PASS', 1, 'rom-01-400')]),
    'rom-xl': ('diag-400-02-rom', ['--xl', '--auto', '--basic', '@BASIC', '--until', '60'], [
        ('TEST 1 PASS', 1, 'rom-02-xl')]),
    'input': ('diag-400-03-input', ['--auto', '--until', '90'], [
        ('KEYS LEFT 2', 0.1, 'input-01-keyboard'),
        ('HEARD IT?', 1, 'input-02-console'),
        ('3 CONSOLE KEYS', 1, 'input-03-results')]),
    'input-fail': ('diag-400-03-input', ['--auto', '--skip', '5', '--until', '60'], [
        ('START=GO ON', 1, 'input-04-fail')]),
    'ports': ('diag-400-04-ports', ['--auto', '--until', '90'], [
        ('STICK 4', 1, 'ports-01-joysticks'),
        ('VAL MIN MAX', 2, 'ports-02-paddles')]),
    'av': ('diag-400-05-av', ['--auto', '--until', '120'], [
        ('PLAYING VOICE 2', 0.4, 'av-01-pokey'),
        ('RAMPS RIGHT?', 1, 'av-02-gtia')]),
    'menu': ('diag-16k-02-system', ['--ram', '0x8000', '--auto', '--until', '400'], [
        ('^START=RUN', 0.5, 'system-01-menu'),
        ('^START=MENU', 1, 'system-02-results')]),
    '16k': ('build/t16-fast', ['--ram', '0x4000', '--key', '10', '--until', '400'], [
        ('^START=AGAIN', 2, '16k-01-summary')]),
    '32k-sum': ('build/t32-fast', ['--xl', '--basic', '@BASIC', '--key', '10',
                                   '--until', '600'], [        # (no --auto: it waits)
        ('^START=SYSTEM TESTS', 2, '32k-01-summary')]),
    '32k': ('build/t32-fast', ['--xl', '--auto', '--basic', '@BASIC', '--key', '10',
                               '--until', '1200'], [
        ('^START=RUN', 0.5, '32k-02-menu'),
        ('^START=MENU', 1, '32k-03-results')]),
    'memtest': ('diag-memtest', ['--ram', '0x8000', '--stuck', '23FC-23FF:3:1',
                                 '--key', '150', '--until', '220'], [
        ('PASS 4', 3, 'memtest-01-running'),
        ('FIX SOLID', 1, 'memtest-02-summary')]),
    # the screen sweep is timed, not text-triggered: at 10 s on 8K it is on
    # row 13 (the save-page churn and the sweep alternate every pass)
    'memtest-sweep': ('diag-400-memtest', ['--ram', '0x2000', '--until', '11',
                                           '--shot', '10:@RAW/memtest-03-sweep.png'], []),
}

# The guide's callouts: picture -> [(first text row, last text row, number)].
# Each is a bracket in the right border beside those rows, with its number.
ANNOT = {
    'ram-01-video-check': [(2, 4, 1), (6, 6, 2), (8, 10, 3), (11, 12, 4), (14, 21, 5)],
    'ram-02-testing': [(2, 3, 1), (5, 5, 2)],
    'ram-03-pass': [(4, 4, 1), (6, 9, 2), (20, 21, 3), (23, 23, 4)],
    'ram-04-summary': [(5, 7, 1), (8, 11, 2), (14, 16, 3)],
    'ram-05-fail': [(4, 4, 1), (6, 7, 2), (20, 21, 3)],
    'rom-01-400': [(5, 7, 1), (8, 8, 2), (9, 9, 3), (21, 23, 4)],
    'rom-02-xl': [(5, 5, 1), (6, 6, 2), (7, 7, 3), (21, 23, 4)],
    'input-01-keyboard': [(8, 12, 1), (13, 13, 2), (14, 14, 3)],
    'input-02-console': [(5, 6, 1), (8, 8, 2), (11, 12, 3)],
    'input-04-fail': [(8, 12, 1), (13, 13, 2), (14, 14, 3), (21, 21, 4), (23, 23, 5)],
    'ports-01-joysticks': [(7, 10, 1)],
    'ports-02-paddles': [(5, 5, 1), (7, 7, 2), (8, 15, 3)],
    'av-01-pokey': [(5, 5, 1), (7, 7, 2), (8, 8, 3)],
    'av-02-gtia': [(3, 3, 1), (5, 11, 2), (13, 20, 3), (21, 21, 4)],
    'system-01-menu': [(4, 10, 1), (11, 11, 2), (12, 12, 3), (18, 19, 4)],
    'system-02-results': [(4, 10, 1), (12, 16, 2)],
    '16k-01-summary': [(5, 7, 1), (8, 11, 2), (14, 16, 3), (23, 23, 4)],
    '32k-01-summary': [(5, 7, 1), (8, 12, 2), (14, 16, 3), (23, 23, 4)],
    '32k-02-menu': [(4, 10, 1), (11, 11, 2), (12, 12, 3), (13, 13, 4), (18, 19, 5)],
    '32k-03-results': [(4, 10, 1), (11, 11, 2), (13, 16, 3)],
    'memtest-01-running': [(5, 5, 1), (6, 6, 2), (8, 9, 3), (23, 23, 4)],
    'memtest-02-summary': [(5, 6, 1), (8, 9, 2)],
    'memtest-03-sweep': [(13, 13, 1)],
}


def annotate(pic, marks):
    """Brackets and numbers in the right border (the pictures are 2x: text
    row r is y 48 + 16r, the text area ends at x 704)."""
    from PIL import Image, ImageDraw, ImageFont
    path = RAW / f'{pic}.png'
    if not path.exists():
        return
    im = Image.open(path).convert('RGB')
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype('arialbd.ttf', 15)
    except OSError:
        font = ImageFont.load_default()
    for r0, r1, n in marks:
        y0, y1 = 48 + 16 * r0 + 1, 48 + 16 * (r1 + 1) - 2
        d.line([(708, y0), (714, y0), (714, y1), (708, y1)], fill=(255, 255, 255), width=2)
        cy = (y0 + y1) // 2
        d.ellipse([720, cy - 11, 742, cy + 11], fill=(255, 255, 255), outline=(0, 0, 0))
        d.text((731, cy), str(n), fill=(0, 0, 0), font=font, anchor='mm')
    im.save(IMG / f'{pic}.png')


# Colors the guide explains: (name, Atari color value, meaning).
COLORS = [
    ('green', 0xC8, 'alive; a pass'),
    ('green flash', 0xCC, 'a pass beep: the jingle, one long flash per bank or test'),
    ('red flash', 0x38, 'a fault beep: long = where, short = which bit or item'),
    ('yellow', 0x1C, 'testing (a hang shows yellow); burn-in: an intermittent fault seen'),
    ('red', 0x34, 'a fault: the beep code follows'),
    ('purple', 0x56, 'waiting for you: a question, or the video check\'s last chance'),
    ('black', 0x00, 'the text background'),
    ('text', 0x0C, 'the text (luminance 12)'),
]


def run(name, sysroms, palette):
    tape, args, shots = RUNS[name]
    osrom = OSXL if '--xl' in args or '--xe' in args else OS800
    args = [str(sysroms / BASIC) if x == '@BASIC' else x.replace('@RAW', str(RAW))
            for x in args]
    cas = ROOT / f'{tape}.cas' if '/' in tape else CAS / f'{tape}.cas'
    cmd = [sys.executable, str(ROOT / 'tools' / 'sim.py'), str(cas),
           '--osrom', str(sysroms / osrom), '--palette', str(palette),
           '--seconds', '999', *args]
    for text, delay, pic in shots:
        cmd += ['--shoton', f'{text}@{delay}@{RAW / (pic + ".png")}']
    r = subprocess.run(cmd, capture_output=True, text=True)
    got = [l for l in r.stdout.splitlines() if l.startswith('shot ')]
    missing = [p for _, _, p in shots if not any(p in g for g in got)]
    return name, got, missing, r.stderr[-400:]


def swatches(palette):
    from PIL import Image
    pal = palette.read_bytes()
    out = []
    for name, c, meaning in COLORS:
        rgb = tuple(pal[(c & 0xFE) * 3:(c & 0xFE) * 3 + 3])
        Image.new('RGB', (48, 24), rgb).save(IMG / f'color-{name.replace(" ", "-")}.png')
        out.append({'name': name, 'atari': f'${c:02X}', 'rgb': '#%02X%02X%02X' % rgb,
                    'meaning': meaning})
    (IMG / 'colors.json').write_text(json.dumps(out, indent=1))
    return out


def fastbuilds():
    sys.path.insert(0, str(ROOT / 'tools'))
    import build
    build.build_one16('t16-fast', {'FAST': 1}, 'T16 FAST')
    build.build_one32('t32-fast', {'FAST': 1}, 'T32 FAST')
    build.main.__globals__['sys'].argv = ['build.py']
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'build.py')], check=True,
                   capture_output=True)    # the release tapes back in cassettes/


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sysroms', type=Path, default=SHARE / '_sysroms')
    ap.add_argument('--palette', type=Path, default=SHARE / 'ntsc.act')
    ap.add_argument('--only', action='append')
    ap.add_argument('--annotate', action='store_true', help='only redraw the callouts')
    ap.add_argument('--nofast', action='store_true', help='use the FAST builds already in build/')
    a = ap.parse_args()
    if a.annotate:
        for pic, marks in ANNOT.items():
            annotate(pic, marks)
        return
    RAW.mkdir(parents=True, exist_ok=True)
    for c in swatches(a.palette):
        print(f"{c['name']:10s} {c['atari']}  {c['rgb']}")
    names = a.only or list(RUNS)
    if {'16k', '32k', '32k-sum'} & set(names) and not a.nofast:
        fastbuilds()
    with ThreadPoolExecutor(len(names)) as ex:
        for name, got, missing, err in ex.map(lambda n: run(n, a.sysroms, a.palette), names):
            print(f'{name}: {len(got)} pictures' + (f', MISSING {missing}' if missing else ''))
            for _, _, pic in RUNS[name][2]:
                if pic in ANNOT and pic not in missing:
                    annotate(pic, ANNOT[pic])
            if missing and err.strip():
                print('   ', err.strip().splitlines()[-1])
    for pic, marks in ANNOT.items():    # every picture again, timed shots too
        annotate(pic, marks)            # (a --shot run lists no pictures)


if __name__ == '__main__':
    main()
