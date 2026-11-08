# A8 Cassette Diagnostics

Diagnostic tapes for the Atari 400, 800, XL and XE computers. Load one like
any cassette program and it tests the machine: RAM, ROMs, keyboard, console
keys, joysticks, paddles, sound and video, plus a memory test (burn-in) for faults that
come and go.

It reports by **border colour and beeps** first, so it works even when the
picture doesn't. Text appears on screen once the screen itself has been
checked.

![The menu](docs/img/system-01-menu.png)

## Get started

1. Pick the tapes for your machine:

   | Your machine | Tapes (in `cassettes/`) |
   |---|---|
   | 400 with 8K | `diag-400-01-ram` to `diag-400-05-av`, then `diag-400-memtest` |
   | 400/800 with 16K | `diag-16k-01-ram`, `diag-16k-02-system`, `diag-memtest` |
   | 800 with 32K-48K, XL, XE | `diag-32k-xl-xe` (one tape), `diag-memtest` |
   | anything that won't get through its own set | the 400 set |
   | keyboard, joysticks, paddles only (16K+) | `diag-controls`: no test harness needed; goes with Atari's SALT disks |

2. Take out any cartridge, then load the first tape: hold START, switch the
   machine on, start the tape and press a key when it beeps. You can
   use a MiSTer, a PC with a USB-SIO cable and AspeQt, or a real cassette.
3. Watch and listen: green is good, red plus beeps is a fault. Long beeps
   say where (RAM bank or test number), short beeps say what (data bit or
   item).

**[The user guide](docs/USER-GUIDE.md)** explains every screen, the colours
and beeps, loading from a PC, and what to do when something fails.

## For developers

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers building from source, the
simulator, the source layout and the attributions. The design notes are in
[Atari-diag-cassette-scope.md](Atari-diag-cassette-scope.md).

## Authorship and status

The author has programmed 6502 machine language and assembler since
childhood. Even so, all of the code and documents here are, for now, 100%
written by AI (Claude, by Anthropic). The author directs the work, reviews
it and tests it on hardware.

Version 0.1. Tested on a MiSTer Atari800 core and in the project's
simulator; not yet on a real 400, 800, XL or XE. Issues and pull requests
are the way to reach the author; email is not checked.
