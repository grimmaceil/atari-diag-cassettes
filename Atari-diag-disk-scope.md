# A8 Diagnostics, Disk Port: Scope

Status: built 2026-11-08 (v0.2): both files pass in the simulator; MiSTer
test pending. Where the build settled a point differently from the
proposal, the text below says what was built.

I can program 6502 ml and assembler since a child but this is 100% AI for now.

## 1. What this is

The two tests that fit a disk best, as Atari binary files (`.xex`):

| File | The tape it comes from | Needs | Loads at | Ends |
|---|---|---|---|---|
| `diag-32k-xl-xe.xex` | `diag-32k-xl-xe.cas` | 32K | $2000 | about $6740 |
| `diag-memtest.xex` | `diag-memtest.cas` | 16K | $2000 | about $3B40 |

These files load from:

- a DOS menu (the binary load option)
- the MiSTer Atari800 core's own XEX loader
- a PC (AspeQt and similar, FujiNet, SIO2SD)

Loading from disk is faster than from tape, and the file can be copied to
any disk the user already has.

**The tapes don't change.** Every `.cas` file builds byte-identical to
v0.1.2 (Mike's rule). The cassette brief (`Atari-diag-cassette-scope.md`)
stays frozen at v0.1.2.

**The disk files are their own build (Mike: "xex versions should have some
differences").** They come from the same source as their tapes, assembled
with an `XEX` define. Every difference sits behind `.ifdef XEX`, so a tape
build can't pick one up. The differences:

- **Title bar:** ` DIAG-32K-XEX ` and ` DIAG-MEMTEST-XEX `, so a screen
  photo shows which one ran.
- **Too-little-RAM check:** it moves out of the program into the guard (see
  4), which checks before anything loads. (The program's own NEEDPG check
  runs too late for a disk file: by the time it runs, the file has already
  loaded into the missing RAM.)

Everything else is the tape program: the tests, the screens, the colours
and the beep codes.

## 2. Why these two, and not the others

- **The 32k test:** the full suite in one file (RAM, ROMs, keyboard,
  console keys, sound, video, joysticks, paddles, and a menu). It needs 32K
  either way: from tape or from disk.
- **The memory test:** small enough (6.75K) to load above DOS on a 16K
  machine.
- **Left out:**
  - The 16k tapes, `diag-16k-01-ram` and `diag-16k-02-system`. Each is
    9.25K, and above DOS they would need 24K. A 24K machine is rare (Mike's
    call), and the 32K file covers the same tests.
  - The 400 tapes, including `diag-400-memtest` (Mike's call). An 8K
    machine has no disk drive in practice: DOS itself needs more.
  - `diag-controls`: the 32k file's menu runs the same tests.

## 3. Goals, non-goals, anti-goals

**Goals:**

- The same results, screens, colours and beep codes as the tape of the
  same name.
- Simple for the user: copy the file and load it. If the machine is too
  small, it says so in plain words, before it loads anything into RAM that
  isn't there.

**Non-goals:**

- No bootable disk image (`.atr`).
- No DOS on the disk: Atari DOS isn't ours to hand out.
- No new tests.
- No change to the tapes.

**Anti-goals:** each of these is a failure even if the test itself runs.

- A disk file that reports something different from its tape.
- A too-small machine that crashes or hangs, when it should say "needs
  32K".
- A file that works only from one loader.

## 4. How it works

The program is the XEX build of the tape's image: the bytes from `$0800`
to `IMGEND`, with the same 6-byte boot header and checksum as on tape. It still runs from
`$0800`, but DOS lives there while the file is loading. So the file loads
the image higher up and moves it down once loading is done. The test never
goes back to DOS, so from then on DOS's memory is the test's: it is
checked like all other RAM.

The `.xex` has three segments, in this order:

1. **Guard (with INITAD), loaded at `$2000`.** (Built there, not at the
   top: a too-small machine has no RAM at the top, so a guard there could
   never run. The image overwrites it once it has passed.) It runs before
   the big segment loads and checks two things:
   - **RAMTOP ($6A):** at least `$80` for the 32k file, `$40` for the
     memtest.
   - **MEMLO ($02E7):** at most `$2000`. It must not run into the load
     address.

   If both pass, it returns and loading goes on. If either fails, the OS
   text screen is still on, so the guard prints one line and then halts
   with the tapes' too-little-RAM signal: red border, low tone on and off.
   - `NEEDS 32K RAM. THIS MACHINE HAS nnK.`
   - `NEEDS 16K RAM. ...`
   - `DOS IS IN THE WAY: USE DOS 2 OR MYDOS.`

   It never returns, so nothing goes into missing RAM.
2. **The image, loaded at `$2000`.** It is the XEX build's `$0800` image,
   with its boot header and checksum: start `$2000`, end
   `$2000 + (IMGEND - $0800) - 1`.
3. **Mover (with RUNAD), in the same top area as the guard.** It does the
   following, in order:
   1. Turns interrupts off.
   2. Copies the image down to `$0800` (ascending: the target is below the
      source).
   3. Sets the RESET vectors (see 5).
   4. Jumps to `$0806` (`LOAD+6`): the same entry the cassette boot uses.

   From then on it runs as the tape program does: the checksum, the low
   RAM test and the RAM probe all run as on tape.

The mover sits just past the image's end, so the copy never overwrites
it. The program overwrites it only later, during its RAM test, after the
jump.

**8K:** the guard itself needs RAM at `$2000`, so an 8K machine can't even
show the message. No disk drive works with 8K (DOS needs more), so this
only matters with a PC or MiSTer loader; the user guide says to use the
400 tapes there.

**Memory, 32k file:** the image is about `$4700` bytes (the XEX
differences may shift it by a few bytes; the build works it out). Loaded at `$2000` it ends
at `$66FF`. With the mover it ends at `$6728`, well under
32K (`$8000`). While it runs, it uses up to `$53FF` (screen `$5000`,
display list `$53C0`), as on tape.

**Memory, memtest:** the image is `$1B00` bytes (`$0800`-`$22FF`). Loaded
at `$2000` it ends at `$3AFF`. The mover is at `$3B00`-`$3B28`, below a
16K machine's OS screen (display list at `$3C20`). So loading never writes
over the screen DOS is showing.

**Why load at $2000:**

- It is above DOS 2.0S, DOS 2.5 and MyDOS. Their MEMLO is about
  `$1CFC`-`$1F00`, and `$2000` is where many games load.
- The MiSTer loader sits at `$0700` (Standard) or `$0100` (Stack), out of
  the way either way.
- SpartaDOS 3.x on disk sits higher. The guard catches that and says so,
  rather than crashing.

## 5. RESET

Right after the move, DOS is gone, so the RESET key must not jump into it.
**Built:** the mover sets `COLDST` (`$0244`) to 1, so RESET starts the
machine again, as at power-on. (On tape, RESET leaves the test for the OS
memo pad or BASIC; with DOS overwritten a cold start is the safe way out.)
To be checked on the MiSTer.

## 6. Build, tools, deploy

**`tools/mkxex.py`** (new) builds the file:

- It takes the stage's `.bin` and `.lab`, the same inputs `mkcas.py`
  takes.
- It patches the image checksum with the same code `mkcas.py` uses (move
  that into a shared helper, don't copy it).
- It writes the three segments.
- The guard and mover are assembled by MADS from
  `src/disk/xexwrap.asm`, with `IMGLEN`, `NEEDPG` and the message passed
  in by `build.py`.

**`tools/build.py`:**

- Builds both `.xex` files: the same builders as the two tapes
  (`build_one32`, `build_bounce`), run again with `XEX=1`, the XEX title
  and no NEEDPG.
- The `.cas` files must come out byte-identical to v0.1.2. Check this with
  `cmp` against the v0.1.2 tag's build before every commit.
- The auto-deploy to `_diag` also copies `*.xex`.

**`tools/sim.py`:** learns to load an `.xex` the way DOS does. It:

- sets MEMLO (`$1CFC`, or another value from an option), RAMTOP and
  RUNAD/INITAD;
- writes each segment, and calls INITAD after any segment that sets it;
- jumps to RUNAD at the end.

**Tests in the simulator:**

- `diag-32k-xl-xe.xex` with 32K, 48K, and 64K XL. Results must match the
  tape run, except for the title bar.
- The same file with 16K: the `NEEDS 32K` line and the halt, and nothing
  written above `$3FFF`.
- `diag-memtest.xex` with 16K and 48K, and with 8K (halt).
- Both files with MEMLO `$2100`: the DOS message.

**On the MiSTer (Mike), for each file:**

- the core's XEX loader
- and, if he has one, a DOS 2.5 disk with the file copied on

The same machine setups as the tapes: 400 and 800 at 16K, 32K and 48K;
800XL; 130XE.

## 7. Docs

- **User guide:** a short "From disk" part under Loading. It covers:
  - which two files;
  - how to load them (MiSTer XEX loader; DOS menu binary load);
  - holding OPTION is not needed (the tests switch BASIC off themselves);
  - a cartridge still shows `CART IN`;
  - what the `NEEDS` / `DOS IS IN THE WAY` lines mean.

  Everything after "Reading the results" is the same as the tapes, so the
  disk part points there and doesn't repeat it.
- **README:** list the two files and their sizes.
- **DEVELOPMENT:** the three segments, the `$2000` load and why, and the
  sim's XEX load.

## 8. Left to the builder

- Exactly where RESET goes (5).
- The guard's text and colours, within the plain-words rule in 4.
- How `sim.py` exposes the MEMLO option.

## 9. Calls made in this proposal

Marked so Mike can check them:

- **The file names follow the tapes:** `diag-32k-xl-xe.xex` and
  `diag-memtest.xex`. Neither needs more RAM than its tape.
- **The differences from the tapes are the two listed in 1:** the title bar
  and where the RAM check runs. Any more need Mike's OK.
- **Load address `$2000`.** SpartaDOS 3.x on disk is not supported; it
  gets a plain message instead.
- **Only `.xex`:** no `.atr`, no DOS shipped.
