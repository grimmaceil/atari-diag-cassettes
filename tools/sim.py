#!/usr/bin/env python3
"""Run a boot image under py65 with a minimal Atari model and decode the
beep/flash code it produces.

Model: RAM from $0000 to --ram (a floating bus above it reads the address high
byte, as the real bus does after an abs or (zp),Y fetch), hardware registers
logged, WSYNC = one scanline. No ANTIC/GTIA/POKEY beyond that.

Real hardware faults can be simulated, independent of the FAULT build flag:
  --stuck BANK:BIT:LEVEL   e.g. 2:5:0 = bank 2 ($4000-$7FFF), D4 stuck low
  --stuck LO-HI:BIT:LEVEL  e.g. 0200-0400:1:1 = D0 stuck high in $0200-$03FF
  --stuck xN:BIT:LEVEL     the same in 130XE extended bank N (0-3, --xe)
  --mirror                 bank 3 aliases bank 2 (a missing address line)
"""
import argparse
import os
import random
import sys

from py65.devices.mpu6502 import MPU

LINES_PER_MS = 15.7


class Atari:
    """Time comes from the CPU cycle count: 114 cycles per scanline, and a
    WSYNC write skips to the start of the next line. (No DMA cycle stealing.)"""

    def __init__(self, ramtop, stuck, mirror, xl, pal, keys, xe=False, xstuck=None):
        self.ram = bytearray(0x10000)
        self.xe = xe             # 130XE: 4 x 16K at $4000 when PORTB bit 4 = 0
        self.ext = bytearray(0x10000)
        self.xstuck = xstuck     # (bank, andmask, ormask) in extended RAM
        self.xealias = False
        self.flaky = None        # (lo, hi, mask, probability)
        self.nmis = 0
        self.irqen, self.irqen_line = 0, 0
        self.stimer = None
        self.presses = []        # (start_line, end_line, kind, value)
        self.kbcode = 0xFF
        self.ramtop = ramtop
        self.stuck = stuck       # (lo, hi, andmask, ormask) or None
        self.mirror = mirror
        self.xl = xl
        self.pal = pal
        self.frame_lines = 312 if pal else 262
        self.keys = keys         # [(start_line, end_line)] a key is held
        self.mpu = None
        self.events = []         # (line, reg, value)
        self.regs = {}
        self.pm = {}            # GRACTL, PMBASE: for the P/M color mask in screen()

    def active(self, kind):
        ln = self.line
        out = []
        for st, en, k, v in self.presses:
            if k == kind and st <= ln < en:
                out.append(v)
                if k == 'KB':
                    self.kbcode = v
        return out

    def press(self, at, kind, value=None, secs=0.25):
        self.presses.append((at, at + int(secs * 1000 * LINES_PER_MS), kind, value))

    @property
    def line(self):
        return self.mpu.processorCycles // 114

    def _map(self, a):
        if self.mirror and 0x8000 <= a < 0xC000:
            return a - 0x4000
        return a

    def __getitem__(self, a):
        if isinstance(a, slice):
            return [self[i] for i in range(*a.indices(0x10000))]
        if 0xD000 <= a < 0xD800:
            if a == 0xD01F:      # console keys, 0 = pressed
                v = 0x0F
                for bit in self.active('CON'):
                    v &= ~bit
                return v
            if a == 0xD209:      # KBCODE: the last key pressed
                return self.kbcode
            if a == 0xD20A:
                return random.randrange(256)
            if a == 0xD40B:
                return (self.line % self.frame_lines) // 2
            if a == 0xD014:
                return 0x01 if self.pal else 0x0F
            if a == 0xD301:
                return self.regs.get(a, 0xFF)
            if a == 0xD20E:      # IRQST: bit 6 latches a keypress while the
                ln = self.line   # keyboard IRQ is enabled (masked or not),
                v = 0xFF         # bit 7 BREAK, bit 0 timer 1 (~4 ms after STIMER)
                if self.irqen & 0x40 and any(self.irqen_line <= s <= ln for s, e in self.keys):
                    v &= ~0x40
                if self.irqen & 0x80 and any(self.irqen_line <= e[0] <= ln
                                             for e in self.presses if e[2] == 'BREAK'):
                    v &= ~0x80
                if self.irqen & 1 and self.stimer is not None and ln - self.stimer > 63:
                    v &= ~1
                return v
            if 0xD200 <= a < 0xD208:
                return 228       # POTn: nothing plugged in
            if a == 0xD20F:      # SKSTAT: bit 2 low while a key is held, 3 SHIFT
                ln = self.line
                v = 0xFF
                if any(s <= ln < e for s, e in self.keys) or self.active('KB'):
                    v &= ~4
                if self.active('SHIFT'):
                    v &= ~8
                return v
            return 0xFF
        if a >= 0xC000 and self.os_out():
            if self.ramtop < 0xC000:
                return a >> 8    # e.g. a 16K 600XL: nothing under the OS
        elif a >= 0xC000:
            if self.xl or a >= 0xD800:
                return ((a * 31) ^ (a >> 3)) & 0xFF    # stand-in ROM bytes
            return a >> 8        # 400/800: nothing at $C000-$CFFF
        if self.ramtop <= a < 0xC000:
            return a >> 8        # floating bus
        x = self._ext(a)
        if x is not None:
            v = self.ext[x]
            if self.xstuck and x >> 14 == self.xstuck[0]:
                v = (v & self.xstuck[1]) | self.xstuck[2]
            return v
        a = self._map(a)
        v = self.ram[a]
        if self.stuck and self.stuck[0] <= a < self.stuck[1]:
            v = (v & self.stuck[2]) | self.stuck[3]
        if self.flaky and self.flaky[0] <= a < self.flaky[1] and random.random() < self.flaky[3]:
            v ^= self.flaky[2]
        return v

    def __setitem__(self, a, v):
        if 0xD000 <= a < 0xD800:
            if a == 0xD20E:
                self.irqen, self.irqen_line = v, self.line
            if a == 0xD209:
                self.stimer = self.line
            if a in (0xD01D, 0xD407):
                self.pm[a] = v
            if a == 0xD40A:
                self.mpu.processorCycles = (self.line + 1) * 114
            elif a in (0xD01A, 0xD200, 0xD201, 0xD01F, 0xD40E, 0xD400,
                       0xD402, 0xD403, 0xD302, 0xD301):
                if self.regs.get(a) != v:
                    self.events.append((self.line, a, v))
                self.regs[a] = v
            return
        if a >= 0xC000 and self.os_out():
            if self.ramtop >= 0xC000:
                self.ram[a] = v
            return
        if a >= self.ramtop or a >= 0xC000:
            return
        x = self._ext(a)
        if x is not None:
            self.ext[x] = v
            return
        self.ram[self._map(a)] = v

    def _ext(self, a):
        pb = self.regs.get(0xD301, 0xFF)
        if self.xe and 0x4000 <= a < 0x8000 and not pb & 0x10:
            bank = (pb >> 2) & 3
            if self.xealias and bank == 3:
                bank = 2         # a stuck bank-select line
            return bank * 0x4000 + a - 0x4000
        return None

    def os_out(self):
        return self.xl and not self.regs.get(0xD301, 0xFF) & 1

    def __len__(self):
        return 0x10000

    def screen(self):
        """The GRAPHICS 0 screen as text (inverse letters shown lowercase)."""
        if not self.regs.get(0xD400, 0) & 0x20:
            return '(ANTIC DMA off)'
        dl = self.regs[0xD402] | self.regs[0xD403] << 8
        rows, addr, scan = [], 0, 8
        # SIM_PMKEEP=1: show the mask even after P/M is switched off (the auto
        # responder finishes the keyboard test before most snapshot times)
        pmb = self.pm.get(0xD407, 0) << 8 if self.pm.get(0xD01D, 0) == 3 or os.environ.get('SIM_PMKEEP') and 0xD407 in self.pm else None
        for _ in range(64):
            op = self.ram[dl]
            if op == 0x41:
                break
            if op & 0x0F == 0:
                dl += 1
                scan += (op >> 4 & 7) + 1
                continue
            if op & 0x40:
                addr = self.ram[dl + 1] | self.ram[dl + 2] << 8
                dl += 3
            else:
                dl += 1
            row = ''
            for c in self.ram[addr:addr + 40]:
                ch = c & 0x7F
                ch = chr(ch + 32) if ch < 64 else '^v[]'[ch - 0x5C] if 0x5C <= ch < 0x60 else '~'
                row += ch.lower() if c & 0x80 and ch.isalpha() else (
                    '#' if c & 0x80 and ch == ' ' else ch)
            row = row.rstrip()
            if pmb is not None:     # double-line P/M: columns with color behind them
                y = scan // 2
                cols = ''.join('=' if self.ram[pmb + 0x200 + (c >> 3) * 0x80 + y] & 0x80 >> (c & 7)
                               else ' ' for c in range(32))
                cols += ''.join('=' if self.ram[pmb + 0x180 + y] & 1 << (2 * (m >> 1) + 1 - (m & 1))
                                else ' ' for m in range(8))
                if cols.strip():
                    row += '\n  |' + cols.rstrip()
            rows.append(row)
            addr += 40
            scan += 8
        return '\n'.join(f'{i:2d}|{r}' for i, r in enumerate(rows))


SIOV = 0xE459
XITVBV = 0xE462


def push(mpu, hw, v):
    hw.ram[0x100 + mpu.sp] = v & 0xFF
    mpu.sp = (mpu.sp - 1) & 0xFF


def pull(mpu, hw):
    mpu.sp = (mpu.sp + 1) & 0xFF
    return hw.ram[0x100 + mpu.sp]


def vbi(mpu, hw):
    """A VBI NMI. With the OS in, do what its NMI handler does before
    JMP (VVBLKI): push A, X, Y. With the OS out (XL/XE), the CPU takes the
    vector from RAM at $FFFA. A VVBLKI still pointing into the OS (its own
    VBI) isn't modelled: those NMIs are skipped."""
    if hw.os_out():
        vec = hw.ram[0xFFFA] | hw.ram[0xFFFB] << 8
        regs = ()
    else:
        vec = hw.ram[0x222] | hw.ram[0x223] << 8
        regs = (mpu.a, mpu.x, mpu.y)
        if vec >= 0xC000:
            return
    push(mpu, hw, mpu.pc >> 8)
    push(mpu, hw, mpu.pc)
    push(mpu, hw, mpu.p & ~mpu.BREAK)
    mpu.p |= mpu.INTERRUPT
    for r in regs:
        push(mpu, hw, r)
    mpu.pc = vec
    hw.nmis += 1


def xitvbv(mpu, hw):
    mpu.y = pull(mpu, hw)
    mpu.x = pull(mpu, hw)
    mpu.a = pull(mpu, hw)
    mpu.p = pull(mpu, hw) | mpu.UNUSED
    lo = pull(mpu, hw)
    mpu.pc = lo | pull(mpu, hw) << 8


def cas_records(path):
    import struct
    d, p, out = open(path, 'rb').read(), 0, []
    while p < len(d):
        ln = struct.unpack('<H', d[p + 4:p + 6])[0]
        if d[p:p + 4] == b'data':
            out.append(d[p + 8:p + 8 + ln])
        p += 8 + ln
    return out


def siov(mpu, hw, stream):
    """Stand-in for the OS's SIOV, cassette reads only, held to what the OS
    listing says the call needs: the cassette DCB as RBLOK builds it, short
    gaps, and interrupts running (VBI timers, serial-input IRQ). Anything
    else is a timeout ($8A)."""
    m = hw.ram
    dcb_ok = (m[0x300] == 0x60 and m[0x302] == 0x52 and m[0x303] == 0x40 and
              m[0x304] | m[0x305] << 8 == 0x3FD and m[0x308] | m[0x309] << 8 == 131
              and m[0x30B] & 0x80)
    irq_ok = not mpu.p & mpu.INTERRUPT and hw.regs.get(0xD40E, 0) & 0x40
    if dcb_ok and irq_ok and stream:
        rec = stream.pop(0)
        m[0x3FD:0x3FD + 131] = rec[:131]
        status = 1
        mpu.processorCycles += int((132 * 10 / 600 + 0.26) * 1.79e6)
    else:
        status = 0x8A
        why = 'DCB' if not dcb_ok else 'interrupts off' if not irq_ok else 'tape end'
        print(f'SIOV timeout ({why})')
    m[0x303] = status
    mpu.y = status
    mpu.p = (mpu.p & ~(mpu.NEGATIVE | mpu.ZERO)) | (mpu.NEGATIVE if status & 0x80 else 0)
    lo = m[0x100 + ((mpu.sp + 1) & 0xFF)]
    hi = m[0x100 + ((mpu.sp + 2) & 0xFF)]
    mpu.sp = (mpu.sp + 2) & 0xFF
    mpu.pc = ((hi << 8) | lo) + 1


KEYCODES = [0x00, 0x01, 0x02, 0x05, 0x06, 0x07, 0x08, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E,
            0x0F, 0x10, 0x12, 0x15, 0x16, 0x17, 0x18, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E,
            0x1F, 0x20, 0x21, 0x22, 0x23, 0x25, 0x26, 0x27, 0x28, 0x2A, 0x2B, 0x2C,
            0x2D, 0x2E, 0x2F, 0x30, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
            0x3A, 0x3C, 0x3D, 0x3E, 0x3F]   # every key all machines have


class Auto:
    """Answers tape 3's prompts as a person would, from the screen text.
    deny: prompt words to answer No to; skip: keys to leave unpressed."""
    PROMPTS = ['PRESS EVERY KEY', 'PRESS START, SELECT AND OPTION', 'HEARD IT?',
               'MOVE EACH STICK', 'UNPLUG ALL PADDLES', 'TURN EACH', 'RAMPS RIGHT?']

    def __init__(self, hw, deny, skip):
        self.hw, self.deny, self.skip, self.seen = hw, deny, skip, set()

    def check(self):
        text = self.hw.screen()
        if 'START=GO ON' in text:    # a failed test's code: go on (a press only
            ln = self.hw.line        # counts in a pause, so keep pressing)
            if not any(e > ln for st, e, k, v in self.hw.presses if k == 'CON'):
                self.hw.press(ln + 4000, 'CON', 1)
            return
        for p in self.PROMPTS:
            if p not in text:
                continue
            sig = p + '|' + '|'.join(l for l in text.splitlines() if 'VOICE' in l
                                     or 'TEST' in l or 'TAPE' in l)
            if sig in self.seen:
                continue
            self.seen.add(sig)
            self.answer(p, text)

    def answer(self, p, text):
        hw, t = self.hw, self.hw.line
        step = int(0.35 * 1000 * LINES_PER_MS)
        if p == 'PRESS EVERY KEY':
            codes = KEYCODES[:len(KEYCODES) - self.skip]
            for i, c in enumerate(codes):
                hw.press(t + (i + 1) * step, 'KB', c | (0x80 if c == 0x3F else 0))
            n = len(codes) + 1
            hw.press(t + n * step, 'SHIFT')
            hw.press(t + (n + 1) * step, 'BREAK')
            hw.press(t + (n + 3) * step, 'CON', 1)
        elif p.startswith('PRESS START'):
            for i, bit in enumerate((1, 2, 4)):
                hw.press(t + (i + 1) * 2 * step, 'CON', bit)
        else:
            yes = not any(d in text for d in self.deny)
            when = t + int(2.5 * 1000 * LINES_PER_MS)
            if p in ('HEARD IT?', 'RAMPS RIGHT?'):
                hw.press(when, 'KB', 0x2B if yes else 0x23)
            else:
                hw.press(when, 'CON', 1)        # START


def tones(events):
    """AUDC1 on/off pairs -> [(start_ms, len_ms, audf, colbk)]."""
    out, audf, col, on = [], 0, 0, None
    for line, reg, v in events:
        if reg == 0xD200:
            audf = v
        elif reg == 0xD01A:
            col = v
        elif reg == 0xD201:
            if v & 0x0F and on is None:
                on = (line, audf, col)
            elif not v & 0x0F and on is not None:
                out.append((on[0] / LINES_PER_MS, (line - on[0]) / LINES_PER_MS,
                            on[1], on[2]))
                on = None
    return out


NAMES = {72: 'L', 35: 'S', 144: 'E', 60: 'J', 47: 'J', 40: 'J'}


def decode(ts):
    """Tones -> code string like 'L2 S5 E | L2 S5 E', groups split on >500 ms
    gaps, report repeats on >2 s gaps."""
    s, prev_end, grp = [], None, []
    def flush():
        if grp:
            s.append(f'{grp[0]}{len(grp)}' if grp[0] in 'LS' else
                     ''.join(grp) if grp[0] == 'J' else grp[0] * len(grp))
    for start, ln, f, col in ts:
        n = NAMES.get(f, '?')
        if n == '?':
            continue            # the alive chirp is a sweep, not a code tone
        gap = None if prev_end is None else start - prev_end
        if gap is not None and (gap > 500 or n != grp[0]):
            flush()
            grp = []
            if gap > 2000:
                s.append('|')
        grp.append(n)
        prev_end = start + ln
    flush()
    return ' '.join(s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tape', help='a .cas (boot stage, then later stages read via SIOV) or a raw boot .bin')
    ap.add_argument('--ram', type=lambda x: int(x, 0), default=0xC000)
    ap.add_argument('--stuck')
    ap.add_argument('--mirror', action='store_true')
    ap.add_argument('--seconds', type=float, default=40,
                    help='simulated time to run after the tests finish')
    ap.add_argument('--xl', action='store_true', help='ROM at $C000 (XL/XE)')
    ap.add_argument('--xe', action='store_true', help='130XE: --xl plus 64K extended RAM')
    ap.add_argument('--xealias', action='store_true', help='extended bank 3 is bank 2')
    ap.add_argument('--pal', action='store_true')
    ap.add_argument('--key', default='', help='seconds at which a key is pressed, e.g. 3,30')
    ap.add_argument('--snap', default='', help='seconds at which to print the screen')
    ap.add_argument('--flaky', help='BANK:BIT:P  a bit that reads wrong with chance P per read')
    ap.add_argument('--insert', nargs=2, metavar=('SECONDS', 'CAS'),
                    help='start playing another tape (e.g. a -part2.cas) at that time')
    ap.add_argument('--auto', action='store_true', help='answer tape 3 prompts')
    ap.add_argument('--until', type=float, help='stop at this simulated time (s)')
    ap.add_argument('--deny', default='', help='with --auto: answer No where the screen shows these (comma list)')
    ap.add_argument('--skip', type=int, default=0, help='with --auto: leave this many keys unpressed')
    ap.add_argument('-v', action='store_true')
    a = ap.parse_args()

    stuck = xstuck = None
    if a.stuck and a.stuck.startswith('x'):
        bank, bit, lvl = a.stuck[1:].split(':')
        m = 1 << (int(bit) - 1)
        xstuck = (int(bank), 0xFF if int(lvl) else 0xFF ^ m, m if int(lvl) else 0)
    elif a.stuck:
        where, bit, lvl = a.stuck.split(':')
        bit, lvl = int(bit), int(lvl)
        m = 1 << (bit - 1)
        if '-' in where:                   # an address range: LO-HI
            lo, hi = (int(x, 16) for x in where.split('-'))
        else:
            lo, hi = (int(where) - 1) * 0x4000, int(where) * 0x4000
        stuck = (lo, hi, 0xFF if lvl else 0xFF ^ m, m if lvl else 0)

    stream = []                            # records left on the tape
    if a.tape.lower().endswith('.cas'):
        recs = cas_records(a.tape)
        nrec = recs[0][4]
        img = b''.join(r[3:131] for r in recs[:nrec])
        stream = recs[nrec + 1:]           # the OS boot also reads the EOF
    else:
        img = open(a.tape, 'rb').read()
    load = img[2] | img[3] << 8
    to_line = lambda t: int(float(t) * 1000 * LINES_PER_MS)
    keys = [(to_line(t), to_line(t) + to_line(0.25)) for t in a.key.split(',') if t]
    snaps = sorted(to_line(t) for t in a.snap.split(',') if t)
    hw = Atari(a.ram, stuck, a.mirror, a.xl or a.xe, a.pal, keys, a.xe, xstuck)
    hw.xealias = a.xealias
    if a.flaky:
        bank, bit, prob = a.flaky.split(':')
        random.seed(1)
        hw.flaky = ((int(bank) - 1) * 0x4000, int(bank) * 0x4000, 1 << (int(bit) - 1),
                    float(prob))
    for i in range(0x800):                 # OS state that must survive
        hw.ram[i] = (i * 7 + 3) & 0xFF
    lowram_before = bytes(hw.ram[:0x800])
    hw.ram[load:load + len(img)] = img

    mpu = MPU(memory=hw, pc=load + 6)
    hw.mpu = mpu
    mpu.sp = 0xF0
    limit = None
    steps = 0
    entered = set()
    insert_at = to_line(a.insert[0]) if a.insert else None
    frame = 0
    auto = Auto(hw, [d for d in a.deny.split(',') if d], a.skip) if a.auto else None
    next_auto = 0
    while True:
        if auto and hw.line >= next_auto:
            next_auto = hw.line + 8000
            if hw.regs.get(0xD400, 0) & 0x20:
                auto.check()
        f = (hw.line - 248) // hw.frame_lines      # VBI at line 248
        if f != frame:
            frame = f
            if hw.regs.get(0xD40E, 0) & 0x40:
                vbi(mpu, hw)
        if mpu.pc == XITVBV:
            xitvbv(mpu, hw)
            continue
        if insert_at is not None and hw.line >= insert_at:
            stream[:] = cas_records(a.insert[1])
            insert_at = None
            print(f'tape {a.insert[1]} started at {hw.line / LINES_PER_MS / 1000:.1f} s')
        if mpu.pc == SIOV:
            siov(mpu, hw, stream)
            continue
        if mpu.pc == 0x2006 and 0x2006 not in entered:
            entered.add(0x2006)
            print(f'stage 2 entered at {hw.line / LINES_PER_MS / 1000:.1f} s')
        mpu.step()
        steps += 1
        if snaps and hw.line >= snaps[0]:
            print(f'--- screen at {snaps.pop(0) / LINES_PER_MS / 1000:.1f} s'
                  f'  COLBK ${hw.regs.get(0xD01A, 0):02X}')
            print(hw.screen())
        # The tests are over once the reporter starts its first flash.
        if limit is None and any(r == 0xD201 and v & 0x0F and ln > 4000
                                 for ln, r, v in hw.events):
            limit = hw.line + a.seconds * 1000 * LINES_PER_MS
            t_done = hw.line / LINES_PER_MS / 1000
        if limit is not None and hw.line > limit:
            break
        if a.until and hw.line > a.until * 1000 * LINES_PER_MS:
            if limit is None:
                t_done = 0
            break
        if steps > 400_000_000:
            sys.exit('runaway: no report produced')

    ts = tones(hw.events)
    if a.v:
        for t in ts:
            print(f'{t[0]:9.0f} ms {t[1]:5.0f} ms audf {t[2]:3d} colbk ${t[3]:02X}')
    bss = load + len(img)
    if 0x2006 in entered:                  # stage 2's BSS follows its image
        bss = 0x2000 + hw.ram[0x2001] * 128
    bad = [hw.ram[bss + 0x40 + b] for b in range(10)]
    print(f'first result at {t_done:.1f} s, {steps} steps, {hw.nmis} VBIs, '
          f'ended at {hw.line / LINES_PER_MS / 1000:.0f} s')
    print('--- final screen'); print(hw.screen())
    print('BADMASK[1..9]', ' '.join(f'${b:02X}' for b in bad[1:]),
          ' RAMTOP $%02X00' % hw.ram[bss + 0x12], ' NBANKS', hw.ram[bss + 0x11])
    for b in range(1, 10):
        if bad[b]:
            r = lambda o: hw.ram[bss + o + b]
            print(f'  bank {b}: first ${r(0x80):02X}{r(0x70):02X} wrote ${r(0x90):02X}'
                  f' read ${r(0xA0):02X} count {r(0x50) | r(0x60) << 8}')
    # Low RAM must come through intact, apart from what the stage itself
    # uses once low RAM has passed: its zero page pointers and the stack page.
    # SIO's control block, the cassette buffer and the display shadows are
    # written on purpose for the stage 2 load; burn-in sets VVBLKI and keeps
    # its log in $0500-$06FF.
    sio = set(range(0x300, 0x30C)) | set(range(0x3FD, 0x480)) | {0x22F, 0x230, 0x231,
          0x2C5, 0x2C6, 0x2C8, 0x2F3, 0x2F4, 0x4D, 0x222, 0x223} | set(range(0x500, 0x700))
    keep = [i for i in range(0x800) if not (0x80 <= i < 0x90 or 0x100 <= i < 0x200
                                            or i in sio)]
    print('low RAM preserved:', all(hw.ram[i] == lowram_before[i] for i in keep))
    print('code:', decode(ts))


if __name__ == '__main__':
    main()
