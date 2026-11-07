# A8 Cassette Diagnostics

Bootable cassette diagnostics for Atari 8-bit computers (400, 800, XL, 130XE).
Each tape reports with synchronized beeps and border flashes first, so it is
useful before the video works. A text screen comes in only once the display
hardware checks out.

| Tape | File | What it does |
|---|---|---|
| 1 | `diag-01-boot-ram.cas` | Low RAM, then the main RAM banks with March C- and address-in-address tests. On the XL/XE it also tests the RAM under the OS ROM, and on the 130XE the four extended banks. Two stages; stage 2 needs 16K. |
| 2 | `diag-02-ram-burnin.cas` | Loops the RAM tests until a key is pressed. It keeps a clock, a pass count and a log of the first and last failure for each bit, and flags intermittent faults. |
| 3 | `diag-03-system.cas` | 1 ROM checksums, 2 keyboard, 3 console keys and speaker, 4 POKEY, 5 joysticks, 6 paddles, 7 GTIA. Two stages; an 8K 400 gets tests 2-3. |

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

## Status

Tapes 1 and 2 have been run on a MiSTer Atari800 core. Tape 3 has only been
run in the simulator so far. The ROM checksums are shown raw; there is no
revision table yet.

Issues and pull requests are the way to reach the author; email is not
checked.
