# A8 Cassette Diagnostics: Project Brief

Multi-stage, cassette-loaded diagnostic suite for Atari 8-bit computers (400, 800, 800XL; 130XE extended RAM as an optional stage). The goal is to give as much diagnostic information as possible through synchronized beeps and border flashes, adding plain-text screens as the video hardware proves itself.

Working style: Claude writes the code; Mike reviews and watches. Keep changes reviewable, comment the 6502 code at the level of "why", and skip explanations of basics.

---

## 1. Target hardware

| Machine | RAM | Notes |
|---|---|---|
| 400 | 8K or 16K | No RAM on motherboard; RAM on plug-in board |
| 800 | Up to 48K, three 16K boards in slots | Slot position sets each board's address range; OS rev A/B on removable OS board |
| 800XL | 64K, eight 4164 DRAMs (U9-U16), one chip per data bit | Verify the exact bit-to-U mapping against the schematic |
| 130XE | 64K main + 64K extended (4 x 16K banks) | Different DRAM layout; needs its own chip table |

Memory decoding:
- **400/800:** a fixed memory map decoded by discrete TTL. No software banking. The cart sets RD5 (left, $A000-$BFFF) or RD4 ($8000-$9FFF), which disables RAM there and asserts S5/S4.
- **XL/XE:** the MMU (C061618) decodes using the address lines, RD4/RD5 and the PIA PORTB bits:
  - bit 0: OS ROM
  - bit 1: BASIC
  - bit 7: self-test ROM
  - bits 2-5 (130XE): bank select, CPU access, ANTIC access
- On the 400/800, PIA PORTB is joystick ports 3/4.

---

## 2. Key constraints

- **Cassette boot needs a working OS ROM and low RAM:** zero page, the stack, the cassette buffer at $0400, and wherever the boot stage loads. The suite diagnoses partly-bad RAM, not dead RAM. On a 400/800 the first RAM board must be mostly sound.
- **Boot procedure:** hold START at power-on (START+OPTION on the XL to disable BASIC), wait for the beep, start playback, press a key.
- **A BOOT ERROR during load is itself diagnostic.** The OS verifies each record's checksum, so the error points at low RAM, the cassette buffer or the SIO path.
- **600 baud is roughly 80-90 s per 4K loaded.** Keep each tape small.
- **Cassette is sequential (no seeking)**, so each test group is a separate, standalone bootable CAS image.
- **Before low RAM is proven, the code must not rely on the stack or zero page:**
  - SEI and NMIEN=0 (no interrupts)
  - no JSR/RTS/PHA/PLA; inline macros instead
  - state kept in A/X/Y only

---

## 3. Feedback design

### Feedback ladder (each level is enabled only after its hardware checks out)
1. **Abstract:** ANTIC DMA off; the border/background (COLBK) color plus POKEY beeps. Works even with garbage video, because GTIA shows COLBK regardless of what ANTIC fetches.
2. **Display prerequisites:** test a 1K screen region (try another bank if it fails), checksum the character ROM, and confirm that VCOUNT ($D40B) counts.
3. **Video check screen:** readable text and 8 color bars. A keypress confirms the video works. With no key within 20 s, a 10 s "last chance" follows (purple border, 3 s siren). If still unconfirmed, the text stays on anyway (the display prerequisites passed), and the results note "video check not confirmed". Beeps-only (ANTIC off) is used only when the display prerequisites fail. During the pauses in a result code, OPTION switches between text and full-screen flashes (for a garbled picture).
4. **Plain-text results:** shown for every step from here on, with the beep/flash code running alongside.

### Colors
- Green = alive / pass
- Yellow = test running (a hang shows which test it stopped in)
- Red = fail
- Optional extra layer: a yellow flash marks a warning (an intermittent error). Color is never required to read a result.

### Beep/flash code (every flash is paired with a beep, so it reads by eye or by ear)
- **Timing:** long = ~600 ms, short = ~200 ms, gap 200 ms, 1 s between groups, 3 s before the report repeats.
- **Group A (long):** where the fault is.
  - Main RAM: bank or slot 1-4 (the slot on the 400/800, the 16K bank on the XL)
  - 130XE extended banks 0-3: report as 5-8
  - Other tests: the test number
- **Group B (short):** what failed: the bit number counted 1-8 (D0 = 1 ... D7 = 8). Never zero.
- **Multiple bad bits:** one B group per bad bit, then a distinct low "end of list" tone.
- **RAM tests** report every bad bit in a bank in one pass. **Other tests** stop at the first failure, wait for a key, then continue.
- **Ceiling:** at most 8 counts per group, because people miscount by ear beyond that.

### Flow control
- **Pass:** auto-advance after ~2 s; holding OPTION pauses on the result.
- **Fail:** stop on the result screen until continued.
- **Continue input:** any key, START/SELECT/OPTION, or joystick fire, so a dead keyboard or POKEY can't strand the user.
- **SELECT** replays the beep code.
- **Every tape ends with a summary screen.** It ends with a green border if everything passed, red if anything failed.

### Screen layout (40-column GRAPHICS 0, uppercase)
- **Header:** `A8 DIAG  TAPE n/3  <TEST NAME>  <step x OF y>`
- **RAM fail screen:**
  - slot or bank, and address range
  - first error address
  - WROTE / READ / XOR values
  - error count
  - bad bit(s) and the chip they map to
  - a likely-cause hint (stuck low/high, dead chip, decoder, address line)
  - the beep code
  - the continue/replay prompt
- **Summary screen:**
  - machine, OS revision and RAM found
  - numbered test list with PASS/FAIL and detail
  - failure count
  - a suggested next action
  - SELECT = replay codes, START = run again

---

## 4. Shared core (included in every tape)

- **Reporter:** the color and beep sequencer, built in two versions: registers-only (no stack) and normal.
- **Continue/input handler** and **auto-advance timer.**
- **Machine detection:** 400/800 versus XL/XE from the OS ROM, a RAM size probe, 130XE extended RAM, and optionally common PORTB RAM upgrades (e.g. 320K).
- **Text screen setup:** the display list and 1K screen placed in RAM that tested good.
- **Summary builder.**

---

## 5. Tape 1: boot and RAM (`diag-01-boot-ram.cas`)

1. **Load.** A BOOT ERROR here points to low RAM or the SIO path.
2. **Alive:** SEI, NMIEN=0, DMACTL=0, COLBK green, POKEY init (SKCTL=3), chirp.
3. **Machine detection.**
4. **Low RAM test** ($0000-$07FF): non-destructive (save, test, restore), registers only. A fail gives the abstract code and halts.
5. **Display prerequisites:** 1K screen region, character ROM checksum, VCOUNT.
6. **Video check screen** (confirmed, or beeps-only).
7. **RAM test by slot or bank:**
   - March C- plus an address-in-address test, which separates decoder/address-line faults from chip faults.
   - The bad-bit mask maps to a chip through the per-machine table.
   - Interpretation hints:
     - one bit failing across a whole board or bank: dead chip
     - all bits failing in one bank: the board, its socket/slot, or the decoder
     - one bank mirroring another: an address line
   - **XL:** also test the RAM under the OS, BASIC and self-test ROMs by banking them out through PORTB, with interrupts and NMIs off while the OS is out.
8. **130XE extended banks** (only if detected): the same tests through the $4000-$7FFF window, using PORTB bits 2-3 for the bank and bit 4 for CPU access.
   - Plus an **ANTIC-access check** (bit 5): put a pattern in an extended bank, point ANTIC at it, and confirm by eye.
9. **Relocate:** copy the code to a bank that tested good, then test the region the loader occupied.
   - **As built:** tape 1 is two files. Stage 1 (the boot file, $0800, must fit an 8K 400 with its screen block at $1C00) runs steps 2-7 and shows compact per-bank results. On pass, or START after a fail, it loads stage 2 at $2000 with the OS's SIO (cassette, short gaps; interrupts back on for the load). Stage 2 needs 16K and a clean bank 1; it tests the loader area ($0800 up to stage 1's end) and shows the summary with the first failure's detail. Every file ends with an EOF record: the OS boot reads one record past its count. Stage 2 also tests the RAM under the XL/XE OS (bank 4) and the 130XE extended banks (5-8; ANTIC-access check not yet). If stage 2 fails to load (read error or wrong file), START retries; the build also writes stage 2 as its own `-part2.cas` for players that don't stop with the motor.
10. **Summary.**

## 6. Tape 2: burn-in (`diag-02-ram-burnin.cas`)

1. Alive check and machine detection, as in tape 1.
2. Loop the RAM tests over all memory, including the extended banks if present.
3. Show a pass counter and elapsed time, with a green pulse at the end of each pass.
4. Keep a compact error log: bank, bit, first pass seen, count.
5. **Intermittent errors** turn the border yellow, and the beep code plays at the end.
6. Stop on a keypress, then show the summary.

## 7. Tape 3: system (`diag-03-system.cas`)

1. **ROM checksums:** the OS (plus BASIC and self-test on the XL), compared against a table of known revisions. An unknown revision shows its raw checksum.
2. **Keyboard:**
   - Check for stuck keys first (KBCODE/SKSTAT showing a key down at start).
   - Then show an on-screen key map that lights each key as it's pressed. Include BREAK.
   - START ends the test.
3. **Console keys** (CONSOL $D01F) and the keyboard speaker click.
4. **POKEY:**
   - Automated: the timer IRQ fires; RANDOM changes.
   - Then the four voices in turn, each confirmed by keypress if heard.
5. **Joysticks and triggers:** a live display of 4 ports on the 400/800, 2 on the XL/XE.
6. **Paddles:**
   - Inputs: POT0-7 (8 total) on the 400/800; POT0-3 only on the XL/XE.
   - The inputs are RC-timing counters, not true ADCs. Write POTGO ($D20B) to start a scan; read POTn ($D200-$D207) for 0-228; ALLPOT ($D208) shows which have finished.
   - **Open-input check:** with nothing plugged in, every input should read 228. That proves the pot scan works.
   - **Live display:** a value bar per input with the min/max seen, to verify a full sweep (about 1 to 228).
   - **Jitter readout:** how much the value moves with the knob held still. A large spread flags a dirty pot.
   - **Paddle triggers:** these share the joystick direction lines; show them live.
   - **Fast-scan mode** (SKCTL bit 2): values settle in a couple of scanlines.
   - **Beep code:** a dead or stuck input reports as the paddle number (1-8).
7. **GTIA:** luminance and color ramps checked by eye, plus automatic PAL/NTSC detection (the PAL register at $D014).
8. **Summary.**

---

## 8. Build and dev environment

- **Claude Code runs at home** on the same network as the SMB share and the MiSTer.
- **Assembler:** MADS.
- **CAS builder:** `tools/mkcas.py`. It wraps each stage as a boot tape:
  - FUJI header and baud chunk
  - data records: $55 $55 sync, control byte, 128 data bytes, checksum
  - a boot header in the first record: flags, record count, load address, init address
- **Repo layout:** `src/common/`, `src/tape1/`, `src/tape2/`, `src/tape3/`, `tools/`, `build/`.
- **Deploy:** the build writes the `.cas` files straight to the SMB share the MiSTer reads, in the Atari800 core's folder under `games` (confirm the exact folder name). No scp.
- **MiSTer:** update the Atari800 core first; CAS support was added recently. SSH is available for launching, logs and screenshots. Look at wizzomafizzo's mrext Remote for remote launch, key injection and screenshots, so Claude Code can see the result (verify it works with this core).
- **Emulators:**
  - Altirra (best debugger): use it to trace the reset and cassette boot paths per OS revision.
  - `atari800 -boottape file.cas` on Linux for quick runs.
  - Test configs: an 8K 400, a 48K 800 with OS rev B, an 800XL, a 130XE.
- **Real hardware:**
  - Play the CAS images through AspeQt over SIO2USB. Verify that the Android AspeQt build supports cassette playback; the desktop AspeQt/RespeQt does.
  - Fallback: export a WAV (a8cas-tools) and play it into a real 410/1010.
- **Build flags:**
  - `FAULT=<slot>,<bit>`: inject a fake RAM failure to test the reporting. No emulator or the MiSTer can simulate a bad chip.
  - `FAST`: skip the slow test patterns.
- **Test order:** emulators, then MiSTer, then real hardware. Finally, a real fault test by pulling a socketed chip.
- **File names** start with diag- and are numbered, so they sort together in AspeQt and the MiSTer browser: `diag-01-boot-ram.cas`, `diag-02-ram-burnin.cas`, `diag-03-system.cas`.

---

## 9. Register quick reference

| Register | Address | Use |
|---|---|---|
| COLBK | $D01A | Border/background color (status color) |
| CONSOL | $D01F | START/SELECT/OPTION; speaker |
| PAL | $D014 | PAL/NTSC detect |
| AUDF1-4 / AUDC1-4 | $D200-$D207 (write) | Tone frequency / control |
| POT0-7 | $D200-$D207 (read) | Paddle values 0-228 |
| AUDCTL / ALLPOT | $D208 (write/read) | Audio control / pot scan status |
| KBCODE | $D209 (read) | Keyboard code |
| RANDOM | $D20A (read) | Random number |
| POTGO | $D20B (write) | Start pot scan |
| SKCTL / SKSTAT | $D20F (write/read) | Serial/keyboard control (3 = normal); bit 2 = fast pot scan |
| PORTA | $D300 | Joysticks 1/2 |
| PORTB | $D301 | Joysticks 3/4 (400/800); banking (XL/XE) |
| PACTL | $D302 | Cassette motor control |
| DMACTL | $D400 | ANTIC DMA (0 = off) |
| DLISTL/H | $D402/$D403 | Display list pointer |
| CHBASE | $D409 | Character set base (ROM font at $E000) |
| WSYNC | $D40A | Wait for horizontal sync |
| VCOUNT | $D40B | Scanline counter / 2 |
| NMIEN | $D40E | NMI enable (0 = off) |
| Cart control | $D500-$D5FF | CCTL area, used by bank-switched carts |

---

## 10. Reference sources

- **Mapping the Atari, Revised Edition** (Ian Chadwick, Compute!): address-by-address map. The revised edition covers the XL. Free at atariarchives.org.
- **Altirra Hardware Reference Manual** (Avery Lee): the most accurate source on chip behavior, timing, and the cassette/SIO protocol.
- **Atari 400/800 OS User's Manual** and **Hardware Manual** (Technical Reference Notes): official specs, including the cassette boot record format and the boot sequence.
- **Atari OS source listings** (rev B for the 400/800, plus the XL OS): exactly what the OS does at reset and cassette boot, and which RAM it uses before handing over control.
- **De Re Atari** (Atari, 1981): display lists, POKEY sound, timing.
- **400/800 Field Service Manual** and **Sams Computerfacts for the 800XL** (and 130XE schematics): for the bit-to-chip tables.
- **a8cas** (a8cas.sourceforge.net): CAS format details and CAS/WAV conversion tools.
- **SALT** and Super SALT (prior art, harness-based) and **Sys-Check** (XL/XE PBI dead-test device): reference for test coverage.

---

## 11. To verify / open items

- [ ] Bit-to-chip tables for the 400, 800 (per 16K board), 800XL and 130XE, from the schematics.
- [ ] Known-good ROM checksum table (OS rev A/B, XL OS revisions, BASIC revisions, self-test).
- [ ] Exact Atari800 folder path on the MiSTer share; MiSTer core 400/800 OS and RAM size options.
- [ ] Android AspeQt cassette playback support.
- [ ] Whether mrext Remote can launch and screenshot this core.
- [ ] Trace in Altirra exactly which RAM the OS uses during cassette boot, per OS revision.

---

## 12. Shelved / background

- **RAM-less "dead test" cartridge (shelved for now).**
  - The diagnostic-cart flag is bit 7 of the option byte at $BFFD; the OS jumps to the cart very early in reset.
  - Cart header layout:

    | Address | Contents |
    |---|---|
    | $BFFA/B | Run address |
    | $BFFC | $00 (cart present) |
    | $BFFD | Option byte |
    | $BFFE/F | Init address |

  - Point both vectors at the entry point.
  - The left slot always maps to $A000-$BFFF; no address switch is needed.
  - Display without RAM: COLBK with DMA off, racing the beam with WSYNC, or a display list held in ROM.
- **Atarimax MaxFlash:** its boot menu needs working RAM and the OS, so it's unsuitable for a no-RAM test. Useful for the later stages.
