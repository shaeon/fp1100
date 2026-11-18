# Casio FP-1100 / FP-1000 for MiST-family FPGA boards

*[Leer en español](README_es.md)*

An FPGA implementation of the **Casio FP-1100** (1982) and its monochrome
sibling, the **FP-1000**, for the **Poseidon**, **SiDi** and **Calypso**
boards. It runs the original ROMs on both of the machine's processors and
boots C82-BASIC and CP/M from EDSK disk images.

## Features

- **Main CPU**: Z80 at 4 MHz (T80) from a 32 MHz system clock; the BASIC ROM
  and the 64K of RAM live in SDRAM, with the CPU stalled only when it
  actually needs data that the SDRAM has not delivered yet.
- **Sub CPU**: the NEC uPD7801 that runs the keyboard, video, cassette and
  printer, emulated on a uPD7800 core with the original internal ROM,
  talking to the Z80 through the same latches and interrupt lines.
- **Video**: HD46505 CRTC and the three-plane colour VRAM (48K, in SDRAM),
  read one line ahead into a line buffer. 80 and 40 columns, 640x200 in
  eight colours, the green-monitor mode of the FP-1000, and **Screen 1**
  (640x400 interlaced): shown either as alternating fields or, by default,
  as a full 640x400 progressive picture with the core's own 31 kHz output.
- **Keyboard**: PS/2 to the FP-1100 key matrix, with protection against
  keys left pressed when the firmware loses a key release.
- **Cassette**: WAV files from the OSD or real audio on the audio input,
  with a tape monitor to hear what is loading.
- **Disk**: the FDC pack (uPD765) with EDSK images in drives A and B; CP/M
  boots from disk.
- **Tools**: WAV/CAS/TZX/TAP tape converter, disk image converters (D88,
  Teledisk, ImageDisk and raw dumps to EDSK), a uPD7801 disassembler and a
  monitor test card on a self-booting disk.

**ROM**: copy `sd/FP1100.ROM` (48K) to the root of the SD card; the board
firmware loads it when the core starts. `roms/README.md` explains how it is
built from the MAME `fp1100` set.

## How it works

**Two processors, as in the real machine.** The FP-1100 splits its work
between a Z80, which runs BASIC, and a uPD7801 that owns the keyboard, the
video memory, the cassette circuit and the printer port. The core keeps that
split: the T80 runs the BASIC ROM from SDRAM, and the uPD7800 core runs the
sub CPU's internal ROM from block RAM. They talk through the original
latches and interrupt lines, and every BASIC command that draws on the
screen or reads the keyboard goes through the sub CPU's own firmware.

**Memory.** ROM, RAM and the colour VRAM share one SDRAM. A fixed-priority
arbiter serves refresh, video, tape and the CPUs. The video reads two words
per character with a single ACTIVE; the Z80 is only held back at the exact
point where it would sample the data bus.

**Video.** Instead of reading the VRAM at the dot clock, the core reads each
CRTC line into a line buffer during the previous line, which makes an SDRAM
VRAM possible on boards with little block RAM. The dot clock is exactly 25/32
of the system clock, so each line is 800 dots of 12.5 MHz (64 us) and the
scandoubled output is standard 640x480 VGA timing.

**Cassette.** The FSK demodulator reproduces the machine's own circuit, and
a player module streams WAV files loaded from the OSD as if they came from a
tape deck under motor control.

**Testing.** The whole machine runs in a Verilator testbench with the real
ROMs: booting BASIC, typing, loading tapes and disks, CP/M, and the games
used to chase timing problems. See `docs/hardware_fp1100.md` for the
development notes.

## Building

Open the project for your board in Quartus (`poseidon/`, `sidi/` or
`calypso/`) and compile. The testbenches run with `make` in `test/`.
The documentation in `docs/` is in Spanish.

`common/` contains copies of T80 and mist-modules with two small local
changes (a cold-start fix in `T80pa.vhd` and a configurable PS/2 queue in
`user_io.v`), so they are included as plain folders rather than submodules.

## Credits

This core stands on the work of many people. Thank you all.

**Code used in the core**

- **T80** Z80 core: Daniel Wallner, with later fixes by Sorgelig and the
  MiST/MiSTer community. BSD-style license.
- **uPD7800** core: David Hunter, from the Super Cassette Vision core.
  GPL license.
- **MiST modules** (`user_io`, `data_io`, `mist_video`, OSD, scandoubler and
  related): Till Harbaum, Gyorgy Szombathelyi (gyurco) and the MiST
  community. GPL v3 or later.
- **u765** uPD765 floppy controller: Gyorgy Szombathelyi (gyurco), from
  Amstrad_MiST. GPL v2 or later.
- Delta-sigma DAC: based on Xilinx application note XAPP154.
- **tv80** (testbench only): Guy Hutchison. MIT-style license.

**References and inspiration**

- **eFP-1100** by Takeda Toshiya (Common Source Code Project): the main
  reference for the hardware; the uPD7801 disassembler in `tools/` is his.
- **MAME** FP-1100 driver (Angelo Salese and the MAME team, BSD 3-clause).
- **FP-1100_SD**, for the file formats and the boot loader.
- The Casio FP-1000/FP-1100 service manual and the C82-BASIC manual.
- The NewBrain core by the same author, whose structure this core follows.

## Thanks

To the **Retro-Wiki FPGA-dev Team**, especially **Ron, Manuel (teiram), Somhi,
Roderick, Rampa, Kyp and Benito**, for their help and patience.

## AI assistance and resources

Parts of this core were developed with the assistance of Claude (Anthropic),
used for code, testbenches, simulation and documentation. Access to Claude
was provided by Advanced Computer Trading, S.L. (actsl.com), which also
authorises the publication of this work under the license below. All design
decisions, integration, testing on real hardware and final review were
carried out by the author, Shaeon (Carlos Palmero).

## License

Copyright (C) 2026 Shaeon (Carlos Palmero).

This program is free software: you can redistribute it and/or modify it
under the terms of the **GNU General Public License** as published by the
Free Software Foundation, either **version 3** of the License, or (at your
option) any later version. See [LICENSE](LICENSE).

Version 3 is required because some of the included modules (the MiST
modules) are licensed under GPL v3 or later. Third-party files keep their
own copyright notices and licenses.

## Disclaimer

This project is provided **"as is", without warranty of any kind**, express
or implied, including but not limited to the warranties of merchantability
and fitness for a particular purpose. In no event shall the authors or
contributors be liable for any claim, damages or other liability arising
from the use of this software, of the hardware it runs on, or of any
connected equipment. Use it at your own risk.

Casio, FP-1000 and FP-1100 are trademarks of their respective owners. This
project is not affiliated with or endorsed by them.
