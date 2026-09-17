// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of rmGalivan_MiSTer. Author: Umberto Parisi (rmonic79)
// GENERATO da mkregions.py — non modificare a mano.
// Le stesse regioni della MRA di dangarj: se cambi qui, rigenera anche la MRA.

localparam [26:0] MAIN_BASE      = 27'h000000;
localparam [26:0] MAIN_END       = 27'h00C000;
localparam [26:0] MAIN_LO        = 27'h000000;
localparam [26:0] MAIN_SZ        = 27'h00C000;

localparam [26:0] MAINBNK_BASE   = 27'h00C000;
localparam [26:0] MAINBNK_END    = 27'h010000;
localparam [26:0] MAINBNK_LO     = 27'h00C000;
localparam [26:0] MAINBNK_SZ     = 27'h004000;

localparam [26:0] AUDIO_BASE     = 27'h010000;
localparam [26:0] AUDIO_END      = 27'h01C000;
localparam [26:0] AUDIO_LO       = 27'h010000;
localparam [26:0] AUDIO_SZ       = 27'h00C000;

localparam [26:0] CHARS_BASE     = 27'h01C000;
localparam [26:0] CHARS_END      = 27'h020000;
localparam [26:0] CHARS_LO       = 27'h01C000;
localparam [26:0] CHARS_SZ       = 27'h004000;

localparam [26:0] BGMAP_BASE     = 27'h020000;
localparam [26:0] BGMAP_END      = 27'h028000;
localparam [26:0] BGMAP_LO       = 27'h020000;
localparam [26:0] BGMAP_SZ       = 27'h008000;

localparam [26:0] TILES_BASE     = 27'h028000;
localparam [26:0] TILES_END      = 27'h048000;
localparam [26:0] TILES_LO       = 27'h028000;
localparam [26:0] TILES_SZ       = 27'h020000;

localparam [26:0] SPRITES_BASE   = 27'h048000;
localparam [26:0] SPRITES_END    = 27'h058000;
localparam [26:0] SPRITES_LO     = 27'h048000;
localparam [26:0] SPRITES_SZ     = 27'h010000;

localparam [26:0] PROMS_BASE     = 27'h058000;
localparam [26:0] PROMS_END      = 27'h058400;
localparam [26:0] PROMS_LO       = 27'h058000;
localparam [26:0] PROMS_SZ       = 27'h000400;

localparam [26:0] SPRBANK_BASE   = 27'h058400;
localparam [26:0] SPRBANK_END    = 27'h058500;
localparam [26:0] SPRBANK_LO     = 27'h058400;
localparam [26:0] SPRBANK_SZ     = 27'h000100;

localparam [26:0] PROT_BASE      = 27'h058500;
localparam [26:0] PROT_END       = 27'h05A500;
localparam [26:0] PROT_LO        = 27'h058500;
localparam [26:0] PROT_SZ        = 27'h002000;

