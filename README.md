# A8 Cassette Diagnostics

Diagnostic tapes for every Atari 8-bit computer: the 400, 800, 1200XL,
600XL, 800XL, 65XE, 800XE, 130XE and XE Game System. Load one like
any cassette program and it tests the machine: RAM, ROMs, keyboard, console
keys, joysticks, paddles, sound and video, plus a memory test (burn-in) for faults that
come and go.

It reports by **border colour and beeps** first, so it works even when the
picture doesn't. Text appears on screen once the screen itself has been
checked.

**Why cassette:** a cassette boot needs the least of the machine: no disk
drive, no DOS, just the computer, its OS and the first few K of RAM. So it
runs on an 8K Atari 400 and on machines too sick to boot a disk. Tape is
slow (about 3K a minute), so there are three sets, by RAM size: the more
RAM, the fewer tapes. Each set works on every machine with at least that
much RAM, newer models included. With a disk drive, the 32k+ tape and the
memory test also come as **disk files** (`.xex`, in `disks/`) that load in
seconds.

Version 0.2.

![The menu](docs/img/system-01-menu.png)

## Get started

1. Pick the tapes by RAM: the biggest set the machine has the RAM for.

   | RAM | Tapes (in `cassettes/`) |
   |---|---|
   | 8K or more (every Atari) | the 400 set: `diag-400-01-ram` to `diag-400-05-av`, about 2 min each; long test `diag-400-memtest` |
   | 16K or more | the 16k set: `diag-16k-01-ram`, `diag-16k-02-system`, about 3.5 min each; long test `diag-memtest` |
   | 32K or more (an 800 with 32K-48K, any 64K or 128K XL/XE) | the 32k+ tape: `diag-32k-xl-xe`, one tape, about 6 min; long test `diag-memtest` |
   | keyboard, joysticks, paddles only (16K or more) | `diag-controls`: no test harness needed; goes with Atari's SALT disks |
   | with a disk drive or a MiSTer: 32K or more | `disks/diag-32k-xl-xe.xex` (the 32k+ tape); long test `disks/diag-memtest.xex` (16K) |

   A machine that won't get through its own set: use the 400 set. A tape
   that needs more RAM than the machine has stops at once: red border, a
   low tone on and off.

2. Take out any cartridge, then load the first tape: hold START, switch the
   machine on, start the tape and press a key when it beeps. You can
   use a MiSTer, a PC with a USB-SIO cable and AspeQt, or a real cassette.
3. Watch and listen: green is good, red plus beeps is a fault. Long beeps
   say where (RAM bank or test number), short beeps say what (data bit or
   item).

**[The user guide](docs/USER-GUIDE.md)** explains every screen, the colours
and beeps, loading from a PC, and what to do when something fails.

## Versions

- **0.2** (2026-11-08)
  - Disk files: `diag-32k-xl-xe.xex` (32K) and `diag-memtest.xex` (16K),
    for DOS 2.0S/2.5, MyDOS, the MiSTer's XEX loader, AspeQt and FujiNet.
    The same tests as their tapes; the title bar says XEX. A machine with
    too little RAM, or a DOS in the way, gets a plain message before the
    file loads.
  - The tapes are unchanged (byte for byte the same as 0.1.2).
- **0.1.2** (2026-11-08)
  - Every tape that needs more than 8K checks the RAM first. On a machine
    with too little it stops at once, with a red border and a low tone on
    and off, instead of giving a meaningless code.
  - The documents pick tapes by RAM, for every Atari 8-bit model.
  - The leftover code of the old 48k+ tape is gone (the other tapes are
    unchanged by that).
- **0.1.1** (2026-11-08)
  - The 16k RAM tape and the 32k+ tape (it replaces the 48k+ tape) are one
    load each, and test their own RAM too. The 32k+ menu has `0 RAM TEST
    AGAIN`.
  - The machine's real RAM is reported (64K on an 800XL, 128K on a 130XE),
    a plugged-in cartridge shows as `CART IN`, and XL/XE BASIC is switched
    off for the RAM test.
  - Every screen's title bar names the tape; the `FOUND:` line below it is
    what the tape detected.
  - GTIA test: the word ATARI in players and missiles, scrolling, with a
    display-list-interrupt rainbow.
  - New `diag-controls` tape: keyboard, joysticks and paddles only.
  - At the end of a tape, START runs the tests again; the ROM test waits for
    a key so you can read it; the summaries name the next tape.
  - The burn-in is renamed the memory test (`diag-memtest`,
    `diag-400-memtest`).
  - Fixed: the keyboard test's stray lines on the INV key; a scrambled
    screen in the 32k+ tape's ROM test on the XL/XE.
- **0.1** (2026-11-07): the first release.

## For developers

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers building from source, the
simulator, the source layout and the attributions. The design notes are in
[Atari-diag-cassette-scope.md](Atari-diag-cassette-scope.md).

## Authorship and status

The author has programmed 6502 machine language and assembler since
childhood. Even so, all of the code and documents here are, for now, 100%
written by AI (Claude, by Anthropic). The author directs the work, reviews
it and tests it on hardware.

Tested on a MiSTer Atari800 core and in the project's
simulator; not yet on a real 400, 800, XL or XE. Issues and pull requests
are the way to reach the author; email is not checked.
