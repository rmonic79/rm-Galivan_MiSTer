# Authors and Credits

## rmGalivan_MiSTer core

**Author**: Umberto Parisi ([rmonic79](https://github.com/rmonic79))

The original RTL for the Galivan core — everything under `rtl/dangar/` and the
project wrapper `Template.sv` — is copyright Umberto Parisi and distributed
under **GNU GPL v3 or later**.

That includes the two custom chips of the family and the three sets MAME marks
`MACHINE_NOT_WORKING`:

- **NB1412M2** (`dangar_nb1412m2.sv`) — the protection of the Japanese *Ufo
  Robo Dangar*, reduced to the decrypter the game actually uses.
- **NB1414M4** (`dangar_nb1414m4.sv`) — the text blitter of *Ninja Emaki*,
  written as a microcode table and verified differentially against a Python
  port of MAME's own routine: 71 cases out of 71 identical byte for byte.
- **The Game Electronics bootlegs** (`youmab`, `youmab2`) and **the Tecfri
  licence** (`ninjemat`) — not ports of anything. Their behaviour was derived
  from the program ROMs, disassembled with a tool written for the purpose, and
  compared byte by byte against the original Nichibutsu sets. The findings are
  written up in
  `docs/YOUMAB_PROTEZIONE.md`, `docs/NINJEMAT.md`,
  `docs/MAME_YOUMAB_NOTE.md` and in the README.

Also original to this core:

| | |
|---|---|
| `dangar_main.sv` | main Z80 bus, memory map and I/O for the four board variants |
| `dangar_video.sv` | text layer, background line buffer, sprites, palette PROM chain |
| `dangar_mem.sv` | ROM loader and the per-variant region tables |
| `dangar_sound.sv`, `dangar_biquad.sv` | sound Z80, YM3526 glue, R2R DACs, the board's analog filters as biquads |
| `crt_adjust_sys.sv`, `crt_vsize.sv` | CRT geometry on the analog output (H-Size, H-Position, V-Shift, V-Size with PVM and Cabinet modes) |
| `pause_overlay.sv`, `pause_text.sv` | VBlank-synchronised pause overlay with logo and supporters scroll |

`ddram_4port.sv` is adapted from Sorgelig's `ddram.v` and keeps its original
copyright.

## Third-party components

This core builds on top of excellent open-source projects. All third-party
sources retain their original copyright and license. The core as a whole
is distributed under **GNU GPL v3 or later** to stay compatible with the
most restrictive upstream (JTFRAME / JTCORES).

| Component | Author | Project | License |
|-----------|--------|---------|---------|
| **T80** — Z80 core (main and sound CPU) | Daniel Wallner, MikeJ, with Sorgelig / MiSTer-devel maintenance | [MiSTer-devel/T80](https://github.com/MiSTer-devel/T80) | BSD / GPL |
| **TV80** — Z80 core, used for the savestate shim | Guy Hutchison, with the auto_ss instrumentation of Martin Donlon | [OpenCores — tv80](https://opencores.org/projects/tv80) | see upstream |
| **JTOPL** — Yamaha YM3526 OPL FM synthesizer | Jose Tejada ([@jotego](https://github.com/jotego)) | [jotego/jtopl](https://github.com/jotego/jtopl) | GPL-3 |
| **JTFRAME** — framework modules, SDRAM64 controller | Jose Tejada | [jotego/jtframe](https://github.com/jotego/jtframe) | GPL-3 |
| **Savestate infrastructure** — ssbus, memory_stream, auto_save_adaptor, RAM adaptors | Martin Donlon ([wickerwaka](https://github.com/wickerwaka)) | [wickerwaka/Arcade-TaitoF2_MiSTer](https://github.com/wickerwaka/Arcade-TaitoF2_MiSTer) | GPL-3 |
| **sdram.sv** — SDRAM controller | Sorgelig ([sorgelig](https://github.com/sorgelig)) | [MiSTer-devel](https://github.com/MiSTer-devel) | GPL-3 |
| **sys/ framework** — MiSTer HPS/IO, OSD, video scaler, audio | Sorgelig / MiSTer-devel | [MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) | GPL-3 |

## Reference

- **The Galivan hardware** — Nichibutsu, 1985–1986 (PCB `GV-1412-I` +
  `GV-1412-II`), running *Cosmo Police Galivan*, *Ufo Robo Dangar* and *Ninja
  Emaki* / *Youma Ninpou Chou*. This FPGA core is a reimplementation from the
  MAME source and, for the sets MAME does not run yet, from the program ROMs
  themselves. ROMs are **not** included and must be provided by the user.
- **MAME project** — `nichibutsu/galivan.cpp` by **Luca Elia** and **Olivier
  Galibert** (BSD-3-Clause), the reference for memory maps, raster timing,
  graphics layouts, mixing ratios and filter component values; and MAME's
  **NB1414M4** emulation by **Angelo Salese**, against which the blitter was
  written and verified. The work on the three non-working sets started from
  there.
  [mamedev/mame](https://github.com/mamedev/mame)
- **The original Nichibutsu sets** (`youma`, `ninjemak`) — used as ground truth
  for the bootlegs and the Tecfri licence: every byte those boards change was
  accounted for against them.

## Special thanks

- **Andrea Bogazzi** ([@asturur](https://github.com/asturur)) for his help on
  one part of the CRT Adjust module during its development. The module is my
  own work; the part he helped with lives on in the module's repository.
