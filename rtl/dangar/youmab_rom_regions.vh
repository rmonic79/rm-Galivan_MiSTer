// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of rmGalivan_MiSTer. Author: Umberto Parisi (rmonic79)
// GENERATO da mkregions.py — non modificare a mano.
// Regioni della MRA di youmab, prefisso YB_ per stare accanto a quelle di
// Galivan e di Ninja Emaki nello stesso modulo. La tabella di youmab2 e'
// IDENTICA byte per byte, quindi i due set bootleg condividono queste
// costanti: cambia solo l'elenco dei file nella MRA.
// Le stesse regioni della MRA di youmab: se cambi qui, rigenera anche la MRA.

localparam [26:0] YB_MAIN_BASE      = 27'h000000;
localparam [26:0] YB_MAIN_END       = 27'h008000;
localparam [26:0] YB_MAIN_LO        = 27'h000000;
localparam [26:0] YB_MAIN_SZ        = 27'h008000;

localparam [26:0] YB_MAINBNK_BASE   = 27'h008000;
localparam [26:0] YB_MAINBNK_END    = 27'h010000;
localparam [26:0] YB_MAINBNK_LO     = 27'h008000;
localparam [26:0] YB_MAINBNK_SZ     = 27'h008000;

localparam [26:0] YB_XBANK_BASE     = 27'h010000;
localparam [26:0] YB_XBANK_END      = 27'h018000;
localparam [26:0] YB_XBANK_LO       = 27'h010000;
localparam [26:0] YB_XBANK_SZ       = 27'h008000;

localparam [26:0] YB_AUDIO_BASE     = 27'h018000;
localparam [26:0] YB_AUDIO_END      = 27'h024000;
localparam [26:0] YB_AUDIO_LO       = 27'h018000;
localparam [26:0] YB_AUDIO_SZ       = 27'h00C000;

localparam [26:0] YB_CHARS_BASE     = 27'h024000;
localparam [26:0] YB_CHARS_END      = 27'h02C000;
localparam [26:0] YB_CHARS_LO       = 27'h024000;
localparam [26:0] YB_CHARS_SZ       = 27'h008000;

localparam [26:0] YB_BGMAP_BASE     = 27'h02C000;
localparam [26:0] YB_BGMAP_END      = 27'h034000;
localparam [26:0] YB_BGMAP_LO       = 27'h02C000;
localparam [26:0] YB_BGMAP_SZ       = 27'h008000;

localparam [26:0] YB_TILES_BASE     = 27'h034000;
localparam [26:0] YB_TILES_END      = 27'h054000;
localparam [26:0] YB_TILES_LO       = 27'h034000;
localparam [26:0] YB_TILES_SZ       = 27'h020000;

localparam [26:0] YB_SPRITES_BASE   = 27'h054000;
localparam [26:0] YB_SPRITES_END    = 27'h074000;
localparam [26:0] YB_SPRITES_LO     = 27'h054000;
localparam [26:0] YB_SPRITES_SZ     = 27'h020000;

localparam [26:0] YB_PROMS_BASE     = 27'h074000;
localparam [26:0] YB_PROMS_END      = 27'h074400;
localparam [26:0] YB_PROMS_LO       = 27'h074000;
localparam [26:0] YB_PROMS_SZ       = 27'h000400;

localparam [26:0] YB_SPRBANK_BASE   = 27'h074400;
localparam [26:0] YB_SPRBANK_END    = 27'h074500;
localparam [26:0] YB_SPRBANK_LO     = 27'h074400;
localparam [26:0] YB_SPRBANK_SZ     = 27'h000100;

