# Development

Version 0.1.1. This is for anyone who wants to build the tapes from source,
change them, or check how they work. To test a machine you only need the `.cas` files in
`cassettes/` and the [user guide](USER-GUIDE.md).

## Authorship

The author has programmed 6502 machine language and assembler since
childhood. Even so, the code, tools and documents here are, for now, 100%
written by AI (Claude, by Anthropic). The author directs the work, reviews it
and tests it on hardware: a MiSTer Atari800 core so far.

## Environment

The tapes were built and tested with:

| What | Version | Notes |
|---|---|---|
| Windows 11 | | any OS with Python and MADS works |
| [MADS](https://github.com/tebe6502/Mad-Assembler) (Mad-Assembler) | 2.1.9 | put `mads.exe` in `tools/bin/` (not in git) |
| Python | 3.12 | |
| [py65](https://github.com/mnaberez/py65) | 1.x | `pip install py65`: the 6502 core in the simulator |
| [Pillow](https://python-pillow.org/) | 13 | `pip install pillow`: only for the documentation pictures |
| MiSTer Atari800 core | | the hardware tests so far |

## Building

```
python tools/build.py              # every tape: build/ (all output), cassettes/ (the release tapes)
python tools/build.py --nodeploy   # the same, without copying the changed tapes to the MiSTer share
python tools/build.py --fault 2,5  # extra builds with a stuck bit 5 in bank 2, to hear a fail code
python tools/build.py --fast       # skip the $55/$AA march pass (quicker runs)
```

Every build copies the release tapes that changed to the share
(`SHARE` in `tools/build.py`, the MiSTer core's `_diag` folder), so a new
build can be tried on the MiSTer at once. A copy that fails (the share
offline, or a tape in use) prints `NOT deployed` and the build goes on.
FAST and fault builds are never copied.

`tools/build.py` holds the list of tapes (`TAPES`) and the share path
(`SHARE`). Some tapes need more than a plain assemble:
- The one-load RAM tapes, 16k (`build_one16`) and 32k+ (`build_one32`):
  tape 1's stage 1 (ONE16) with stage 2 and, for 32k+, the system tests,
  inserted into the same image at the addresses they were built for, all
  sharing stage 1's BSS page. Stage 2 tests stage 1's RAM page by page
  (`src/common/pagetest.asm`). The addresses depend on the sizes and not
  the other way round, so a few rounds settle them.
- The 16K+ memory test (`build_bounce`): a relocation bitmap, made by
  assembling at $0800 and at $0C00. The build then proves it, byte for
  byte, against the code assembled at both addresses the second copy can
  go to.
- `build_oneload` (the earlier 48k+ tape: stage 1 at $4000 with a payload
  copied down to $0800) is kept but no longer in `TAPES`.
- The two-stage tapes: `tools/mkcas.py` writes each stage as its own file on
  the tape, with an end-of-file record after each.

`tools/gen_kbmap.py` regenerates `src/system/kbmap.asm`, the keyboard map.

## Source layout

| Path | What |
|---|---|
| `src/common/` | shared code: boot (alive, checksum, low RAM test, size probe), display checks, the beep and flash reporter, the text screen, the RAM tests, XL/XE RAM, the stage loader |
| `src/tape1/` | the RAM tape: stage 1, and stage 2 (relocated test, RAM under the OS, 130XE banks) |
| `src/tape2/` | the memory test (one source, two builds: `diag-400-memtest` with OWNTEST and NOXL, `diag-memtest` with BOUNCE) |
| `src/system/` | the system tests: `main.asm` builds a tape from the tests that `WANT_*` defines pick; one file per test (`t_rom`, `t_kb`, `t_con`, `t_joy`, `t_pad`, `t_pok`, `t_gtia`); `common.asm` has the test flow and the menu |
| `tools/` | build, CAS writer, simulator, keyboard map, documentation pictures |
| `cassettes/` | the release tapes |
| `Atari-diag-cassette-scope.md` | the design: constraints, the feedback code, memory use, the ROM table, open items |

## The simulator

`tools/sim.py` runs a tape on a cycle-timed 6502 (py65), with 114 cycles a
scan line and a floating bus. It models:
- the cassette boot, and later stages read through a stand-in for the OS's
  SIOV
- RAM faults: stuck bits (`--stuck`), flaky bits (`--flaky`), mirrored banks
  (`--mirror`), and 130XE bank aliasing
- XL/XE banking, the RAM under the OS, the 130XE banks, the self-test ROM
- the VBI, the keyboard, console keys, joysticks and paddles, and POKEY's
  interrupt latches
- real OS and BASIC ROMs (`--osrom`, `--basic`), or made-up ROM bytes
  without them. `--forge` gives the made-up 400/800 OS chips chosen CRC32s,
  to test the ROM names.

It doesn't model ANTIC running a display list from memory that changes
under it: the screen picture always comes from the display list the program
set up. So a fault where ANTIC goes astray (as the 32k+ ROM test once did,
with the self-test ROM switched in over its screen) only shows on the
MiSTer or real hardware.

It prints the screen as text, decodes the beep code, and can save the screen
as a picture. `--auto` answers the prompts as a person would; `--menuwalk`
runs the menu's tests one by one.

```
python tools/sim.py cassettes/diag-400-03-input.cas --auto --until 90
python tools/sim.py cassettes/diag-400-01-ram.cas --stuck 2:5:1 --until 200
python tools/sim.py cassettes/diag-32k-xl-xe.cas --xl --auto --until 900
```

A run takes minutes: py65 is pure Python. `tools/docshots.py` runs its
scenarios in parallel, one process each.

## Documentation pictures

`python tools/docshots.py` runs the simulator on the release tapes and saves
the screens in `docs/img/`. It needs real ROMs (`--sysroms`) for the font and
the ROM names, and the MiSTer core's palette file (`--palette`, `ntsc.act`),
so the colors are the core's. Neither is in this repository.

Each scenario in `RUNS` takes a picture a set time after some text first
shows on screen. A trigger that starts with `^` must be at the start of a
screen row: the RAM tapes' page test shows the program's own pages,
strings and all, in the top rows, which would trip a plain match. `ANNOT`
holds the numbered callouts; `--annotate` redraws them without running the
simulator. The raw screens go to `docs/img/raw/` (not in git).

## Attributions

- **ROM identification:** the CRC32 table combines these sources. The
  design doc (section 10a) records how they cross-check.
  - the [atari800 emulator](https://github.com/atari800/atari800)'s
    `src/sysrom.c`, for whole images
  - [MAME](https://github.com/mamedev/mame)'s `src/mame/atari/atari400.cpp`,
    per chip
  - Freddy Offenga's *Atari 8-bit Operating Systems* (OSROMS.TXT v3.3), for
    dates, systems and part numbers
- **Hardware facts** (memory map, banking, registers) come from general
  Atari knowledge, not yet checked line by line against a book. Checking
  them against *Mapping the Atari* is an open item.
- **AspeQt** (Fatih Aygün and contributors) for cassette playback over
  SIO2PC.
- **MADS** by Tomasz Biela (Tebe); **py65** by Mike Naberezny.
- The tapes contain no Atari ROM code. The simulator and the documentation
  pictures used the author's own ROM files, which are not distributed here.
