// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of rmGalivan_MiSTer. Author: Umberto Parisi (rmonic79)
// GENERATO da mkregions.py — non modificare a mano.
// Regioni della MRA di ninjemak, prefisso NJ_ per stare accanto a quelle di
// Galivan nello stesso modulo. Le stesse regioni della MRA di ninjemak: se cambi qui, rigenera anche la MRA.

localparam [26:0] NJ_MAIN_BASE      = 27'h000000;
localparam [26:0] NJ_MAIN_END       = 27'h00C000;
localparam [26:0] NJ_MAIN_LO        = 27'h000000;
localparam [26:0] NJ_MAIN_SZ        = 27'h00C000;

localparam [26:0] NJ_MAINBNK_BASE   = 27'h00C000;
localparam [26:0] NJ_MAINBNK_END    = 27'h014000;
localparam [26:0] NJ_MAINBNK_LO     = 27'h00C000;
localparam [26:0] NJ_MAINBNK_SZ     = 27'h008000;

localparam [26:0] NJ_AUDIO_BASE     = 27'h014000;
localparam [26:0] NJ_AUDIO_END      = 27'h020000;
localparam [26:0] NJ_AUDIO_LO       = 27'h014000;
localparam [26:0] NJ_AUDIO_SZ       = 27'h00C000;

localparam [26:0] NJ_CHARS_BASE     = 27'h020000;
localparam [26:0] NJ_CHARS_END      = 27'h028000;
localparam [26:0] NJ_CHARS_LO       = 27'h020000;
localparam [26:0] NJ_CHARS_SZ       = 27'h008000;

localparam [26:0] NJ_BGMAP_BASE     = 27'h028000;
localparam [26:0] NJ_BGMAP_END      = 27'h030000;
localparam [26:0] NJ_BGMAP_LO       = 27'h028000;
localparam [26:0] NJ_BGMAP_SZ       = 27'h008000;

localparam [26:0] NJ_TILES_BASE     = 27'h030000;
localparam [26:0] NJ_TILES_END      = 27'h050000;
localparam [26:0] NJ_TILES_LO       = 27'h030000;
localparam [26:0] NJ_TILES_SZ       = 27'h020000;

localparam [26:0] NJ_SPRITES_BASE   = 27'h050000;
localparam [26:0] NJ_SPRITES_END    = 27'h070000;
localparam [26:0] NJ_SPRITES_LO     = 27'h050000;
localparam [26:0] NJ_SPRITES_SZ     = 27'h020000;

localparam [26:0] NJ_PROMS_BASE     = 27'h070000;
localparam [26:0] NJ_PROMS_END      = 27'h070400;
localparam [26:0] NJ_PROMS_LO       = 27'h070000;
localparam [26:0] NJ_PROMS_SZ       = 27'h000400;

localparam [26:0] NJ_SPRBANK_BASE   = 27'h070400;
localparam [26:0] NJ_SPRBANK_END    = 27'h070500;
localparam [26:0] NJ_SPRBANK_LO     = 27'h070400;
localparam [26:0] NJ_SPRBANK_SZ     = 27'h000100;

localparam [26:0] NJ_BLIT_BASE      = 27'h070500;
localparam [26:0] NJ_BLIT_END       = 27'h074500;
localparam [26:0] NJ_BLIT_LO        = 27'h070500;
localparam [26:0] NJ_BLIT_SZ        = 27'h004000;

