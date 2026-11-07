# A8 Cassette Diagnostics

Bootable cassette diagnostics for Atari 8-bit computers (400, 800, XL, 130XE).
Each tape reports with synchronized beeps and border flashes first, so it is
useful before the video works. A text screen comes in only once the display
hardware checks out.

There are three sets, one per RAM size, so a tape never needs more RAM than
the machine has, and bigger machines load in fewer steps:

| Set | For | Tapes |
|---|---|---|
| `diag-400-*` | 8K 400 | 01 RAM, then four small tapes that each fit 8K by themselves: 02 ROMs, 03 input, 04 ports, 05 sound and video |
| `diag-16k-*` | 16K-32K 400/800 | 01 RAM, 02 system: all seven tests in one load, with a menu |
| `diag-48k-*` | 48K 800, XL/XE | as 16k. This set is where the RAM-hungry graphics and sound tests will go. |
| `diag-burnin` | all | one version |

The tapes of a set run in order. Each one relies only on what the earlier
ones proved; for example, the keyboard is tested before any test asks a Y/N
question.

The system tape's menu (16k/48k):
- START runs the highlighted test, SELECT moves down, OPTION moves up, and the
  keys 1-7 run that test.
- After a test the menu comes back with the next test highlighted, so
  pressing START again and again walks through them.
- Left alone for 10 s at power-on, it runs them all in order, then shows the
  results and plays the final code.

The 400 set, tape by tape:

| Tape | File | What it does |
|---|---|---|
| 1 | `diag-400-01-ram.cas` | Low RAM, then the main RAM banks with March C- and address-in-address tests. On 16K and up, a second stage also tests the RAM the first stage sat in, the RAM under the XL/XE OS ROM, and the 130XE's four extended banks. Every set has this tape. |
| 2 | `diag-400-02-rom.cas` | Test 1: the OS chips, BASIC or a cartridge, and the font, identified by CRC32 against published tables. On the 400/800 each chip is named, so a repaired board with mixed revisions shows up. |
| 3 | `diag-400-03-input.cas` | Test 2: the keyboard, as a map with three key states (not pressed, done, held) told apart by brightness. Test 3: the console keys and speaker. |
| 4 | `diag-400-04-ports.cas` | Test 5: joysticks, live, on all four ports. Test 6: paddles, with an open-input check, then value, min/max, jitter and trigger. |
| 5 | `diag-400-05-av.cas` | Test 4: the POKEY timer, RANDOM and the four voices by ear. Test 7: GTIA luminance and hue ramps. |
| - | `diag-burnin.cas` | Every machine. It loops the RAM tests until a key is pressed, with a clock, a pass count and a log of the first and last failure for each bit, and flags intermittent faults. |

A test's number (and so its beep code) is the same on every tape.

The `-part2.cas` files hold stage 2 alone. Use them if your tape player or
emulator doesn't stop between stages.

Booting: hold START at power-on (START+OPTION on an XL to leave BASIC out),
wait for the beep, start the tape and press a key. The design, the beep and
flash code, and the open items are in
[`Atari-diag-cassette-scope.md`](Atari-diag-cassette-scope.md).

## Reading the beeps

- **Pass:** a green border and a short jingle, then one flash for each bank
  (or test) that passed.
- **Fail:** a red border. The long beeps give the bank (or test) number, the
  short beeps give the bit (or item), and a low tone ends each fault.
- **During a result:** START goes on, SELECT replays the code, and OPTION
  switches between the text screen and full-screen flashes.

## Building

You need Python 3 and the [MADS](https://github.com/tebe6502/Mad-Assembler)
assembler. Put `mads.exe` in `tools/bin/` (built and tested with MADS 2.1.9
on Windows).

```
python tools/build.py              # all tapes into build/
python tools/build.py --fault 2,5  # tape 1 with a stuck bit 5 in bank 2, to hear a fail code
python tools/sim.py build/03-system.cas --auto --until 400   # run a tape in the simulator
```

`tools/sim.py` is a cycle-timed 6502 simulator for the tapes; it uses
[py65](https://github.com/mnaberez/py65) (`pip install py65`). It models the
cassette boot, SIO stage loads, RAM faults (stuck bits, flaky bits, mirrors),
XL/XE banking, keys and joysticks. It prints the screen and decodes the beep
code. `tools/gen_kbmap.py` regenerates the tape 3 keyboard map.

## Authorship

The author has programmed 6502 machine language and assembler since
childhood. Even so, all of the code and documents here are, for now, 100%
written by AI (Claude, by Anthropic). The author directs the work, reviews it
and tests it on hardware.

## Status

The RAM tape and the burn-in have been run on a MiSTer Atari800 core. The
other tapes have only been run in the simulator so far.

Issues and pull requests are the way to reach the author; email is not
checked.
