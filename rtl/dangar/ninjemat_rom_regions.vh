// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of rmGalivan_MiSTer. Author: Umberto Parisi (rmonic79)
// GENERATO da mkregions.py — non modificare a mano.
// Regioni della MRA di ninjemat, prefisso NT_ per stare accanto a quelle di
// Galivan, di Ninja Emaki e del bootleg nello stesso modulo. Nessuna regione
// blitter: la scheda Tecfri il NB1414M4 non ce l'ha, il testo lo disegna il
// programma.
//
// MAINBNK e' 32 KB = QUATTRO banchi da 8 KB, e i primi due NON vengono da
// ninjemat: al suo dump mancano. Sono la mappa delle collisioni col terreno,
// presa da ninjemak, che ha gli stessi livelli byte per byte. Il perche'
// sta in docs/NINJEMAT.md.
// Le stesse regioni della MRA: se cambi qui, rigenera anche la MRA.

localparam [26:0] NT_MAIN_BASE      = 27'h000000;
localparam [26:0] NT_MAIN_END       = 27'h00C000;
localparam [26:0] NT_MAIN_LO        = 27'h000000;
localparam [26:0] NT_MAIN_SZ        = 27'h00C000;

localparam [26:0] NT_MAINBNK_BASE   = 27'h00C000;
localparam [26:0] NT_MAINBNK_END    = 27'h014000;
localparam [26:0] NT_MAINBNK_LO     = 27'h00C000;
localparam [26:0] NT_MAINBNK_SZ     = 27'h008000;

localparam [26:0] NT_AUDIO_BASE     = 27'h014000;
localparam [26:0] NT_AUDIO_END      = 27'h020000;
localparam [26:0] NT_AUDIO_LO       = 27'h014000;
localparam [26:0] NT_AUDIO_SZ       = 27'h00C000;

localparam [26:0] NT_CHARS_BASE     = 27'h020000;
localparam [26:0] NT_CHARS_END      = 27'h028000;
localparam [26:0] NT_CHARS_LO       = 27'h020000;
localparam [26:0] NT_CHARS_SZ       = 27'h008000;

localparam [26:0] NT_BGMAP_BASE     = 27'h028000;
localparam [26:0] NT_BGMAP_END      = 27'h030000;
localparam [26:0] NT_BGMAP_LO       = 27'h028000;
localparam [26:0] NT_BGMAP_SZ       = 27'h008000;

localparam [26:0] NT_TILES_BASE     = 27'h030000;
localparam [26:0] NT_TILES_END      = 27'h050000;
localparam [26:0] NT_TILES_LO       = 27'h030000;
localparam [26:0] NT_TILES_SZ       = 27'h020000;

localparam [26:0] NT_SPRITES_BASE   = 27'h050000;
localparam [26:0] NT_SPRITES_END    = 27'h070000;
localparam [26:0] NT_SPRITES_LO     = 27'h050000;
localparam [26:0] NT_SPRITES_SZ     = 27'h020000;

localparam [26:0] NT_PROMS_BASE     = 27'h070000;
localparam [26:0] NT_PROMS_END      = 27'h070400;
localparam [26:0] NT_PROMS_LO       = 27'h070000;
localparam [26:0] NT_PROMS_SZ       = 27'h000400;

localparam [26:0] NT_SPRBANK_BASE   = 27'h070400;
localparam [26:0] NT_SPRBANK_END    = 27'h070500;
localparam [26:0] NT_SPRBANK_LO     = 27'h070400;
localparam [26:0] NT_SPRBANK_SZ     = 27'h000100;

